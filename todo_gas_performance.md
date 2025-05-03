Setup
Use Foundry's gas reporting features (forge test --gas-report).
Balance Updates
[ ] test_Gas_ProcessUserBalanceUpdates_Single: Measure gas for processing a single update via processUserBalanceUpdates.
[ ] test_Gas_ProcessUserBalanceUpdates_Batch_10: Measure gas for processing a batch of 10 updates via processUserBalanceUpdates.
[ ] test_Gas_ProcessUserBalanceUpdates_Batch_50: Measure gas for processing a batch of 50 updates via processUserBalanceUpdates.
[ ] test_Gas_ProcessUserBalanceUpdates_Batch_100: Measure gas for processing a batch of 100 updates via processUserBalanceUpdates. (Observe potential block gas limit issues).
[ ] test_Gas_ProcessBalanceUpdates_Batch_10: Measure gas for processing a multi-user batch of 10 updates via processBalanceUpdates.
[ ] test_Gas_ProcessBalanceUpdates_Batch_50: Measure gas for processing a multi-user batch of 50 updates via processBalanceUpdates.
[ ] test_Gas_ProcessBalanceUpdates_Batch_100: Measure gas for processing a multi-user batch of 100 updates via processBalanceUpdates. (Observe potential block gas limit issues).
Claiming
[ ] test_Gas_ClaimRewardsForCollection_Simple: Measure gas for a simple claimRewardsForCollection (1 active collection).
[ ] test_Gas_ClaimRewardsForAll_1_Collection: Measure gas for claimRewardsForAll when the user has 1 active collection.
[ ] test_Gas_ClaimRewardsForAll_5_Collections: Measure gas for claimRewardsForAll when the user has 5 active collections.
[ ] test_Gas_ClaimRewardsForAll_20_Collections: Measure gas for claimRewardsForAll when the user has 20 active collections. (Observe potential gas increase per collection).
View Functions (Optional)
[ ] test_Gas_PreviewRewards_Single: Measure gas for previewRewards with 1 collection, no simulation.
[ ] test_Gas_PreviewRewards_Multiple: Measure gas for previewRewards with multiple collections (e.g., 10), no simulation.
[ ] test_Gas_PreviewRewards_WithSimulation: Measure gas for previewRewards with simulation updates.
[ ] test_Gas_GetWhitelistedCollections_Many: Measure gas for getWhitelistedCollections when many collections are whitelisted.
Note: Absolute gas costs will vary based on compiler settings and EVM version. Focus on relative changes and identifying operations that scale poorly.
