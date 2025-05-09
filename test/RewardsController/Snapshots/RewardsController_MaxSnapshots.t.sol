// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {console} from "forge-std/console.sol";

contract RewardsController_MaxSnapshots_Test is RewardsController_Test_Base {
    function setUp() public override {
        super.setUp();
        // USER_A is available from base.
        // mockERC721 (NFT_COLLECTION_1) is added.
    }

    function test_T5_MaxSnapshots_Overflow() public {
        address collection = address(mockERC721); // NFT_COLLECTION_1

        // 1. Get MAX_SNAPSHOTS value
        // Assuming MAX_SNAPSHOTS is a public view function or constant in RewardsController.
        // If this is not the case, this line needs to be adjusted based on how MAX_SNAPSHOTS is exposed.
        // MAX_SNAPSHOTS is a private constant in RewardsController.sol, value is 50.
        uint256 maxSnapshots = 50;
        assertTrue(maxSnapshots > 0, "MAX_SNAPSHOTS should be greater than 0");

        // 2. Add MAX_SNAPSHOTS snapshots successfully.
        // The _processSingleUserUpdate function creates a snapshot.
        // The first call to _processSingleUserUpdate will create the first snapshot.
        // We need to make `maxSnapshots` calls to _processSingleUserUpdate to fill the snapshots.

        // Mint an NFT to USER_A to ensure they are tracked for the collection.
        vm.startPrank(OWNER);
        mockERC721.mintSpecific(USER_A, 100); // Mint a new NFT to USER_A for this test
        vm.stopPrank();

        // Initial update to make sure user is in the system for this collection. This is the 1st snapshot.
        _processSingleUserUpdate(USER_A, collection, block.number, int256(1), int256(100 * PRECISION));
        vm.roll(block.number + 1); // Advance block to ensure next update is distinct

        // Add `maxSnapshots - 1` more snapshots.
        uint256 snapshotsToAddMore = maxSnapshots - 1;

        for (uint256 i = 0; i < snapshotsToAddMore; ++i) {
            // Ensure distinct blockNumber for each snapshot. Balance delta can also vary.
            _processSingleUserUpdate(
                USER_A, collection, block.number + i + 1, int256(1), int256(100 * PRECISION + i + 1)
            );
        }

        // At this point, MAX_SNAPSHOTS should be filled.
        // We can verify this by trying to add one more, which should fail.

        // 3. Attempt to add one more snapshot (the MAX_SNAPSHOTS + 1)-th overall for this sequence.
        // This transaction should revert.
        // Error: MaxSnapshotsReached(address user, address collection, uint256 limit)
        bytes4 expectedErrorSelector = bytes4(keccak256("MaxSnapshotsReached(address,address,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(expectedErrorSelector, USER_A, collection, maxSnapshots));
        _processSingleUserUpdate(
            USER_A, collection, block.number + snapshotsToAddMore + 1, int256(1), int256(200 * PRECISION)
        );
    }
}
