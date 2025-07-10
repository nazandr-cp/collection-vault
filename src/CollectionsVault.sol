// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {RolesBase} from "./RolesBase.sol";
import {CrossContractSecurity} from "./CrossContractSecurity.sol";
import {Roles} from "./Roles.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";

import {CollectionYieldLib} from "./libraries/CollectionYieldLib.sol";
import {CollectionCoreLib} from "./libraries/CollectionCoreLib.sol";
import {BatchOperationsLib} from "./libraries/BatchOperationsLib.sol";

interface ICToken {
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
    function underlying() external view returns (address);
}

contract CollectionsVault is ERC4626, ICollectionsVault, RolesBase, CrossContractSecurity {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using CollectionCoreLib for *;

    modifier onlyValidEpochManager() {
        if (address(epochManager) == address(0)) revert EpochManagerNotSet();
        _;
    }

    function _getCurrentEpochIdSafe() internal returns (uint256 currentEpochId) {
        try epochManager.getCurrentEpochId() returns (uint256 epochId) {
            currentEpochId = epochId;
            if (currentEpochId == 0) revert NoActiveEpoch();
        } catch Error(string memory reason) {
            emit EpochManagerCallUnavailable(address(this), "getCurrentEpochId", reason);
            revert EpochManagerUnavailable();
        } catch {
            emit EpochManagerCallUnavailable(address(this), "getCurrentEpochId", "Unknown");
            revert EpochManagerUnavailable();
        }
    }

    function ADMIN_ROLE() external pure returns (bytes32) {
        return Roles.ADMIN_ROLE;
    }

    function DEBT_SUBSIDIZER_ROLE() external pure returns (bytes32) {
        return Roles.OPERATOR_ROLE;
    }

    ILendingManager public lendingManager;
    IEpochManager public epochManager;
    ICollectionRegistry public collectionRegistry;

    uint256 public constant DEPOSIT_INDEX_PRECISION = 1e18;
    uint256 public constant MAX_BATCH_SIZE = 50;

    struct VaultGlobals {
        uint256 totalAssetsDep;
        uint256 totalYieldReserved;
        uint256 globalDepositIndex;
        uint256 totalYieldAllocated;
    }

    VaultGlobals public vaultGlobals;

    struct CollectionMetrics {
        uint256 totalBorrowVolume;
        uint256 totalYieldGenerated;
        uint256 performanceScore;
    }

    mapping(address => CollectionVaultData) public collectionVaultsData;
    mapping(address => bool) private isCollectionRegistered;
    mapping(uint256 => uint256) public epochYieldAllocations;
    mapping(uint256 => mapping(address => bool)) public epochYieldApplied;
    mapping(address => CollectionMetrics) public collectionMetrics;

    address[] private allCollectionAddresses;

    modifier onlyCollectionOperator(address collection) {
        _requireRoleOrGuardian(Roles.COLLECTION_MANAGER_ROLE, _msgSender());
        _;
    }

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialAdmin,
        address _lendingManager,
        address _collectionRegistry
    ) ERC4626(_asset) ERC20(_name, _symbol) RolesBase(initialAdmin) {
        if (address(_asset) == address(0)) revert AddressZero();
        if (initialAdmin == address(0)) revert AddressZero();
        if (_collectionRegistry == address(0)) revert AddressZero();

        if (_lendingManager != address(0)) {
            ILendingManager tempLendingManager = ILendingManager(_lendingManager);
            if (address(tempLendingManager.asset()) != address(_asset)) {
                revert LendingManagerMismatch();
            }
            lendingManager = tempLendingManager;
            IERC20(_asset).forceApprove(_lendingManager, type(uint256).max);
        }

        vaultGlobals.globalDepositIndex = DEPOSIT_INDEX_PRECISION;
        collectionRegistry = ICollectionRegistry(_collectionRegistry);
    }

    function _updateGlobalDepositIndex() internal {
        vaultGlobals.globalDepositIndex = CollectionYieldLib.updateGlobalDepositIndex(
            lendingManager, vaultGlobals.totalYieldReserved, vaultGlobals.globalDepositIndex
        );
    }

    function _accrueCollectionYield(address collectionAddress) internal {
        if (!isCollectionRegistered[collectionAddress]) {
            return;
        }

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];
        (, uint256 newTotal, uint256 newYieldGenerated) = CollectionYieldLib.accrueCollectionYield(
            collectionAddress,
            vaultData,
            collectionRegistry,
            vaultGlobals.globalDepositIndex,
            vaultGlobals.totalAssetsDep,
            collectionMetrics[collectionAddress].totalYieldGenerated
        );
        vaultGlobals.totalAssetsDep = newTotal;
        collectionMetrics[collectionAddress].totalYieldGenerated = newYieldGenerated;
    }

    function _ensureCollectionKnownAndRegistered(address collectionAddress) private {
        CollectionCoreLib.ensureCollectionKnownAndRegistered(
            collectionAddress,
            collectionRegistry,
            isCollectionRegistered,
            allCollectionAddresses,
            collectionVaultsData[collectionAddress],
            vaultGlobals.globalDepositIndex
        );
    }

    function setLendingManager(address _lendingManager) external onlyRole(Roles.ADMIN_ROLE) whenNotPaused {
        CollectionCoreLib.validateAddress(_lendingManager);
        address oldLendingManagerAddress = address(lendingManager);
        lendingManager = ILendingManager(_lendingManager);
        if (address(lendingManager.asset()) != address(asset())) {
            revert LendingManagerMismatch();
        }

        IERC20 assetToken = IERC20(asset());
        if (oldLendingManagerAddress != address(0)) {
            assetToken.forceApprove(oldLendingManagerAddress, 0);
        }
        assetToken.forceApprove(_lendingManager, type(uint256).max);

        emit LendingManagerChanged(oldLendingManagerAddress, _lendingManager, _msgSender());
    }

    function setEpochManager(address _epochManager) external onlyRole(Roles.ADMIN_ROLE) whenNotPaused {
        CollectionCoreLib.validateAddress(_epochManager);
        epochManager = IEpochManager(_epochManager);
    }

    function setCollectionRegistry(address _collectionRegistry) external onlyRole(Roles.ADMIN_ROLE) whenNotPaused {
        if (_collectionRegistry == address(0)) revert AddressZero();
        address oldRegistry = address(collectionRegistry);
        collectionRegistry = ICollectionRegistry(_collectionRegistry);
        emit CollectionRegistryUpdated(oldRegistry, _collectionRegistry);
    }

    function setDebtSubsidizer(address _debtSubsidizer) external onlyRole(Roles.ADMIN_ROLE) whenNotPaused {
        if (_debtSubsidizer == address(0)) revert AddressZero();
        _grantRole(Roles.OPERATOR_ROLE, _debtSubsidizer);
    }

    function isCollectionOperator(address, address operator) public view returns (bool) {
        return hasRole(Roles.COLLECTION_MANAGER_ROLE, operator) || hasRole(Roles.GUARDIAN_ROLE, operator);
    }

    function collectionTotalAssetsDeposited(address collectionAddress) public view override returns (uint256) {
        return CollectionCoreLib.calculateCollectionTotalAssets(
            collectionAddress,
            collectionVaultsData[collectionAddress],
            collectionRegistry,
            vaultGlobals.globalDepositIndex,
            isCollectionRegistered
        );
    }

    function underlying() external view override returns (address) {
        return asset();
    }

    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return vaultGlobals.totalAssetsDep;
    }

    function totalAssetsDeposited() external view returns (uint256) {
        return vaultGlobals.totalAssetsDep;
    }

    function totalYieldReserved() external view returns (uint256) {
        return vaultGlobals.totalYieldReserved;
    }

    function totalYieldAllocated() external view returns (uint256) {
        return vaultGlobals.totalYieldAllocated;
    }

    function deposit(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("depFC");
    }

    function _performCollectionDeposit(
        address collectionAddress,
        address receiver,
        uint256 assetsOrShares,
        CollectionCoreLib.DepositOperationType operationType
    ) internal returns (uint256 assets, uint256 shares) {
        _updateGlobalDepositIndex();
        _ensureCollectionKnownAndRegistered(collectionAddress);
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];

        (assets, shares) = CollectionCoreLib.calculateDepositAmounts(
            assetsOrShares, operationType, this.previewDeposit, this.previewMint
        );

        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);

        vaultGlobals.totalAssetsDep =
            CollectionCoreLib.updateCollectionDataAfterDeposit(vaultData, assets, shares, vaultGlobals.totalAssetsDep);

        emit CollectionDeposit(collectionAddress, _msgSender(), receiver, assets, shares, shares);
    }

    function depositForCollection(uint256 assets, address receiver, address collectionAddress)
        public
        override(ICollectionsVault)
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (uint256 shares)
    {
        (, shares) = _performCollectionDeposit(
            collectionAddress, receiver, assets, CollectionCoreLib.DepositOperationType.DEPOSIT_FOR_COLLECTION
        );
    }

    function transfer(address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert FunctionDisabledUse("transFC");
    }

    function transferFrom(address, address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert FunctionDisabledUse("transFC");
    }

    function transferForCollection(address collectionAddress, address to, uint256 assets)
        public
        override(ICollectionsVault)
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (uint256 shares)
    {
        (, shares) = _performCollectionDeposit(
            collectionAddress, to, assets, CollectionCoreLib.DepositOperationType.TRANSFER_FOR_COLLECTION
        );
    }

    function mint(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("mintFC");
    }

    function mintForCollection(uint256 shares, address receiver, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (uint256 assets)
    {
        (assets,) = _performCollectionDeposit(
            collectionAddress, receiver, shares, CollectionCoreLib.DepositOperationType.MINT_FOR_COLLECTION
        );
    }

    function withdraw(uint256, address, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("withFC");
    }

    function withdrawForCollection(uint256 assets, address receiver, address owner, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (uint256 shares)
    {
        _updateGlobalDepositIndex();
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];
        uint256 currentTotalAssets = vaultData.totalAssetsDeposited;
        if (assets > currentTotalAssets) {
            revert CollectionInsufficientBalance(collectionAddress, assets, currentTotalAssets);
        }

        shares = previewWithdraw(assets);
        _hookWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        vaultData.totalAssetsDeposited = currentTotalAssets - assets;
        vaultGlobals.totalAssetsDep -= assets;
        if (vaultData.totalSharesMinted < shares || vaultData.totalCTokensMinted < shares) {
            revert ShareBalanceUnderflow();
        }
        vaultData.totalSharesMinted -= shares;
        vaultData.totalCTokensMinted -= shares;

        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares);
    }

    function redeem(uint256, address, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("redeemFC");
    }

    function redeemForCollection(uint256 shares, address receiver, address owner, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (uint256 assets)
    {
        _updateGlobalDepositIndex();
        _ensureCollectionKnownAndRegistered(collectionAddress);
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];
        uint256 currentTotalAssets = vaultData.totalAssetsDeposited;

        assets = previewRedeem(shares);
        if (assets == 0) {
            if (shares != 0) revert RedeemRoundsToZero(shares);
        }

        _hookWithdraw(assets);
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        emit Transfer(owner, address(0), shares);

        uint256 finalAssetsToTransfer = _handleFullRedemption(assets, shares);

        _performAssetTransfer(receiver, finalAssetsToTransfer, owner, shares);
        _updateCollectionData(vaultData, assets, shares, currentTotalAssets);

        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares);
        return finalAssetsToTransfer;
    }

    function _handleFullRedemption(uint256 assets, uint256 shares) internal returns (uint256 finalAssetsToTransfer) {
        return CollectionCoreLib.handleFullRedemption(
            assets, shares, totalSupply(), lendingManager, vaultGlobals.totalYieldReserved
        );
    }

    function _performAssetTransfer(address receiver, uint256 finalAssetsToTransfer, address owner, uint256 shares)
        internal
    {
        CollectionCoreLib.performAssetTransfer(IERC20(asset()), receiver, finalAssetsToTransfer, owner, shares);
    }

    function _updateCollectionData(
        CollectionVaultData storage vaultData,
        uint256 assets,
        uint256 shares,
        uint256 currentTotalAssets
    ) internal {
        vaultGlobals.totalAssetsDep = CollectionCoreLib.updateCollectionDataAfterWithdraw(
            vaultData, assets, shares, currentTotalAssets, vaultGlobals.totalAssetsDep
        );
    }

    function _hookDeposit(uint256 assets) internal virtual {
        if (assets > 0) {
            try lendingManager.depositToLendingProtocol(assets) returns (bool success) {
                if (!success) {
                    emit LendingManagerCallFailed(address(this), "deposit", assets, "Deposit failed");
                    revert LendingManagerDepositFailed();
                }
            } catch Error(string memory reason) {
                emit LendingManagerCallFailed(address(this), "deposit", assets, reason);
                revert LendingManagerDepositFailed();
            } catch {
                emit LendingManagerCallFailed(address(this), "deposit", assets, "Unknown");
                revert LendingManagerDepositFailed();
            }
        }
    }

    function _hookWithdraw(uint256 assets) internal virtual {
        CollectionCoreLib.handleWithdrawOperation(
            assets, IERC20(asset()), lendingManager, vaultGlobals.totalYieldReserved, _msgSender(), this.hasRole
        );
    }

    function repayBorrowBehalf(uint256 amount, address borrower)
        external
        onlyRole(Roles.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) return;

        _updateGlobalDepositIndex();
        _hookWithdraw(amount);

        IERC20 assetToken = IERC20(asset());
        assetToken.forceApprove(address(lendingManager), amount);

        try lendingManager.repayBorrowBehalf(borrower, amount) returns (uint256 lmError) {
            if (lmError != 0) {
                revert RepayBorrowFailed();
            }
        } catch {
            revert RepayBorrowFailed();
        }

        if (address(epochManager) != address(0)) {
            try epochManager.getCurrentEpochId() returns (uint256 epochId) {
                if (epochId != 0 && epochYieldAllocations[epochId] >= amount) {
                    epochYieldAllocations[epochId] -= amount;
                }
            } catch {}
        }
        if (vaultGlobals.totalYieldReserved >= amount) {
            vaultGlobals.totalYieldReserved -= amount;
        } else {
            vaultGlobals.totalYieldReserved = 0;
        }

        assetToken.forceApprove(address(lendingManager), 0);
    }

    function repayBorrowBehalfBatch(uint256[] calldata amounts, address[] calldata borrowers, uint256 totalAmount)
        external
        onlyRole(Roles.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (totalAmount == 0) {
            return;
        }

        _updateGlobalDepositIndex();
        _hookWithdraw(totalAmount);

        (uint256 actualTotalRepaid, uint256 newTotalYieldReserved) = BatchOperationsLib.processBatchRepayment(
            amounts,
            borrowers,
            totalAmount,
            IERC20(asset()),
            lendingManager,
            epochManager,
            epochYieldAllocations,
            vaultGlobals.totalYieldReserved
        );

        vaultGlobals.totalYieldReserved = newTotalYieldReserved;
        emit YieldBatchRepaid(actualTotalRepaid, msg.sender);
    }

    function getCurrentEpochYield(bool includeNonShared) public view override returns (uint256 availableYield) {
        if (includeNonShared) {
            return CollectionYieldLib.getCurrentEpochYield(lendingManager, 0, true);
        }

        if (address(epochManager) == address(0)) {
            return 0;
        }

        try epochManager.getCurrentEpochId() returns (uint256 currentEpochId) {
            if (currentEpochId == 0) {
                return 0;
            }

            uint256 allocated = epochYieldAllocations[currentEpochId];
            return CollectionYieldLib.getCurrentEpochYield(lendingManager, allocated, false);
        } catch {
            return 0;
        }
    }

    function getTotalAvailableYield() public view returns (uint256 totalAvailableYield) {
        return CollectionYieldLib.getTotalAvailableYield(lendingManager);
    }

    function getRemainingCumulativeYield() public view returns (uint256 remainingYield) {
        return CollectionYieldLib.getRemainingCumulativeYield(lendingManager, vaultGlobals.totalYieldAllocated);
    }

    function validateCumulativeClaims(uint256 totalClaimedAmount) external view returns (bool isValid) {
        return totalClaimedAmount <= vaultGlobals.totalYieldAllocated;
    }

    function validateMerkleTreeAllocation(uint256 merkleTreeTotal)
        external
        view
        returns (bool canAllocate, uint256 totalAvailable, uint256 currentlyAllocated, uint256 remainingYield)
    {
        totalAvailable = getTotalAvailableYield();
        currentlyAllocated = vaultGlobals.totalYieldAllocated;
        remainingYield = getRemainingCumulativeYield();

        canAllocate = merkleTreeTotal <= remainingYield && (currentlyAllocated + merkleTreeTotal) <= totalAvailable;
    }

    function allocateEpochYield(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRole(Roles.ADMIN_ROLE)
        onlyValidEpochManager
    {
        if (amount == 0) revert AllocationAmountZero();

        uint256 currentAvailableYield = getCurrentEpochYield(false);
        if (amount > currentAvailableYield) revert AllocExceedsAvail();

        uint256 currentEpochId = _getCurrentEpochIdSafe();

        try epochManager.allocateVaultYield(address(this), amount) {
            epochYieldAllocations[currentEpochId] += amount;
            vaultGlobals.totalYieldReserved += amount;
        } catch Error(string memory reason) {
            emit EpochManagerCallFailed(address(this), currentEpochId, amount, reason);
            revert EpochManagerAllocationFailed();
        } catch {
            emit EpochManagerCallFailed(address(this), currentEpochId, amount, "Unknown");
            revert EpochManagerAllocationFailed();
        }

        emit VaultYieldAllocatedToEpoch(currentEpochId, amount);
    }

    function allocateYieldToEpoch(uint256 epochId)
        external
        nonReentrant
        whenNotPaused
        onlyRole(Roles.ADMIN_ROLE)
        onlyValidEpochManager
    {
        uint256 currentEpochId = _getCurrentEpochIdSafe();
        if (epochId != currentEpochId || epochId == 0) revert InvalidEpochId();

        uint256 amount = getRemainingCumulativeYield();
        if (amount == 0) {
            revert NoCumulativeYield();
        }

        try epochManager.allocateVaultYield(address(this), amount) {
            epochYieldAllocations[epochId] += amount;
            vaultGlobals.totalYieldAllocated += amount; // Track cumulative allocation
            vaultGlobals.totalYieldReserved += amount;
        } catch Error(string memory reason) {
            emit EpochManagerCallFailed(address(this), epochId, amount, reason);
            revert EpochManagerAllocationFailed();
        } catch {
            emit EpochManagerCallFailed(address(this), epochId, amount, "Unknown");
            revert EpochManagerAllocationFailed();
        }
        emit VaultYieldAllocatedToEpoch(epochId, amount);
    }

    function allocateCumulativeYieldToEpoch(uint256 epochId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRole(Roles.ADMIN_ROLE)
        onlyValidEpochManager
    {
        uint256 currentEpochId = _getCurrentEpochIdSafe();
        if (epochId != currentEpochId || epochId == 0) revert InvalidEpochId();
        if (amount == 0) {
            revert AllocationAmountZero();
        }

        uint256 remainingYield = getRemainingCumulativeYield();
        uint256 totalAvailable = getTotalAvailableYield();
        uint256 newCumulativeTotal = vaultGlobals.totalYieldAllocated + amount;

        if (amount > remainingYield) {
            revert ReqAmountExceeds();
        }

        if (newCumulativeTotal > totalAvailable) {
            revert TotalAllocExceeds();
        }

        try epochManager.allocateVaultYield(address(this), amount) {
            epochYieldAllocations[epochId] += amount;
            vaultGlobals.totalYieldAllocated += amount; // Track cumulative allocation
            vaultGlobals.totalYieldReserved += amount;
        } catch Error(string memory reason) {
            emit EpochManagerCallFailed(address(this), epochId, amount, reason);
            revert EpochManagerAllocationFailed();
        } catch {
            emit EpochManagerCallFailed(address(this), epochId, amount, "Unknown");
            revert EpochManagerAllocationFailed();
        }

        emit VaultYieldAllocatedToEpoch(epochId, amount);
    }

    function getEpochYieldAllocated(uint256 epochId) external view returns (uint256 amount) {
        return epochYieldAllocations[epochId];
    }

    function totalCollectionYieldShareBps() public view returns (uint16 totalBps) {
        return CollectionYieldLib.totalCollectionYieldShareBps(allCollectionAddresses, collectionRegistry);
    }

    function indexCollectionsDeposits() external onlyRole(Roles.ADMIN_ROLE) whenNotPaused nonReentrant {
        _updateGlobalDepositIndex();
        address[] memory collectionList = allCollectionAddresses;
        uint256 length = collectionList.length;
        for (uint256 i = 0; i < length;) {
            _accrueCollectionYield(collectionList[i]);
            unchecked {
                ++i;
            }
        }
    }

    function getCollectionTotalBorrowVolume(address collectionAddress) external view returns (uint256) {
        return collectionMetrics[collectionAddress].totalBorrowVolume;
    }

    function getCollectionTotalYieldGenerated(address collectionAddress) external view returns (uint256) {
        return collectionMetrics[collectionAddress].totalYieldGenerated;
    }

    function getCollectionPerformanceScore(address collectionAddress) external view returns (uint256) {
        return collectionMetrics[collectionAddress].performanceScore;
    }

    function updateCollectionPerformanceScore(address collectionAddress, uint256 score)
        external
        onlyRole(Roles.ADMIN_ROLE)
        whenNotPaused
    {
        if (collectionAddress == address(0)) revert AddressZero();
        CollectionCoreLib.validatePerformanceScore(score);
        collectionMetrics[collectionAddress].performanceScore = score;
        emit CollectionPerformanceUpdated(collectionAddress, score, block.timestamp);
    }

    function recordCollectionBorrowVolume(address collectionAddress, uint256 borrowAmount)
        external
        onlyRole(Roles.ADMIN_ROLE)
        whenNotPaused
    {
        if (collectionAddress == address(0)) revert AddressZero();
        collectionMetrics[collectionAddress].totalBorrowVolume += borrowAmount;
        emit CollectionBorrowVolumeUpdated(
            collectionAddress, collectionMetrics[collectionAddress].totalBorrowVolume, borrowAmount, block.timestamp
        );
    }

    function applyCollectionYieldForEpoch(address collectionAddress, uint256 epochId)
        external
        nonReentrant
        whenNotPaused
        onlyRole(Roles.ADMIN_ROLE)
        onlyValidEpochManager
    {
        if (collectionAddress == address(0)) {
            revert AddressZero();
        }
        if (!isCollectionRegistered[collectionAddress]) {
            revert CollectionNotRegistered(collectionAddress);
        }
        if (epochYieldApplied[epochId][collectionAddress]) {
            revert YieldAlreadyApplied();
        }

        uint256 totalEpochAllocation = epochYieldAllocations[epochId];
        if (totalEpochAllocation == 0) {
            epochYieldApplied[epochId][collectionAddress] = true;
            emit CollectionYieldAppliedForEpoch(
                epochId,
                collectionAddress,
                collectionRegistry.getCollection(collectionAddress).yieldSharePercentage,
                0,
                collectionVaultsData[collectionAddress].totalAssetsDeposited
            );
            return;
        }

        _updateGlobalDepositIndex();
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];
        ICollectionRegistry.Collection memory registryCollection = collectionRegistry.getCollection(collectionAddress);

        if (registryCollection.yieldSharePercentage == 0) {
            epochYieldApplied[epochId][collectionAddress] = true;
            emit CollectionYieldAppliedForEpoch(epochId, collectionAddress, 0, 0, vaultData.totalAssetsDeposited);
            return;
        }

        uint256 collectionYieldFromEpoch = (totalEpochAllocation * registryCollection.yieldSharePercentage) / 10000;

        if (collectionYieldFromEpoch > epochYieldAllocations[epochId]) {
            revert AllocationUnderflow();
        }

        if (collectionYieldFromEpoch > 0) {
            vaultData.totalAssetsDeposited += collectionYieldFromEpoch;
            vaultGlobals.totalAssetsDep += collectionYieldFromEpoch;
            epochYieldAllocations[epochId] -= collectionYieldFromEpoch;
            if (vaultGlobals.totalYieldReserved >= collectionYieldFromEpoch) {
                vaultGlobals.totalYieldReserved -= collectionYieldFromEpoch;
            } else {
                vaultGlobals.totalYieldReserved = 0;
            }
        }

        epochYieldApplied[epochId][collectionAddress] = true;

        emit CollectionYieldAppliedForEpoch(
            epochId,
            collectionAddress,
            registryCollection.yieldSharePercentage,
            collectionYieldFromEpoch,
            vaultData.totalAssetsDeposited
        );
    }

    function resetEpochCollectionYieldFlags(uint256 epochId, address[] calldata collectionsToReset)
        external
        onlyRole(Roles.ADMIN_ROLE)
    {
        uint256 length = collectionsToReset.length;
        if (length > MAX_BATCH_SIZE) {
            revert BatchSizeExceedsLimit();
        }
        for (uint256 i = 0; i < length;) {
            delete epochYieldApplied[epochId][collectionsToReset[i]];
            unchecked {
                ++i;
            }
        }
    }
}
