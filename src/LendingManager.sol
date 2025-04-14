// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/utils/SafeERC20.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

/**
 * @title LendingManager (Compound V2 Fork)
 * @notice Manages asset allocation into a specific Compound V2 fork cToken market.
 * @dev Implements ILendingManager. Interacts with a cToken contract.
 *      Requires approval from the Vault to spend its assets for deposits.
 */
contract LendingManager is ILendingManager, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable override asset;
    CErc20Interface public immutable cToken;
    address public rewardsController;

    uint256 public constant R0_BASIS_POINTS = 5; // Example: 0.05% base rate -> R0 = 5 * 10^(18-4)
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;
    uint256 private constant PRECISION = 1e18;

    event RewardsControllerSet(address indexed controller);
    event YieldTransferred(address indexed recipient, uint256 amount);
    event DepositToProtocol(address indexed caller, uint256 amount);
    event WithdrawFromProtocol(address indexed caller, uint256 amount);

    error MintFailed();
    error RedeemFailed();
    error TransferYieldFailed();
    error AddressZero();
    error CallerNotVaultOrOwner();
    error CallerNotRewardsController();

    constructor(address initialOwner, address _assetAddress, address _cTokenAddress) Ownable(initialOwner) {
        if (_assetAddress == address(0) || _cTokenAddress == address(0)) {
            revert AddressZero();
        }
        asset = IERC20(_assetAddress);
        cToken = CErc20Interface(_cTokenAddress);

        // Approve the cToken contract to spend the underlying asset held by this LendingManager
        asset.approve(address(cToken), type(uint256).max);
    }

    /**
     * @notice Deposits assets from the caller (expected to be the Vault) into the Compound protocol.
     * @dev Requires the caller (Vault) to have approved this contract to spend its assets.
     * @param amount The amount of the underlying asset to deposit.
     */
    function depositToLendingProtocol(uint256 amount, address /* nftCollection */ )
        external
        override
        returns (bool success)
    {
        // TODO: Add vault address check? msg.sender == vaultAddress || msg.sender == owner()

        if (amount == 0) return true;

        // Pull assets from the Vault (caller), which must have approved this contract
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Mint cTokens with the received assets
        require(asset.balanceOf(address(this)) >= amount, "LM: Insufficient balance post-transfer"); // Sanity check

        uint256 mintResult = cToken.mint(amount);
        if (mintResult != 0) {
            // Compound V2 returns 0 on success
            revert MintFailed();
        }
        emit DepositToProtocol(msg.sender, amount);
        return true;
    }

    /**
     * @notice Withdraws assets from the Compound protocol and sends them to the caller (expected to be the Vault).
     */
    function withdrawFromLendingProtocol(uint256 amount) external override returns (bool success) {
        // TODO: Add vault address check? msg.sender == vaultAddress || msg.sender == owner()

        if (amount == 0) return true;

        // Check if enough assets are in Compound
        uint256 compoundBalance = totalAssets(); // Checks underlying balance in cToken
        if (compoundBalance < amount) {
            revert("LM: Insufficient balance in protocol"); // Reverting on insufficient balance
        }

        // Redeem the required amount of underlying assets.
        // The cToken contract transfers the 'amount' back to this LendingManager contract.
        uint256 redeemResult = cToken.redeemUnderlying(amount);
        if (redeemResult != 0) {
            // Compound V2 returns 0 on success
            revert RedeemFailed();
        }

        // Send the withdrawn assets back to the Vault (caller)
        asset.safeTransfer(msg.sender, amount);
        emit WithdrawFromProtocol(msg.sender, amount);
        return true;
    }

    /**
     * @notice Returns the total underlying asset balance held within the Compound cToken market.
     * @dev Calculates using cToken balance and stored exchange rate to keep the function `view`.
     *      May not reflect interest accrued in the current block.
     */
    function totalAssets() public view override returns (uint256) {
        uint256 cTokenBalance = CTokenInterface(address(cToken)).balanceOf(address(this));
        if (cTokenBalance == 0) {
            return 0;
        }

        // Formula: underlying = (cTokenBalance * exchangeRateStored) / 1e18
        // exchangeRateStored is scaled by 1e(18 + underlyingDecimals - cTokenDecimals)
        uint256 exchangeRate = CTokenInterface(address(cToken)).exchangeRateStored();
        if (exchangeRate == 0) {
            return 0; // Should not happen in practice
        }

        // Perform the calculation using the stored (potentially slightly stale) exchange rate
        return (cTokenBalance * exchangeRate) / 1e18;
    }

    /**
     * @notice Calculates the *potential* base reward generation per block based on current balance.
     * @dev Formula: R₀ * loan_balance / PRECISION. R₀ is scaled by PRECISION.
     *      This is a simplified view; actual yield depends on Compound's internal mechanics.
     *      The RewardsController will use this as input for its distribution logic.
     */
    function getBaseRewardPerBlock() external view override returns (uint256) {
        uint256 currentBalance = totalAssets();
        // Calculate R0 scaled to precision
        uint256 scaledR0 = R0_BASIS_POINTS * (PRECISION / BASIS_POINTS_DENOMINATOR);
        return (currentBalance * scaledR0) / PRECISION;
    }

    /**
     * @notice Transfers accrued yield (underlying asset) to the RewardsController.
     * @dev Only callable by the registered RewardsController address.
     *      Requires this contract to have sufficient *directly held* underlying asset balance.
     *      This implies yield needs to be periodically redeemed from Compound or sent here.
     *      Alternative: Could redeem directly here before transfer.
     */
    function transferYield(uint256 amount, address recipient) external override returns (bool success) {
        if (msg.sender != rewardsController) revert CallerNotRewardsController();
        if (amount == 0) return true;

        // Assumes yield is already held directly in this contract (e.g., transferred periodically).
        // If yield needs to be redeemed on demand, uncomment Option 2 below.
        uint256 directBalance = asset.balanceOf(address(this));
        if (directBalance < amount) {
            revert TransferYieldFailed(); // Not enough directly held yield
        }
        asset.safeTransfer(recipient, amount);

        /* // Option 2: Redeem the required yield amount from Compound first.
        if (cToken.redeemUnderlying(amount) != 0) {
            revert RedeemFailed(); // Could not redeem yield
        }
        // Now the contract should have the balance
        uint256 balanceAfterRedeem = asset.balanceOf(address(this));
        require(balanceAfterRedeem >= amount, "LM: Insufficient balance post-redeem"); // Sanity check
        asset.safeTransfer(recipient, amount);
        */

        emit YieldTransferred(recipient, amount);
        return true;
    }

    /**
     * @notice Sets the address of the RewardsController authorized to call transferYield.
     */
    function setRewardsController(address _controller) external onlyOwner {
        if (_controller == address(0)) revert AddressZero();
        rewardsController = _controller;
        emit RewardsControllerSet(_controller);
    }
}
