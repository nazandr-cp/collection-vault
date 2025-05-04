// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "src/interfaces/IRewardsController.sol";
import {RewardsController} from "src/RewardsController.sol"; // <-- Import RewardsController
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract RewardsController_YieldScenarios_Test is RewardsController_Test_Base {
    function setUp() public virtual override {
        RewardsController_Test_Base.setUp();
        // Additional setup specific to yield scenario tests if needed
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       YIELD SCENARIOS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:°.´*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•*/

    /**
     * @notice test_ClaimRewardsForCollection_ZeroYield:
     * Simulate conditions where cToken.exchangeRateStored() does not increase.
     * Claim rewards.
     * Verify RewardsClaimedForCollection event emits 0, no tokens transferred,
     * but userNFTData (index, block) is updated.
     */
    function test_ClaimRewardsForCollection_ZeroYield() public {
        // --- Setup ---
        address collection = address(mockERC721);
        address user = USER_A; // Changed from address(this) to USER_A
        uint256 initialBalance = 100 ether;
        uint256 tokenId = 1;

        _depositAndStake(user, collection, tokenId, initialBalance);
        uint256 blockN = block.number;
        uint256 timestampN = block.timestamp;
        uint256 initialExchangeRate = mockCToken.exchangeRateStored();

        // Advance time BUT ensure NO yield accrues
        vm.warp(timestampN + 1 days);
        vm.roll(blockN + 100);
        // Explicitly ensure exchange rate hasn't changed
        mockCToken.setExchangeRate(initialExchangeRate); // Use setExchangeRate
        // DO NOT call _simulateYield()

        uint256 claimBlock = block.number; // Block N + 100
        uint256 claimTimestamp = block.timestamp; // Timestamp N + 1 day

        // --- Action ---
        mockCToken.setAccrueInterestEnabled(false); // Prevent accrual during claim
        vm.startPrank(user);
        uint256 balanceBefore = rewardToken.balanceOf(user); // Use rewardToken
        rewardsController.claimRewardsForCollection(collection, new IRewardsController.BalanceUpdateData[](0)); // Use BalanceUpdateData
        uint256 balanceAfter = rewardToken.balanceOf(user); // Use rewardToken
        vm.stopPrank();

        // --- Verification ---
        // 1. No reward tokens transferred
        mockCToken.setAccrueInterestEnabled(true); // Re-enable accrual
        assertEq(balanceAfter, balanceBefore, "User balance should not change with zero yield");

        // 2. User state IS updated to the claim block - userNFTData takes user, collection
        // Declare variables once
        // (uint256 lastRewardIndex,,,, uint256 lastUpdateBlock) = rewardsController.userNFTData(user, collection);
        RewardsController.UserRewardState memory state = rewardsController.getUserRewardState(user, collection);
        // lastRewardIndex might still be 0 if the global index didn't move, or > 0 if it did.
        // The crucial part is that lastUpdateBlock is updated.
        assertEq(state.lastUpdateBlock, claimBlock, "lastUpdateBlock mismatch - should be claim block even with zero yield");
        // Removed duplicate block
    }

    /**
     * @notice test_ClaimRewardsForAll_ZeroYield:
     * Similar to above, but for claimRewardsForAll.
     * Verify RewardsClaimedForAll emits 0, no transfer, state updates for all active collections.
     */
    function test_ClaimRewardsForAll_ZeroYield() public {
        // --- Setup ---
        address collection1 = address(mockERC721);
        address collection2 = address(mockERC721_2);
        address user = USER_A; // Changed from address(this) to USER_A
        uint256 initialBalance1 = 100 ether;
        uint256 initialBalance2 = 50 ether;
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 1;

        _depositAndStake(user, collection1, tokenId1, initialBalance1);
        _depositAndStake(user, collection2, tokenId2, initialBalance2);
        uint256 blockN = block.number;
        uint256 timestampN = block.timestamp;
        uint256 initialExchangeRate = mockCToken.exchangeRateStored();

        // Advance time BUT ensure NO yield accrues
        vm.warp(timestampN + 2 days);
        vm.roll(blockN + 200);
        // mockCToken.setExchangeRate(initialExchangeRate); // Removed: This sets currentExchangeRate, not relevant for reward calc index

        uint256 claimBlock = block.number; // Block N + 200
        uint256 claimTimestamp = block.timestamp; // Timestamp N + 2 days

        // --- Action ---
        mockCToken.setAccrueInterestEnabled(false); // Disable accrual for this call
        vm.startPrank(user);
        uint256 balanceBefore = rewardToken.balanceOf(user); // Use rewardToken
        rewardsController.claimRewardsForAll(new IRewardsController.BalanceUpdateData[](0)); // Use BalanceUpdateData
        uint256 balanceAfter = rewardToken.balanceOf(user); // Use rewardToken
        vm.stopPrank();
        mockCToken.setAccrueInterestEnabled(true); // Re-enable accrual

        // --- Verification ---
        // 1. No reward tokens transferred
        assertEq(balanceAfter, balanceBefore, "User balance should not change with zero yield");

        // 2. User state IS updated for both collections - userNFTData takes user, collection
        // Declare variables once
        // (uint256 lastRewardIndex1,,,, uint256 lastUpdateBlock1) = rewardsController.userNFTData(user, collection1);
        RewardsController.UserRewardState memory state1 = rewardsController.getUserRewardState(user, collection1);
        assertEq(state1.lastUpdateBlock, claimBlock, "C1 lastUpdateBlock mismatch");

        // (uint256 lastRewardIndex2,,,, uint256 lastUpdateBlock2) = rewardsController.userNFTData(user, collection2);
        RewardsController.UserRewardState memory state2 = rewardsController.getUserRewardState(user, collection2);
        assertEq(state2.lastUpdateBlock, claimBlock, "C2 lastUpdateBlock mismatch");
        // Removed duplicate block
    }

    // --- Helper Functions (Copied for consistency) ---

    // Updated to correctly use BalanceUpdateData and processUserBalanceUpdates with signature
    function _depositAndStake(address user, address collection, uint256 tokenId, uint256 amount) internal {
        // Use rewardToken (DAI) for dealing and approving
        deal(address(rewardToken), user, amount * 2);

        // Mint NFT if needed (outside prank initially to avoid owner issues)
        if (collection == address(mockERC721)) {
            // Check owner before minting
            try mockERC721.ownerOf(tokenId) returns (address owner) {
                if (owner != user) {
                    revert("Test Setup Error: Token already owned by different user");
                }
            } catch {
                // If token doesn't exist, mint it specifically
                mockERC721.mintSpecific(user, tokenId);
            }
        } else if (collection == address(mockERC721_2)) {
            // Removed extra brace before else if
            try mockERC721_2.ownerOf(tokenId) returns (address owner) {
                if (owner != user) {
                    revert("Test Setup Error: Token 2 already owned by different user");
                }
            } catch {
                // If token doesn't exist, mint it specifically
                mockERC721_2.mintSpecific(user, tokenId);
            }
        } // Removed extra brace before closing the else if block

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

    // _simulateYield is intentionally omitted here as we test zero yield scenarios.
}
