// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title INFTDataUpdater Interface
 * @notice Defines the functions for an external service (like an oracle or backend)
 *         to push NFT balance updates to the system (likely the RewardsController).
 */
interface INFTDataUpdater {
    /**
     * @notice Updates the NFT balance for a specific user and collection.
     * @param user The user whose balance is being updated.
     * @param nftCollection The address of the NFT collection.
     * @param currentBalance The user's current balance in the NFT collection.
     */
    function updateNFTBalance(address user, address nftCollection, uint256 currentBalance) external;

    /**
     * @notice Updates NFT balances for multiple collections for a single user.
     * @param user The user whose balances are being updated.
     * @param nftCollections Array of NFT collection addresses.
     * @param currentBalances Array of corresponding current balances.
     */
    function updateNFTBalances(address user, address[] calldata nftCollections, uint256[] calldata currentBalances)
        external;
}
