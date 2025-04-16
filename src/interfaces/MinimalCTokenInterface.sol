// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";

/**
 * @title MinimalCTokenInterface
 * @notice Minimal interface for Compound V2 cToken interactions, as required by LendingManager.
 */
interface MinimalCTokenInterface {
    /**
     * @notice Mint cTokens in exchange for the underlying asset.
     * @param mintAmount Amount of underlying asset to supply.
     * @return 0 on success, otherwise error code.
     */
    function mint(uint256 mintAmount) external returns (uint256);

    /**
     * @notice Redeem cTokens for the underlying asset.
     * @param redeemUnderlyingAmount Amount of underlying asset to receive.
     * @return 0 on success, otherwise error code.
     */
    function redeemUnderlying(uint256 redeemUnderlyingAmount) external returns (uint256);

    /**
     * @notice Get the underlying asset value of an account's balance.
     * @param owner Account address.
     * @return Amount of underlying asset owned.
     */
    function balanceOfUnderlying(address owner) external returns (uint256);

    // --- Optional but useful --- //

    /**
     * @notice Get the underlying asset address.
     */
    function underlying() external view returns (address);

    /**
     * @notice Get the decimals of the cToken.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get the current exchange rate, scaled by 1e(18 + underlyingDecimals - cTokenDecimals).
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Get the cToken balance of an account.
     * @param owner Account address.
     * @return cToken balance.
     */
    function balanceOf(address owner) external view returns (uint256);
}
