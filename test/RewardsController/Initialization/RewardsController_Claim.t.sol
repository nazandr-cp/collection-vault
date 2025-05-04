// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {RewardsController} from "../../../src/RewardsController.sol";
import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";

contract RewardsController_Claim_Test is RewardsController_Test_Base {
    // --- Claiming Tests ---

    // --- claimRewardsForCollection ---
    function test_ClaimRewardsForCollection_Basic() public {
        // 1. Setup initial state
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        uint256 nftCount = 3;
        uint256 balance = 1000 ether;
        // Use actual mock address
        _processSingleUserUpdate(USER_A, address(mockERC721), updateBlock, int256(nftCount), int256(balance));

        // 2. Accrue rewards
        uint256 claimBlock = block.number + 100;
        vm.roll(claimBlock);
        // REMOVED: mockCToken.accrueInterest(); // Explicitly accrue interest BEFORE preview

        // 3. Preview rewards just before claim
        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = address(mockERC721); // Use actual mock address
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 expectedReward = rewardsController.previewRewards(USER_A, collectionsToPreview, noSimUpdates); // Reads rate AFTER accrual within preview
        assertTrue(expectedReward > 0, "Expected reward should be positive before claim");

        // 4. Simulate available yield in LendingManager (ensure enough for full claim)
        // Use the previewed reward (expectedReward) for yield simulation
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(lendingManager), expectedReward * 2); // Provide ample yield based on initial preview
        vm.stopPrank();
        uint256 userBalanceBefore = rewardToken.balanceOf(USER_A); // Get balance before

        // 6. Claim and Record Logs
        vm.recordLogs(); // Start recording events
        vm.startPrank(USER_A);
        rewardsController.claimRewardsForCollection(address(mockERC721), noSimUpdates); // Claim uses the already accrued index
        vm.stopPrank();
        uint256 userBalanceAfter = rewardToken.balanceOf(USER_A); // Get balance after

        // 7. Verify Balance Change
        uint256 actualClaimed = userBalanceAfter - userBalanceBefore;
        // Now preview and claim use the same index calculation logic
        assertApproxEqAbs(
            actualClaimed,
            expectedReward, // Compare with reward BEFORE manual accrual simulation
            expectedReward / 1000, // Allow 0.1% delta
            "Claimed amount should match preview amount (pre-manual accrual)"
        );

        // Check internal state reset
        // (uint256 lastIdx, uint256 accrued, uint256 nftBal, uint256 depAmt, uint256 lastUpdate) =
        //     rewardsController.userNFTData(USER_A, address(mockERC721)); // Use actual mock address
        RewardsController.UserRewardState memory state =
            rewardsController.getUserRewardState(USER_A, address(mockERC721));
        assertEq(state.accruedReward, 0, "Accrued should be 0 after claim");
        assertTrue(state.lastRewardIndex >= rewardsController.globalRewardIndex(), "Last index should be updated"); // Use >=
        assertEq(state.lastUpdateBlock, block.number, "Last update block should be claim block");
        assertEq(state.lastNFTBalance, nftCount, "NFT balance should persist");
        assertEq(state.lastBalance, balance, "Deposit amount should persist");
    }

    function test_ClaimRewardsForCollection_YieldCapped() public {
        // 1. Setup initial state
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        _processSingleUserUpdate(USER_A, address(mockERC721), updateBlock, 3, 1000 ether); // Use actual mock address

        // 2. Accrue rewards
        uint256 claimBlock = block.number + 100;
        vm.roll(claimBlock);
        // REMOVED: mockCToken.accrueInterest(); // Accrue interest - preview/claim do this internally

        // 3. Preview rewards
        address[] memory collections = new address[](1);
        collections[0] = address(mockERC721); // Use actual mock address
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 expectedReward = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
        assertTrue(expectedReward > 0);

        // 4. Simulate INSUFFICIENT available yield in LendingManager
        uint256 availableYield = expectedReward / 2; // Cap based on initial preview expectation
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(lendingManager), availableYield);
        vm.stopPrank();
        lendingManager.setMockAvailableYield(availableYield); // Set the mock available yield
        uint256 userBalanceBefore = rewardToken.balanceOf(USER_A);

        // 6. Claim and Record Logs
        vm.recordLogs(); // Start recording events
        vm.startPrank(USER_A);
        rewardsController.claimRewardsForCollection(address(mockERC721), noSimUpdates); // Claim uses the already accrued index
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Get recorded events
        uint256 userBalanceAfter = rewardToken.balanceOf(USER_A);

        // 7. Verify Event: Find the RewardsClaimedForCollection event
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("RewardsClaimedForCollection(address,address,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedTopic0 && entries[i].topics[1] == bytes32(uint256(uint160(USER_A)))) {
                // Check user topic
                Vm.Log memory entry = entries[i];
                // Correct decoding: Cast the bytes32 topic to uint256, then uint160, then address
                address loggedCollection = address(uint160(uint256(entry.topics[2]))); // Decode indexed collection
                uint256 loggedAmount = abi.decode(entry.data, (uint256)); // Decode non-indexed amount

                assertEq(loggedCollection, address(mockERC721), "Event collection mismatch"); // Check collection topic
                // Check the amount emitted equals the available yield (cap)
                assertApproxEqAbs(
                    loggedAmount, availableYield, 1, "Emitted claimed amount should equal available yield when capped"
                );
                eventFound = true;
                break; // Found the event, exit loop
            }
        }
        assertTrue(eventFound, "RewardsClaimedForCollection event not found or user/collection mismatch");

        // 8. Verify user received the capped amount
        uint256 actualClaimed = userBalanceAfter - userBalanceBefore;
        assertApproxEqAbs(actualClaimed, availableYield, 1, "User received incorrect amount when capped");

        // Check internal state - accrued should store the deficit
        // (uint256 lastIdx, uint256 accrued,,, uint256 lastUpdate) =
        //     rewardsController.userNFTData(USER_A, address(mockERC721)); // Use actual mock address
        RewardsController.UserRewardState memory state =
            rewardsController.getUserRewardState(USER_A, address(mockERC721));
        // Deficit should be expectedReward - availableYield (since double accrual is fixed)
        assertApproxEqAbs(
            state.accruedReward,
            expectedReward - availableYield, // Deficit based on pre-manual accrual reward
            (expectedReward - availableYield) / 1000 + 1, // Allow 0.1% delta + 1 wei
            "Accrued deficit mismatch after capped claim"
        );
        assertTrue(state.lastRewardIndex >= rewardsController.globalRewardIndex(), "Last index should be updated");
        assertEq(state.lastUpdateBlock, block.number, "Last update block should be claim block");
    }

    function test_ClaimRewardsForCollection_ZeroRewards() public {
        // 1. Setup initial state (but don't accrue rewards)
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        _processSingleUserUpdate(USER_A, address(mockERC721), updateBlock, 3, 1000 ether); // Use actual mock address

        // 2. Preview rewards (should be 0)
        address[] memory collections = new address[](1);
        collections[0] = address(mockERC721); // Use actual mock address
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 expectedReward = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
        assertEq(expectedReward, 0, "Expected reward should be 0 before claim");

        // 3. Claim
        vm.startPrank(USER_A);
        uint256 userBalanceBefore = rewardToken.balanceOf(USER_A);
        // Expect claim event with 0 amount
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.RewardsClaimedForCollection(USER_A, address(mockERC721), 0); // Use actual mock address
        rewardsController.claimRewardsForCollection(address(mockERC721), noSimUpdates); // Use actual mock address
        uint256 userBalanceAfter = rewardToken.balanceOf(USER_A);
        vm.stopPrank();

        // 4. Verify
        uint256 actualClaimed = userBalanceAfter - userBalanceBefore;
        assertEq(actualClaimed, 0, "Claimed amount should be 0 when no rewards");

        // Check internal state reset (index and block updated, accrued remains 0)
        // (uint256 lastIdx, uint256 accrued,,, uint256 lastUpdate) =
        //     rewardsController.userNFTData(USER_A, address(mockERC721)); // Use actual mock address
        RewardsController.UserRewardState memory state =
            rewardsController.getUserRewardState(USER_A, address(mockERC721));
        assertEq(state.accruedReward, 0, "Accrued should be 0 after claim");
        assertTrue(state.lastRewardIndex >= rewardsController.globalRewardIndex(), "Last index should be updated");
        assertEq(state.lastUpdateBlock, block.number, "Last update block should be claim block");
    }

    function test_Revert_ClaimRewardsForCollection_NotWhitelisted() public {
        vm.startPrank(USER_A);
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.claimRewardsForCollection(NFT_COLLECTION_3, noSimUpdates); // Keep using non-whitelisted constant here
        vm.stopPrank();
    }
    // --- Simple Claim Test (from todo_initialization_admin_view.md line 44) ---

    function test_ClaimRewardsForCollection_Simple_Success() public {
        // 1. Setup: Use USER_A and mockERC721
        address user = USER_A;
        address collection = address(mockERC721); // Use actual mock address
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        uint256 nftCount = 5;
        uint256 balance = 2000 ether;
        _processSingleUserUpdate(user, collection, updateBlock, int256(nftCount), int256(balance));

        // 2. Advance time and accrue interest
        uint256 timePassed = 1 days; // Advance 1 day
        vm.warp(block.timestamp + timePassed); // Use warp for predictable time passage
        vm.roll(block.number + (timePassed / 12)); // Roll blocks roughly corresponding to time (assuming ~12s block time)
        // REMOVED: mockCToken.accrueInterest(); // previewRewards will now handle accrual

        // 3. Preview rewards (optional but good practice)
        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collection;
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 expectedReward = rewardsController.previewRewards(user, collectionsToPreview, noSimUpdates);
        assertTrue(expectedReward > 0, "Previewed reward should be greater than 0 after time passage");

        // 4. Ensure Lending Manager has sufficient yield
        uint256 yieldAmount = expectedReward * 2; // Provide more than needed based on initial preview expectation
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(lendingManager), yieldAmount);
        vm.stopPrank();
        uint256 userBalanceBefore = rewardToken.balanceOf(user);

        // 5. Call claimRewardsForCollection and record logs
        vm.recordLogs(); // Start recording
        vm.startPrank(user);
        // Expect event with correct user, collection, and amount
        // The amount emitted should be based on the claim calculation (1 accrual)
        // Use the reward previewed *before* the manual accrual for expectation
        vm.expectEmit(true, true, true, true, address(rewardsController));
        // Expect event with the pre-manual accrual amount
        emit IRewardsController.RewardsClaimedForCollection(user, collection, expectedReward);
        rewardsController.claimRewardsForCollection(collection, noSimUpdates);
        vm.stopPrank();
        // Vm.Log[] memory entries = vm.getRecordedLogs(); // No longer needed if expectEmit works
        uint256 userBalanceAfter = rewardToken.balanceOf(user);

        // 7. Verify Balance Change (Primary Check)
        uint256 actualClaimed = userBalanceAfter - userBalanceBefore;
        assertApproxEqAbs(
            actualClaimed,
            expectedReward, // Check against pre-manual accrual amount
            expectedReward / 1000,
            "User balance change mismatch"
        ); // 0.1% delta (tighter)

        // 8. Verify Event Data (Secondary Check - removed, rely on expectEmit)
        // bool eventFound = false;
        // bytes32 expectedTopic0 = keccak256("RewardsClaimedForCollection(address,address,uint256)");
        // bytes32 userTopic = bytes32(uint256(uint160(user)));
        // bytes32 collectionTopic = bytes32(uint256(uint160(collection)));
        // for (uint256 i = 0; i < entries.length; i++) {
        //     if (
        //         entries[i].topics.length == 3 && entries[i].topics[0] == expectedTopic0
        //             && entries[i].topics[1] == userTopic && entries[i].topics[2] == collectionTopic
        //     ) {
        //         (uint256 emittedAmount) = abi.decode(entries[i].data, (uint256));
        //         assertApproxEqAbs(
        //             emittedAmount,
        //             expectedRewardAfterAccrual, // Check against post-accrual amount
        //             expectedRewardAfterAccrual / 1000,
        //             "Emitted amount mismatch" // 0.1% delta (tighter)
        //         );
        //         eventFound = true;
        //         break;
        //     }
        // }
        // assertTrue(eventFound, "RewardsClaimedForCollection event not found or topics mismatch");

        // 9. Verify userNFTData state reset
        RewardsController.UserRewardState memory state = rewardsController.getUserRewardState(user, collection);
        assertEq(state.accruedReward, 0, "Accrued reward should be reset to 0 after claim");
        assertTrue(
            state.lastRewardIndex >= rewardsController.globalRewardIndex(), "User's lastRewardIndex should be updated"
        ); // Use >= due to potential index updates
        assertEq(state.lastUpdateBlock, block.number, "User's lastUpdateBlock should be the claim block number");
        // Ensure other state remains
        assertEq(state.lastNFTBalance, nftCount, "NFT balance should remain unchanged");
        assertEq(state.lastBalance, balance, "Balance should remain unchanged");
    }

    // --- claimRewardsForAll ---
    function test_ClaimRewardsForAll_MultipleCollections() public {
        // 1. Setup state for two collections
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, address(mockERC721), block1, 2, 500 ether); // Use actual mock address
        uint256 block2 = block.number + 1;
        vm.roll(block2);
        _processSingleUserUpdate(USER_A, address(mockERC721_2), block2, 1, 300 ether); // Use actual mock address

        // 2. Accrue rewards
        uint256 claimBlock = block.number + 100;
        vm.roll(claimBlock);
        // REMOVED: mockCToken.accrueInterest(); // Accrue interest - preview/claim do this internally

        // 3. Preview total rewards
        address[] memory allCols = rewardsController.getUserNFTCollections(USER_A);
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 totalExpectedRewardPreview = rewardsController.previewRewards(USER_A, allCols, noSimUpdates);
        // REMOVED: uint256 totalExpectedRewardClaim = totalExpectedRewardPreview; // Based on claim's 1 accrual
        assertTrue(totalExpectedRewardPreview > 0, "Total expected reward should be positive");

        // 4. Simulate available yield
        vm.startPrank(DAI_WHALE);
        // Provide yield based on initial preview expectation
        rewardToken.transfer(address(lendingManager), totalExpectedRewardPreview);
        vm.stopPrank();
        uint256 userBalanceBefore = rewardToken.balanceOf(USER_A);

        // 6. Claim All and Record Logs
        vm.recordLogs(); // Start recording events
        vm.startPrank(USER_A);
        // Expect event with pre-manual accrual preview amount
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.RewardsClaimedForAll(USER_A, totalExpectedRewardPreview);
        rewardsController.claimRewardsForAll(noSimUpdates);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Get recorded events
        uint256 userBalanceAfter = rewardToken.balanceOf(USER_A);

        // 6. Verify Balance Change
        uint256 actualClaimed = userBalanceAfter - userBalanceBefore;
        assertApproxEqAbs(
            actualClaimed,
            totalExpectedRewardPreview, // Expect pre-manual accrual preview amount
            totalExpectedRewardPreview / 1000, // 0.1% delta
            "Total claimed amount mismatch"
        );

        // 7. Verify Event Data (Removed - Rely on expectEmit)
        // bool eventFound = false;
        // bytes32 expectedTopic0 = keccak256("RewardsClaimedForAll(address,uint256)"); // <-- Keep first declaration
        // bytes32 userTopic = bytes32(uint256(uint160(USER_A)));
        // for (uint256 i = 0; i < entries.length; i++) {
        //     if (
        //         entries[i].topics.length == 2 && entries[i].topics[0] == expectedTopic0
        //             && entries[i].topics[1] == userTopic
        //     ) {
        //         (uint256 emittedAmount) = abi.decode(entries[i].data, (uint256));
        //         assertApproxEqAbs(
        //             emittedAmount,
        //             totalExpectedRewardAfterAccrual, // Check against post-accrual amount
        //             totalExpectedRewardAfterAccrual / 1000, // 0.1% delta
        //             "Emitted total claimed amount mismatch"
        //         );
        //         eventFound = true;
        //         break;
        //     }
        // }
        // assertTrue(eventFound, "RewardsClaimedForAll event not found or user mismatch");

        // 8. Verify state reset for both collections
        RewardsController.UserRewardState memory state1 =
            rewardsController.getUserRewardState(USER_A, address(mockERC721));
        RewardsController.UserRewardState memory state2 =
            rewardsController.getUserRewardState(USER_A, address(mockERC721_2));
        assertEq(state1.accruedReward, 0, "Accrued should be 0 for collection 1");
        assertEq(state2.accruedReward, 0, "Accrued should be 0 for collection 2");
        assertTrue(
            state1.lastRewardIndex >= rewardsController.globalRewardIndex(), "Index should be updated for collection 1"
        );
        assertTrue(
            state2.lastRewardIndex >= rewardsController.globalRewardIndex(), "Index should be updated for collection 2"
        );
        assertEq(state1.lastUpdateBlock, block.number, "Block should be updated for collection 1");
        assertEq(state2.lastUpdateBlock, block.number, "Block should be updated for collection 2");
    }

    function test_ClaimRewardsForAll_YieldCapped() public {
        // 1. Setup state for two collections
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, address(mockERC721), block1, 2, 500 ether);
        uint256 block2 = block.number + 1;
        vm.roll(block2);
        _processSingleUserUpdate(USER_A, address(mockERC721_2), block2, 1, 300 ether);

        // 2. Accrue rewards
        uint256 claimBlock = block.number + 100;
        vm.roll(claimBlock);

        // 3. Preview total rewards
        address[] memory allCols = rewardsController.getUserNFTCollections(USER_A); // Define allCols
        IRewardsController.BalanceUpdateData[] memory noSimUpdates; // Define noSimUpdates
        uint256 totalExpectedRewardPreview = rewardsController.previewRewards(USER_A, allCols, noSimUpdates);
        assertTrue(totalExpectedRewardPreview > 0);

        // 5. Simulate INSUFFICIENT available yield
        uint256 availableYield = totalExpectedRewardPreview / 3; // Use initial preview amount for calculation
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(lendingManager), availableYield);
        vm.stopPrank();
        lendingManager.setMockAvailableYield(availableYield);
        uint256 userBalanceBefore = rewardToken.balanceOf(USER_A);

        // 6. Claim All and Record Logs
        vm.recordLogs();
        vm.startPrank(USER_A);
        // Expect YieldTransferCapped event with pre-manual accrual preview amount as requested
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.YieldTransferCapped(USER_A, totalExpectedRewardPreview, availableYield);
        // Expect RewardsClaimedForAll event with the capped amount
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.RewardsClaimedForAll(USER_A, availableYield);

        rewardsController.claimRewardsForAll(noSimUpdates);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 userBalanceAfter = rewardToken.balanceOf(USER_A);

        // 7. Verify Balance Change
        uint256 actualClaimed = userBalanceAfter - userBalanceBefore;
        assertApproxEqAbs(actualClaimed, availableYield, 1, "User received incorrect total amount when capped");

        // 8. Verify Event Data (Removed - Rely on expectEmit)
        // bool eventFound = false;
        // bytes32 expectedTopic0 = keccak256("RewardsClaimedForAll(address,uint256)");
        // bytes32 userTopic = bytes32(uint256(uint160(USER_A)));
        // for (uint256 i = 0; i < entries.length; i++) {
        //     if (entries[i].topics[0] == expectedTopic0 && entries[i].topics[1] == userTopic) {
        //         uint256 emittedAmount = abi.decode(entries[i].data, (uint256));
        //         // Check if the emitted amount matches the available (capped) yield
        //         if (emittedAmount == availableYield) {
        //             eventFound = true;
        //             break;
        //         }
        //     }
        // }
        // assertTrue(eventFound, "RewardsClaimedForAll event not found or user/amount mismatch (capped)");

        // 9. Verify state reset ...
        // Check that accrued rewards (deficits) were stored correctly for each collection
        uint256 deficit1 = rewardsController.getUserRewardState(USER_A, address(mockERC721)).accruedReward;
        uint256 deficit2 = rewardsController.getUserRewardState(USER_A, address(mockERC721_2)).accruedReward;
        // The total deficit should be the difference between pre-manual accrual preview and available
        assertApproxEqAbs(
            deficit1 + deficit2, totalExpectedRewardPreview - availableYield, 2, "Total accrued deficit mismatch"
        );
    }
}
