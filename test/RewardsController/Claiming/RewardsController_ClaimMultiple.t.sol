// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "src/interfaces/IRewardsController.sol";
import {MockERC721} from "src/mocks/MockERC721.sol";

contract RewardsController_ClaimMultiple_Test is RewardsController_Test_Base {
    MockERC721 internal mockNft;
    address internal collectionAddress;

    function setUp() public virtual override {
        super.setUp();
        mockNft = new MockERC721("Mock NFT", "MNFT");
        collectionAddress = address(mockNft);

        // Whitelist the collection
        rewardsController.addNFTCollection(
            collectionAddress,
            1e18, // beta
            IRewardsController.RewardBasis.DEPOSIT,
            10000 // 100% reward share
        );

        // Manually update USER_A's lastSyncedNonce to the current globalUpdateNonce
        // to pass the STALE_BALANCES check in claimMultiple.
        // The updateUserRewardStateForTesting function was removed.
        // This vm.store hack is used as this test primarily cares about
        // the MAX_SNAPSHOTS_PER_CLAIM check.
        // Ideally, syncAndClaim or processUserBalanceUpdates would be used for nonce syncing.
        uint64 currentGlobalNonce = rewardsController.globalUpdateNonce();
        bytes32 slot = keccak256(abi.encode(USER_A, uint256(97))); // userLastSyncedNonce slot for 'USER_A'
        vm.store(address(rewardsController), slot, bytes32(uint256(currentGlobalNonce)));
    }

    function test_ClaimMultiple_With_MaxSnapshots_Succeeds() public {
        uint256[] memory snapshotIDs = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            snapshotIDs[i] = i;
        }
        IRewardsController.BalanceUpdateData[] memory simulatedUpdates = new IRewardsController.BalanceUpdateData[](0);

        vm.prank(USER_A);
        rewardsController.claimMultiple(collectionAddress, snapshotIDs, simulatedUpdates);
        // Expect no revert
    }

    function test_ClaimMultiple_With_MoreThanMaxSnapshots_Reverts() public {
        uint256[] memory snapshotIDs = new uint256[](101);
        for (uint256 i = 0; i < 101; i++) {
            snapshotIDs[i] = i;
        }
        IRewardsController.BalanceUpdateData[] memory simulatedUpdates = new IRewardsController.BalanceUpdateData[](0);

        vm.prank(USER_A);
        vm.expectRevert("TOO_MANY_SNAPSHOTS");
        rewardsController.claimMultiple(collectionAddress, snapshotIDs, simulatedUpdates);
    }
}
