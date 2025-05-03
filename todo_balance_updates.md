Large Batches
[ ] test_ProcessUserBalanceUpdates_LargeBatch_Gas: Process a batch with many updates (e.g., 50+) using processUserBalanceUpdates. Verify success and record gas usage.
[ ] test_ProcessBalanceUpdates_LargeBatch_Gas: Process a batch with many updates (e.g., 50+) for multiple users using processBalanceUpdates. Verify success and record gas usage.
Same-Block Updates
[ ] test_ProcessUserBalanceUpdates_SameBlock_MultipleUpdates: Include multiple BalanceUpdateData entries for the same user/collection within a single processUserBalanceUpdates call, all with the same blockNumber. Verify state aggregates correctly and lastUpdateBlock reflects the block number.
[ ] test_ProcessBalanceUpdates_SameBlock_MultipleUpdates: Include multiple UserBalanceUpdateData entries for the same user/collection within a single processBalanceUpdates call, all with the same blockNumber. Verify state aggregates correctly.
[ ] test_PreviewRewards_AfterSameBlockUpdates: Preview rewards immediately after processing multiple same-block updates. Ensure rewards are calculated based on the state before the updates for that block (zero duration).
Interleaved Updates
[ ] test_ProcessBalanceUpdates_Interleaved: Process a batch using processBalanceUpdates containing updates for User A/Collection 1 at block N, User B/Collection 2 at block N, User A/Collection 2 at block N+1, User B/Collection 1 at block N+1. Verify final state for all users/collections.
Zero Deltas
[ ] test_ProcessUserBalanceUpdates_ZeroNFTDelta: Process an update with nftDelta = 0 and balanceDelta != 0. Verify state updates correctly.
[ ] test_ProcessUserBalanceUpdates_ZeroBalanceDelta: Process an update with nftDelta != 0 and balanceDelta = 0. Verify state updates correctly.
[ ] test_ProcessUserBalanceUpdates_ZeroBothDeltas: Process an update with nftDelta = 0 and balanceDelta = 0. Verify state updates correctly (index/block should update if block number increases) and nonce increments.
Rapid Fluctuations
[ ] test_PreviewRewards_RapidFluctuations: Process a sequence of updates across consecutive blocks: increase NFT/balance, decrease, increase again. Preview rewards at the end and verify calculation considers the balances held during each period.
Simulation Reverts
[ ] test_Revert_PreviewRewards_SimulationUpdateOutOfOrder: Set up state with lastUpdateBlock = N. Call previewRewards with a simulatedUpdates entry where blockNumber < N. Verify revert with SimulationUpdateOutOfOrder.
[ ] test_Revert_PreviewRewards_SimulationBalanceUnderflow: Set up state with lastBalance = X. Call previewRewards with a simulatedUpdates entry where balanceDelta is negative and abs(balanceDelta) > X. Verify revert with SimulationBalanceUpdateUnderflow.
[ ] test_Revert_PreviewRewards_SimulationNFTUnderflow: Set up state with lastNFTBalance = Y. Call previewRewards with a simulatedUpdates entry where nftDelta is negative and abs(nftDelta) > Y. Verify revert with SimulationBalanceUpdateUnderflow.
