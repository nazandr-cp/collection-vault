// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin-contracts-5.2.0/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/utils/SafeERC20.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";

/**
 * @title ERC4626Vault
 * @notice An ERC-4626 compliant vault that delegates asset management to a LendingManager.
 * @dev Uses OpenZeppelin's ERC4626 implementation as a base.
 *      Asset deposit/withdrawal logic is handled by an external LendingManager contract.
 *      Overrides deposit and withdraw to interact with the LendingManager.
 */
contract ERC4626Vault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    // --- State --- //
    ILendingManager public immutable lendingManager;

    // --- Errors --- //
    error LendingManagerDepositFailed();
    error LendingManagerWithdrawFailed();
    error LendingManagerMismatch();
    error WithdrawInsufficientBalance();

    // --- Constructor --- //

    /**
     * @param _asset The underlying ERC20 token managed by this vault.
     * @param _name The name for the vault share ERC20 token.
     * @param _symbol The symbol for the vault share ERC20 token.
     * @param _initialOwner The owner of this vault contract.
     * @param _lendingManagerAddress The address of the LendingManager contract.
     */
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _initialOwner,
        address _lendingManagerAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) Ownable(_initialOwner) {
        require(_lendingManagerAddress != address(0), "Zero lending manager address");
        require(address(_asset) != address(0), "Zero asset address");

        lendingManager = ILendingManager(_lendingManagerAddress);

        if (lendingManager.asset() != _asset) {
            revert LendingManagerMismatch();
        }

        // Approve the Lending Manager to spend the vault's assets
        _asset.approve(_lendingManagerAddress, type(uint256).max);
    }

    // --- ERC4626 Overrides --- //

    /**
     * @notice Calculates the total amount of underlying assets managed by the vault.
     * @dev Overrides the default ERC4626 implementation to query the LendingManager
     *      for the total underlying balance, including principal and yield.
     * @return The total underlying assets held via the LendingManager.
     */
    function totalAssets() public view override returns (uint256) {
        return lendingManager.totalAssets();
    }

    /**
     * @notice Deposits `assets` amount of underlying tokens and grants `receiver` shares.
     * @dev Overrides to deposit assets into the LendingManager *after* minting shares.
     * @param assets Amount of underlying asset to deposit.
     * @param receiver Address that will receive the shares.
     * @return shares Amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        // Call base deposit function first to handle checks and mint shares
        shares = super.deposit(assets, receiver);

        // If assets > 0 and shares were minted, deposit to LendingManager
        if (assets > 0) {
            // Assets should now be held by this contract after super.deposit call
            uint256 balanceAfterSuper = IERC20(asset()).balanceOf(address(this));
            require(balanceAfterSuper >= assets, "Vault: Inconsistent state after deposit"); // Sanity check

            // PUSH assets from vault to LM using safeTransfer (reverts on failure)
            IERC20(asset()).safeTransfer(address(lendingManager), assets);

            // Inform the lending manager about the deposit *after* successful transfer
            // This call now implicitly assumes the transfer succeeded.
            bool reportedSuccess = lendingManager.depositToLendingProtocol(assets);
            if (!reportedSuccess) {
                // Handle case where LM rejects the deposit notification (e.g., capacity reached)
                // This might require reverting the transfer and the share minting. Complex.
                // Revert with the generic error, which implies LM failed deposit step.
                revert LendingManagerDepositFailed();
            }
        }
        // Event Emission is handled by super.deposit
        return shares;
    }

    /**
     * @notice Withdraws `assets` amount of underlying tokens by burning shares from `owner`
     * @dev Overrides to withdraw assets from the LendingManager *before* burning shares.
     * @param assets Amount of underlying asset to withdraw.
     * @param receiver Address that will receive the underlying asset.
     * @param owner Address from which shares are burned.
     * @return shares Amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        // --- Pre-Withdraw Hook Logic ---
        if (assets > 0) {
            // How many assets does the vault hold directly?
            uint256 directBalance = IERC20(asset()).balanceOf(address(this));

            // How many assets are available in total (via LM)?
            uint256 totalAvailable = totalAssets();

            // Calculate required shares *before* potentially withdrawing from LM
            // This ensures we use the correct pre-withdrawal exchange rate.
            shares = previewWithdraw(assets);

            // Check if the owner has enough shares FIRST (standard ERC4626 check)
            // This check is implicitly done in super.withdraw, but we might need it earlier.
            // require(balanceOf[owner] >= shares, "ERC4626: withdraw exceeds balance"); // Replicated check

            // Check if the requested asset amount is available in the system
            if (totalAvailable < assets) {
                revert WithdrawInsufficientBalance(); // Use a specific error
            }

            // Do we need to pull funds from the Lending Manager?
            if (directBalance < assets) {
                uint256 amountToWithdrawFromLM = assets - directBalance;

                // Request withdrawal from LendingManager
                bool success = lendingManager.withdrawFromLendingProtocol(amountToWithdrawFromLM);
                if (!success) {
                    revert LendingManagerWithdrawFailed();
                }

                // Sanity check: Vault should now have enough direct balance
                uint256 balanceAfterLMWithdraw = IERC20(asset()).balanceOf(address(this));
                require(balanceAfterLMWithdraw >= assets, "Vault: Insufficient balance post-LM withdraw");
            }
        } else {
            // If assets == 0, previewWithdraw would return 0 shares
            shares = 0;
        }
        // --- End Pre-Withdraw Hook Logic ---

        // Call base withdraw function to handle burning shares and transferring assets
        // Note: super.withdraw recalculates shares based on the state *after* we potentially withdrew from LM.
        // This might slightly change the number of shares burned compared to the `shares` calculated above
        // if the LM withdrawal somehow changed totalAssets significantly (e.g. fees).
        // For consistency, it might be better to rely *only* on super.withdraw's share calculation.
        // Let's stick to calling super.withdraw and letting it handle the share burning.
        shares = super.withdraw(assets, receiver, owner);

        // Event Emission is handled by super.withdraw
        return shares;
    }

    /**
     * @notice Mints `shares` amount of vault tokens and pulls `assets` amount of underlying tokens from `caller`.
     * @dev Overrides to deposit assets into the LendingManager *after* base mint operation.
     * @param shares Amount of shares to mint.
     * @param receiver Address that will receive the shares.
     * @return assets Amount of underlying assets pulled.
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        // Call base mint first. It handles checks, asset transfer (caller -> vault), and share minting.
        assets = super.mint(shares, receiver);

        // After base mint, assets are in the vault. Push them to the Lending Manager.
        if (assets > 0) {
            IERC20(asset()).safeTransfer(address(lendingManager), assets);
            bool reportedSuccess = lendingManager.depositToLendingProtocol(assets);
            if (!reportedSuccess) {
                // Revert if LM rejects the deposit notification. Base mint already occurred.
                // This leaves shares minted but assets potentially stuck if transfer failed before notification.
                // A more robust solution might require a two-phase commit or revert capability in LM.
                revert LendingManagerDepositFailed();
            }
        }
        // Event Emission is handled by super.mint
        return assets;
    }

    /**
     * @notice Burns `shares` amount of vault tokens from `owner` and sends `assets` to `receiver`.
     * @dev Overrides to withdraw assets from the LendingManager *before* base redeem operation.
     * @param shares Amount of shares to burn.
     * @param receiver Address that will receive the underlying asset.
     * @param owner Address from which shares are burned.
     * @return assets Amount of underlying assets sent.
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        // Calculate definitive asset amount based on current state BEFORE any withdrawal
        assets = previewRedeem(shares);

        // --- Pre-Withdraw Hook Logic ---
        if (assets > 0) {
            uint256 directBalance = IERC20(asset()).balanceOf(address(this));
            uint256 totalAvailable = totalAssets(); // Use overridden totalAssets
            if (totalAvailable < assets) {
                revert WithdrawInsufficientBalance();
            }
            if (directBalance < assets) {
                uint256 amountToWithdrawFromLM = assets - directBalance;
                bool success = lendingManager.withdrawFromLendingProtocol(amountToWithdrawFromLM);
                if (!success) {
                    revert LendingManagerWithdrawFailed();
                }
                uint256 balanceAfterLMWithdraw = IERC20(asset()).balanceOf(address(this));
                require(balanceAfterLMWithdraw >= assets, "Vault: Insufficient balance post-LM withdraw for redeem");
            }
        }
        // --- End Pre-Withdraw Hook Logic ---

        // Call internal burn and transfer functions directly.

        // 1. Burn the specified shares from the owner (includes allowance check)
        // The base ERC20 _burn function: _burn(address account, uint256 amount)
        // We need to handle allowance check manually if not using _spendAllowance
        if (owner != msg.sender) {
            // Allowance check only needed if caller is not owner
            uint256 currentAllowance = allowance(owner, msg.sender);
            if (currentAllowance != type(uint256).max) {
                require(currentAllowance >= shares, "ERC4626: redeem exceeds allowance");
                _approve(owner, msg.sender, currentAllowance - shares); // Consume allowance
            }
            // If allowance is max, no need to update it.
        }
        // If owner == msg.sender, no allowance check needed.

        _burn(owner, shares); // Use base ERC20 _burn

        // 2. Transfer the pre-calculated asset amount
        if (assets > 0) {
            SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);
        }

        // Emit the standard event
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return assets; // Return the pre-calculated asset amount
    }

    // --- Custom Functions (Optional) ---
    // Add any other custom logic specific to this vault if needed.
}
