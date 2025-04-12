// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin-contracts-5.2.0/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin-contracts-5.2.0/utils/math/Math.sol"; // Import Math for safer subtraction

import {ILendingManager} from "./interfaces/ILendingManager.sol";

/**
 * @title ERC4626Vault
 * @notice An ERC-4626 compliant vault that delegates asset management to a LendingManager.
 * @dev Uses OpenZeppelin's ERC4626 implementation and hooks for LM interaction.
 */
contract ERC4626Vault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    // --- State --- //
    ILendingManager public immutable lendingManager;

    // --- Errors --- //
    error LendingManagerDepositFailed();
    error LendingManagerWithdrawFailed();
    error LendingManagerMismatch();

    // --- Constructor --- //
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
        IERC20 assetToken = IERC20(asset());
        bool success = assetToken.approve(_lendingManagerAddress, type(uint256).max);
        require(success, "Vault: Asset approval failed");
    }

    // --- ERC4626 Overrides --- //

    /**
     * @dev Overridden to return the total amount of the underlying asset managed by the vault
     * via the lending manager. Assets held directly by the vault are usually in transit.
     */
    function totalAssets() public view override returns (uint256) {
        // Rely solely on LM for total assets, as vault balance is transient.
        return super.totalAssets() + lendingManager.totalAssets();
    }

    // --- Public Functions (Simplified Overrides) --- //

    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
        _hookDeposit(assets, shares);
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        assets = super.mint(shares, receiver);
        _hookDeposit(assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        _hookWithdraw(assets, 0); // Pass 0 for shares placeholder
        shares = super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        uint256 assetsToWithdraw = previewRedeem(shares);
        _hookWithdraw(assetsToWithdraw, shares);
        assets = super.redeem(shares, receiver, owner);
    }

    // --- Internal Hooks for Lending Manager Interaction --- //

    /**
     * @dev Hook called after assets are received by the vault (via deposit/mint).
     *      Transfers the received assets to the LendingManager.
     *      Reverts if the LendingManager interaction fails.
     */
    function _hookDeposit(uint256 assets, uint256 /* shares */ ) internal virtual {
        if (assets > 0) {
            // Assets are now held by the vault. Transfer them to the LM.
            IERC20(asset()).safeTransfer(address(lendingManager), assets);

            // Optionally, call LM's deposit function if it needs notification beyond the transfer.
            // bool success = lendingManager.depositToLendingProtocol(assets);
            // if (!success) {
            //     revert LendingManagerDepositFailed();
            // }
        }
    }

    /**
     * @dev Hook called before assets are sent from the vault (via withdraw/redeem).
     *      Ensures the vault has enough assets, pulling from LendingManager if necessary.
     *      Reverts if the LendingManager interaction fails.
     * @param assets The amount of underlying assets intended to be withdrawn.
     */
    function _hookWithdraw(uint256 assets, uint256 /* shares */ ) internal virtual {
        if (assets == 0) {
            return;
        }

        uint256 directBalance = IERC20(asset()).balanceOf(address(this));
        if (directBalance < assets) {
            uint256 neededFromLM = assets - directBalance;
            uint256 availableInLM = lendingManager.totalAssets(); // Assuming this reflects withdrawable assets

            if (neededFromLM > availableInLM) {
                // Let the base function handle the revert
                return;
            }

            // Request withdrawal from LM to this vault contract
            bool success = lendingManager.withdrawFromLendingProtocol(neededFromLM);
            if (!success) {
                revert LendingManagerWithdrawFailed(); // Reverts the whole withdraw/redeem
            }

            uint256 balanceAfterLMWithdraw = IERC20(asset()).balanceOf(address(this));
            require(balanceAfterLMWithdraw >= assets, "Vault: Insufficient balance post-LM withdraw");
        }
    }
}
