// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin-contracts-5.2.0/token/ERC721/IERC721.sol";

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
}
