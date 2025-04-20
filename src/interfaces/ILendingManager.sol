// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILendingManager
 * @notice Interface for managing asset allocation into a lending protocol.
 */
interface ILendingManager {
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
     * @notice Transfer accrued base yield to a recipient (called by RewardsController).
     * @param amount Amount of yield tokens to transfer.
     * @param recipient Recipient address.
     * @return amountTransferred The actual amount of yield transferred (may be less than requested due to capping).
     */
    function transferYield(uint256 amount, address recipient) external returns (uint256 amountTransferred);

    /**
     * @notice Redeems the entire cToken balance held by the LendingManager.
     * @dev Used for scenarios like full vault redemption to sweep remaining dust.
     * @param recipient Recipient address.
     * @return amountRedeemed The amount of underlying asset received from redeeming all cTokens.
     */
    function redeemAllCTokens(address recipient) external returns (uint256 amountRedeemed);
}
