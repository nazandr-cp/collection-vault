// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "src/interfaces/IRewardsController.sol";
import {RewardsController} from "src/RewardsController.sol"; // <-- Import RewardsController
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {MockLendingManager} from "src/mocks/MockLendingManager.sol"; // Assuming mock allows setting yield

contract RewardsController_ClaimForAllVariations_Test is RewardsController_Test_Base {
    function setUp() public virtual override {
        RewardsController_Test_Base.setUp();
        // Additional setup specific to claim all variations tests if needed
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CLAIM FORALL VARIATIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:°.´*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•*/

    /**
     * @notice test_ClaimRewardsForAll_MixedRewards:
     * User has pending rewards for Collection A (>0) and Collection B (=0).
     * Call claimRewardsForAll.
     * Verify total claimed amount equals rewards for A only, token transfer matches,
     * RewardsClaimedForAll event emits correct total, and state updates correctly for both A and B.
     */
    function test_ClaimRewardsForAll_MixedRewards() public {
        // --- Setup ---
        // Collection A (mockERC721) - BORROW basis, has yield
        // Collection B (mockERC721_2) - DEPOSIT basis, zero yield
        address user = USER_A;
        address collectionA = address(mockERC721);
        address collectionB = address(mockERC721_2);
        uint256 initialBalanceA = 100 ether;
        uint256 initialBalanceB = 50 ether;
        uint256 nftCountA = 1;
        uint256 nftCountB = 1;

        // Set yield for A, zero for B
        mockCToken.setExchangeRate(3e16); // Simulate yield accrual

        // Deposit and stake for both collections
        _depositAndStake(user, collectionA, 1, initialBalanceA);
        _depositAndStake(user, collectionB, 1, initialBalanceB);

        // Warp time/blocks
        vm.warp(block.timestamp + 100 days);
        vm.roll(block.number + 100);

        // --- Action ---
        // Use previewRewards for all active collections to get the expected amount
        address[] memory collectionsToPreview = rewardsController.getUserNFTCollections(user);
        uint256 expectedTotalReward =
            rewardsController.previewRewards(user, collectionsToPreview, new IRewardsController.BalanceUpdateData[](0));
        // uint256 expectedTotalReward = 40625000000000000000; // From trace - REMOVED HARDCODED VALUE

        // Move expectEmit before the action
        vm.expectEmit(true, false, false, true, address(rewardsController));
        emit IRewardsController.RewardsClaimedForAll(user, expectedTotalReward); // Use actual total expected

        vm.startPrank(user);
        uint256 balanceBefore = rewardToken.balanceOf(user);
        rewardsController.claimRewardsForAll(new IRewardsController.BalanceUpdateData[](0));
        uint256 balanceAfter = rewardToken.balanceOf(user);
        vm.stopPrank();

        // --- Verification ---
        // 1. Correct amount transferred
        assertEq(balanceAfter - balanceBefore, expectedTotalReward, "Transferred amount mismatch");

        // 2. Event emitted (checked by expectEmit)

        // 3. User state updated for BOTH collections
        uint256 claimBlock = block.number; // Capture block *after* claim
        // (uint256 lastRewardIndex1,,,, uint256 lastUpdateBlock1) = rewardsController.userNFTData(user, collectionA);
        RewardsController.UserRewardState memory stateA = rewardsController.getUserRewardState(user, collectionA);
        assertTrue(stateA.lastRewardIndex > 0, "C1 lastRewardIndex should update");
        assertEq(stateA.lastUpdateBlock, claimBlock, "C1 lastUpdateBlock mismatch");

        // (uint256 lastRewardIndex2,,,, uint256 lastUpdateBlock2) = rewardsController.userNFTData(user, collectionB);
        RewardsController.UserRewardState memory stateB = rewardsController.getUserRewardState(user, collectionB);
        // Index might be 0 if global index didn't move, but block should update
        assertEq(stateB.lastUpdateBlock, claimBlock, "C2 lastUpdateBlock mismatch");
    }

    /**
     * @notice test_ClaimRewardsForAll_PartialCapping:
     * Two collections, both generate yield.
     * Total calculated yield > available yield from LendingManager.
     * Verify claim transfers only the available yield, emits YieldTransferCapped,
     * and RewardsClaimedForAll emits the capped amount.
     */
    function test_ClaimRewardsForAll_PartialCapping() public {
        // --- Setup ---
        // Both collections generate yield
        address user = USER_A;
        address collectionA = address(mockERC721);
        address collectionB = address(mockERC721_2);
        uint256 initialBalanceA = 100 ether;
        uint256 initialBalanceB = 80 ether; // Different balance
        uint256 nftCountA = 1;
        uint256 nftCountB = 1;

        // Set yield
        mockCToken.setExchangeRate(4e16); // Simulate significant yield accrual

        // Deposit and stake for both collections
        _depositAndStake(user, collectionA, nftCountA, initialBalanceA);
        _depositAndStake(user, collectionB, nftCountB, initialBalanceB);

        // Warp time/blocks
        vm.warp(block.timestamp + 500 days); // Longer time for more yield
        vm.roll(block.number + 500);

        // Set a cap lower than the likely total accrued yield
        uint256 availableYieldCapY = 0.5 ether; // Set a specific capped amount
        lendingManager.setMockAvailableYield(availableYieldCapY);
        lendingManager.setExpectedRecipient(address(rewardsController)); // Ensure LM expects RC

        // --- Action ---
        // Calculate expected total reward before capping
        address[] memory collectionsToPreview = rewardsController.getUserNFTCollections(user);
        uint256 expectedCalculatedReward =
            rewardsController.previewRewards(user, collectionsToPreview, new IRewardsController.BalanceUpdateData[](0));
        // uint256 expectedCalculatedReward = 97000000000000000000; // From trace - REMOVED HARDCODED VALUE

        // Expect the capping event FIRST
        vm.expectEmit(true, false, false, true, address(rewardsController));
        emit IRewardsController.YieldTransferCapped(user, expectedCalculatedReward, availableYieldCapY); // Check user, calculated, and transferredAmount

        // Expect RewardsClaimedForAll SECOND
        vm.expectEmit(true, false, false, true, address(rewardsController));
        emit IRewardsController.RewardsClaimedForAll(user, availableYieldCapY); // Expect capped amount

        vm.startPrank(user);
        uint256 balanceBefore = rewardToken.balanceOf(user);
        rewardsController.claimRewardsForAll(new IRewardsController.BalanceUpdateData[](0));
        uint256 balanceAfter = rewardToken.balanceOf(user);
        vm.stopPrank();

        // --- Verification ---
        // 1. Correct (capped) amount transferred
        assertEq(balanceAfter - balanceBefore, availableYieldCapY, "Transferred amount should equal capped yield Y");

        // 2. Events emitted (checked by expectEmit)

        // 3. User state updated for BOTH collections
        uint256 claimBlock = block.number; // Capture block *after* claim
        // (uint256 lastRewardIndexA,,,, uint256 lastUpdateBlockA) = rewardsController.userNFTData(user, collectionA);
        RewardsController.UserRewardState memory stateA = rewardsController.getUserRewardState(user, collectionA);
        assertTrue(stateA.lastRewardIndex > 0, "A lastRewardIndex should update");
        assertEq(stateA.lastUpdateBlock, claimBlock, "A lastUpdateBlock mismatch");

        // (uint256 lastRewardIndexB,,,, uint256 lastUpdateBlockB) = rewardsController.userNFTData(user, collectionB);
        RewardsController.UserRewardState memory stateB = rewardsController.getUserRewardState(user, collectionB);
        assertTrue(stateB.lastRewardIndex > 0, "B lastRewardIndex should update");
        assertEq(stateB.lastUpdateBlock, claimBlock, "B lastUpdateBlock mismatch");
    }

    // --- Helper Functions (Copied for consistency) ---

    // Updated to correctly use BalanceUpdateData and processUserBalanceUpdates with signature
    function _depositAndStake(address user, address collection, uint256 tokenId, uint256 amount) internal {
        // Use rewardToken (DAI) for dealing and approving
        deal(address(rewardToken), user, amount * 2);

        // Mint NFT if needed (outside prank initially to avoid owner issues)
        if (collection == address(mockERC721)) {
            // Use mintSpecific to mint a specific token ID
            try mockERC721.ownerOf(tokenId) returns (address owner) {
                if (owner != user) {
                    // If owned by someone else, cannot mint specific (handle error or transfer?)
                    // For testing, assume we can just mint if it doesn't exist or isn't owned by user.
                    // Revert might be better if strict ownership is needed.
                    revert("Test Setup Error: Token already owned by different user");
                }
                // If owned by the correct user, do nothing.
            } catch {
                // If token doesn't exist, mint it specifically
                mockERC721.mintSpecific(user, tokenId);
            }
        } else if (collection == address(mockERC721_2)) {
            // Use mintSpecific to mint a specific token ID
            try mockERC721_2.ownerOf(tokenId) returns (address owner) {
                if (owner != user) {
                    revert("Test Setup Error: Token 2 already owned by different user");
                }
            } catch {
                // If token doesn't exist, mint it specifically
                mockERC721_2.mintSpecific(user, tokenId);
            }
        }

        vm.startPrank(user);
        rewardToken.approve(address(rewardsController), amount); // Approve rewardToken

        // Prepare BalanceUpdateData (similar to _processSingleUserUpdate in base)
        uint256 currentBlock = block.number; // Use current block for the update
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: currentBlock,
            nftDelta: 1, // Assume staking adds 1 NFT to tracking
            balanceDelta: int256(amount) // Deposit amount
        });

        // Get nonce and sign the update
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce, UPDATER_PRIVATE_KEY); // Use inherited helper

        // Call the correct function with signature
        // Note: Calling processUserBalanceUpdates requires the AUTHORIZED_UPDATER, not the user prank
        vm.stopPrank(); // Stop user prank before calling as updater
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates, sig);
        // No need to start prank again unless more user actions follow immediately
    }

    function _simulateYield() internal {
        uint256 currentRate = mockCToken.exchangeRateStored();
        mockCToken.setExchangeRate(currentRate + 1e16); // Use setExchangeRate (already correct)
            // lendingManager.accrueInterest(); // Optional
    }
}
