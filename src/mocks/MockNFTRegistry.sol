// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INFTRegistry} from "../interfaces/INFTRegistry.sol";

/**
 * @title MockNFTRegistry
 * @notice Mock for testing RewardsController NFT balance checks.
 */
contract MockNFTRegistry is INFTRegistry {
    mapping(address => mapping(address => uint256)) private _balances;

    // --- Mock Control Functions ---
    function setBalance(address user, address collection, uint256 balance) external {
        _balances[user][collection] = balance;
    }

    function batchSetBalance(address[] calldata users, address[] calldata collections, uint256[] calldata balances)
        external
    {
        require(users.length == collections.length && users.length == balances.length, "Length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            _balances[users[i]][collections[i]] = balances[i];
        }
    }

    // --- INFTRegistry Implementation ---
    function balanceOf(address user, address collectionAddress) external view override returns (uint256) {
        return _balances[user][collectionAddress];
    }
}
