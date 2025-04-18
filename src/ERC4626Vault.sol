// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";

/**
 * @title ERC4626Vault
 * @notice ERC-4626 compliant vault delegating asset management to a LendingManager.
 * @dev Uses OpenZeppelin ERC4626 and AccessControl. Overrides _hookDeposit and _hookWithdraw for LendingManager integration.
 */
contract ERC4626Vault is
    ERC4626,
    AccessControl // Inherit AccessControl for role management
{
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role for administrative actions within the vault.

    ILendingManager public immutable lendingManager;

    /// @notice Reverts if depositToLendingProtocol call to LendingManager fails.
    error LendingManagerDepositFailed();
    /// @notice Reverts if withdrawFromLendingProtocol call from LendingManager fails.
    error LendingManagerWithdrawFailed();
    /// @notice Reverts if LendingManager asset does not match vault asset.
    error LendingManagerMismatch();
    /// @notice Reverts if a critical address is zero during deployment.
    error AddressZero();
    /// @notice Reverts if vault asset balance is insufficient after LendingManager withdrawal.
    error Vault_InsufficientBalancePostLMWithdraw();

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialAdmin, // Address to grant initial admin roles.
        address _lendingManagerAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        // Validate constructor arguments: critical addresses must not be zero.
        if (_lendingManagerAddress == address(0)) revert AddressZero();
        if (address(_asset) == address(0)) revert AddressZero();
        if (initialAdmin == address(0)) revert AddressZero();

        lendingManager = ILendingManager(_lendingManagerAddress);

        // Ensure LendingManager's asset matches vault asset.
        if (address(lendingManager.asset()) != address(_asset)) {
            revert LendingManagerMismatch();
        }

        // Grant initial admin roles.
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);

        // Grant infinite approval to LendingManager for the asset.
        IERC20 assetToken = IERC20(asset());
        // No need to check return value; non-standard tokens might not return bool, SafeERC20.safeApprove is deprecated.
        // Reverts internally on failure for standard tokens.
        assetToken.approve(_lendingManagerAddress, type(uint256).max);
    }

    /**
     * @notice Get total underlying assets managed by the vault, including those held by LendingManager.
     * @dev Overrides totalAssets to sum vault and LendingManager assets.
     * @return Total underlying assets managed by the vault.
     */
    function totalAssets() public view override returns (uint256) {
        // `super.totalAssets()` returns `asset.balanceOf(address(this))`.
        // We add the assets managed externally by the Lending Manager.
        return super.totalAssets() + lendingManager.totalAssets();
    }

    /**
     * @notice Deposit assets into the vault, minting shares for the receiver.
     * @dev Overrides deposit. Calls _hookDeposit after base logic.
     */
    function deposit(uint256 assets, address recipient) public virtual override returns (uint256 shares) {
        shares = super.deposit(assets, recipient); // Perform standard ERC4626 deposit
        _hookDeposit(assets); // Delegate assets to Lending Manager
    }

    /**
     * @notice Mint shares for the recipient by depositing required assets.
     * @dev Overrides mint. Calls _hookDeposit after base logic.
     */
    function mint(uint256 shares, address recipient) public virtual override returns (uint256 assets) {
        assets = super.mint(shares, recipient); // Perform standard ERC4626 mint
        _hookDeposit(assets); // Delegate deposited assets to Lending Manager
    }

    /**
     * @notice Withdraw assets from the vault by burning shares from the owner.
     * @dev Overrides withdraw. Calls _hookWithdraw before base logic.
     * Removed owner check to allow standard ERC4626 allowance mechanism.
     */
    function withdraw(uint256 assets, address recipient, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        // Removed check: `if (msg.sender != owner)` to allow standard ERC4626 allowance behavior.
        // The base ERC4626 implementation correctly handles allowances.
        _hookWithdraw(assets); // Ensure vault has enough assets locally, potentially pulling from LM.
        shares = super.withdraw(assets, recipient, owner); // Perform standard ERC4626 withdraw.
    }

    /**
     * @notice Redeem shares from the owner, transferring assets to the recipient.
     * @dev Overrides redeem. Calls _hookWithdraw before base logic.
     * Removed owner check to allow standard ERC4626 allowance mechanism.
     */
    function redeem(uint256 shares, address recipient, address owner)
        public
        virtual
        override
        returns (uint256 assets)
    {
        uint256 assetsToWithdraw = previewRedeem(shares); // Determine assets needed for the redemption.
        _hookWithdraw(assetsToWithdraw); // Ensure vault has enough assets locally, potentially pulling from LM.
        assets = super.redeem(shares, recipient, owner); // Perform standard ERC4626 redeem.
    }

    /**
     * @notice Internal hook after assets are received by the vault (deposit or mint).
     * @dev Delegates assets to LendingManager via depositToLendingProtocol.
     * @param assets Amount of assets received.
     */
    function _hookDeposit(uint256 assets) internal virtual {
        if (assets > 0) {
            bool success = lendingManager.depositToLendingProtocol(assets);
            if (!success) {
                revert LendingManagerDepositFailed();
            }
        }
    }

    /**
     * @notice Internal hook before assets are sent out by the vault (withdraw or redeem).
     * @dev Ensures vault holds enough assets; pulls from LendingManager if needed.
     * @param assets Amount of assets required.
     */
    function _hookWithdraw(uint256 assets) internal virtual {
        if (assets == 0) {
            return; // No assets requested, nothing to do.
        }

        // Check the vault's current balance of the underlying asset.
        IERC20 assetToken = IERC20(asset()); // Cache asset token instance
        uint256 directBalance = assetToken.balanceOf(address(this));

        // If the vault doesn't have enough assets locally...
        if (directBalance < assets) {
            uint256 neededFromLM = assets - directBalance; // Calculate the shortfall.
            uint256 availableInLM = lendingManager.totalAssets(); // Check how much is available in the LM.

            if (neededFromLM > availableInLM) {
                return;
            }

            // Request the Lending Manager to send the needed assets back to this vault contract.
            bool success = lendingManager.withdrawFromLendingProtocol(neededFromLM);
            if (!success) {
                revert LendingManagerWithdrawFailed(); // Revert if the LM fails to send the assets.
            }

            // Sanity check: Verify the vault's balance is now sufficient after the LM withdrawal.
            // Use cached assetToken instance and read balance again.
            uint256 balanceAfterLMWithdraw = assetToken.balanceOf(address(this));
            if (balanceAfterLMWithdraw < assets) {
                // This should not happen if the LM functions correctly. Indicates a potential issue.
                revert Vault_InsufficientBalancePostLMWithdraw();
            }
        }
    }

    // --- Administrative Functions ---
    // Access-controlled functions (e.g., onlyRole(ADMIN_ROLE)) can be added here if needed.
    // Example:
    // function pause() external onlyRole(ADMIN_ROLE) { /* ... */ }

    // Note: lendingManager is immutable; cannot be changed post-deployment.
    // Role management (grant/revoke ADMIN_ROLE) is handled by DEFAULT_ADMIN_ROLE via AccessControl.
}
