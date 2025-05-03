Setup
Create a MaliciousERC20 contract implementing IERC20.
This mock token needs a reference to the RewardsController proxy address.
Override the transfer function in MaliciousERC20. Inside the transfer function, attempt to call back into a nonReentrant function on the RewardsController (e.g., claimRewardsForCollection or claimRewardsForAll).
Deploy RewardsController and dependencies as usual, but configure LendingManager (or RewardsController directly if possible, though LM sets it) to use the MaliciousERC20 as the rewardToken. This might require deploying a modified LM or using vm.store if initialization checks prevent using the mock directly.
Tests
[ ] test_Revert_Reentrancy_ClaimRewardsForCollection:
Set up state so a user has rewards pending for a collection.
Ensure rewardToken is the MaliciousERC20.
Provide yield to LM using the MaliciousERC20.
Call claimRewardsForCollection for the user.
The claim should proceed until rewardToken.safeTransfer is called.
The MaliciousERC20.transfer function attempts to call claimRewardsForCollection again.
Verify the transaction reverts due to the nonReentrant guard (ReentrancyGuard: reentrant call).
[ ] test_Revert_Reentrancy_ClaimRewardsForAll:
Similar setup as above.
Call claimRewardsForAll for the user.
The claim should proceed until rewardToken.safeTransfer is called.
The MaliciousERC20.transfer function attempts to call claimRewardsForAll again.
Verify the transaction reverts due to the nonReentrant guard.
[ ] test_Revert_Reentrancy_ProcessUpdates: (Less likely scenario, but for completeness)
If any external calls exist within processUserBalanceUpdates or processBalanceUpdates (currently none seem apparent), create a mock for that external call that attempts to re-enter process...Updates. Verify revert. Currently, these functions seem safe as they only read state and emit events after signature verification.
Note: The main focus is reentrancy via the rewardToken.safeTransfer during claims, as this is the most common pattern.
