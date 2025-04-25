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
 * Adds functionality to track deposits per collection ID.
 */
contract ERC4626Vault is ERC4626, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role for administrative actions within the vault.

    ILendingManager public immutable lendingManager;

    /// @notice Mapping from collection address to total assets deposited for that collection.
    mapping(address => uint256) public collectionTotalAssetsDeposited;

    /// @notice Emitted when assets are deposited for a specific collection.
    event CollectionDeposit(
        address indexed collectionAddress,
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

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
        shares = super.deposit(assets, recipient);
        _hookDeposit(assets);
    }

    /**
     * @notice Deposit assets into the vault for a specific collection, minting shares for the receiver.
     * @param assets Amount of underlying asset to deposit.
     * @param receiver Address that will receive the shares.
     * @param collectionAddress Address of the collection associated with this deposit.
     * @return shares Amount of shares minted for the receiver.
     */
    function depositForCollection(uint256 assets, address receiver, address collectionAddress)
        public
        virtual
        returns (uint256 shares)
    {
        // Call the standard deposit function first
        shares = deposit(assets, receiver);

        // Update collection tracking
        collectionTotalAssetsDeposited[collectionAddress] += assets;
        emit CollectionDeposit(collectionAddress, msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Mint shares for the recipient by depositing required assets.
     * @dev Overrides mint. Calls _hookDeposit after base logic.
     */
    function mint(uint256 shares, address recipient) public virtual override returns (uint256 assets) {
        assets = super.mint(shares, recipient);
        _hookDeposit(assets);
    }

    /**
     * @notice Mint shares for the recipient for a specific collection by depositing required assets.
     * @param shares Amount of shares to mint.
     * @param receiver Address that will receive the shares.
     * @param collectionAddress Address of the collection associated with this deposit.
     * @return assets Amount of underlying assets required for the mint.
     */
    function mintForCollection(uint256 shares, address receiver, address collectionAddress)
        public
        virtual
        returns (uint256 assets)
    {
        // Call the standard mint function first
        assets = mint(shares, receiver);

        // Update collection tracking
        collectionTotalAssetsDeposited[collectionAddress] += assets;
        // Note: The standard mint function doesn't return shares, so we pass the input shares to the event.
        // If shares were 0, assets would also be 0 due to the internal _mint logic.
        emit CollectionDeposit(collectionAddress, msg.sender, receiver, assets, shares);
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
        _hookWithdraw(assets);
        shares = super.withdraw(assets, recipient, owner);
    }

    /**
     * @notice Redeem shares from the owner, transferring assets to the recipient.
     * @dev Overrides redeem. Calls _hookWithdraw before base logic.
     */
    function redeem(uint256 shares, address recipient, address owner)
        public
        virtual
        override
        returns (uint256 assets)
    {
        // 0. Store total supply before potential burn to check for full redemption later.
        uint256 _totalSupply = totalSupply();

        // 1. Calculate assets based on shares BEFORE the hook (potential rate change)
        assets = previewRedeem(shares);
        // Replicate OZ check: Cannot redeem 0 assets for non-zero shares.
        if (assets == 0) {
            require(shares == 0, "ERC4626: redeem rounds down to zero assets"); // Match OZ revert message
        }

        // 2. Ensure vault has enough assets locally for the initial calculated amount, pulling from LM if needed.
        _hookWithdraw(assets);

        // --- Manual Redeem Logic ---

        // 3. Check & spend allowance BEFORE burning shares
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // 4. Burn the original 'shares' amount
        _burn(owner, shares);
        emit Transfer(owner, address(0), shares);

        // 5. Check for full redeem scenario & sweep LM dust
        uint256 finalAssetsToTransfer = assets;
        bool isFullRedeem = (shares == _totalSupply && shares != 0);

        if (isFullRedeem) {
            uint256 remainingDustInLM = lendingManager.totalAssets();
            if (remainingDustInLM > 0) {
                // Withdraw the dust from LM to the vault using redeemAllCTokens
                // This calls cToken.redeem() directly, avoiding redeemUnderlying issues with tiny amounts.
                // The redeemed assets are sent directly to this vault contract.
                uint256 redeemedDust = lendingManager.redeemAllCTokens(address(this));
                finalAssetsToTransfer += redeemedDust;
            }
        }

        // 6. Transfer the final asset amount (pre-calculated assets + potential LM dust)
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        if (vaultBalance < finalAssetsToTransfer) {
            // This indicates an internal logic error or LM failure not caught earlier.
            revert Vault_InsufficientBalancePostLMWithdraw();
        }
        SafeERC20.safeTransfer(IERC20(asset()), recipient, finalAssetsToTransfer);

        // 7. Emit the standard Withdraw event with the final amounts
        emit Withdraw(msg.sender, recipient, owner, finalAssetsToTransfer, shares);

        return finalAssetsToTransfer;
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

        IERC20 assetToken = IERC20(asset());
        uint256 directBalance = assetToken.balanceOf(address(this));

        if (directBalance < assets) {
            uint256 neededFromLM = assets - directBalance;
            uint256 availableInLM = lendingManager.totalAssets();

            // Check if the LM has enough funds to cover the shortfall.
            if (neededFromLM <= availableInLM) {
                // Only proceed if LM has enough to cover the shortfall.
                if (neededFromLM > 0) {
                    bool success = lendingManager.withdrawFromLendingProtocol(neededFromLM);
                    if (!success) {
                        // If LM fails even when it should have funds, revert here.
                        revert LendingManagerWithdrawFailed();
                    }
                    // Sanity check after successful LM withdraw: Ensure vault now has enough.
                    // This check should ideally not fail if LM transferred correctly.
                    uint256 balanceAfterLMWithdraw = assetToken.balanceOf(address(this));
                    if (balanceAfterLMWithdraw < assets) {
                        // This indicates an internal logic error or unexpected LM behavior.
                        revert Vault_InsufficientBalancePostLMWithdraw();
                    }
                }
            }
            // If neededFromLM > availableInLM, we do nothing here.
            // The subsequent super.withdraw() call will fail the previewWithdraw check
            // because totalAssets() hasn't increased enough, resulting in ERC4626ExceededMaxWithdraw.
        }
    }
}
