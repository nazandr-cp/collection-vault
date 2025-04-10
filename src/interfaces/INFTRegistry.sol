// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title INFTRegistry
 * @notice Interface for a registry that tracks user NFT holdings across multiple collections.
 * @dev This could be a simple on-chain registry or an interface to an off-chain indexer
 *      accessed via an oracle or bridge.
 */
interface INFTRegistry {
    /**
     * @notice Returns the number of NFTs a user owns in a specific collection.
     * @param user The address of the user.
     * @param collectionAddress The address of the NFT collection contract.
     * @return The count of NFTs owned by the user in that collection.
     */
    function balanceOf(address user, address collectionAddress) external view returns (uint256);

    /**
     * @notice Checks if a given address is a registered NFT collection.
     * @dev This could be maintained by the registry itself or queried elsewhere.
     *      Included here for completeness as VaultManager might need it.
     * @param collectionAddress The address to check.
     * @return True if the collection is registered, false otherwise.
     */
    // function isCollectionRegistered(address collectionAddress) external view returns (bool);

    // --- Optional: Functions for managing registered collections (might live elsewhere) ---
    // function addCollection(address collectionAddress) external;
    // function removeCollection(address collectionAddress) external;
}
