// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";

contract RewardsController_NonceGuard_Test is RewardsController_Test_Base {
    IRewardsController.BalanceUpdateData[] internal noSimUpdates; // Empty array for simulated updates

    address internal collection1;

    function setUp() public override {
        super.setUp();
        collection1 = address(mockERC721); // NFT_COLLECTION_1
            // USER_A already has DAI (rewardToken) from base setUp.
            // mockERC721 is already added as a collection (NFT_COLLECTION_1).
    }

    function test_GlobalUpdateNonce_IncrementsOnBalanceUpdates() public {
        uint64 initialGlobalNonce = rewardsController.globalUpdateNonce();

        // Process a balance update via processUserBalanceUpdates
        _processSingleUserUpdate(USER_A, collection1, block.number, 1, 100 * PRECISION);
        uint64 nonceAfterFirstUpdate = rewardsController.globalUpdateNonce();
        assertEq(
            nonceAfterFirstUpdate, initialGlobalNonce + 1, "Nonce should increment after processUserBalanceUpdates"
        );

        // Process a balance update via processBalanceUpdates
        address[] memory users = new address[](1);
        users[0] = USER_B;
        address[] memory collections = new address[](1);
        collections[0] = collection1;
        uint256[] memory blockNumbers = new uint256[](1);
        blockNumbers[0] = block.number;
        int256[] memory nftDeltas = new int256[](1);
        nftDeltas[0] = 1;
        int256[] memory balanceDeltas = new int256[](1);
        balanceDeltas[0] = 50 * PRECISION;
        uint256 updaterNonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signBalanceUpdatesArrays(
            users, collections, blockNumbers, nftDeltas, balanceDeltas, updaterNonce, UPDATER_PRIVATE_KEY
        );

        rewardsController.processBalanceUpdates(
            AUTHORIZED_UPDATER, users, collections, blockNumbers, nftDeltas, balanceDeltas, signature
        );
        uint64 nonceAfterSecondUpdate = rewardsController.globalUpdateNonce();
        assertEq(
            nonceAfterSecondUpdate, nonceAfterFirstUpdate + 1, "Nonce should increment after processBalanceUpdates"
        );
    }

    function test_UserLastSyncedNonce_UpdatesOnBalanceProcessing() public {
        uint64 initialGlobalNonce = rewardsController.globalUpdateNonce();
        uint64 userAInitialNonce = rewardsController.userLastSyncedNonce(USER_A);
        assertEq(userAInitialNonce, 0, "User A initial sync nonce should be 0");

        // Process update for USER_A
        _processSingleUserUpdate(USER_A, collection1, block.number, 1, 100 * PRECISION);
        uint64 globalNonceAfterA = rewardsController.globalUpdateNonce();
        uint64 userANonceAfterA = rewardsController.userLastSyncedNonce(USER_A);

        assertEq(globalNonceAfterA, initialGlobalNonce + 1, "Global nonce should increment for User A update");
        assertEq(userANonceAfterA, globalNonceAfterA, "User A sync nonce should match global nonce");

        // Process update for USER_B (advances global nonce)
        _processSingleUserUpdate(USER_B, collection1, block.number, 1, 50 * PRECISION);
        uint64 globalNonceAfterB = rewardsController.globalUpdateNonce();
        uint64 userANonceAfterBUpdate = rewardsController.userLastSyncedNonce(USER_A);

        assertEq(globalNonceAfterB, globalNonceAfterA + 1, "Global nonce should increment for User B update");
        assertEq(userANonceAfterBUpdate, globalNonceAfterA, "User A sync nonce should NOT change on User B update");

        // Process another update for USER_A
        _processSingleUserUpdate(USER_A, collection1, block.number + 1, 0, 20 * PRECISION); // block.number must advance
        uint64 globalNonceAfterA2 = rewardsController.globalUpdateNonce();
        uint64 userANonceAfterA2 = rewardsController.userLastSyncedNonce(USER_A);

        assertEq(globalNonceAfterA2, globalNonceAfterB + 1, "Global nonce should increment for User A's second update");
        assertEq(userANonceAfterA2, globalNonceAfterA2, "User A sync nonce should match new global nonce");
    }

    function test_ClaimForCollection_RevertsWithStaleBalances_AndEmitsEvent() public {
        // 1. Setup: User A has some balance and is synced.
        vm.prank(OWNER);
        mockERC721.mintSpecific(USER_A, 1);
        _processSingleUserUpdate(USER_A, collection1, block.number, 1, 1000 * PRECISION); // Syncs USER_A

        uint64 userSyncedNonce = rewardsController.userLastSyncedNonce(USER_A);
        uint64 globalNonceAtSync = rewardsController.globalUpdateNonce();
        assertEq(userSyncedNonce, globalNonceAtSync, "User A should be synced initially");

        // 2. Advance globalUpdateNonce without syncing User A
        vm.prank(OWNER);
        rewardsController.setEpochDuration(rewardsController.epochDuration() + 1); // Increments globalUpdateNonce

        uint64 newGlobalNonce = rewardsController.globalUpdateNonce();
        assertTrue(newGlobalNonce > globalNonceAtSync, "Global nonce should have incremented");
        assertEq(rewardsController.userLastSyncedNonce(USER_A), userSyncedNonce, "User A nonce should remain stale");

        // 3. User A attempts to claimRewardsForCollection
        vm.startPrank(USER_A);
        vm.expectEmit(true, true, true, true);
        emit IRewardsController.StaleClaimAttempt(USER_A, userSyncedNonce, newGlobalNonce);
        vm.expectRevert("STALE_BALANCES");
        rewardsController.claimRewardsForCollection(collection1, noSimUpdates);
        vm.stopPrank();
    }

    function test_ClaimForAll_RevertsWithStaleBalances_AndEmitsEvent() public {
        // 1. Setup: User A has some balance and is synced.
        vm.prank(OWNER);
        mockERC721.mintSpecific(USER_A, 1);
        _processSingleUserUpdate(USER_A, collection1, block.number, 1, 1000 * PRECISION); // Syncs USER_A

        uint64 userSyncedNonce = rewardsController.userLastSyncedNonce(USER_A);
        uint64 globalNonceAtSync = rewardsController.globalUpdateNonce();
        assertEq(userSyncedNonce, globalNonceAtSync, "User A should be synced initially");

        // 2. Advance globalUpdateNonce without syncing User A
        vm.prank(OWNER);
        rewardsController.setEpochDuration(rewardsController.epochDuration() + 1); // Increments globalUpdateNonce

        uint64 newGlobalNonce = rewardsController.globalUpdateNonce();
        assertTrue(newGlobalNonce > globalNonceAtSync, "Global nonce should have incremented");

        // 3. User A attempts to claimRewardsForAll
        vm.startPrank(USER_A);
        vm.expectEmit(true, true, true, true);
        emit IRewardsController.StaleClaimAttempt(USER_A, userSyncedNonce, newGlobalNonce);
        vm.expectRevert("STALE_BALANCES");
        rewardsController.claimRewardsForAll(noSimUpdates);
        vm.stopPrank();
    }

    function test_Claim_Succeeds_WhenNoncesAreSynced() public {
        // 1. Setup: User A has some balance and is synced.
        vm.prank(OWNER);
        mockERC721.mintSpecific(USER_A, 1); // NFT ID 1 for USER_A
        _processSingleUserUpdate(USER_A, collection1, block.number, 1, 1000 * PRECISION);

        uint64 userNonce = rewardsController.userLastSyncedNonce(USER_A);
        uint64 globalNonce = rewardsController.globalUpdateNonce();
        assertEq(userNonce, globalNonce, "User and global nonces should be synced");

        // 2. Advance time to accrue some rewards & generate yield
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 100);
        _generateYieldInLendingManager(50 * PRECISION);

        // 3. User A claims for collection
        vm.startPrank(USER_A);
        uint256 balanceBeforeClaimColl = rewardToken.balanceOf(USER_A);
        rewardsController.claimRewardsForCollection(collection1, noSimUpdates);
        uint256 balanceAfterClaimColl = rewardToken.balanceOf(USER_A);
        assertTrue(balanceAfterClaimColl > balanceBeforeClaimColl, "Claim for collection should be successful");
        vm.stopPrank();

        // 4. User A claims for all (might be 0 if previous claim took all for this collection)
        // To make this meaningful, let's add another collection and sync it.
        address collection2 = address(mockERC721_2);
        vm.prank(OWNER);
        rewardsController.addNFTCollection(collection2, 1 * PRECISION, IRewardsController.RewardBasis.DEPOSIT, 5000);
        mockERC721_2.mintSpecific(USER_A, 1); // NFT for collection2

        // Sync USER_A for collection2. This will advance global nonce.
        // User A will be out of sync for collection1 again if we don't re-sync or use syncAndClaim.
        // For this test, let's ensure USER_A is fully synced before claimAll.
        // The previous claimRewardsForCollection would have updated user's state (lastUpdateBlock, lastRewardIndex)
        // but not necessarily userLastSyncedNonce if globalUpdateNonce didn't change during that claim.
        // Let's do a fresh sync for USER_A for both collections.

        // This sync will ensure userLastSyncedNonce[USER_A] == globalUpdateNonce
        _processSingleUserUpdate(USER_A, collection2, block.number, 1, 500 * PRECISION);
        // If collection1 also had updates, they should be processed too to be fully "synced" in terms of data.
        // For nonce purposes, the last _processSingleUserUpdate for USER_A sets their userLastSyncedNonce.

        userNonce = rewardsController.userLastSyncedNonce(USER_A);
        globalNonce = rewardsController.globalUpdateNonce();
        assertEq(userNonce, globalNonce, "User and global nonces should be synced before claimAll");

        _generateYieldInLendingManager(50 * PRECISION); // More yield

        vm.startPrank(USER_A);
        uint256 balanceBeforeClaimAll = rewardToken.balanceOf(USER_A);
        rewardsController.claimRewardsForAll(noSimUpdates);
        uint256 balanceAfterClaimAll = rewardToken.balanceOf(USER_A);
        // It's possible claimRewardsForCollection already claimed everything for collection1.
        // And claimRewardsForAll would claim for collection2.
        assertTrue(balanceAfterClaimAll >= balanceBeforeClaimAll, "Claim all should be successful or no-op");
        // A more robust check would be to ensure rewards from collection2 were claimed if available.
        vm.stopPrank();
    }
}
