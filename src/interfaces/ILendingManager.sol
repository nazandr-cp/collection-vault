// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILendingManager
 * @notice Interface for managing asset allocation into a lending protocol.
 */
interface ILendingManager {
    // Events
    event YieldTransferred(address indexed recipient, uint256 amount);
    event YieldTransferredBatch(
        address indexed recipient, uint256 totalAmount, address[] collections, uint256[] amounts
    );
    event DepositToProtocol(address indexed caller, uint256 amount);
    event WithdrawFromProtocol(address indexed caller, uint256 amount);
    event PrincipalReset(uint256 oldValue, address indexed trigger);

    // --- Specific cToken interaction errors ---
    error LendingManagerCTokenMintFailed(uint256 errorCode);
    error LendingManagerCTokenMintFailedReason(string reason);
    error LendingManagerCTokenMintFailedBytes(bytes data);

    error LendingManagerCTokenRedeemFailed(uint256 errorCode);
    error LendingManagerCTokenRedeemFailedReason(string reason);
    error LendingManagerCTokenRedeemFailedBytes(bytes data);

    error LendingManagerCTokenRedeemUnderlyingFailed(uint256 errorCode);
    error LendingManagerCTokenRedeemUnderlyingFailedReason(string reason);
    error LendingManagerCTokenRedeemUnderlyingFailedBytes(bytes data);
    // --- End Specific cToken interaction errors ---

    error AddressZero();
    error InsufficientBalanceInProtocol();
    error LM_CallerNotVault(address caller);
    error LM_CallerNotRewardsController(address caller);
    error CannotRemoveLastAdmin(bytes32 role);
    error LendingManager__BalanceCheckFailed(string reason, uint256 expected, uint256 actual);

    /**
     * @notice Get the underlying ERC20 asset managed by the lending manager.
     * @return ERC20 asset address.
     */
    function asset() external view returns (IERC20);

    /**
     * @notice Get the cToken address associated with the underlying asset.
     * @return cToken address.
     */
    function cToken() external view returns (address);

    /**
     * @notice Deposit a specified amount of the asset into the lending protocol.
     * @param amount Amount to deposit.
     * @return success True if deposit was successful.
     */
    function depositToLendingProtocol(uint256 amount) external returns (bool success);

    /**
     * @notice Withdraw a specified amount of the asset from the lending protocol.
     * @param amount Amount to withdraw.
     * @return success True if withdrawal was successful.
     */
    function withdrawFromLendingProtocol(uint256 amount) external returns (bool success);

    /**
     * @notice Get the total amount of assets managed by the lending manager (principal + yield).
     * @return Total underlying assets.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Get the base reward generated per block by assets in the lending protocol.
     * @return Base reward per block.
     */
    function getBaseRewardPerBlock() external view returns (uint256);

    /**
     * @notice Redeems the entire cToken balance held by the LendingManager.
     * @dev Used for scenarios like full vault redemption to sweep remaining dust.
     * @param recipient Recipient address.
     * @return amountRedeemed The amount of underlying asset received from redeeming all cTokens.
     */
    function redeemAllCTokens(address recipient) external returns (uint256 amountRedeemed);

    /**
     * @notice Returns the total principal amount deposited by the Vault into the lending protocol.
     * @return The total principal deposited in the underlying asset's units.
     */
    function totalPrincipalDeposited() external view returns (uint256);
}
