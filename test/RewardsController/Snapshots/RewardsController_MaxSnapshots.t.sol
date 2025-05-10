// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {console} from "forge-std/console.sol";

contract RewardsController_MaxSnapshots_Test is RewardsController_Test_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_T5_MaxSnapshots_Overflow() public {
        console.log("Starting test_T5_MaxSnapshots_Overflow");
        address collection = address(mockERC721);
        uint256 maxSnapshots = 50;
        assertTrue(maxSnapshots > 0, "MAX_SNAPSHOTS should be greater than 0");

        // Mint an NFT to USER_A
        vm.startPrank(OWNER);
        mockERC721.mintSpecific(USER_A, 100);
        vm.stopPrank();

        // Initial update creates snapshot 1
        uint256 currentBlock = block.number;
        console.log("Making initial update at block %s (creates snapshot 1)", currentBlock);
        _processSingleUserUpdate(USER_A, collection, currentBlock, int256(1), int256(100 * PRECISION));

        // Loop to add up to maxSnapshots snapshots
        for (uint256 i = 0; i < maxSnapshots; ++i) {
            currentBlock++;
            vm.roll(currentBlock);
            console.log(
                "Loop iteration i=%d: Processing update (aiming for snapshot %d) at block %s", i, i + 2, currentBlock
            );

            if (i == maxSnapshots - 1) {
                // This iteration should revert (overflow)
                uint256 snapshotsBefore = rewardsController.getUserSnapshotsLength(USER_A, collection);
                console.log(
                    "Expecting revert on this iteration (i=%d). Snapshots before this call: %d (expected %d)",
                    i,
                    snapshotsBefore,
                    maxSnapshots
                );
                assertEq(snapshotsBefore, maxSnapshots, "Snapshot count mismatch before expected revert in loop");

                uint256 nonceToUse = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
                bytes memory expectedRevertData = abi.encodeWithSelector(
                    IRewardsController.MaxSnapshotsReached.selector, USER_A, collection, maxSnapshots
                );
                vm.expectRevert(expectedRevertData);
                _callProcessUserBalanceUpdates_WithNonce(
                    USER_A, collection, currentBlock, int256(1), int256(100 * PRECISION + i + 1), nonceToUse
                );
            } else {
                _processSingleUserUpdate(USER_A, collection, currentBlock, int256(1), int256(100 * PRECISION + i + 1));
            }

            if (i < maxSnapshots - 1) {
                uint256 expectedSnapshots = i + 2;
                assertEq(
                    rewardsController.getUserSnapshotsLength(USER_A, collection),
                    expectedSnapshots,
                    "Incorrect snapshot count after loop iteration"
                );
            }
        }

        // Final assertions
        if (maxSnapshots > 0) {
            assertEq(
                rewardsController.getUserSnapshotsLength(USER_A, collection),
                maxSnapshots,
                "Snapshot count should be maxSnapshots after attempting to overflow"
            );
            console.log(
                "Test completed. Final snapshot count for USER_A, collection %s: %s (expected %s)",
                collection,
                rewardsController.getUserSnapshotsLength(USER_A, collection),
                maxSnapshots
            );
        } else {
            assertEq(
                rewardsController.getUserSnapshotsLength(USER_A, collection),
                1,
                "Snapshot count should be 1 if maxSnapshots is 0"
            );
        }
    }

    function test_MaxSnapshots_ClaimClearsSnapshots() public {
        console.log("Starting test_MaxSnapshots_ClaimClearsSnapshots");
        address collection = address(mockERC721);
        uint256 maxSnapshots = 50;

        // Mint an NFT to USER_A
        vm.startPrank(OWNER);
        mockERC721.mintSpecific(USER_A, 100);
        vm.stopPrank();

        // Fill up snapshots to MAX_SNAPSHOTS
        uint256 currentBlock = block.number;
        _processSingleUserUpdate(USER_A, collection, currentBlock, int256(1), int256(100 * PRECISION));
        for (uint256 i = 0; i < maxSnapshots - 1; ++i) {
            currentBlock++;
            vm.roll(currentBlock);
            _processSingleUserUpdate(USER_A, collection, currentBlock, int256(1), int256(100 * PRECISION + i + 1));
        }
        assertEq(
            rewardsController.getUserSnapshotsLength(USER_A, collection),
            maxSnapshots,
            "Should have MAX_SNAPSHOTS before claim"
        );

        // Sync user nonce before claiming
        uint256 nonce_for_signature = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        vm.startPrank(USER_A);
        rewardsController.syncAndClaim(
            AUTHORIZED_UPDATER,
            new IRewardsController.BalanceUpdateData[](0),
            _signUserBalanceUpdates(
                USER_A, new IRewardsController.BalanceUpdateData[](0), nonce_for_signature, UPDATER_PRIVATE_KEY
            ),
            new IRewardsController.BalanceUpdateData[](0)
        );
        vm.stopPrank();

        assertEq(
            rewardsController.getUserSnapshotsLength(USER_A, collection), 0, "Snapshots should be cleared after claim"
        );
    }
}
