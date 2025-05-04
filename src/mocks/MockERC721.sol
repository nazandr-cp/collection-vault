// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin-contracts-5.2.0/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";

/**
 * @title MockERC721
 * @notice Basic ERC721 token mock for testing, includes minting.
 */
contract MockERC721 is ERC721, Ownable {
    // Remove using Counters directive
    // using Counters for Counters.Counter;

    // Replace Counters.Counter with simple uint256
    uint256 private _tokenIdCounter;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {}

    function mint(address to) public returns (uint256) {
        // Only owner or the contract itself (for setup convenience) can mint
        // require(msg.sender == owner() || msg.sender == address(this), "MockERC721: Caller is not owner or self");
        // Adjusted: Allow anyone to mint for easier test setup

        // Use standard uint increment
        uint256 tokenId = ++_tokenIdCounter; // Start IDs from 1
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Mints a specific token ID to an address. For testing only.
     * @param to The address to mint to.
     * @param tokenId The specific token ID to mint.
     */
    function mintSpecific(address to, uint256 tokenId) public {
        // Check if token exists using ownerOf within a try/catch block
        bool exists = true;
        try this.ownerOf(tokenId) {
            // If ownerOf succeeds, the token exists
        } catch {
            // If ownerOf reverts, the token does not exist
            exists = false;
        }
        require(!exists, "MockERC721: Token already minted");

        _safeMint(to, tokenId);
        // Note: This doesn't update the internal counter, which might be desired
        // depending on how the auto-incrementing mint is used elsewhere.
    }

    // Expose internal function for testing purposes if needed
    function _balanceOf(address owner) internal view returns (uint256) {
        return super.balanceOf(owner);
    }
}
