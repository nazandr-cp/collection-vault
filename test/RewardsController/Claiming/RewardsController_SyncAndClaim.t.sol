// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {console} from "forge-std/console.sol";

contract RewardsController_SyncAndClaim_Test is RewardsController_Test_Base {
    IRewardsController.BalanceUpdateData[] internal noUpdates; // Empty array for updates
    IRewardsController.BalanceUpdateData[] internal noSimUpdates; // Empty array for simulated updates during claim

    address internal collection1;
    address internal collection2;

    function setUp() public override {
        super.setUp();
        collection1 = address(mockERC721);
        collection2 = address(mockERC721_2);
    }

    function test_SyncAndClaim_WithUpdates_SuccessfullySyncsAndClaims() public {
        // 1. Initial setup for USER_A in collection1
        // This mint corresponds to the 'initial' 1 NFT.
        mockERC721.mintSpecific(USER_A, 1);
        // Process this initial state for collection1: 1 NFT and 1000e18 balance (from vault deposit in Test_Base.setUp)
        // The 1000e18 balance for USER_A in collection1 comes from tokenVault.depositForCollection in RewardsController_Test_Base.setUp()
        _processSingleUserUpdate(USER_A, collection1, block.number, 1, int256(1000 * PRECISION));

        vm.roll(block.number + 1); // Advance block before next state update for clarity and ordering

        // Initial setup for USER_A in collection2 (as it was)
        _processSingleUserUpdate(USER_A, collection2, block.number, 1, int256(500 * PRECISION));
        uint64 userNonceBeforeStale = rewardsController.userLastSyncedNonce(USER_A);
        uint64 globalNonceBeforeStale = rewardsController.globalUpdateNonce();
        assertEq(userNonceBeforeStale, globalNonceBeforeStale, "User A should be synced initially");

        uint64 globalNonceWhenStale = rewardsController.globalUpdateNonce();

        // 3. Prepare new updates for USER_A for collection1
        // This update corresponds to the '1 update' NFT and the additional 500 balance.
        IRewardsController.BalanceUpdateData[] memory updatesToSync = new IRewardsController.BalanceUpdateData[](1);
        updatesToSync[0] = IRewardsController.BalanceUpdateData({
            collection: collection1,
            blockNumber: block.number + 1, // Ensure block number advances from the initial _processSingleUserUpdate for collection1
            nftDelta: 1, // This is for the *second* NFT
            balanceDelta: int256(500 * PRECISION)
        });
        // This mint corresponds to the nftDelta: 1 in updatesToSync
        mockERC721.mintSpecific(USER_A, 2);

        // 4. Sign updates
        uint256 updaterNonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signUserBalanceUpdates(USER_A, updatesToSync, updaterNonce, UPDATER_PRIVATE_KEY);

        // 5. Generate yield
        _generateYieldInLendingManager(100 * PRECISION);

        // 6. USER_A calls syncAndClaim
        uint256 balanceBefore = rewardToken.balanceOf(USER_A);
        vm.startPrank(USER_A);
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, updaterNonce, updatesToSync.length);
        rewardsController.syncAndClaim(AUTHORIZED_UPDATER, updatesToSync, signature, noSimUpdates);
        vm.stopPrank();

        // 7. Verifications
        uint64 globalNonceAfterSync = rewardsController.globalUpdateNonce();
        assertTrue(
            globalNonceAfterSync > globalNonceWhenStale, "Global nonce should increment from sync's internal update"
        );
        assertEq(
            rewardsController.userLastSyncedNonce(USER_A), globalNonceAfterSync, "User A's nonce should be updated"
        );
        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER),
            updaterNonce + 1,
            "Updater nonce should increment"
        );

        uint256 balanceAfter = rewardToken.balanceOf(USER_A);
        assertTrue(balanceAfter > balanceBefore, "Rewards should be claimed");

        IRewardsController.UserCollectionTracking[] memory tracking = _getUserTracking(USER_A, collection1);
        assertEq(tracking[0].lastNFTBalance, 2, "NFT balance after sync incorrect"); // 1 initial (from _processSingleUserUpdate) + 1 from updatesToSync
        assertEq(tracking[0].lastBalance, (1000 + 500) * PRECISION, "Token balance after sync incorrect"); // 1000 initial + 500 from updatesToSync
    }

    function test_SyncAndClaim_WithNoUpdates_SyncsNonceAndClaims() public {
        // 1. Initial setup for USER_A in collection1
        mockERC721.mintSpecific(USER_A, 1);
        _processSingleUserUpdate(USER_A, collection1, block.number, 1, int256(1000 * PRECISION));
        uint64 userNonceBeforeStale = rewardsController.userLastSyncedNonce(USER_A);
        uint64 globalNonceBeforeStale = rewardsController.globalUpdateNonce();

        // 2. Make USER_A's nonce stale
        _processSingleUserUpdate(USER_B, address(mockERC721_2), block.number + 1, 0, 0);
        uint64 globalNonceWhenStale = rewardsController.globalUpdateNonce();
        assertTrue(globalNonceWhenStale > globalNonceBeforeStale);

        // 3. Sign empty updates (to sync nonce)
        uint256 updaterNonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signUserBalanceUpdates(USER_A, noUpdates, updaterNonce, UPDATER_PRIVATE_KEY);

        // 4. Generate yield
        _generateYieldInLendingManager(100 * PRECISION);

        // 5. USER_A calls syncAndClaim with no actual data updates
        uint256 balanceBefore = rewardToken.balanceOf(USER_A);
        vm.startPrank(USER_A);
        rewardsController.syncAndClaim(AUTHORIZED_UPDATER, noUpdates, signature, noSimUpdates);
        vm.stopPrank();

        // 6. Verifications
        // Global nonce should NOT have changed by this specific syncAndClaim call if updates array was empty.
        assertEq(
            rewardsController.globalUpdateNonce(),
            globalNonceWhenStale,
            "Global nonce should not change for empty updates sync"
        );
        assertEq(
            rewardsController.userLastSyncedNonce(USER_A),
            globalNonceWhenStale,
            "User A's nonce should be synced to current global"
        );

        // Updater nonce should NOT increment if updates array is empty, as per current RewardsController logic.
        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER),
            updaterNonce,
            "Updater nonce should not increment for empty updates"
        );

        uint256 balanceAfter = rewardToken.balanceOf(USER_A);
        assertTrue(balanceAfter > balanceBefore, "Rewards should still be claimed even with empty sync updates");
    }

    function test_SyncAndClaim_Reverts_WithInvalidSignature() public {
        IRewardsController.BalanceUpdateData[] memory updatesToSync = new IRewardsController.BalanceUpdateData[](1);
        updatesToSync[0] = IRewardsController.BalanceUpdateData({
            collection: collection1,
            blockNumber: block.number,
            nftDelta: 1,
            balanceDelta: int256(100 * PRECISION)
        });

        uint256 updaterNonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        // Sign with a different key (OWNER_PRIVATE_KEY instead of UPDATER_PRIVATE_KEY)
        bytes memory badSignature = _signUserBalanceUpdates(USER_A, updatesToSync, updaterNonce, OWNER_PRIVATE_KEY);

        vm.startPrank(USER_A);
        vm.expectRevert(IRewardsController.InvalidSignature.selector);
        rewardsController.syncAndClaim(AUTHORIZED_UPDATER, updatesToSync, badSignature, noSimUpdates);
        vm.stopPrank();
    }

    function test_SyncAndClaim_Reverts_WithIncorrectUpdaterNonceInSignature() public {
        IRewardsController.BalanceUpdateData[] memory updatesToSync = new IRewardsController.BalanceUpdateData[](1);
        updatesToSync[0] = IRewardsController.BalanceUpdateData({
            collection: collection1,
            blockNumber: block.number,
            nftDelta: 1,
            balanceDelta: int256(100 * PRECISION)
        });

        uint256 correctUpdaterNonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        // Sign with an incorrect nonce
        bytes memory signatureWithBadNonce =
            _signUserBalanceUpdates(USER_A, updatesToSync, correctUpdaterNonce + 1, UPDATER_PRIVATE_KEY);

        vm.startPrank(USER_A);
        vm.expectRevert(IRewardsController.InvalidSignature.selector); // Same error as bad signature
        rewardsController.syncAndClaim(AUTHORIZED_UPDATER, updatesToSync, signatureWithBadNonce, noSimUpdates);
        vm.stopPrank();
    }

    function test_SyncAndClaim_ClaimsForAllCollections_AfterSyncing() public {
        // 1. Setup USER_A with balances in collection1 and collection2
        mockERC721.mintSpecific(USER_A, 3);
        mockERC721_2.mintSpecific(USER_A, 4);
        _processSingleUserUpdate(USER_A, collection1, block.number, 1, int256(1000 * PRECISION));
        _processSingleUserUpdate(USER_A, collection2, block.number, 1, int256(500 * PRECISION));
        uint64 userNonceBeforeStale = rewardsController.userLastSyncedNonce(USER_A);
        uint64 globalNonceBeforeStale = rewardsController.globalUpdateNonce();

        // 2. Make USER_A's nonce stale
        _processSingleUserUpdate(USER_B, address(mockERC721_2), block.number + 1, 0, 0);
        uint64 globalNonceWhenStale = rewardsController.globalUpdateNonce();

        // 3. Prepare updates for USER_A for collection1 only
        IRewardsController.BalanceUpdateData[] memory updatesToSync = new IRewardsController.BalanceUpdateData[](1);
        updatesToSync[0] = IRewardsController.BalanceUpdateData({
            collection: collection1,
            blockNumber: block.number + 1,
            nftDelta: 0, // No change in NFT, just balance
            balanceDelta: int256(200 * PRECISION)
        });
        uint256 updaterNonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signUserBalanceUpdates(USER_A, updatesToSync, updaterNonce, UPDATER_PRIVATE_KEY);

        // 4. Generate yield for both collections
        _generateYieldInLendingManager(100 * PRECISION); // For collection1
        _generateYieldInLendingManager(150 * PRECISION); // For collection2 (via general pool)

        // 5. USER_A calls syncAndClaim
        uint256 balUserBefore = rewardToken.balanceOf(USER_A);
        vm.startPrank(USER_A);
        rewardsController.syncAndClaim(AUTHORIZED_UPDATER, updatesToSync, signature, noSimUpdates);
        vm.stopPrank();

        // 6. Verifications
        uint64 globalNonceAfterSync = rewardsController.globalUpdateNonce();
        assertEq(
            rewardsController.userLastSyncedNonce(USER_A), globalNonceAfterSync, "User A's nonce should be updated"
        );

        uint256 balUserAfter = rewardToken.balanceOf(USER_A);
        assertTrue(balUserAfter > balUserBefore, "Total rewards from all collections should be claimed");

        // Verify state for collection1 was updated
        IRewardsController.UserCollectionTracking[] memory tracking1 = _getUserTracking(USER_A, collection1);
        assertEq(tracking1[0].lastBalance, (1000 + 200) * PRECISION, "Coll1 balance after sync incorrect");

        // Verify state for collection2 was NOT directly updated by these specific updates, but rewards were claimed
        IRewardsController.UserCollectionTracking[] memory tracking2 = _getUserTracking(USER_A, collection2);
        assertEq(tracking2[0].lastBalance, 500 * PRECISION, "Coll2 balance should be unchanged by sync for coll1");
        assertTrue(
            tracking2[0].lastUpdateBlock >= block.number, "Coll2 lastUpdateBlock should be recent after claimAll"
        );
    }

    // Helper to get user tracking info for a single collection
    function _getUserTracking(address user, address collection)
        internal
        view
        returns (IRewardsController.UserCollectionTracking[] memory)
    {
        address[] memory collectionsToTrack = new address[](1);
        collectionsToTrack[0] = collection;
        return rewardsController.getUserCollectionTracking(user, collectionsToTrack);
    }
}
