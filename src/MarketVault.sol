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
import {IMarketVault} from "./interfaces/IMarketVault.sol";

/**
 * @title MarketVault
 * @dev ERC4626 compliant vault for managing asset collections and distributing yield.
 * It integrates with a LendingManager to deposit and withdraw assets from an external lending protocol.
 * This contract also handles collection-specific deposits, withdrawals, and yield distribution.
 */
contract MarketVault is ERC4626, IMarketVault, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @dev Role for administrators who can pause the contract, set the lending manager, and set reward percentages.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @dev Role for the RewardsController contract, allowing it to transfer yield in batches.
    bytes32 public constant REWARDS_CONTROLLER_ROLE = keccak256("REWARDS_CONTROLLER_ROLE");

    /// @notice Address of the LendingManager contract.
    ILendingManager public lendingManager;
    /// @notice Tracks the total assets deposited by each collection.
    mapping(address => uint256) public collectionTotalAssetsDeposited;
    /// @notice Tracks the total yield transferred to each collection.
    mapping(address => uint256) public collectionYieldTransferred;
    /// @notice Stores the reward share percentage for each collection (basis points, 10000 = 100%).
    mapping(address => uint16) public collectionRewardSharePercentage;

    /**
     * @dev Emitted when yield is transferred to a specific collection.
     * @param collection The address of the collection.
     * @param amount The amount of yield transferred.
     */
    event CollectionYieldTransferred(address indexed collection, uint256 amount);

    /**
     * @notice Initializes the CollectionsVault contract.
     * @param _asset The address of the underlying ERC20 asset.
     * @param _name The name of the vault's ERC20 shares.
     * @param _symbol The symbol of the vault's ERC20 shares.
     * @param initialAdmin The address to be granted ADMIN_ROLE and DEFAULT_ADMIN_ROLE.
     * @param _lendingManagerAddress The address of the LendingManager contract, can be address(0) initially.
     */
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialAdmin,
        address _lendingManagerAddress // Can be address(0) initially
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        if (address(_asset) == address(0)) revert AddressZero(); // Asset must be valid
        if (initialAdmin == address(0)) revert AddressZero(); // Admin must be valid

        // If a lendingManagerAddress is provided at construction, validate and set it.
        // Otherwise, it's expected to be set later via setLendingManager().
        if (_lendingManagerAddress != address(0)) {
            ILendingManager tempLendingManager = ILendingManager(_lendingManagerAddress);
            // Ensure the provided lending manager's asset matches this vault's asset.
            if (address(tempLendingManager.asset()) != address(_asset)) {
                revert LendingManagerMismatch();
            }
            lendingManager = tempLendingManager;
        }

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
    }

    /**
     * @notice Sets or updates the address of the LendingManager contract.
     * @dev Only callable by an address with the ADMIN_ROLE.
     * @param _lendingManagerAddress The new address of the LendingManager contract.
     */
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

    /**
     * @notice Grants the REWARDS_CONTROLLER_ROLE to a new address.
     * @dev Only callable by an address with the ADMIN_ROLE.
     * @param newRewardsController The address to grant the REWARDS_CONTROLLER_ROLE to.
     */
    function setRewardsControllerRole(address newRewardsController) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (newRewardsController == address(0)) revert AddressZero();
        _grantRole(REWARDS_CONTROLLER_ROLE, newRewardsController);
    }

    /**
     * @notice Sets the reward share percentage for a specific collection.
     * @dev Only callable by an address with the ADMIN_ROLE.
     * The percentage is in basis points (e.g., 100 = 1%).
     * @param collectionAddress The address of the collection.
     * @param percentage The new reward share percentage in basis points.
     */
    function setCollectionRewardSharePercentage(address collectionAddress, uint16 percentage)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        if (collectionAddress == address(0)) revert AddressZero();
        collectionRewardSharePercentage[collectionAddress] = percentage;
    }

    /**
     * @notice Returns the total amount of underlying assets managed by the vault.
     * @dev This includes assets held directly by the vault and those deposited in the LendingManager.
     * @return The total amount of assets.
     */
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return super.totalAssets() + lendingManager.totalAssets();
    }

    /**
     * @notice Disables the direct ERC4626 deposit function.
     * @dev Users should use `depositForCollection` instead to associate deposits with a collection.
     * @param assets The amount of assets to deposit.
     * @param receiver The address to receive the shares.
     * @return shares The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override(ERC4626, IERC4626)
        returns (uint256 shares)
    {
        revert FunctionDisabledUse("depositForCollection");
    }

    /**
     * @notice Deposits assets into the vault on behalf of a specific collection.
     * @dev This function mints vault shares to the `receiver` and tracks the assets for the `collectionAddress`.
     * @param assets The amount of underlying assets to deposit.
     * @param receiver The address that will receive the minted shares.
     * @param collectionAddress The address of the collection associated with this deposit.
     * @return shares The amount of vault shares minted to the receiver.
     */
    function depositForCollection(uint256 assets, address receiver, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);
        collectionTotalAssetsDeposited[collectionAddress] += assets;
        emit CollectionDeposit(collectionAddress, _msgSender(), receiver, assets, shares, shares);
    }

    /**
     * @notice Disables the direct ERC4626 mint function.
     * @dev Users should use `mintForCollection` instead to associate deposits with a collection.
     * @param shares The amount of shares to mint.
     * @param receiver The address to receive the shares.
     * @return assets The amount of underlying assets required.
     */
    function mint(uint256 shares, address receiver)
        public
        virtual
        override(ERC4626, IERC4626)
        returns (uint256 assets)
    {
        revert FunctionDisabledUse("mintForCollection");
    }

    /**
     * @notice Mints a specified amount of vault shares to a receiver on behalf of a collection.
     * @dev This function calculates the required assets for the given shares and tracks them for the `collectionAddress`.
     * @param shares The amount of vault shares to mint.
     * @param receiver The address that will receive the minted shares.
     * @param collectionAddress The address of the collection associated with this mint.
     * @return assets The amount of underlying assets that were deposited to mint the shares.
     */
    function mintForCollection(uint256 shares, address receiver, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);
        collectionTotalAssetsDeposited[collectionAddress] += assets;
        emit CollectionDeposit(collectionAddress, _msgSender(), receiver, assets, shares, shares);
    }

    /**
     * @notice Disables the direct ERC4626 withdraw function.
     * @dev Users should use `withdrawForCollection` instead to track withdrawals against a collection.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address to receive the assets.
     * @param owner The address whose shares are burned.
     * @return shares The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override(ERC4626, IERC4626)
        returns (uint256 shares)
    {
        revert FunctionDisabledUse("withdrawForCollection");
    }

    /**
     * @notice Withdraws a specified amount of underlying assets from the vault on behalf of a collection.
     * @dev This function burns shares from the `owner` and transfers assets to the `receiver`.
     * It also updates the tracked assets for the `collectionAddress`.
     * @param assets The amount of underlying assets to withdraw.
     * @param receiver The address that will receive the withdrawn assets.
     * @param owner The address whose shares will be burned.
     * @param collectionAddress The address of the collection associated with this withdrawal.
     * @return shares The amount of vault shares burned.
     */
    function withdrawForCollection(uint256 assets, address receiver, address owner, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        uint256 collectionBalance = collectionTotalAssetsDeposited[collectionAddress];
        if (assets > collectionBalance) {
            revert CollectionInsufficientBalance(collectionAddress, assets, collectionBalance);
        }
        shares = previewWithdraw(assets);
        _hookWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        collectionTotalAssetsDeposited[collectionAddress] = collectionBalance - assets;
        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares);
    }

    /**
     * @notice Disables the direct ERC4626 redeem function.
     * @dev Users should use `redeemForCollection` instead to track redemptions against a collection.
     * @param shares The amount of shares to redeem.
     * @param receiver The address to receive the assets.
     * @param owner The address whose shares are burned.
     * @return assets The amount of underlying assets withdrawn.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override(ERC4626, IERC4626)
        returns (uint256 assets)
    {
        revert FunctionDisabledUse("redeemForCollection");
    }

    /**
     * @notice Redeems a specified amount of vault shares for underlying assets on behalf of a collection.
     * @dev This function burns shares from the `owner` and transfers assets to the `receiver`.
     * It also updates the tracked assets for the `collectionAddress`.
     * Handles dust remaining in the LendingManager during full redemptions.
     * @param shares The amount of vault shares to burn.
     * @param receiver The address that will receive the underlying assets.
     * @param owner The address whose shares will be burned.
     * @param collectionAddress The address of the collection associated with this redemption.
     */
    function redeemForCollection(uint256 shares, address receiver, address owner, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        uint256 _totalSupply = totalSupply();
        assets = previewRedeem(shares);
        if (assets == 0) {
            require(shares == 0, "ERC4626: redeem rounds down to zero assets");
        }
        uint256 collectionBalance = collectionTotalAssetsDeposited[collectionAddress];
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
        collectionTotalAssetsDeposited[collectionAddress] = collectionBalance - assets;
        emit CollectionWithdraw(collectionAddress, _msgSender(), receiver, assets, shares, shares);
        return finalAssetsToTransfer;
    }

    /**
     * @dev Internal hook called after a deposit to transfer assets to the LendingManager.
     * @param assets The amount of assets to deposit into the LendingManager.
     */
    function _hookDeposit(uint256 assets) internal virtual {
        if (assets > 0) {
            IERC20 assetToken = IERC20(asset());
            assetToken.forceApprove(address(lendingManager), assets);
            bool success = lendingManager.depositToLendingProtocol(assets);
            assetToken.forceApprove(address(lendingManager), 0);
            if (!success) revert LendingManagerDepositFailed();
        }
    }

    /**
     * @dev Internal hook called before a withdrawal to ensure sufficient assets are available.
     * If the vault's direct balance is insufficient, it attempts to withdraw from the LendingManager.
     * @param assets The amount of assets required for the withdrawal.
     */
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

    /**
     * @notice Validates if a yield redemption amount for a collection is within allowed limits
     * @dev Ensures the amount doesn't exceed the collection's share of available yield
     * @param collection The collection address
     * @param requestedAmount The amount being requested
     * @return isValid Whether the requested amount is valid
     * @return maxAllowed The maximum allowed amount for this collection
     */
    function _validateYieldAmount(address collection, uint256 requestedAmount)
        internal
        view
        returns (bool isValid, uint256 maxAllowed)
    {
        // Get collection's reward share percentage (out of 10000)
        uint16 rewardSharePercentage = collectionRewardSharePercentage[collection];

        // If percentage is 0, collection can't claim any yield
        if (rewardSharePercentage == 0) {
            return (requestedAmount == 0, 0);
        }

        // Calculate total available yield in the system (totalAssets - totalPrincipal)
        uint256 totalPrincipal = lendingManager.totalPrincipalDeposited();
        uint256 lmTotalAssets = lendingManager.totalAssets();

        // Calculate total yield available (can't be negative)
        uint256 totalYield = lmTotalAssets > totalPrincipal ? lmTotalAssets - totalPrincipal : 0;

        // Calculate collection's max allowed share of yield
        uint256 collectionYieldShare = (totalYield * rewardSharePercentage) / 10000;

        // Account for yield already transferred to this collection
        uint256 alreadyTransferred = collectionYieldTransferred[collection];
        maxAllowed = collectionYieldShare > alreadyTransferred ? collectionYieldShare - alreadyTransferred : 0;

        return (requestedAmount <= maxAllowed, maxAllowed);
    }

    /**
     * @notice Transfer accrued base yield for multiple collections in a single batch to a recipient.
     * @param collections Array of collection addresses (for logging/tracking, not used in core logic).
     * @param amounts Array of yield token amounts to transfer per collection.
     * @param totalAmount The total sum of amounts to transfer.
     * @param recipient Recipient address.
     */
    /**
     * @notice Transfers accrued base yield for multiple collections in a single batch to a recipient.
     * @dev Only callable by an address with the REWARDS_CONTROLLER_ROLE.
     * Validates each collection's yield amount against its allowed share.
     * @param collections Array of collection addresses for which yield is being transferred.
     * @param amounts Array of yield token amounts to transfer for each corresponding collection.
     * @param totalAmount The total sum of all amounts to transfer in this batch.
     * @param recipient The address to receive the total transferred yield.
     */
    function transferYieldBatch(
        address[] calldata collections,
        uint256[] calldata amounts,
        uint256 totalAmount,
        address recipient
    ) external onlyRole(REWARDS_CONTROLLER_ROLE) whenNotPaused {
        if (collections.length != amounts.length) {
            revert FunctionDisabledUse("transferYieldBatch");
        }

        // Validate that we have sufficient balance for the entire batch transfer
        uint256 availableBalance = IERC20(asset()).balanceOf(address(this));
        if (availableBalance < totalAmount) {
            revert CollectionInsufficientBalance(
                address(0), // Using address(0) to indicate this is for the entire batch
                totalAmount,
                availableBalance
            );
        }

        // Validate the amounts sum up to totalAmount
        uint256 calculatedTotal = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            calculatedTotal += amounts[i];
        }
        require(calculatedTotal == totalAmount, "Amounts sum mismatch");

        // Validate and update collection balances without transferring assets yet
        for (uint256 i = 0; i < collections.length; i++) {
            address collection = collections[i];
            uint256 amount = amounts[i];

            // Skip collections with zero amount
            if (amount == 0) continue;

            // Validate the yield amount doesn't exceed collection's allowed share
            (bool isValidAmount, uint256 maxAllowed) = _validateYieldAmount(collection, amount);
            if (!isValidAmount) {
                revert ExcessiveYieldAmount(collection, amount, maxAllowed);
            }

            // Update collection yield tracking
            collectionYieldTransferred[collection] += amount;
            collectionTotalAssetsDeposited[collection] -= amount;

            // Emit an event for this collection's yield transfer
            emit CollectionYieldTransferred(collection, amount);
        }

        // Perform a single transfer for the total amount
        if (totalAmount > 0) {
            // Use the internal function to redeem and transfer yield
            _redeemYieldFromLandingManager(recipient, totalAmount);

            // Emit a batch transfer event
            emit YieldBatchTransferred(totalAmount, recipient);
        }
    }

    /**
     * @dev Internal function to redeem and transfer yield from the LendingManager to a recipient.
     * @param recipient The address to receive the redeemed yield.
     * @param amount The amount of yield to redeem and transfer.
     */
    function _redeemYieldFromLandingManager(address recipient, uint256 amount) internal {
        if (recipient == address(0)) revert AddressZero();
        if (amount == 0) return;

        // Determine how much we need to withdraw from the lending manager
        IERC20 assetToken = IERC20(asset());
        uint256 vaultBalance = assetToken.balanceOf(address(this));

        // If we don't have enough in the vault, we need to redeem from the lending manager
        if (vaultBalance < amount) {
            uint256 amountToRedeem = amount - vaultBalance;

            // Make sure the lending manager has enough assets
            uint256 availableInLM = lendingManager.totalAssets();
            if (availableInLM < amountToRedeem) {
                revert InsufficientBalanceInProtocol();
            }

            // Withdraw from lending manager
            bool success = lendingManager.withdrawFromLendingProtocol(amountToRedeem);
            if (!success) revert LendingManagerWithdrawFailed();

            // Verify we have enough balance after withdrawal
            uint256 balanceAfterWithdraw = assetToken.balanceOf(address(this));
            if (balanceAfterWithdraw < amount) {
                revert Vault_InsufficientBalancePostLMWithdraw();
            }
        }

        // Transfer assets to recipient
        assetToken.safeTransfer(recipient, amount);
    }

    // --- Pausable Functions ---

    /**
     * @notice Pauses the contract.
     * @dev This function can only be called by an address with the ADMIN_ROLE.
     * All pausable functions will revert when the contract is paused.
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev This function can only be called by an address with the ADMIN_ROLE.
     * All pausable functions will resume normal operation when unpaused.
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
