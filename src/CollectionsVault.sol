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
import {EpochManager} from "./EpochManager.sol";

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
    EpochManager public epochManager;

    mapping(address => ICollectionsVault.Collection) public collections;
    uint256 public globalDepositIndex; // Represents the total value accrued per unit of principal over time
    uint256 public constant GLOBAL_DEPOSIT_INDEX_PRECISION = 1e18; // Precision for globalDepositIndex

    address[] private allCollectionAddresses;
    mapping(address => bool) private isCollectionRegistered;

    mapping(uint256 => uint256) public epochYieldAllocations;
    mapping(uint256 => mapping(address => bool)) public epochCollectionYieldApplied;

    // Temporary storage used during batch repayment to aggregate borrower amounts
    mapping(address => uint256) private _tempAggregatedAmounts;
    address[] private _tempBorrowers;

    event VaultYieldAllocatedToEpoch(uint256 indexed epochId, uint256 amount);

    event CollectionYieldAppliedForEpoch(
        uint256 indexed epochId,
        address indexed collection,
        uint16 yieldSharePercentage,
        uint256 yieldAdded,
        uint256 newTotalDeposits
    );

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
        }

        globalDepositIndex = GLOBAL_DEPOSIT_INDEX_PRECISION; // Initialize with precision

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
    }

    function _updateGlobalDepositIndex() internal {
        if (address(lendingManager) == address(0)) return;
        uint256 totalPrincipal = lendingManager.totalPrincipalDeposited();
        if (totalPrincipal == 0) {
            // If there's no principal, the index doesn't change, or could reset to precision
            // For now, let's assume it doesn't change to avoid division by zero if totalAssets is also zero.
            // If totalAssets > 0 and totalPrincipal == 0, this implies pure yield, which is an edge case.
            // A common approach is to not update index if principal is zero.
            return;
        }
        uint256 currentTotalAssets = lendingManager.totalAssets();
        // globalDepositIndex = (currentTotalAssets * GLOBAL_DEPOSIT_INDEX_PRECISION) / totalPrincipal;
        // More robust: update based on yield generated since last update
        // This requires storing lastTotalAssets and lastTotalPrincipal or similar.
        // For simplicity with current LM interface, we'll use the direct calculation.
        // Ensure it doesn't decrease if totalAssets somehow becomes less than totalPrincipal (e.g. due to losses not yet accounted for in principal)
        uint256 newIndex = (currentTotalAssets * GLOBAL_DEPOSIT_INDEX_PRECISION) / totalPrincipal;
        if (newIndex > globalDepositIndex) {
            // Index should only increase or stay same
            globalDepositIndex = newIndex;
        }
        // If newIndex is less, it implies a loss or principal withdrawal not reflected.
        // The current design assumes totalAssets >= totalPrincipalDeposited from LM.
    }

    function _accrueCollectionYield(address collectionAddress) internal {
        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        // Ensure collection is actually registered before proceeding
        if (!isCollectionRegistered[collectionAddress] || collection.collectionAddress == address(0)) {
            // This should ideally not be hit if called from a loop of registered addresses,
            // but good for safety if called directly.
            return;
        }

        if (collection.yieldSharePercentage == 0) {
            // No yield share for this collection
            collection.lastGlobalDepositIndex = globalDepositIndex; // Keep it updated
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
            // Initialize basic info if it's truly new for the 'collections' mapping
            if (collection.collectionAddress == address(0)) {
                collection.collectionAddress = collectionAddress;
                // Initialize lastGlobalDepositIndex only if it's zero (first time setup)
                // If yieldSharePercentage is set later, _accrue will handle it.
                // If deposit happens, it will also set it.
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
        epochManager = EpochManager(_epochManagerAddress);
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
        // collection.collectionAddress = collectionAddress; // Handled by _register...
        collection.yieldSharePercentage = percentage;
        // collection.lastGlobalDepositIndex will be set by _accrueCollectionYield or _register...
        // If it was new, _register set it. If existing, _accrue updated it.
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
        _registerCollectionAddressIfNeeded(collectionAddress); // Ensure registered before accruing
        _accrueCollectionYield(collectionAddress); // Accrue yield before deposit

        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        // Initialization of collection.collectionAddress and lastGlobalDepositIndex
        // is handled by _registerCollectionAddressIfNeeded if it's the first time,
        // or _accrueCollectionYield updates lastGlobalDepositIndex.

        // previewDeposit uses totalAssets(), which now needs to be accurate
        // totalAssets() internally calls ERC4626.totalAssets() + lendingManager.totalAssets()
        // The ERC4626 part is fine. The LM part is external.
        // The shares calculation depends on the current total supply of shares and total assets in the vault.
        // If individual collection deposits grow, but the shares they "own" don't change,
        // then previewDeposit might give fewer shares for the same asset amount over time,
        // which is correct as their existing "virtual" assets have grown.

        shares = previewDeposit(assets); // This should use the global totalAssets
        _deposit(msg.sender, receiver, assets, shares); // ERC4626 _deposit updates totalShares and pulls assets
        _hookDeposit(assets); // Moves assets to LM

        collection.totalAssetsDeposited += assets; // Add the new principal
        // Note: totalSharesMinted for collection is not tracked in this version of Collection struct
        emit CollectionDeposit(collectionAddress, _msgSender(), receiver, assets, shares, shares); // Assuming cTokenAmount is shares for now
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
        // Initialization handled by _registerCollectionAddressIfNeeded or _accrueCollectionYield

        assets = previewMint(shares); // Calculates assets based on global totalAssets and totalShares
        _deposit(msg.sender, receiver, assets, shares); // ERC4626 _deposit
        _hookDeposit(assets); // Moves assets to LM

        collection.totalAssetsDeposited += assets; // Add the new principal
        emit CollectionDeposit(collectionAddress, _msgSender(), receiver, assets, shares, shares); // Assuming cTokenAmount is shares
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

        uint256 currentCollectionTotalAssets = collections[collectionAddress].totalAssetsDeposited; // This is now the accrued balance
        if (assets > currentCollectionTotalAssets) {
            revert CollectionInsufficientBalance(collectionAddress, assets, currentCollectionTotalAssets);
        }

        // previewWithdraw uses totalAssets()
        shares = previewWithdraw(assets);
        _hookWithdraw(assets); // Ensure funds are in vault
        _withdraw(msg.sender, receiver, owner, assets, shares); // ERC4626 _withdraw burns shares, transfers assets

        collections[collectionAddress].totalAssetsDeposited = currentCollectionTotalAssets - assets;
        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares); // Assuming cTokenAmount is shares
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

        uint256 currentCollectionTotalAssets = collections[collectionAddress].totalAssetsDeposited; // Accrued balance

        uint256 _totalSupply = totalSupply(); // Global total supply of shares
        assets = previewRedeem(shares); // Calculates assets based on global totalAssets and totalShares

        if (assets == 0) {
            // This check is from OpenZeppelin's ERC4626 and should be fine.
            // It means the number of shares is too small to correspond to any assets.
            require(shares == 0, "ERC4626: redeem rounds down to zero assets");
        }

        // The amount of assets redeemed belongs to the share owner, not necessarily limited by one collection's deposit.
        // However, we are tracking collection deposits. If a collection's users redeem more than its tracked deposit,
        // it implies shares were transferred or the accounting is complex.
        // For now, we reduce the collection's tracked deposit by the redeemed assets,
        // but this could go negative if shares were moved between users of different "virtual" collections.
        // This model assumes shares are not moved out of a collection's users.
        // A stricter check would be:
        // if (assets > currentCollectionTotalAssets) {
        //     revert CollectionInsufficientBalance(collectionAddress, assets, currentCollectionTotalAssets);
        // }
        // However, ERC4626 allows redeeming any shares one owns. The collection tracking is an overlay.

        _hookWithdraw(assets); // Ensure funds are in vault
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares); // Burn the global shares
        emit Transfer(owner, address(0), shares);

        uint256 finalAssetsToTransfer = assets;
        bool isFullRedeem = (shares == _totalSupply && shares != 0);
        if (isFullRedeem) {
            // This part is for redeeming all assets from the vault, including dust from LM
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
        emit Withdraw(msg.sender, receiver, owner, finalAssetsToTransfer, shares); // Standard ERC4626 event

        // Update collection's tracked deposit
        // If assets > currentCollectionTotalAssets due to share transfers, this will underflow.
        // This implies the model might need refinement if shares are highly mobile across collection boundaries.
        // For now, assume shares stay within users attributed to a collection or this is an expected outcome.
        if (assets <= currentCollectionTotalAssets) {
            collections[collectionAddress].totalAssetsDeposited = currentCollectionTotalAssets - assets;
        } else {
            // This case means more assets were redeemed than the collection's tracked balance.
            // This can happen if shares were transferred from another collection's user or if the user
            // is redeeming shares that were part of the "general" pool before this collection existed.
            // Set to 0, as a collection cannot have negative deposits.
            collections[collectionAddress].totalAssetsDeposited = 0;
        }

        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares); // Assuming cTokenAmount is shares
        return finalAssetsToTransfer;
    }

    function _hookDeposit(uint256 assets) internal virtual {
        if (assets > 0) {
            IERC20 assetToken = IERC20(asset());
            uint256 allowance = assetToken.allowance(address(this), address(lendingManager));
            if (allowance < assets) {
                assetToken.forceApprove(address(lendingManager), type(uint256).max);
            }
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

        for (uint256 i = 0; i < numEntries; ) {
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
        for (uint256 i = 0; i < borrowersLength; ) {
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

    function getEpochYieldAllocated(uint256 epochId) external view returns (uint256 amount) {
        return epochYieldAllocations[epochId];
    }

    /**
     * @notice Updates the global deposit index based on the current state of the lending manager
     *         and then accrues yield for all registered collections based on this updated index.
     */
    function indexCollectionsDeposits() external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
        _updateGlobalDepositIndex();
        address[] memory collectionList = allCollectionAddresses;
        uint256 length = collectionList.length;
        for (uint256 i = 0; i < length; ) {
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
}
