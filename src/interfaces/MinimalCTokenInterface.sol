// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";

/**
 * @title MinimalCTokenInterface
 * @notice Minimal interface required for Compound V2 cToken interactions.
 * @dev Based on standard Compound V2 cToken functions used by the LendingManager.
 */
interface MinimalCTokenInterface {
    /**
     * @notice Mints cTokens in exchange for the underlying asset.
     * @param mintAmount The amount of the underlying asset to supply.
     * @return 0 on success, otherwise an error code.
     */
    function mint(uint256 mintAmount) external returns (uint256);

    /**
     * @notice Redeems cTokens for the underlying asset.
     * @param redeemUnderlyingAmount The amount of underlying asset to receive.
     * @return 0 on success, otherwise an error code.
     */
    function redeemUnderlying(uint256 redeemUnderlyingAmount) external returns (uint256);

    /**
     * @notice Calculates the underlying asset value of the balance held by an account.
     * @param owner The address to check the balance of.
     * @return The amount of underlying asset owned by the account.
     */
    function balanceOfUnderlying(address owner) external returns (uint256);

    // --- Optional but useful --- //

    /**
     * @notice Returns the underlying asset address.
     */
    function underlying() external view returns (address);

    /**
     * @notice Returns the decimals of the cToken.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the current exchange rate as an unsigned integer, scaled by 1e(18 + underlyingDecimals - cTokenDecimals).
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Returns the cToken balance of the specified account.
     */
    function balanceOf(address owner) external view returns (uint256);
}
