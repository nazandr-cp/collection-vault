// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "../interfaces/IRewardsController.sol";

/**
 * @title MockRewardsController
 * @notice Mock for testing interactions with the Rewards Controller interface.
 * @dev Needs to implement all functions from IRewardsController.
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

    // --- Mock State & Events (Optional) ---
    event MockClaimForCollectionCalled(address user, address collection);
    event MockClaimForAllCalled(address user);
    event MockProcessBalanceUpdatesCalled(address signer, uint256 nonce, uint256 numUpdates);
    event MockProcessUserBalanceUpdatesCalled(address user, uint256 nonce, uint256 numUpdates);
    event MockSetAuthorizedUpdaterCalled(address newUpdater);

    uint256 public claimRewardsForCollectionCalledCount;
    uint256 public claimRewardsForAllCollectionsCalledCount;
    uint256 public processBalanceUpdatesCalledCount;
    uint256 public processUserBalanceUpdatesCalledCount;
    uint256 public setAuthorizedUpdaterCalledCount;

    // Store last call details if needed for assertions
    struct LastProcessBalanceUpdatesCall {
        address signer;
        uint256 nonce;
        UserBalanceUpdateData[] updates;
        bytes signature;
    }

    struct LastProcessUserBalanceUpdatesCall {
        address user;
        uint256 nonce;
        BalanceUpdateData[] updates;
        bytes signature;
    }

    LastProcessBalanceUpdatesCall public lastProcessBalanceUpdatesCall;
    LastProcessUserBalanceUpdatesCall public lastProcessUserBalanceUpdatesCall;
    address public lastSetAuthorizedUpdaterAddress;

    // --- Mock Helpers (Optional) --- //
    uint256 public previewRewardsAmount;
    bool public claimResult;

    // --- Mock Setters --- //
    function setPreviewRewards(uint256 _amount) external {
        previewRewardsAmount = _amount;
    }

    function setClaimResult(bool _result) external {
        claimResult = _result;
    }

    // --- IRewardsController Implementation (Mocks) --- //
    function addNFTCollection(address, /*collection*/ uint256 /*beta*/ ) external override {}

    function removeNFTCollection(address /*collection*/ ) external override {}

    function updateBeta(address, /*collection*/ uint256 /*newBeta*/ ) external override {}

    function processBalanceUpdates(
        address signer,
        UserBalanceUpdateData[] calldata updates,
        bytes calldata /*signature*/
    ) external override {
        processBalanceUpdatesCalledCount++;
        // Using block.timestamp as placeholder for nonce
        emit MockProcessBalanceUpdatesCalled(signer, block.timestamp, updates.length);
        // Store details if needed
        lastProcessBalanceUpdatesCall = LastProcessBalanceUpdatesCall({
            signer: signer,
            nonce: block.timestamp, // Placeholder
            updates: updates,
            signature: "" // Placeholder
        });
    }

    function processUserBalanceUpdates(
        address signer,
        address user,
        BalanceUpdateData[] calldata updates,
        bytes calldata /*signature*/
    ) external override {
        processUserBalanceUpdatesCalledCount++;
        // Using block.timestamp as placeholder for nonce
        emit MockProcessUserBalanceUpdatesCalled(user, block.timestamp, updates.length); // Note: Event doesn't include signer
        // Store details if needed
        lastProcessUserBalanceUpdatesCall = LastProcessUserBalanceUpdatesCall({
            user: user,
            nonce: block.timestamp, // Placeholder
            updates: updates,
            signature: "" // Placeholder
        });
    }

    function claimRewardsForCollection(address collection) external override {
        claimRewardsForCollectionCalledCount++;
        emit MockClaimForCollectionCalled(msg.sender, collection);
        if (!claimResult) revert("Mock claim failed");
    }

    function claimRewardsForAll() external override {
        claimRewardsForAllCollectionsCalledCount++;
        emit MockClaimForAllCalled(msg.sender);
        if (!claimResult) revert("Mock claim failed");
    }

    function previewRewards(
        address, /* user */
        address[] calldata, /* nftCollections */
        BalanceUpdateData[] calldata /* simulatedUpdates */
    ) external view override returns (uint256 pendingReward) {
        return previewRewardsAmount;
    }

    // --- View Functions (Mocks) --- //
    function getUserCollectionTracking(address, /* user */ address[] calldata nftCollections)
        external
        view
        override
        returns (IRewardsController.UserCollectionTracking[] memory infos)
    {
        // Return empty structs for the correct length array
        infos = new IRewardsController.UserCollectionTracking[](nftCollections.length);
    }

    function getWhitelistedCollections() external view override returns (address[] memory) {
        address[] memory collections = new address[](2);
        collections[0] = address(0xC1);
        collections[1] = address(0xC2);
        return collections;
    }

    function getCollectionBeta(address /*collection*/ ) external view override returns (uint256 beta) {
        return 0.1 ether; // Example beta
    }

    function getUserNFTCollections(address /*user*/ ) external view override returns (address[] memory) {
        address[] memory collections = new address[](1);
        collections[0] = address(0xC1);
        return collections;
    }

    function setAuthorizedUpdater(address _newUpdater) external {
        setAuthorizedUpdaterCalledCount++;
        lastSetAuthorizedUpdaterAddress = _newUpdater;
        emit MockSetAuthorizedUpdaterCalled(_newUpdater);
    }
}
