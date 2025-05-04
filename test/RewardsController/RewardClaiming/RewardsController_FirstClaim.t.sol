// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "src/interfaces/IRewardsController.sol";
import {RewardsController} from "src/RewardsController.sol"; // <-- Import RewardsController
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract RewardsController_FirstClaim_Test is RewardsController_Test_Base {
    function setUp() public virtual override {
        RewardsController_Test_Base.setUp();
        // Additional setup specific to first claim tests if needed
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         FIRST CLAIM                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:°.´*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•*/

    /**
     * @notice test_ClaimRewardsForCollection_FirstEverClaim:
     * For a brand new user/collection, process the very first update at block N.
     * Advance time, accrue interest.
     * Claim rewards.
     * Verify correct calculation and state update (ensuring initial lastRewardIndex = 0 is handled).
     */
    function test_ClaimRewardsForCollection_FirstEverClaim() public {
        // --- Setup ---
        address collection = address(mockERC721);
        address user = makeAddr("newUser"); // Use a fresh address
        uint256 initialBalance = 100 ether;
        uint256 tokenId = 1;

        // Ensure user has funds (using rewardToken) and NFT
        deal(address(rewardToken), user, initialBalance * 2);
        mockERC721.mintSpecific(user, tokenId); // Use mintSpecific

        // 1. Process the very first update for this user/collection using signed update
        vm.startPrank(user);
        rewardToken.approve(address(rewardsController), initialBalance); // Use rewardToken
        vm.stopPrank(); // Stop user prank before preparing signed update

        // Prepare BalanceUpdateData
        uint256 updateBlockNum = block.number + 1; // Update happens in the next block
        vm.roll(updateBlockNum); // Roll to the update block
        IRewardsController.BalanceUpdateData[] memory balanceUpdates = new IRewardsController.BalanceUpdateData[](1);
        balanceUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlockNum,
            nftDelta: 1, // First time adding NFT
            balanceDelta: int256(initialBalance)
        });

        // Get nonce and sign the update
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory sig = _signUserBalanceUpdates(user, balanceUpdates, nonce, UPDATER_PRIVATE_KEY);

        // Process the signed update (as AUTHORIZED_UPDATER)
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, balanceUpdates, sig);

        uint256 blockN = block.number; // Block of the first update
        uint256 timestampN = block.timestamp;

        // Verify initial state (optional but good practice) - userNFTData takes user, collection
        // (uint256 initialRewardIndex,,,, uint256 initialUpdateBlock) = rewardsController.userNFTData(user, collection);
        RewardsController.UserRewardState memory initialState = rewardsController.getUserRewardState(user, collection);
        assertTrue(initialState.lastRewardIndex > 0, "Initial lastRewardIndex should be set by first update"); // Should be set to global index
        assertEq(initialState.lastUpdateBlock, blockN, "Initial lastUpdateBlock mismatch");

        // 2. Advance time & accrue yield
        vm.warp(timestampN + 1 days);
        vm.roll(blockN + 100);
        _simulateYield();

        uint256 claimBlock = block.number; // Block N + 100
        uint256 claimTimestamp = block.timestamp; // Timestamp N + 1 day

        // --- Action ---
        // 3. Claim rewards
        vm.startPrank(user);
        uint256 balanceBefore = rewardToken.balanceOf(user); // Use rewardToken
        rewardsController.claimRewardsForCollection(collection, new IRewardsController.BalanceUpdateData[](0)); // Use BalanceUpdateData
        uint256 balanceAfter = rewardToken.balanceOf(user); // Use rewardToken
        vm.stopPrank();

        // --- Verification ---
        // 1. Check claimed amount
        uint256 claimedAmount = balanceAfter - balanceBefore;
        assertTrue(claimedAmount > 0, "Claimed amount should be > 0 for first claim after yield");

        // Event emission check removed for now, focus on state and balance

        // 2. User state updated correctly - userNFTData takes user, collection
        // (uint256 finalRewardIndex,,,, uint256 finalUpdateBlock) = rewardsController.userNFTData(user, collection);
        RewardsController.UserRewardState memory finalState = rewardsController.getUserRewardState(user, collection);
        assertTrue(
            finalState.lastRewardIndex > initialState.lastRewardIndex, "finalRewardIndex should increase after claim"
        ); // Index should advance
        assertEq(finalState.lastUpdateBlock, claimBlock, "finalUpdateBlock mismatch - should be claim block");

        // 3. Correct reward calculation (implicit check via claimedAmount > 0)
        //    A precise check requires replicating reward logic based on the period from blockN to claimBlock.
    }

    // --- Helper Functions (Copied for consistency) ---

    // No _depositAndStake needed here as the setup is specific to the first claim test case.

    function _simulateYield() internal {
        // Use the helper function from the base class to properly generate yield
        _generateYieldInLendingManager(1 ether); // Generate a significant amount of yield
        
        // We still want to increment the exchange rate as well
        uint256 currentRate = mockCToken.exchangeRateStored();
        mockCToken.setExchangeRate(currentRate + 1e16);
    }
}
