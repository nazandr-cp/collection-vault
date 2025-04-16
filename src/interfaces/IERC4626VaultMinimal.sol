// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC4626VaultMinimal
 * @notice Minimal interface for ERC4626 vaults, required by RewardsController.
 */
interface IERC4626VaultMinimal {
    /**
     * @notice Get the amount of assets deposited by a user for a specific NFT collection.
     * @param user User address.
     * @param nftCollection NFT collection address.
     * @return Amount deposited.
     */
    function deposits(address user, address nftCollection) external view returns (uint256);

    /**
     * @notice Get the underlying ERC20 asset managed by the vault.
     * @return Address of the ERC20 asset.
     */
    function asset() external view returns (address);
}
