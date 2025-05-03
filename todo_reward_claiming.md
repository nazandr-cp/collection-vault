Claim Timing & Updates
[ ] test_ClaimRewardsForCollection_AfterSameBlockUpdate: Process an update at block N. In the same block N, claim rewards for that collection. Verify rewards are calculated based on the state before the update in block N (zero duration for the last period), state is updated correctly post-claim.
[ ] test_ClaimRewardsForAll_AfterSameBlockUpdate: Process updates for multiple collections at block N. In the same block N, claim rewards for all. Verify rewards and state updates.
Claiming with Simulation
[ ] test_ClaimRewardsForCollection_WithFutureSimulation: Accrue rewards up to block N. Call claimRewardsForCollection at block N, providing simulatedUpdates with blockNumber > N. Verify the claim processes rewards only up to block N, the simulation doesn't affect the claimed amount, and the user's state (lastRewardIndex, lastUpdateBlock) is updated to block N.
[ ] test_ClaimRewardsForAll_WithFutureSimulation: Accrue rewards up to block N. Call claimRewardsForAll at block N, providing simulatedUpdates with blockNumber > N. Verify claim processes rewards only up to block N for all active collections.
Yield Scenarios
[ ] test_ClaimRewardsForCollection_ZeroYield: Simulate conditions where cToken.exchangeRateStored() does not increase between the user's last update and the claim block (e.g., by manually setting the rate or using a mock cToken if necessary). Claim rewards. Verify RewardsClaimedForCollection event emits 0, no tokens are transferred, but userNFTData (index, block) is updated.
[ ] test_ClaimRewardsForAll_ZeroYield: Similar to above, but for claimRewardsForAll. Verify RewardsClaimedForAll emits 0, no transfer, state updates for all active collections.
First Claim
[ ] test_ClaimRewardsForCollection_FirstEverClaim: For a brand new user/collection, process the very first update at block N. Advance time, accrue interest. Claim rewards. Verify correct calculation and state update (ensuring initial lastRewardIndex = 0 is handled gracefully if applicable, though _processSingleUpdate should set it).
Claim ForAll Variations
[ ] test_ClaimRewardsForAll_MixedRewards: User has pending rewards for Collection A (>0) and Collection B (=0, e.g., due to 0 NFTs or 0 balance during the period). Call claimRewardsForAll. Verify total claimed amount equals rewards for A only, token transfer matches, RewardsClaimedForAll event emits correct total, and state updates correctly for both A and B.
[ ] test_ClaimRewardsForAll_PartialCapping: User has pending rewards R_A for Collection A and R_B for Collection B. Total R = R_A + R_B. Simulate LendingManager having available yield Y such that 0 < Y < R. Call claimRewardsForAll. Verify total transferred amount equals Y, RewardsClaimedForAll event emits Y, and accruedReward is 0 for both A and B post-claim.
