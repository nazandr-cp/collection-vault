// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";

interface ICToken {
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
    function underlying() external view returns (address);
}

contract CollectionsVault is ERC4626, ICollectionsVault, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEBT_SUBSIDIZER_ROLE = keccak256("DEBT_SUBSIDIZER_ROLE");

    ILendingManager public lendingManager;
    IEpochManager public epochManager;

    mapping(address => ICollectionsVault.Collection) public collections;
    uint256 public globalDepositIndex;
    uint256 public constant GLOBAL_DEPOSIT_INDEX_PRECISION = 1e18;

    address[] private allCollectionAddresses;
    mapping(address => bool) private isCollectionRegistered;

    mapping(uint256 => uint256) public epochYieldAllocations;
    mapping(uint256 => mapping(address => bool)) public epochCollectionYieldApplied;

    mapping(address => uint256) private _tempAggregatedAmounts;
    address[] private _tempBorrowers;

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialAdmin,
        address _lendingManagerAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        if (address(_asset) == address(0)) revert AddressZero();
        if (initialAdmin == address(0)) revert AddressZero();

        if (_lendingManagerAddress != address(0)) {
            ILendingManager tempLendingManager = ILendingManager(_lendingManagerAddress);
            if (address(tempLendingManager.asset()) != address(_asset)) {
                revert LendingManagerMismatch();
            }
            lendingManager = tempLendingManager;
            IERC20(_asset).forceApprove(_lendingManagerAddress, type(uint256).max);
        }

        globalDepositIndex = GLOBAL_DEPOSIT_INDEX_PRECISION;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
    }

    function _updateGlobalDepositIndex() internal {
        if (address(lendingManager) == address(0)) return;
        uint256 totalPrincipal = lendingManager.totalPrincipalDeposited();
        if (totalPrincipal == 0) {
            return;
        }
        uint256 currentTotalAssets = lendingManager.totalAssets();
        uint256 newIndex = (currentTotalAssets * GLOBAL_DEPOSIT_INDEX_PRECISION) / totalPrincipal;
        if (newIndex > globalDepositIndex) {
            globalDepositIndex = newIndex;
        }
        // If newIndex is less, it implies a loss or principal withdrawal not reflected.
    }

    function _accrueCollectionYield(address collectionAddress) internal {
        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        if (!isCollectionRegistered[collectionAddress] || collection.collectionAddress == address(0)) {
            return;
        }

        if (collection.yieldSharePercentage == 0) {
            collection.lastGlobalDepositIndex = globalDepositIndex;
            return;
        }

        uint256 lastIndex = collection.lastGlobalDepositIndex;
        if (globalDepositIndex > lastIndex) {
            uint256 accruedRatio = globalDepositIndex - lastIndex;
            uint256 yieldAccrued = (collection.totalAssetsDeposited * accruedRatio * collection.yieldSharePercentage)
                / (GLOBAL_DEPOSIT_INDEX_PRECISION * 10000);

            if (yieldAccrued > 0) {
                collection.totalAssetsDeposited += yieldAccrued;
                emit CollectionYieldAccrued(
                    collectionAddress, yieldAccrued, collection.totalAssetsDeposited, globalDepositIndex, lastIndex
                );
            }
        }
        collection.lastGlobalDepositIndex = globalDepositIndex;
    }

    function _registerCollectionAddressIfNeeded(address collectionAddress) private {
        if (!isCollectionRegistered[collectionAddress]) {
            isCollectionRegistered[collectionAddress] = true;
            allCollectionAddresses.push(collectionAddress);

            ICollectionsVault.Collection storage collection = collections[collectionAddress];
            if (collection.collectionAddress == address(0)) {
                collection.collectionAddress = collectionAddress;
                if (collection.lastGlobalDepositIndex == 0) {
                    collection.lastGlobalDepositIndex = globalDepositIndex;
                }
            }
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

    function setCollectionYieldSharePercentage(address collectionAddress, uint16 percentage)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        if (collectionAddress == address(0)) revert AddressZero();
        _updateGlobalDepositIndex(); // Update global index first
        _registerCollectionAddressIfNeeded(collectionAddress); // Register before accruing or setting percentage
        _accrueCollectionYield(collectionAddress); // Accrue any pending yield with old percentage

        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        collection.yieldSharePercentage = percentage;
    }

    function collectionTotalAssetsDeposited(address collectionAddress) public view override returns (uint256) {
        ICollectionsVault.Collection memory collection = collections[collectionAddress];
        if (
            collection.collectionAddress == address(0) || collection.yieldSharePercentage == 0
                || globalDepositIndex <= collection.lastGlobalDepositIndex
        ) {
            return collection.totalAssetsDeposited;
        }

        uint256 accruedRatio = globalDepositIndex - collection.lastGlobalDepositIndex;
        uint256 potentialYieldAccrued = (
            collection.totalAssetsDeposited * accruedRatio * collection.yieldSharePercentage
        ) / (GLOBAL_DEPOSIT_INDEX_PRECISION * 10000);

        return collection.totalAssetsDeposited + potentialYieldAccrued;
    }

    function collectionYieldTransferred(address collectionAddress) public view override returns (uint256) {
        return collections[collectionAddress].totalYieldTransferred;
    }

    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return super.totalAssets() + lendingManager.totalAssets();
    }

    function deposit(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("depositForCollection");
    }

    function depositForCollection(uint256 assets, address receiver, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        _updateGlobalDepositIndex();
        _registerCollectionAddressIfNeeded(collectionAddress);
        _accrueCollectionYield(collectionAddress);

        ICollectionsVault.Collection storage collection = collections[collectionAddress];

        shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);

        collection.totalAssetsDeposited += assets;
        collection.totalSharesMinted += shares;
        collection.totalCTokensMinted += shares;
        emit CollectionDeposit(collectionAddress, _msgSender(), receiver, assets, shares, shares);
    }

    function mint(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("mintForCollection");
    }

    function mintForCollection(uint256 shares, address receiver, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        _updateGlobalDepositIndex();
        _registerCollectionAddressIfNeeded(collectionAddress); // Ensure registered before accruing
        _accrueCollectionYield(collectionAddress); // Accrue yield before mint

        ICollectionsVault.Collection storage collection = collections[collectionAddress];

        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);

        collection.totalAssetsDeposited += assets;
        collection.totalSharesMinted += shares;
        collection.totalCTokensMinted += shares;
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
        returns (uint256 shares)
    {
        _updateGlobalDepositIndex();
        _accrueCollectionYield(collectionAddress); // Accrue yield before withdrawal

        uint256 currentCollectionTotalAssets = collections[collectionAddress].totalAssetsDeposited;
        if (assets > currentCollectionTotalAssets) {
            revert CollectionInsufficientBalance(collectionAddress, assets, currentCollectionTotalAssets);
        }

        shares = previewWithdraw(assets);
        _hookWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        collections[collectionAddress].totalAssetsDeposited = currentCollectionTotalAssets - assets;
        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        if (collection.totalSharesMinted < shares || collection.totalCTokensMinted < shares) {
            revert ShareBalanceUnderflow();
        }
        collection.totalSharesMinted -= shares;
        collection.totalCTokensMinted -= shares;

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
        returns (uint256 assets)
    {
        _updateGlobalDepositIndex();
        _accrueCollectionYield(collectionAddress); // Accrue yield before redeem

        uint256 currentCollectionTotalAssets = collections[collectionAddress].totalAssetsDeposited;

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
            if (remainingDustInLM > 0) {
                uint256 redeemedDust = lendingManager.redeemAllCTokens(address(this));
                finalAssetsToTransfer += redeemedDust;
            }
        }

        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        if (vaultBalance < finalAssetsToTransfer) {
            revert Vault_InsufficientBalancePostLMWithdraw();
        }
        SafeERC20.safeTransfer(IERC20(asset()), receiver, finalAssetsToTransfer);
        emit Withdraw(msg.sender, receiver, owner, finalAssetsToTransfer, shares);

        if (assets <= currentCollectionTotalAssets) {
            collections[collectionAddress].totalAssetsDeposited = currentCollectionTotalAssets - assets;
        } else {
            collections[collectionAddress].totalAssetsDeposited = 0;
        }
        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        if (collection.totalSharesMinted < shares || collection.totalCTokensMinted < shares) {
            revert ShareBalanceUnderflow();
        }
        collection.totalSharesMinted -= shares;
        collection.totalCTokensMinted -= shares;

        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares);
        return finalAssetsToTransfer;
    }

    function transfer(address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert FunctionDisabledUse("transferForCollection");
    }

    function transferFrom(address, address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        revert FunctionDisabledUse("transferForCollection");
    }

    function transferForCollection(address to, uint256 amount, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (bool)
    {
        if (to == address(0)) revert AddressZero();
        if (amount == 0) return true;

        _updateGlobalDepositIndex();
        _accrueCollectionYield(collectionAddress);

        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        if (!isCollectionRegistered[collectionAddress]) {
            revert CollectionNotRegistered(collectionAddress);
        }

        uint256 currentCollectionTotalAssets = collectionTotalAssetsDeposited(collectionAddress);
        if (amount > currentCollectionTotalAssets) {
            revert CollectionInsufficientBalance(collectionAddress, amount, currentCollectionTotalAssets);
        }

        _transfer(msg.sender, to, amount);
        emit Transfer(msg.sender, to, amount);

        collection.totalAssetsDeposited -= amount;
        if (collection.totalSharesMinted < amount || collection.totalCTokensMinted < amount) {
            revert ShareBalanceUnderflow();
        }
        collection.totalSharesMinted -= amount;
        collection.totalCTokensMinted -= amount;

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
            if (neededFromLM <= availableInLM) {
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

    function _validateYieldAmount(address collection, uint256 requestedAmount)
        internal
        view
        returns (bool isValid, uint256 maxAllowed)
    {
        ICollectionsVault.Collection memory collectionData = collections[collection];

        if (collectionData.yieldSharePercentage == 0) {
            return (requestedAmount == 0, 0);
        }

        // Calculate total available yield for this collection using index-based approach
        uint256 currentCollectionAssets = collectionTotalAssetsDeposited(collection);
        uint256 originalDeposit = collectionData.totalAssetsDeposited;

        // Available yield is the difference between current accrued assets and original deposit
        uint256 availableYield =
            currentCollectionAssets > originalDeposit ? currentCollectionAssets - originalDeposit : 0;

        // Calculate shared yield (already transferred to borrowers or other purposes)
        uint256 sharedYield = collectionData.totalYieldTransferred;

        // Max allowed is available yield minus what has already been shared/transferred
        maxAllowed = availableYield > sharedYield ? availableYield - sharedYield : 0;

        return (requestedAmount <= maxAllowed, maxAllowed);
    }

    function repayBorrowBehalfBatch(
        address[] calldata collectionAddresses,
        uint256[] calldata amounts,
        address[] calldata borrowers,
        uint256 totalAmount
    ) external onlyRole(DEBT_SUBSIDIZER_ROLE) whenNotPaused nonReentrant {
        uint256 numEntries = borrowers.length;
        if (numEntries != amounts.length || numEntries != collectionAddresses.length) {
            revert("CollectionsVault: Array lengths mismatch");
        }

        if (totalAmount == 0) {
            return;
        }

        _updateGlobalDepositIndex();

        for (uint256 i = 0; i < numEntries; i++) {
            if (amounts[i] == 0) continue;

            address collectionAddress = collectionAddresses[i];
            uint256 amount = amounts[i];

            _accrueCollectionYield(collectionAddress);

            (bool isValid, uint256 maxAllowed) = _validateYieldAmount(collectionAddress, amount);
            if (!isValid) {
                revert ExcessiveYieldAmount(collectionAddress, amount, maxAllowed);
            }
        }

        _hookWithdraw(totalAmount);

        IERC20 assetToken = IERC20(asset());
        assetToken.forceApprove(address(lendingManager), totalAmount);
        delete _tempBorrowers;

        for (uint256 i = 0; i < numEntries;) {
            uint256 amt = amounts[i];
            if (amt != 0) {
                address borrowerAddr = borrowers[i];
                if (_tempAggregatedAmounts[borrowerAddr] == 0) {
                    _tempBorrowers.push(borrowerAddr);
                }
                _tempAggregatedAmounts[borrowerAddr] += amt;
            }
            unchecked {
                ++i;
            }
        }

        uint256 actualTotalRepaid = 0;
        uint256 borrowersLength = _tempBorrowers.length;
        for (uint256 i = 0; i < borrowersLength;) {
            address borrower = _tempBorrowers[i];
            uint256 repayAmountForThisBorrower = _tempAggregatedAmounts[borrower];

            uint256 lmError = lendingManager.repayBorrowBehalf(borrower, repayAmountForThisBorrower);

            if (lmError != 0) {
                revert("CollectionsVault: Repay borrow behalf failed via LendingManager");
            }
            actualTotalRepaid += repayAmountForThisBorrower;

            delete _tempAggregatedAmounts[borrower];
            unchecked {
                ++i;
            }
        }

        delete _tempBorrowers;

        for (uint256 i = 0; i < numEntries; i++) {
            if (amounts[i] == 0) continue;

            address collectionAddress = collectionAddresses[i];
            uint256 amount = amounts[i];

            collections[collectionAddress].totalYieldTransferred += amount;
        }

        assetToken.forceApprove(address(lendingManager), 0);
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
        emit VaultYieldAllocatedToEpoch(epochId, amount);
    }

    function getEpochYieldAllocated(uint256 epochId) external view returns (uint256 amount) {
        return epochYieldAllocations[epochId];
    }

    function totalCollectionYieldShareBps() public view returns (uint16 totalBps) {
        uint256 length = allCollectionAddresses.length;
        for (uint256 i = 0; i < length;) {
            totalBps += collections[allCollectionAddresses[i]].yieldSharePercentage;
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

    // Task 3: Apply epoch yield
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
                collections[collectionAddress].yieldSharePercentage,
                0,
                collections[collectionAddress].totalAssetsDeposited
            );
            return;
        }

        _updateGlobalDepositIndex();
        _accrueCollectionYield(collectionAddress);

        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        if (collection.yieldSharePercentage == 0) {
            epochCollectionYieldApplied[epochId][collectionAddress] = true;
            emit CollectionYieldAppliedForEpoch(epochId, collectionAddress, 0, 0, collection.totalAssetsDeposited);
            return;
        }

        uint256 collectionYieldFromEpoch = (totalEpochAllocation * collection.yieldSharePercentage) / 10000;

        if (collectionYieldFromEpoch > epochYieldAllocations[epochId]) {
            revert("CollectionsVault: Allocation underflow");
        }

        if (collectionYieldFromEpoch > 0) {
            collection.totalAssetsDeposited += collectionYieldFromEpoch;
            epochYieldAllocations[epochId] -= collectionYieldFromEpoch;
        }

        epochCollectionYieldApplied[epochId][collectionAddress] = true;

        emit CollectionYieldAppliedForEpoch(
            epochId,
            collectionAddress,
            collection.yieldSharePercentage,
            collectionYieldFromEpoch,
            collection.totalAssetsDeposited
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
