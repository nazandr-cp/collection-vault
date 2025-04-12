// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Minimal IERC4626Vault Interface
 * @notice Defines only the functions needed by RewardsController.
 */
interface IERC4626VaultMinimal {
    /**
     * @notice Returns the amount of assets deposited by a user for a specific NFT collection.
     * @param user The address of the user.
     * @param nftCollection The address of the NFT collection.
     * @return The amount deposited.
     */
    function deposits(address user, address nftCollection) external view returns (uint256);

    /**
     * @notice Returns the underlying asset token managed by the vault.
     * @return The address of the underlying ERC20 asset.
     */
    function asset() external view returns (address); // Needed to ensure consistency
}
