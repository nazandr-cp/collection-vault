// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "../interfaces/IRewardsController.sol";

/**
 * @title MockRewardsController
 * @notice Mock for testing NFTDataUpdater interactions.
 */
contract MockRewardsController is IRewardsController {
    // Track calls
    struct UpdateBalanceCall {
        address user;
        address nftCollection;
        uint256 currentBalance;
    }

    struct UpdateBalancesCall {
        address user;
        address[] collections;
        uint256[] balances;
    }

    UpdateBalanceCall public lastUpdateBalanceCall;
    UpdateBalancesCall public lastUpdateBalancesCall;
    uint256 public updateBalanceCalledCount;
    uint256 public updateBalancesCalledCount;

    // --- IRewardsController Implementation (Mocks) ---

    function updateNFTBalance(address user, address nftCollection, uint256 currentBalance) external override {
        updateBalanceCalledCount++;
        lastUpdateBalanceCall =
            UpdateBalanceCall({user: user, nftCollection: nftCollection, currentBalance: currentBalance});
        // Emit event if needed for testing
    }

    function updateNFTBalances(address user, address[] calldata nftCollections, uint256[] calldata currentBalances)
        external
        override
    {
        updateBalancesCalledCount++;
        // Note: Storing dynamic arrays in storage can be complex/costly.
        // For mocks, simply storing the user might be sufficient, or use events/forge cheats.
        // Storing the whole call for simplicity here, be mindful of gas in real mocks if complex.
        lastUpdateBalancesCall =
            UpdateBalancesCall({user: user, collections: nftCollections, balances: currentBalances});
        // Emit event if needed
    }

    // --- Unused IRewardsController Functions (Stubs) ---
    // Implement other functions as empty stubs or revert if they shouldn't be called.

    function claimRewardsForCollection(address) external override { /* stub */ }
    function claimRewardsForAll() external override { /* stub */ }

    function getPendingRewards(address, address) external pure override returns (uint256, uint256) {
        return (0, 0);
    }

    function getUserNFTInfo(address, address) external pure override returns (UserNFTInfo memory) {
        return UserNFTInfo(0, 0, 0);
    }

    function getWhitelistedCollections() external pure override returns (address[] memory) {
        address[] memory collections; // Return empty array
        return collections;
    }

    function getCollectionBeta(address) external pure override returns (uint256) {
        return 0;
    }

    function getUserNFTCollections(address) external pure override returns (address[] memory) {
        address[] memory collections; // Return empty array
        return collections;
    }

    function addNFTCollection(address, uint256) external override { /* stub */ }
    function removeNFTCollection(address) external override { /* stub */ }
    function updateBeta(address, uint256) external override { /* stub */ }

    // --- Mock Helpers (Optional) --- //
    function getLastUpdateBalanceArgs() external view returns (UpdateBalanceCall memory) {
        return lastUpdateBalanceCall;
    }

    function getLastUpdateBalancesArgs() external view returns (address, address[] memory, uint256[] memory) {
        return (lastUpdateBalancesCall.user, lastUpdateBalancesCall.collections, lastUpdateBalancesCall.balances);
    }
}
