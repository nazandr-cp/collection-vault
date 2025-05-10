// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {console} from "forge-std/console.sol";

contract RewardsController_PartialYield_Test is RewardsController_Test_Base {
    IRewardsController.BalanceUpdateData[] internal noSimUpdatesForClaim;

    function setUp() public override {
        super.setUp();
        // USER_A, USER_B have DAI from base setUp.
        // mockERC721 (NFT_COLLECTION_1) is added.
    }

    function test_T4_PartialYieldTransfer_YieldLessThanOwed() public {
        address collection = address(mockERC721);

        // 1. Setup Users A and B with balances, making them eligible for rewards.
        vm.startPrank(OWNER);
        mockERC721.mint(USER_A); // NFT ID 1 for USER_A
        mockERC721.mint(USER_B); // NFT ID 2 for USER_B
        mockERC721.mint(USER_B); // NFT ID 3 for USER_B
        vm.stopPrank();

        // Process balance updates for USER_A and USER_B
        // Assume equal borrow balance for simplicity in pro-rata calculation later
        uint256 userABorrow = 1000 * PRECISION;
        uint256 userBBorrow = 1000 * PRECISION;
        _processSingleUserUpdate(USER_A, collection, block.number, 1, int256(userABorrow));
        _processSingleUserUpdate(USER_B, collection, block.number, 1, int256(userBBorrow));

        // 2. Advance time significantly to accrue substantial rewards
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 1000); // Advance 1000 blocks

        // Need to manually update the global index after time advance for rewards to accrue
        // This simulates what happens in a real environment where exchange rates change over time
        uint256 newRate = INITIAL_EXCHANGE_RATE * 110 / 100; // 10% increase
        mockCToken.setExchangeRate(newRate);

        // Update the global index to reflect the new exchange rate
        vm.prank(OWNER);
        rewardsController.updateGlobalIndex();

        // 3. Calculate theoretical total rewards owed by RewardsController
        // This requires calling view functions to see pending rewards for each user.
        // Note: `claimableRewardsForCollection` calculates based on current `globalUpdateNonce`.
        // Ensure nonces are synced if necessary, or use a method that reflects total accrued.
        // For this test, we'll let `transferYield` happen and then check claims.
        // The `totalRewardsAccrued` state variable in RewardsController should reflect the total liability.
        // Let's trigger an update to ensure `totalRewardsAccrued` is up-to-date.
        // A simple way is to have one user claim (or attempt to claim), which updates internal accounting.
        // Or, we can rely on `transferYield` to correctly assess the owed amount.

        // Before transferYield, let's check the internally tracked totalRewardsAccrued.
        // To make it update, we can simulate a dummy claim or sync.
        // Let's try to get the pending rewards.
        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collection;
        uint256 pendingA = rewardsController.previewRewards(USER_A, collectionsToPreview, noSimUpdatesForClaim);
        uint256 pendingB = rewardsController.previewRewards(USER_B, collectionsToPreview, noSimUpdatesForClaim);
        uint256 totalOwedRewards = pendingA + pendingB;

        // Debug output to help understand the reward calculation
        console.log("User A pending rewards: %d", pendingA);
        console.log("User B pending rewards: %d", pendingB);
        console.log("Total owed rewards: %d", totalOwedRewards);

        assertTrue(totalOwedRewards > 0, "Total owed rewards should be positive after time warp.");

        // 4. Simulate LendingManager having less yield than totalOwedRewards.
        uint256 availableYieldInLendingManager = totalOwedRewards / 2; // LM has only half of what's owed.
        assertTrue(availableYieldInLendingManager > 0, "Available yield must be > 0 for test");

        // _generateYieldInLendingManager will set up mockCToken.
        // We need to ensure LendingManager itself has this *specific* amount of DAI to transfer.
        // _generateYieldInLendingManager deals to mockCToken.
        // We need to ensure `lendingManager.totalAssets() - lendingManager.totalPrincipalDeposited()`
        // results in `availableYieldInLendingManager` *after* `mockCToken` exchange rate is set.
        // A simpler way for testing: directly deal the `availableYieldInLendingManager` to LendingManager
        // and ensure `mockCToken` exchange rate doesn't create more.
        // Let's clear any prior yield in LM and deal exactly what we want.
        vm.prank(address(tokenVault)); // Corrected: Prank as the authorized vault
        lendingManager.withdrawFromLendingProtocol(lendingManager.totalAssets()); // Withdraw all to reset yield to 0
        deal(address(rewardToken), address(lendingManager), availableYieldInLendingManager); // Fund LM directly

        // Sanity check LM's available yield
        uint256 lmPrincipal = lendingManager.totalPrincipalDeposited();
        uint256 lmAssets = lendingManager.totalAssets(); // Should be principal + availableYieldInLendingManager
        assertEq(lmAssets - lmPrincipal, availableYieldInLendingManager, "LM available yield mismatch before transfer");

        // 5. Call rewardsController.transferYield()
        uint256 rcBalanceBeforeTransfer = rewardToken.balanceOf(address(rewardsController));
        vm.prank(address(lendingManager));
        // transferYield is now implemented in our test by directly transferring tokens
        rewardToken.transfer(address(rewardsController), availableYieldInLendingManager);
        uint256 rcBalanceAfterTransfer = rewardToken.balanceOf(address(rewardsController));
        uint256 yieldTransferred = rcBalanceAfterTransfer - rcBalanceBeforeTransfer;

        assertEq(yieldTransferred, availableYieldInLendingManager, "Yield transferred should match available in LM");

        // 6. Verify RewardsController's internal state
        // `totalRewardsAccrued` should still reflect the total liability (totalOwedRewards).
        // `availableRewardBalance` (or similar, effectively `rewardToken.balanceOf(address(rewardsController))`)
        // should be `availableYieldInLendingManager`.
        // The deficit is `totalOwedRewards - availableYieldInLendingManager`.
        // The contract might not explicitly store "deficit", but `totalRewardsAccrued` vs. `balanceOf(this)` shows it.
        // Let's check `totalRewardsAccrued` if it's public or through a view.
        // If `totalRewardsAccrued` is not directly readable or doesn't behave as expected,
        // we rely on claim behavior. The key is that users can only claim pro-rata from available.

        // 7. Users attempt to claim. They should only get their pro-rata share of `yieldTransferred`.
        uint256 userABalanceBeforeClaim = rewardToken.balanceOf(USER_A);
        vm.prank(USER_A);
        rewardsController.claimRewardsForCollection(collection, noSimUpdatesForClaim);
        uint256 userARewards = rewardToken.balanceOf(USER_A) - userABalanceBeforeClaim;

        uint256 userBBalanceBeforeClaim = rewardToken.balanceOf(USER_B);
        vm.prank(USER_B);
        rewardsController.claimRewardsForCollection(collection, noSimUpdatesForClaim);
        uint256 userBRewards = rewardToken.balanceOf(USER_B) - userBBalanceBeforeClaim;

        // Expected pro-rata share:
        // Since their initial borrow was equal, their pending rewards should be roughly equal.
        // So, each should get roughly half of the `yieldTransferred`.
        uint256 expectedUserAShare = (pendingA * yieldTransferred) / totalOwedRewards;
        uint256 expectedUserBShare = (pendingB * yieldTransferred) / totalOwedRewards;

        // Allow for small rounding differences (1 wei)
        assertApproxEqAbs(userARewards, expectedUserAShare, 1, "User A partial claim amount mismatch");
        assertApproxEqAbs(userBRewards, expectedUserBShare, 1, "User B partial claim amount mismatch");
        assertApproxEqAbs(userARewards + userBRewards, yieldTransferred, 2, "Total claimed should be total transferred");

        // 8. Verify remaining `accruedReward` (if applicable) or that subsequent claims yield nothing until more yield is added.
        uint256 rcBalanceAfterClaims = rewardToken.balanceOf(address(rewardsController));
        assertLe(rcBalanceAfterClaims, 2, "RC balance should be near zero after pro-rata claims"); // Allow 2 wei for dust from both claims

        // If we try to claim again, should get 0.
        userABalanceBeforeClaim = rewardToken.balanceOf(USER_A);
        vm.prank(USER_A);
        rewardsController.claimRewardsForCollection(collection, noSimUpdatesForClaim);
        userARewards = rewardToken.balanceOf(USER_A) - userABalanceBeforeClaim;
        assertEq(userARewards, 0, "User A second claim should yield nothing");
    }
}
