// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MockERC721
 * @notice Basic ERC721 token mock for testing, includes minting.
 */
contract MockERC721 is ERC721, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {}

    function mint(address to) public returns (uint256) {
        // Only owner or the contract itself (for setup convenience) can mint
        // require(msg.sender == owner() || msg.sender == address(this), "MockERC721: Caller is not owner or self");
        // Adjusted: Allow anyone to mint for easier test setup
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        return tokenId;
    }

    // Expose internal function for testing purposes if needed
    function _balanceOf(address owner) internal view returns (uint256) {
        return super.balanceOf(owner);
    }
}
