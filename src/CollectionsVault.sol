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
    uint256 public globalDepositIndex; // Represents the total value accrued per unit of principal over time
    uint256 public constant GLOBAL_DEPOSIT_INDEX_PRECISION = 1e18; // Precision for globalDepositIndex

    address[] private allCollectionAddresses;
    mapping(address => bool) private isCollectionRegistered;

    mapping(uint256 => uint256) public epochYieldAllocations;
    mapping(uint256 => mapping(address => bool)) public epochCollectionYieldApplied;

    // Temporary storage used during batch repayment to aggregate borrower amounts
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
            // Task 5: Allowance hygiene - Approve LM in constructor
            IERC20(_asset).forceApprove(_lendingManagerAddress, type(uint256).max);
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
        // Task 1: Track supply correctly
        collection.totalSharesMinted += shares;
        collection.totalCTokensMinted += shares; // Placeholder, actual cToken amount depends on LM
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
        // Task 1: Track supply correctly
        collection.totalSharesMinted += shares;
        collection.totalCTokensMinted += shares; // Placeholder, actual cToken amount depends on LM
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
        // Task 1: Track supply correctly
        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        if (collection.totalSharesMinted < shares || collection.totalCTokensMinted < shares) {
            revert ShareBalanceUnderflow();
        }
        collection.totalSharesMinted -= shares;
        collection.totalCTokensMinted -= shares; // Placeholder, actual cToken amount depends on LM

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
        // Task 1: Track supply correctly
        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        if (collection.totalSharesMinted < shares || collection.totalCTokensMinted < shares) {
            revert ShareBalanceUnderflow();
        }
        collection.totalSharesMinted -= shares;
        collection.totalCTokensMinted -= shares; // Placeholder, actual cToken amount depends on LM

        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares); // Assuming cTokenAmount is shares
        return finalAssetsToTransfer;
    }

    function transfer(address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        revert FunctionDisabledUse("transferForCollection");
    }

    function transferFrom(address from, address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        revert FunctionDisabledUse("transferForCollection");
    }

    function _hookDeposit(uint256 assets) internal virtual {
        if (assets > 0) {
            // Task 5: Allowance hygiene - Approval is now set in constructor and setLendingManager
            // IERC20 assetToken = IERC20(asset());
            // uint256 allowance = assetToken.allowance(address(this), address(lendingManager));
            // if (allowance < assets) {
            //     assetToken.forceApprove(address(lendingManager), type(uint256).max);
            // }
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

    /**
     * @notice Updates the global deposit index based on the current state of the lending manager
     *         and then accrues yield for all registered collections based on this updated index.
     */
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
    /**
     * @notice Applies the allocated yield for a specific collection for a given epoch.
     * @dev This function can only be called by an admin. It checks if the epoch exists,
     *      is in a valid state (assumed, needs EpochManager to enforce or check status),
     *      and if yield for this collection and epoch has not already been applied.
     *      It then calculates the collection's share of the epoch's allocated yield and
     *      adds it to the collection's totalAssetsDeposited.
     * @param collectionAddress The address of the collection to apply yield to.
     * @param epochId The ID of the epoch for which to apply yield.
     */
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

        // Check epoch status (e.g., Processing or Completed) - This might require EpochManager to expose status or a helper
        // For now, we assume EpochManager handles the state logic for when allocation is possible.
        // (uint256 id, , , uint256 totalYieldAvailableInEpoch, , IEpochManager.EpochStatus status) = epochManager.getEpoch(epochId);
        // if (status != IEpochManager.EpochStatus.Processing && status != IEpochManager.EpochStatus.Completed) {
        //     revert("CollectionsVault: Epoch not in Processing or Completed state");
        // }

        uint256 totalEpochAllocation = epochYieldAllocations[epochId];
        if (totalEpochAllocation == 0) {
            // No yield allocated to this epoch in the vault, or epoch doesn't exist for this vault's tracking
            // Still mark as applied to prevent re-calls for non-yielding epochs.
            epochCollectionYieldApplied[epochId][collectionAddress] = true;
            // Optionally emit an event indicating zero yield applied, or just return.
            // For consistency, we can emit with zero yield.
            emit CollectionYieldAppliedForEpoch(
                epochId,
                collectionAddress,
                collections[collectionAddress].yieldSharePercentage,
                0,
                collections[collectionAddress].totalAssetsDeposited
            );
            return;
        }

        _updateGlobalDepositIndex(); // Ensure global index is current
        _accrueCollectionYield(collectionAddress); // Accrue any passive yield first

        ICollectionsVault.Collection storage collection = collections[collectionAddress];
        if (collection.yieldSharePercentage == 0) {
            // No yield share for this collection, mark as applied.
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
}
