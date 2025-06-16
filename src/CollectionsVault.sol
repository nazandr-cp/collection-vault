// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Roles} from "./Roles.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";

interface ICToken {
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
    function underlying() external view returns (address);
}

contract CollectionsVault is ERC4626, ICollectionsVault, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant ADMIN_ROLE = Roles.ADMIN_ROLE;
    bytes32 public constant DEBT_SUBSIDIZER_ROLE = Roles.DEBT_SUBSIDIZER_ROLE;

    ILendingManager public lendingManager;
    IEpochManager public epochManager;
    ICollectionRegistry public collectionRegistry;

    mapping(address => CollectionVaultData) public collectionVaultsData;
    uint256 public totalAssetsDepositedAllCollections;
    uint256 public totalYieldReserved;
    uint256 public globalDepositIndex;
    uint256 public constant GLOBAL_DEPOSIT_INDEX_PRECISION = 1e18;

    address[] private allCollectionAddresses;
    mapping(address => bool) private isCollectionRegistered;

    mapping(address => mapping(address => bool)) private collectionOperators;

    mapping(uint256 => uint256) public epochYieldAllocations;
    mapping(uint256 => mapping(address => bool)) public epochCollectionYieldApplied;

    modifier onlyCollectionOperator(address collection) {
        if (!collectionOperators[collection][_msgSender()]) {
            revert UnauthorizedCollectionAccess(collection, _msgSender());
        }
        _;
    }

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialAdmin,
        address _lendingManagerAddress,
        address _collectionRegistryAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) {
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

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
    }

    function _updateGlobalDepositIndex() internal {
        if (address(lendingManager) == address(0)) return;
        uint256 totalPrincipal = lendingManager.totalPrincipalDeposited();
        if (totalPrincipal == 0) {
            return;
        }
        uint256 lmAssets = lendingManager.totalAssets();
        uint256 currentTotalAssets = lmAssets > totalYieldReserved ? lmAssets - totalYieldReserved : 0;
        uint256 newIndex = (currentTotalAssets * GLOBAL_DEPOSIT_INDEX_PRECISION) / totalPrincipal;
        if (newIndex > globalDepositIndex) {
            globalDepositIndex = newIndex;
        }
    }

    function _accrueCollectionYield(address collectionAddress) internal {
        if (!isCollectionRegistered[collectionAddress]) {
            return;
        }
        ICollectionRegistry.Collection memory registryCollection = collectionRegistry.getCollection(collectionAddress);
        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];

        if (registryCollection.yieldSharePercentage == 0) {
            vaultData.lastGlobalDepositIndex = globalDepositIndex;
            return;
        }

        uint256 lastIndex = vaultData.lastGlobalDepositIndex;
        if (globalDepositIndex > lastIndex) {
            uint256 accruedRatio = globalDepositIndex - lastIndex;
            uint256 yieldAccrued = (
                vaultData.totalAssetsDeposited * accruedRatio * registryCollection.yieldSharePercentage
            ) / (GLOBAL_DEPOSIT_INDEX_PRECISION * 10000);

            if (yieldAccrued > 0) {
                vaultData.totalAssetsDeposited += yieldAccrued;
                totalAssetsDepositedAllCollections += yieldAccrued;
                emit CollectionYieldAccrued(
                    collectionAddress, yieldAccrued, vaultData.totalAssetsDeposited, globalDepositIndex, lastIndex
                );
            }
        }
        vaultData.lastGlobalDepositIndex = globalDepositIndex;
    }

    function _ensureCollectionKnownAndRegistered(address collectionAddress) private {
        if (!collectionRegistry.isRegistered(collectionAddress)) {
            revert CollectionNotRegistered(collectionAddress);
        }
        if (!isCollectionRegistered[collectionAddress]) {
            isCollectionRegistered[collectionAddress] = true;
            allCollectionAddresses.push(collectionAddress);
            collectionVaultsData[collectionAddress].lastGlobalDepositIndex = globalDepositIndex;
        }
    }

    function setLendingManager(address _lendingManagerAddress) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (_lendingManagerAddress == address(0)) revert AddressZero();
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
        if (_epochManagerAddress == address(0)) revert AddressZero();
        epochManager = IEpochManager(_epochManagerAddress);
    }

    function setDebtSubsidizer(address _debtSubsidizerAddress) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (_debtSubsidizerAddress == address(0)) revert AddressZero();
        _grantRole(DEBT_SUBSIDIZER_ROLE, _debtSubsidizerAddress);
    }

    function grantCollectionAccess(address collectionAddress, address operator) external onlyRole(ADMIN_ROLE) {
        if (collectionAddress == address(0) || operator == address(0)) revert AddressZero();
        collectionOperators[collectionAddress][operator] = true;
        emit CollectionAccessGranted(collectionAddress, operator);
    }

    function revokeCollectionAccess(address collectionAddress, address operator) external onlyRole(ADMIN_ROLE) {
        if (collectionAddress == address(0) || operator == address(0)) revert AddressZero();
        collectionOperators[collectionAddress][operator] = false;
        emit CollectionAccessRevoked(collectionAddress, operator);
    }

    function isCollectionOperator(address collectionAddress, address operator) public view returns (bool) {
        return collectionOperators[collectionAddress][operator];
    }

    function collectionTotalAssetsDeposited(address collectionAddress) public view override returns (uint256) {
        if (!isCollectionRegistered[collectionAddress]) {
            ICollectionRegistry.Collection memory registryCollectionTest =
                collectionRegistry.getCollection(collectionAddress);
            if (registryCollectionTest.collectionAddress == address(0)) return 0;
        }

        CollectionVaultData memory vaultData = collectionVaultsData[collectionAddress];
        ICollectionRegistry.Collection memory registryCollection = collectionRegistry.getCollection(collectionAddress);

        if (
            registryCollection.collectionAddress == address(0) || registryCollection.yieldSharePercentage == 0
                || globalDepositIndex <= vaultData.lastGlobalDepositIndex
        ) {
            return vaultData.totalAssetsDeposited;
        }

        uint256 accruedRatio = globalDepositIndex - vaultData.lastGlobalDepositIndex;
        uint256 potentialYieldAccrued = (
            vaultData.totalAssetsDeposited * accruedRatio * registryCollection.yieldSharePercentage
        ) / (GLOBAL_DEPOSIT_INDEX_PRECISION * 10000);

        return vaultData.totalAssetsDeposited + potentialYieldAccrued;
    }

    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return totalAssetsDepositedAllCollections;
    }

    function deposit(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("depositForCollection");
    }

    function depositForCollection(uint256 assets, address receiver, address collectionAddress)
        public
        override(ICollectionsVault)
        nonReentrant
        whenNotPaused
        onlyCollectionOperator(collectionAddress)
        returns (uint256 shares)
    {
        _updateGlobalDepositIndex();
        _ensureCollectionKnownAndRegistered(collectionAddress);
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];

        shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);

        vaultData.totalAssetsDeposited += assets;
        totalAssetsDepositedAllCollections += assets;
        vaultData.totalSharesMinted += shares;
        vaultData.totalCTokensMinted += shares;
        emit CollectionDeposit(collectionAddress, _msgSender(), receiver, assets, shares, shares);
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
        _updateGlobalDepositIndex();
        _ensureCollectionKnownAndRegistered(collectionAddress);
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];

        shares = previewDeposit(assets);
        _deposit(msg.sender, to, assets, shares);
        _hookDeposit(assets);

        vaultData.totalAssetsDeposited += assets;
        totalAssetsDepositedAllCollections += assets;
        vaultData.totalSharesMinted += shares;
        vaultData.totalCTokensMinted += shares;
        emit CollectionDeposit(collectionAddress, _msgSender(), to, assets, shares, shares);
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
        _updateGlobalDepositIndex();
        _ensureCollectionKnownAndRegistered(collectionAddress);
        _accrueCollectionYield(collectionAddress);

        CollectionVaultData storage vaultData = collectionVaultsData[collectionAddress];

        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);

        vaultData.totalAssetsDeposited += assets;
        totalAssetsDepositedAllCollections += assets;
        vaultData.totalSharesMinted += shares;
        vaultData.totalCTokensMinted += shares;
        emit CollectionDeposit(collectionAddress, _msgSender(), receiver, assets, shares, shares);
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

        uint256 _totalSupply = totalSupply();
        assets = previewRedeem(shares);

        if (assets == 0) {
            require(shares == 0, "ERC4626: redeem rounds down to zero assets");
        }

        _hookWithdraw(assets);
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        emit Transfer(owner, address(0), shares);

        uint256 finalAssetsToTransfer = assets;
        bool isFullRedeem = (shares == _totalSupply && shares != 0);
        if (isFullRedeem) {
            uint256 remainingDustInLM = lendingManager.totalAssets();
            uint256 reserve = totalYieldReserved;
            if (remainingDustInLM > reserve) {
                uint256 redeemable = remainingDustInLM - reserve;
                if (redeemable > 0) {
                    bool success = lendingManager.withdrawFromLendingProtocol(redeemable);
                    if (!success) revert LendingManagerWithdrawFailed();
                    finalAssetsToTransfer += redeemable;
                }
            }
        }

        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        if (vaultBalance < finalAssetsToTransfer) {
            revert Vault_InsufficientBalancePostLMWithdraw();
        }
        SafeERC20.safeTransfer(IERC20(asset()), receiver, finalAssetsToTransfer);
        emit Withdraw(msg.sender, receiver, owner, finalAssetsToTransfer, shares);

        uint256 deduction;
        if (assets <= currentCollectionTotalAssets) {
            vaultData.totalAssetsDeposited = currentCollectionTotalAssets - assets;
            deduction = assets;
        } else {
            deduction = currentCollectionTotalAssets;
            vaultData.totalAssetsDeposited = 0;
        }
        totalAssetsDepositedAllCollections -= deduction;
        if (vaultData.totalSharesMinted < shares || vaultData.totalCTokensMinted < shares) {
            revert ShareBalanceUnderflow();
        }
        vaultData.totalSharesMinted -= shares;
        vaultData.totalCTokensMinted -= shares;

        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares);
        return finalAssetsToTransfer;
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
            // This check is good, _ensure... would have been called by _accrue...
            revert CollectionNotRegistered(collectionAddress);
        }

        // Use collectionTotalAssetsDeposited view function which considers pending yield
        uint256 currentTotalAssetsView = collectionTotalAssetsDeposited(collectionAddress);
        if (amount > currentTotalAssetsView) {
            // Check against the view that includes potential yield
            revert CollectionInsufficientBalance(collectionAddress, amount, currentTotalAssetsView);
        }
        // However, for actual deduction, use the stored vaultData.totalAssetsDeposited
        if (amount > vaultData.totalAssetsDeposited) {
            // Double check against actual stored assets if different from view logic
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
            bool success = lendingManager.depositToLendingProtocol(assets);
            if (!success) revert LendingManagerDepositFailed();
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
            uint256 usableInLM = hasRole(DEBT_SUBSIDIZER_ROLE, _msgSender())
                ? availableInLM
                : (availableInLM > reserve ? availableInLM - reserve : 0);
            if (neededFromLM <= usableInLM) {
                if (neededFromLM > 0) {
                    bool success = lendingManager.withdrawFromLendingProtocol(neededFromLM);
                    if (!success) revert LendingManagerWithdrawFailed();
                    uint256 balanceAfterLMWithdraw = assetToken.balanceOf(address(this));
                    if (balanceAfterLMWithdraw < assets) {
                        revert Vault_InsufficientBalancePostLMWithdraw();
                    }
                }
            }
        }
    }

    function repayBorrowBehalf(uint256 amount, address borrower)
        external
        onlyRole(DEBT_SUBSIDIZER_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) return;

        _updateGlobalDepositIndex();
        _hookWithdraw(amount);

        IERC20 assetToken = IERC20(asset());
        assetToken.forceApprove(address(lendingManager), amount);

        uint256 lmError = lendingManager.repayBorrowBehalf(borrower, amount);
        if (lmError != 0) {
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
        onlyRole(DEBT_SUBSIDIZER_ROLE)
        whenNotPaused
        nonReentrant
    {
        uint256 numEntries = borrowers.length;
        if (numEntries != amounts.length) {
            revert("CollectionsVault: Array lengths mismatch");
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
                uint256 lmError = lendingManager.repayBorrowBehalf(borrowerAddr, amt);
                if (lmError != 0) {
                    revert("CollectionsVault: Repay borrow behalf failed via LendingManager");
                }
                actualTotalRepaid += amt;
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
        if (address(lendingManager) == address(0)) {
            return 0;
        }

        uint256 totalLMYield = lendingManager.totalAssets() > lendingManager.totalPrincipalDeposited()
            ? lendingManager.totalAssets() - lendingManager.totalPrincipalDeposited()
            : 0;

        if (includeNonShared) {
            return totalLMYield;
        }

        if (address(epochManager) == address(0)) {
            return 0;
        }

        uint256 currentEpochId = epochManager.getCurrentEpochId();
        if (currentEpochId == 0) {
            return 0;
        }

        uint256 allocated = epochYieldAllocations[currentEpochId];
        return totalLMYield > allocated ? totalLMYield - allocated : 0;
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

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
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
        for (uint256 i = 0; i < length;) {
            delete epochCollectionYieldApplied[epochId][collectionsToReset[i]];
            unchecked {
                ++i;
            }
        }
    }
}
