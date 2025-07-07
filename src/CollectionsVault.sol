// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AccessControlBase} from "./AccessControlBase.sol";
import {CrossContractSecurity} from "./CrossContractSecurity.sol";
import {Roles} from "./Roles.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";

// Import libraries for size optimization
import {CollectionYieldLib} from "./libraries/CollectionYieldLib.sol";
import {CollectionOperationsLib} from "./libraries/CollectionOperationsLib.sol";
import {CollectionValidationLib} from "./libraries/CollectionValidationLib.sol";

interface ICToken {
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
    function underlying() external view returns (address);
}

contract CollectionsVault is ERC4626, ICollectionsVault, AccessControlBase, CrossContractSecurity {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using CollectionOperationsLib for *;

    bytes32 public constant ADMIN_ROLE = Roles.ADMIN_ROLE;
    bytes32 public constant OPERATOR_ROLE = Roles.OPERATOR_ROLE;

    // For interface compatibility - returns OPERATOR_ROLE
    function DEBT_SUBSIDIZER_ROLE() external pure returns (bytes32) {
        return OPERATOR_ROLE;
    }

    ILendingManager public lendingManager;
    IEpochManager public epochManager;
    ICollectionRegistry public collectionRegistry;

    mapping(address => CollectionVaultData) public collectionVaultsData;
    uint256 public totalAssetsDepositedAllCollections;
    uint256 public totalYieldReserved;
    uint256 public globalDepositIndex;
    uint256 public constant GLOBAL_DEPOSIT_INDEX_PRECISION = 1e18;
    uint256 public constant MAX_BATCH_SIZE = 50;

    address[] private allCollectionAddresses;
    mapping(address => bool) private isCollectionRegistered;

    mapping(address => mapping(address => bool)) private collectionOperators;

    mapping(uint256 => uint256) public epochYieldAllocations;
    mapping(uint256 => mapping(address => bool)) public epochCollectionYieldApplied;

    // Collection-specific statistics
    mapping(address => uint256) public collectionTotalBorrowVolume;
    mapping(address => uint256) public collectionTotalYieldGenerated;
    mapping(address => uint256) public collectionPerformanceScore;

    modifier onlyCollectionOperator(address collection) {
        CollectionValidationLib.validateCollectionOperator(collection, _msgSender(), collectionOperators);
        _;
    }

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialAdmin,
        address _lendingManagerAddress,
        address _collectionRegistryAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) AccessControlBase(initialAdmin) {
        if (address(_asset) == address(0)) revert AddressZero();
        if (initialAdmin == address(0)) revert AddressZero();
        if (_collectionRegistryAddress == address(0)) revert AddressZero();

        if (_lendingManagerAddress != address(0)) {
            ILendingManager tempLendingManager = ILendingManager(_lendingManagerAddress);
            if (address(tempLendingManager.asset()) != address(_asset)) {
                revert LendingManagerMismatch();
            }
            lendingManager = tempLendingManager;
            IERC20(_asset).forceApprove(_lendingManagerAddress, type(uint256).max);
        }

        globalDepositIndex = GLOBAL_DEPOSIT_INDEX_PRECISION;
        collectionRegistry = ICollectionRegistry(_collectionRegistryAddress);
    }

    function _updateGlobalDepositIndex() internal {
        globalDepositIndex = CollectionYieldLib.updateGlobalDepositIndex(
            lendingManager,
            totalYieldReserved,
            globalDepositIndex
        );
    }

    function _accrueCollectionYield(address collectionAddress) internal {
        if (!isCollectionRegistered[collectionAddress]) {
            return;
        }
        
        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];
        (, uint256 newTotal) = CollectionYieldLib.accrueCollectionYield(
            collectionAddress,
            vaultData,
            collectionRegistry,
            globalDepositIndex,
            totalAssetsDepositedAllCollections,
            collectionTotalYieldGenerated
        );
        totalAssetsDepositedAllCollections = newTotal;
    }

    function _ensureCollectionKnownAndRegistered(address collectionAddress) private {
        CollectionValidationLib.ensureCollectionKnownAndRegistered(
            collectionAddress,
            collectionRegistry,
            isCollectionRegistered,
            allCollectionAddresses,
            collectionVaultsData[collectionAddress],
            globalDepositIndex
        );
    }

    function setLendingManager(address _lendingManagerAddress) external onlyRole(ADMIN_ROLE) whenNotPaused {
        CollectionValidationLib.validateAddress(_lendingManagerAddress);
        address oldLendingManagerAddress = address(lendingManager);
        lendingManager = ILendingManager(_lendingManagerAddress);
        if (address(lendingManager.asset()) != address(asset())) {
            revert LendingManagerMismatch();
        }

        IERC20 assetToken = IERC20(asset());
        if (oldLendingManagerAddress != address(0)) {
            assetToken.forceApprove(oldLendingManagerAddress, 0);
        }
        assetToken.forceApprove(_lendingManagerAddress, type(uint256).max);

        emit LendingManagerChanged(oldLendingManagerAddress, _lendingManagerAddress, _msgSender());
    }

    function setEpochManager(address _epochManagerAddress) external onlyRole(ADMIN_ROLE) whenNotPaused {
        CollectionValidationLib.validateAddress(_epochManagerAddress);
        epochManager = IEpochManager(_epochManagerAddress);
    }

    function setCollectionRegistry(address _collectionRegistryAddress) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (_collectionRegistryAddress == address(0)) revert AddressZero();
        address oldRegistry = address(collectionRegistry);
        collectionRegistry = ICollectionRegistry(_collectionRegistryAddress);
        emit CollectionRegistryUpdated(oldRegistry, _collectionRegistryAddress);
    }

    function setDebtSubsidizer(address _debtSubsidizerAddress) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (_debtSubsidizerAddress == address(0)) revert AddressZero();
        _grantRole(OPERATOR_ROLE, _debtSubsidizerAddress);
    }

    function grantCollectionAccess(address collectionAddress, address operator) external onlyRole(ADMIN_ROLE) {
        CollectionValidationLib.validateAddress(collectionAddress);
        CollectionValidationLib.validateAddress(operator);
        collectionOperators[collectionAddress][operator] = true;
        emit CollectionAccessGranted(collectionAddress, operator);
    }

    function revokeCollectionAccess(address collectionAddress, address operator) external onlyRole(ADMIN_ROLE) {
        CollectionValidationLib.validateAddress(collectionAddress);
        CollectionValidationLib.validateAddress(operator);
        collectionOperators[collectionAddress][operator] = false;
        emit CollectionAccessRevoked(collectionAddress, operator);
    }

    function isCollectionOperator(address collectionAddress, address operator) public view returns (bool) {
        return collectionOperators[collectionAddress][operator];
    }

    function collectionTotalAssetsDeposited(address collectionAddress) public view override returns (uint256) {
        return CollectionValidationLib.calculateCollectionTotalAssets(
            collectionAddress,
            collectionVaultsData[collectionAddress],
            collectionRegistry,
            globalDepositIndex,
            isCollectionRegistered
        );
    }

    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return totalAssetsDepositedAllCollections;
    }

    function deposit(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("depositForCollection");
    }

    function _performCollectionDeposit(
        address collectionAddress,
        address receiver,
        uint256 assetsOrShares,
        CollectionOperationsLib.DepositOperationType operationType
    ) internal returns (uint256 assets, uint256 shares) {
        _updateGlobalDepositIndex();
        _ensureCollectionKnownAndRegistered(collectionAddress);
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];

        (assets, shares) = CollectionOperationsLib.calculateDepositAmounts(
            assetsOrShares,
            operationType,
            this.previewDeposit,
            this.previewMint
        );

        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);

        totalAssetsDepositedAllCollections = CollectionOperationsLib.updateCollectionDataAfterDeposit(
            vaultData,
            assets,
            shares,
            totalAssetsDepositedAllCollections
        );
        
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
        (, shares) = _performCollectionDeposit(collectionAddress, receiver, assets, CollectionOperationsLib.DepositOperationType.DEPOSIT_FOR_COLLECTION);
    }

    function transfer(address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert FunctionDisabledUse("transferForCollection");
    }

    function transferFrom(address, address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert FunctionDisabledUse("transferForCollection");
    }

    function transferForCollection(address collectionAddress, address to, uint256 assets)
        public
        override(ICollectionsVault)
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (uint256 shares)
    {
        (, shares) = _performCollectionDeposit(collectionAddress, to, assets, CollectionOperationsLib.DepositOperationType.TRANSFER_FOR_COLLECTION);
    }

    function mint(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("mintForCollection");
    }

    function mintForCollection(uint256 shares, address receiver, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (uint256 assets)
    {
        (assets, ) = _performCollectionDeposit(collectionAddress, receiver, shares, CollectionOperationsLib.DepositOperationType.MINT_FOR_COLLECTION);
    }

    function withdraw(uint256, address, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("withdrawForCollection");
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
        uint256 currentCollectionTotalAssets = vaultData.totalAssetsDeposited;
        if (assets > currentCollectionTotalAssets) {
            revert CollectionInsufficientBalance(collectionAddress, assets, currentCollectionTotalAssets);
        }

        shares = previewWithdraw(assets);
        _hookWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        vaultData.totalAssetsDeposited = currentCollectionTotalAssets - assets;
        totalAssetsDepositedAllCollections -= assets;
        if (vaultData.totalSharesMinted < shares || vaultData.totalCTokensMinted < shares) {
            revert ShareBalanceUnderflow();
        }
        vaultData.totalSharesMinted -= shares;
        vaultData.totalCTokensMinted -= shares;

        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares);
    }

    function redeem(uint256, address, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("redeemForCollection");
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
        uint256 currentCollectionTotalAssets = vaultData.totalAssetsDeposited;

        assets = previewRedeem(shares);
        if (assets == 0) {
            require(shares == 0, "ERC4626: redeem rounds down to zero assets");
        }

        _hookWithdraw(assets);
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        emit Transfer(owner, address(0), shares);

        uint256 finalAssetsToTransfer = _handleFullRedemption(assets, shares);

        _performAssetTransfer(receiver, finalAssetsToTransfer, owner, shares);
        _updateCollectionData(vaultData, assets, shares, currentCollectionTotalAssets);

        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares);
        return finalAssetsToTransfer;
    }

    function _handleFullRedemption(uint256 assets, uint256 shares) internal returns (uint256 finalAssetsToTransfer) {
        return CollectionOperationsLib.handleFullRedemption(
            assets,
            shares,
            totalSupply(),
            lendingManager,
            totalYieldReserved
        );
    }

    function _performAssetTransfer(address receiver, uint256 finalAssetsToTransfer, address owner, uint256 shares)
        internal
    {
        CollectionOperationsLib.performAssetTransfer(
            IERC20(asset()),
            receiver,
            finalAssetsToTransfer,
            owner,
            shares
        );
    }

    function _updateCollectionData(
        CollectionVaultData storage vaultData,
        uint256 assets,
        uint256 shares,
        uint256 currentCollectionTotalAssets
    ) internal {
        totalAssetsDepositedAllCollections = CollectionOperationsLib.updateCollectionDataAfterWithdraw(
            vaultData,
            assets,
            shares,
            currentCollectionTotalAssets,
            totalAssetsDepositedAllCollections
        );
    }

    function transferForCollection(address to, uint256 amount, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (bool)
    {
        if (to == address(0)) revert AddressZero();
        if (amount == 0) return true;

        _updateGlobalDepositIndex();
        _accrueCollectionYield(collectionAddress); // Ensures collection is known and yield accrued

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];
        if (!isCollectionRegistered[collectionAddress]) {
            revert CollectionNotRegistered(collectionAddress);
        }

        uint256 currentTotalAssetsView = collectionTotalAssetsDeposited(collectionAddress);
        if (amount > currentTotalAssetsView) {
            revert CollectionInsufficientBalance(collectionAddress, amount, currentTotalAssetsView);
        }
        if (amount > vaultData.totalAssetsDeposited) {
            revert CollectionInsufficientBalance(collectionAddress, amount, vaultData.totalAssetsDeposited);
        }

        _transfer(msg.sender, to, amount);
        emit Transfer(msg.sender, to, amount);

        vaultData.totalAssetsDeposited -= amount;
        totalAssetsDepositedAllCollections -= amount;
        if (vaultData.totalSharesMinted < amount || vaultData.totalCTokensMinted < amount) {
            revert ShareBalanceUnderflow();
        }
        vaultData.totalSharesMinted -= amount;
        vaultData.totalCTokensMinted -= amount;

        emit CollectionTransfer(collectionAddress, msg.sender, to, amount);
        return true;
    }

    function _hookDeposit(uint256 assets) internal virtual {
        if (assets > 0) {
            try lendingManager.depositToLendingProtocol(assets) returns (bool success) {
                if (!success) {
                    revert LendingManagerDepositFailed();
                }
            } catch {
                revert LendingManagerDepositFailed();
            }
        }
    }

    function _hookWithdraw(uint256 assets) internal virtual {
        if (assets == 0) return;
        IERC20 assetToken = IERC20(asset());
        uint256 directBalance = assetToken.balanceOf(address(this));
        if (directBalance < assets) {
            uint256 neededFromLM = assets - directBalance;
            uint256 availableInLM = lendingManager.totalAssets();
            uint256 reserve = totalYieldReserved;
            uint256 usableInLM = hasRole(OPERATOR_ROLE, _msgSender())
                ? availableInLM
                : (availableInLM > reserve ? availableInLM - reserve : 0);
            if (neededFromLM <= usableInLM) {
                if (neededFromLM > 0) {
                    try lendingManager.withdrawFromLendingProtocol(neededFromLM) returns (bool success) {
                        if (!success) {
                            revert LendingManagerWithdrawFailed();
                        }
                        uint256 balanceAfterLMWithdraw = assetToken.balanceOf(address(this));
                        if (balanceAfterLMWithdraw < assets) {
                            revert Vault_InsufficientBalancePostLMWithdraw();
                        }
                    } catch {
                        revert LendingManagerWithdrawFailed();
                    }
                }
            }
        }
    }

    function repayBorrowBehalf(uint256 amount, address borrower)
        external
        onlyRole(OPERATOR_ROLE)
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
                revert("CollectionsVault: Repay borrow behalf failed via LendingManager");
            }
        } catch {
            revert("CollectionsVault: Repay borrow behalf failed via LendingManager");
        }

        if (address(epochManager) != address(0)) {
            uint256 epochId = epochManager.getCurrentEpochId();
            if (epochId != 0 && epochYieldAllocations[epochId] >= amount) {
                epochYieldAllocations[epochId] -= amount;
            }
        }
        if (totalYieldReserved >= amount) {
            totalYieldReserved -= amount;
        } else {
            totalYieldReserved = 0;
        }

        assetToken.forceApprove(address(lendingManager), 0);
    }

    function repayBorrowBehalfBatch(uint256[] calldata amounts, address[] calldata borrowers, uint256 totalAmount)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        uint256 numEntries = borrowers.length;
        if (numEntries != amounts.length) {
            revert("CollectionsVault: Array lengths mismatch");
        }
        if (numEntries > MAX_BATCH_SIZE) {
            revert("CollectionsVault: Batch size exceeds maximum limit");
        }

        if (totalAmount == 0) {
            return;
        }

        _updateGlobalDepositIndex();
        _hookWithdraw(totalAmount);

        IERC20 assetToken = IERC20(asset());
        assetToken.forceApprove(address(lendingManager), totalAmount);

        uint256 actualTotalRepaid = 0;
        for (uint256 i = 0; i < numEntries;) {
            uint256 amt = amounts[i];
            address borrowerAddr = borrowers[i];

            if (amt != 0) {
                try lendingManager.repayBorrowBehalf(borrowerAddr, amt) returns (uint256 lmError) {
                    if (lmError != 0) {
                        revert("CollectionsVault: Repay borrow behalf failed via LendingManager");
                    }
                    actualTotalRepaid += amt;
                } catch {
                    revert("CollectionsVault: Repay borrow behalf failed via LendingManager");
                }
            }
            unchecked {
                ++i;
            }
        }

        assetToken.forceApprove(address(lendingManager), 0);
        if (address(epochManager) != address(0)) {
            uint256 epochId = epochManager.getCurrentEpochId();
            if (epochId != 0 && epochYieldAllocations[epochId] >= actualTotalRepaid) {
                epochYieldAllocations[epochId] -= actualTotalRepaid;
            }
        }
        if (totalYieldReserved >= actualTotalRepaid) {
            totalYieldReserved -= actualTotalRepaid;
        } else {
            totalYieldReserved = 0;
        }
        emit YieldBatchRepaid(actualTotalRepaid, msg.sender);
    }

    function getCurrentEpochYield(bool includeNonShared) public view override returns (uint256 availableYield) {
        if (includeNonShared) {
            return CollectionYieldLib.getCurrentEpochYield(lendingManager, 0, true);
        }

        if (address(epochManager) == address(0)) {
            return 0;
        }

        uint256 currentEpochId = epochManager.getCurrentEpochId();
        if (currentEpochId == 0) {
            return 0;
        }

        uint256 allocated = epochYieldAllocations[currentEpochId];
        return CollectionYieldLib.getCurrentEpochYield(lendingManager, allocated, false);
    }

    function allocateEpochYield(uint256 amount) external nonReentrant whenNotPaused onlyRole(ADMIN_ROLE) {
        if (address(epochManager) == address(0)) {
            revert("CollectionsVault: EpochManager not set");
        }
        if (amount == 0) {
            revert("CollectionsVault: Allocation amount cannot be zero");
        }

        uint256 currentAvailableYield = getCurrentEpochYield(false);
        if (amount > currentAvailableYield) {
            revert("CollectionsVault: Allocation amount exceeds available yield");
        }

        uint256 currentEpochId = epochManager.getCurrentEpochId();
        if (currentEpochId == 0) {
            revert("CollectionsVault: No active epoch in EpochManager");
        }

        epochManager.allocateVaultYield(address(this), amount);
        epochYieldAllocations[currentEpochId] += amount;
        totalYieldReserved += amount;

        emit VaultYieldAllocatedToEpoch(currentEpochId, amount);
    }

    function allocateYieldToEpoch(uint256 epochId) external nonReentrant whenNotPaused onlyRole(ADMIN_ROLE) {
        if (address(epochManager) == address(0)) revert("CollectionsVault: EpochManager not set");
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        if (epochId != currentEpochId || epochId == 0) {
            revert("CollectionsVault: Invalid epochId");
        }
        uint256 amount = getCurrentEpochYield(false);
        if (amount == 0) {
            revert("CollectionsVault: No yield available for allocation");
        }
        epochManager.allocateVaultYield(address(this), amount);
        epochYieldAllocations[epochId] += amount;
        totalYieldReserved += amount;
        emit VaultYieldAllocatedToEpoch(epochId, amount);
    }

    function getEpochYieldAllocated(uint256 epochId) external view returns (uint256 amount) {
        return epochYieldAllocations[epochId];
    }

    function totalCollectionYieldShareBps() public view returns (uint16 totalBps) {
        uint256 length = allCollectionAddresses.length;
        for (uint256 i = 0; i < length;) {
            totalBps += collectionRegistry.getCollection(allCollectionAddresses[i]).yieldSharePercentage;
            unchecked {
                ++i;
            }
        }
    }

    function indexCollectionsDeposits() external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
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
        return collectionTotalBorrowVolume[collectionAddress];
    }

    function getCollectionTotalYieldGenerated(address collectionAddress) external view returns (uint256) {
        return collectionTotalYieldGenerated[collectionAddress];
    }

    function getCollectionPerformanceScore(address collectionAddress) external view returns (uint256) {
        return collectionPerformanceScore[collectionAddress];
    }

    function updateCollectionPerformanceScore(address collectionAddress, uint256 score)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        if (collectionAddress == address(0)) revert AddressZero();
        if (score > 10000) {
            revert("CollectionsVault: Performance score cannot exceed 10000 (100%)");
        }
        collectionPerformanceScore[collectionAddress] = score;
        emit CollectionPerformanceUpdated(collectionAddress, score, block.timestamp);
    }

    function recordCollectionBorrowVolume(address collectionAddress, uint256 borrowAmount)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        if (collectionAddress == address(0)) revert AddressZero();
        collectionTotalBorrowVolume[collectionAddress] += borrowAmount;
        emit CollectionBorrowVolumeUpdated(
            collectionAddress, collectionTotalBorrowVolume[collectionAddress], borrowAmount, block.timestamp
        );
    }


    function applyCollectionYieldForEpoch(address collectionAddress, uint256 epochId)
        external
        nonReentrant
        whenNotPaused
        onlyRole(ADMIN_ROLE)
    {
        if (address(epochManager) == address(0)) {
            revert("CollectionsVault: EpochManager not set");
        }
        if (collectionAddress == address(0)) {
            revert AddressZero();
        }
        if (!isCollectionRegistered[collectionAddress]) {
            revert("CollectionsVault: Collection not registered");
        }
        if (epochCollectionYieldApplied[epochId][collectionAddress]) {
            revert("CollectionsVault: Yield already applied for this collection and epoch");
        }

        uint256 totalEpochAllocation = epochYieldAllocations[epochId];
        if (totalEpochAllocation == 0) {
            epochCollectionYieldApplied[epochId][collectionAddress] = true;
            emit CollectionYieldAppliedForEpoch(
                epochId,
                collectionAddress,
                collectionRegistry.getCollection(collectionAddress).yieldSharePercentage, // Fetch from registry
                0,
                collectionVaultsData[collectionAddress].totalAssetsDeposited // Fetch from vault data
            );
            return;
        }

        _updateGlobalDepositIndex();
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];
        ICollectionRegistry.Collection memory registryCollection = collectionRegistry.getCollection(collectionAddress);

        if (registryCollection.yieldSharePercentage == 0) {
            epochCollectionYieldApplied[epochId][collectionAddress] = true;
            emit CollectionYieldAppliedForEpoch(epochId, collectionAddress, 0, 0, vaultData.totalAssetsDeposited);
            return;
        }

        uint256 collectionYieldFromEpoch = (totalEpochAllocation * registryCollection.yieldSharePercentage) / 10000;

        if (collectionYieldFromEpoch > epochYieldAllocations[epochId]) {
            revert("CollectionsVault: Allocation underflow");
        }

        if (collectionYieldFromEpoch > 0) {
            vaultData.totalAssetsDeposited += collectionYieldFromEpoch;
            totalAssetsDepositedAllCollections += collectionYieldFromEpoch;
            epochYieldAllocations[epochId] -= collectionYieldFromEpoch;
            if (totalYieldReserved >= collectionYieldFromEpoch) {
                totalYieldReserved -= collectionYieldFromEpoch;
            } else {
                totalYieldReserved = 0;
            }
        }

        epochCollectionYieldApplied[epochId][collectionAddress] = true;

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
        onlyRole(ADMIN_ROLE)
    {
        uint256 length = collectionsToReset.length;
        if (length > MAX_BATCH_SIZE) {
            revert("CollectionsVault: Batch size exceeds maximum limit");
        }
        for (uint256 i = 0; i < length;) {
            delete epochCollectionYieldApplied[epochId][collectionsToReset[i]];
            unchecked {
                ++i;
            }
        }
    }
}
