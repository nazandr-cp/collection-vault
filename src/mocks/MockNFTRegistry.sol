// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INFTRegistry} from "../interfaces/INFTRegistry.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
 * @title MockNFTRegistry
 * @notice A simplified mock implementation of the INFTRegistry interface.
 * @dev This mock directly queries the `balanceOf` function of the provided ERC721 contract.
 *      It assumes the collection contract implements `balanceOf` correctly.
 *      It does NOT maintain its own state of registered collections; registration
 *      is assumed to be handled by the VaultManager or tested externally.
 */
contract MockNFTRegistry is INFTRegistry {
    /**
     * @notice Returns the number of NFTs a user owns by calling the collection directly.
     * @dev Requires the collection contract to implement `balanceOf`.
     * @param user The address of the user.
     * @param collectionAddress The address of the NFT collection contract.
     * @return The count of NFTs owned by the user in that collection.
     */
    function balanceOf(address user, address collectionAddress) external view override returns (uint256) {
        // Basic check for zero address
        if (user == address(0) || collectionAddress == address(0)) {
            return 0;
        }

        // Directly query the NFT contract's balance
        try IERC721(collectionAddress).balanceOf(user) returns (uint256 balance) {
            return balance;
        } catch {
            // If the call fails (e.g., not a contract, doesn't implement balanceOf),
            // return 0 or handle as an error depending on desired behavior.
            return 0;
        }

        // --- Alternative using IERC721Enumerable (if available/required) ---
        // try IERC721Enumerable(collectionAddress).balanceOf(user) returns (uint256 balance) {
        //     return balance;
        // } catch {
        //     return 0;
        // }
    }

    // --- No internal state for registered collections in this mock ---
    // The VaultManager is responsible for tracking which collections are registered.
    // function isCollectionRegistered(address collectionAddress) external view override returns (bool) {
    //     // In this mock, we assume any valid ERC721 address *could* be queried.
    //     // Actual registration logic resides in VaultManager.
    //     return collectionAddress != address(0); // Basic check
    // }
}
