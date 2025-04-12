// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/ERC20.sol"; // For decimals
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/utils/SafeERC20.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {MinimalCTokenInterface} from "./interfaces/MinimalCTokenInterface.sol"; // Assuming this interface exists

/**
 * @title LendingManager (Compound V2 Fork)
 * @notice Manages asset allocation into a specific Compound V2 fork cToken market.
 * @dev Implements ILendingManager. Interacts with a cToken contract.
 *      Requires approval from the Vault to spend its assets for deposits.
 */
contract LendingManager is ILendingManager, Ownable {
    using SafeERC20 for IERC20;

    // --- State Variables ---
    IERC20 public immutable override asset;
    MinimalCTokenInterface public immutable cToken;
    address public rewardsController; // Address authorized to call transferYield

    uint256 public constant R0_BASIS_POINTS = 5; // Example: 0.05% base rate -> R0 = 5 * 10^(18-4)
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;
    uint256 private constant PRECISION = 1e18;

    // --- Events ---
    event RewardsControllerSet(address indexed controller);
    event YieldTransferred(address indexed recipient, uint256 amount);
    event DepositToProtocol(address indexed caller, uint256 amount);
    event WithdrawFromProtocol(address indexed caller, uint256 amount);

    // --- Errors ---
    error MintFailed();
    error RedeemFailed();
    error TransferYieldFailed();
    error AddressZero();
    error CallerNotVaultOrOwner(); // Allow owner for direct interaction/rescue
    error CallerNotRewardsController();

    // --- Constructor ---
    constructor(address initialOwner, address _assetAddress, address _cTokenAddress) Ownable(initialOwner) {
        if (_assetAddress == address(0) || _cTokenAddress == address(0)) {
            revert AddressZero();
        }
        asset = IERC20(_assetAddress);
        cToken = MinimalCTokenInterface(_cTokenAddress);

        // Approve the cToken contract to spend the underlying asset *held by this LendingManager*
        // This might be needed if yield is held here before transfer
        asset.approve(address(cToken), type(uint256).max);
    }

    // --- ILendingManager Implementation ---

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
        // Allow owner for potential recovery/manual deposits
        // require(msg.sender == owner(), "Caller not vault"); // TODO: Add vault address check?

        if (amount == 0) return true;

        // Pull assets from the Vault (caller)
        // Vault must have approved this contract address
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Mint cTokens with the received assets
        uint256 balanceBefore = asset.balanceOf(address(this));
        require(balanceBefore >= amount, "LM: Insufficient balance"); // Sanity check

        if (cToken.mint(amount) != 0) {
            revert MintFailed();
        }
        emit DepositToProtocol(msg.sender, amount);
        return true;
    }

    /**
     * @notice Withdraws assets from the Compound protocol and sends them to the caller (expected to be the Vault).
     */
    function withdrawFromLendingProtocol(uint256 amount) external override returns (bool success) {
        // Allow owner for potential recovery/manual withdrawals
        // require(msg.sender == owner(), "Caller not vault"); // TODO: Add vault address check?

        if (amount == 0) return true;

        // Check if enough assets are in Compound
        uint256 compoundBalance = totalAssets(); // Checks underlying balance in cToken
        if (compoundBalance < amount) {
            // Optional: Allow partial withdrawal or revert? Reverting for now.
            revert("LM: Insufficient balance in protocol");
        }

        // Redeem the required amount of underlying assets
        // The cToken contract will transfer the 'amount' back to this LendingManager contract
        if (cToken.redeemUnderlying(amount) != 0) {
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
        uint256 cTokenBalance = cToken.balanceOf(address(this));
        if (cTokenBalance == 0) {
            return 0;
        }

        // exchangeRateStored is scaled by 1e(18 + underlyingDecimals - cTokenDecimals)
        // Formula: underlying = (cTokenBalance * exchangeRateStored) / 1e18
        uint256 exchangeRate = cToken.exchangeRateStored();
        if (exchangeRate == 0) {
            // Should not happen in practice
            return 0;
        }

        // Perform the calculation using the scaled rate
        return (cTokenBalance * exchangeRate) / 1e18;

        /* // Old complex calculation - remove
        uint8 underlyingDecimals = ERC20(address(asset)).decimals();
        uint8 cTokenDecimals = cToken.decimals();

        // Calculate scaling factor = 10**(18 + underlyingDecimals - cTokenDecimals)
        uint exponent = 18 + underlyingDecimals;
        if (exponent < cTokenDecimals) { // Defensive check for large cToken decimals
            return 0;
        }
        uint256 scalingFactor = 10**(exponent - cTokenDecimals);
        if (scalingFactor == 0) { // Defensive check for extremely large difference
            return 0;
        }

        // underlying = (cTokenBalance * exchangeRate) / scalingFactor
        return (cTokenBalance * exchangeRate) / scalingFactor;
        */
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

        // TODO: Decision point - does the LM explicitly hold yield, or redeem on demand?
        // Option 1: Assume yield is already held directly in this contract.
        uint256 directBalance = asset.balanceOf(address(this));
        if (directBalance < amount) {
            // Consider logging this event or handling differently
            revert TransferYieldFailed(); // Not enough directly held yield
        }
        asset.safeTransfer(recipient, amount);

        // Option 2: Redeem the required yield amount from Compound first.
        /*
        if (cToken.redeemUnderlying(amount) != 0) {
            revert RedeemFailed(); // Could not redeem yield
        }
        // Now the contract should have the balance
        uint256 balanceAfterRedeem = asset.balanceOf(address(this));
        if (balanceAfterRedeem < amount) { // Sanity check
             revert TransferYieldFailed();
        }
        asset.safeTransfer(recipient, amount);
        */

        emit YieldTransferred(recipient, amount);
        return true;
    }

    // --- Admin Functions ---

    /**
     * @notice Sets the address of the RewardsController authorized to call transferYield.
     */
    function setRewardsController(address _controller) external onlyOwner {
        if (_controller == address(0)) revert AddressZero();
        rewardsController = _controller;
        emit RewardsControllerSet(_controller);
    }

    // --- Helper Functions (for scaling, if needed) ---

    // Consider adding functions for precision handling if complex math is involved.
}
