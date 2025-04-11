// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";

/**
 * @title ILendingManager Interface
 * @notice Defines the functions for a contract that manages asset allocation into a lending protocol (e.g., Compound V2 fork).
 */
interface ILendingManager {
    /**
     * @notice Returns the underlying asset token managed by the lending manager.
     * @return The address of the underlying ERC20 asset.
     */
    function asset() external view returns (IERC20);

    /**
     * @notice Deposits a specified amount of the underlying asset into the lending protocol.
     * @dev Should typically only be called by the Vault.
     * @param amount The amount of the underlying asset to deposit.
     * @return success Boolean indicating if the deposit was successful.
     */
    function depositToLendingProtocol(uint256 amount) external returns (bool success);

    /**
     * @notice Withdraws a specified amount of the underlying asset from the lending protocol.
     * @dev Should typically only be called by the Vault.
     * @param amount The amount of the underlying asset to withdraw.
     * @return success Boolean indicating if the withdrawal was successful.
     */
    function withdrawFromLendingProtocol(uint256 amount) external returns (bool success);

    /**
     * @notice Returns the total amount of underlying assets currently managed by the lending manager,
     *         including principal and accrued yield within the lending protocol.
     * @return The total amount of underlying assets.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Calculates the base reward generated per block by the assets in the lending protocol.
     * @dev Formula: R₀ * loan_balance (where R₀ is a base rate and loan_balance is the amount in the protocol).
     *      The exact implementation depends on how R₀ and loan_balance are tracked.
     * @return The base reward amount per block.
     */
    function getBaseRewardPerBlock() external view returns (uint256);

    /**
     * @notice Allows the RewardsController to pull accrued base yield.
     * @dev The LendingManager needs to track how much yield has been generated and not yet pulled.
     *      This function transfers the calculated yield (using getBaseRewardPerBlock * blocks) to the caller.
     *      The caller should be the RewardsController.
     * @param amount The amount of yield tokens to pull.
     * @param recipient The address to send the yield tokens to.
     * @return success Boolean indicating success.
     */
    function transferYield(uint256 amount, address recipient) external returns (bool success);
}
