# Gas Optimization To-Do List

## 1. Refactor RewardsController
- [ ] Break `processBalanceUpdates` into off-chain or batched on-chain calls.
- [ ] Accept `uint256[] calldata deltas` instead of looping over collections/users in a single tx.

## 2. Optimize Role Management
- [ ] Switch from per-call `grantRole`/`revokeRole` to bit-mask storage (batch grants).
- [ ] Consider implementing an ERC-extended batch-grant API.

## 3. Minimize Deployment Cost
- [ ] Replace string `revert` messages with custom errors.
- [ ] Remove unused storage variables.
- [ ] Convert constructor/storage variables to `immutable` or `constant` where applicable.
- [ ] Move repeated logic to shared libraries (e.g., `SafeCast`).

## 4. Improve LendingManager Efficiency
- [ ] Cache external protocol addresses as `immutable`.
- [ ] Hoist invariant checks out of internal loops.

## 5. Measure & Iterate
- [ ] Run a new gas report after each optimization cycle.
- [ ] Target ~10–15% gas reduction per iteration.
- [ ] Aim for a 20–30% total reduction in gas costs.