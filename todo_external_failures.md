LendingManager Failures
[ ] test_Revert_Claim_LendingManagerTransferYieldReverts: During claimRewardsForCollection or claimRewardsForAll (when reward > 0), use vm.expectRevert on the LendingManager address to simulate transferYield reverting. Verify the entire claim transaction reverts, and userNFTData state remains unchanged from before the claim attempt.
[ ] test_Initialize_LendingManagerAssetReverts: Use a mock LM where asset() reverts. Attempt to initialize RewardsController. Verify initialization fails.
[ ] test_Initialize_LendingManagerCTokenReverts: Use a mock LM where cToken() reverts. Attempt to initialize RewardsController. Verify initialization fails.
cToken Failures
[ ] test_Revert_Preview_CTokenAccrueInterestReverts: Use vm.expectRevert on the cToken address to simulate accrueInterest reverting. Call previewRewards. Verify the transaction reverts.
[ ] test_Revert_Claim_CTokenAccrueInterestReverts: Use vm.expectRevert on the cToken address to simulate accrueInterest reverting. Call claimRewardsForCollection or claimRewardsForAll. Verify the transaction reverts.
[ ] test_Preview_CTokenExchangeRateStoredReturnsZero: Use a mock cToken (or manipulate state if possible on fork) where exchangeRateStored returns 0 after accrueInterest. Call previewRewards. Verify preview returns 0 (due to division by zero protection or zero index delta).
[ ] test_Claim_CTokenExchangeRateStoredReturnsZero: Similar to above, but call claimRewards.... Verify 0 rewards are claimed, state updates correctly.
[ ] test_Initialize_CTokenExchangeRateStoredReverts: Use a mock cToken where exchangeRateStored reverts. Attempt to initialize RewardsController. Verify initialization fails.
Reward Token Failures
[ ] test_Revert_Claim_RewardTokenTransferReverts: Use a mock ERC20 as the rewardToken which reverts on transfer or safeTransfer. Perform a claim where amountActuallyTransferred > 0. Verify the claim transaction reverts after the transferYield call (if possible to check intermediate state) but before completing successfully. Ensure userNFTData state is updated (as transfer is the last step), but the user does not receive tokens. Note: This tests the behavior when the final step fails.
Vault Failures (Initialization)
[ ] test_Revert_Initialize_VaultAssetReverts: Use a mock Vault where asset() reverts. Attempt to initialize RewardsController. Verify initialization fails.
