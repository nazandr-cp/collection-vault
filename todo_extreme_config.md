Extreme Beta Values
[ ] test_PreviewRewards_ZeroBeta: Set beta = 0 for a collection using updateBeta. Process update, accrue time/interest, preview rewards. Verify preview returns 0 (as boost factor becomes 0).
[ ] test_PreviewRewards_VeryLargeBeta: Set a very large beta such that nftBalance * beta would exceed PRECISION_FACTOR * 9. Process update, accrue time/interest, preview rewards. Verify the reward calculation correctly uses the capped boost factor internally.
Extreme Reward Shares
[ ] test_PreviewRewards_ZeroRewardShare: Set rewardSharePercentage = 0 for a collection. Process update, accrue time/interest, preview rewards. Verify preview returns 0 (as allocated yield becomes 0).
[ ] test_PreviewRewards_MaxRewardShare: Set rewardSharePercentage = 10000 (100%). Process update, accrue time/interest, preview rewards. Verify preview calculation uses the full yield reward (before boost).
[ ] test_ClaimRewards_ZeroRewardShare: Claim rewards for a collection with rewardSharePercentage = 0. Verify 0 rewards claimed, state updates.
[ ] test_ClaimRewards_MaxRewardShare: Claim rewards for a collection with rewardSharePercentage = 10000. Verify full potential reward (subject to LM yield) is claimed.
Max NFT Boost Cap
[ ] test_CalculateBoost_MaxCap: Call calculateBoost with nftBalance and beta such that nftBalance * beta > PRECISION_FACTOR * 9. Verify it returns exactly PRECISION_FACTOR * 9.
[ ] test_PreviewRewards_MaxBoost: Use NFT balance and beta that trigger the boost cap. Preview rewards and verify the calculation reflects the capped boost.
Large Balances / Amounts
[ ] test_ProcessUpdate_LargeBalanceDelta: Process an update with a very large positive balanceDelta (e.g., type(uint256).max / 10). Verify state updates correctly.
[ ] test_PreviewRewards_LargeBalance: Have a user state with a very large lastBalance. Accrue rewards and preview. Verify calculation handles large numbers without overflow (expected with Solidity 0.8+).
[ ] test_ClaimRewards_LargeAmount: Simulate a scenario leading to a very large reward amount. Provide sufficient yield in LM. Claim rewards and verify transfer and state updates.
Many Whitelisted Collections
[ ] test_AddNFTCollection_Many: Add a large number of collections (e.g., 20+) via addNFTCollection. Verify success.
[ ] test_GetWhitelistedCollections_Many: Call getWhitelistedCollections after adding many collections. Verify all are returned. Check gas usage.
[ ] test_ClaimRewardsForAll_ManyActive: Have a user with updates/balances across many active collections (e.g., 20+). Call claimRewardsForAll. Verify success and check gas usage (see todo_gas_performance.md).
