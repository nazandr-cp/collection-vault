# Gas Optimization To-Do List

## 1. Refactor RewardsController
- [X] Break `processBalanceUpdates` into off-chain or batched on-chain calls. (Implemented via parallel arrays for on-chain batch)
- [X] Accept `address[] users, address[] collections, uint256[] blockNumbers, int256[] nftDeltas, int256[] balanceDeltas` instead of `UserBalanceUpdateData[]`.

## 2. Optimize Role Management
- [ ] Switch from per-call `grantRole`/`revokeRole` to bit-mask storage (batch grants).
- [ ] Consider implementing an ERC-extended batch-grant API.

## 3. Minimize Deployment Cost
- [X] Replace string `revert` messages with custom errors. (Verified for RewardsController; further optimized by removing redundant checks, unused errors. Attempted to localize `OwnableUpgradeable` `onlyOwner` error, but not possible due to non-virtual modifier in OZ 5.3.0. Localized `initialOwner` check with `RewardsControllerInvalidInitialOwner`.)
- [X] Remove unused storage variables. (Verified no unused variables in RewardsController)
- [-] Convert constructor/storage variables to `immutable` or `constant` where applicable. (Constants already used. Variables like `lendingManager`, `vault`, `rewardToken`, `cToken` are set in `initialize` and cannot be `immutable` in an upgradeable contract.)
- [ ] Move repeated logic to shared libraries (e.g., `SafeCast`). (No clear candidates in RewardsController beyond existing library usage)
- [-] Conditionally compile test-only helper functions (`processNFTBalanceUpdate`, `processDepositUpdate`, `updateUserRewardStateForTesting`) using `#ifdef TESTING` to exclude them from production bytecode. (Attempted, but `#ifdef` is not standard Solidity/`solc` preprocessor syntax. Test functions remain in contract. True exclusion would require moving them to separate test-only contracts/libraries.)
## 4. Improve LendingManager Efficiency
- [ ] Cache external protocol addresses as `immutable`.
- [ ] Hoist invariant checks out of internal loops.

## 5. Measure & Iterate
- [ ] Run a new gas report after each optimization cycle.
- [ ] Target ~10–15% gas reduction per iteration.
- [ ] Aim for a 20–30% total reduction in gas costs.