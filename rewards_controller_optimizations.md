
# RewardsController Optimization Tasks

This document outlines specific optimizations for the `RewardsController` contract, with implementation plans and to-do lists for each selected area.

---

## 3. Bitmap-Based Active Collection Tracking

**Goal:** Replace expensive `EnumerableSet` iteration for tracking user–collection activity with efficient bitmask operations.

### Principle

Instead of maintaining an `EnumerableSet` for each user’s active NFT collections, we use a 256-bit bitmap (`uint256`) where each bit represents a whitelisted collection. Each collection is assigned a unique index `i ∈ [0, 255]`.

If a user holds NFTs or deposits in collection `i`, the corresponding bit `userActiveMask[user] |= 1 << i` is set. If both balances go to zero, it's cleared.

This allows:
- Constant-time checking of activity.
- Efficient iteration over active collections using bitwise operations (e.g., `BitScan`).

### To-Do

- [ ] Assign a unique numeric index to each whitelisted NFT collection (0…255).
- [ ] Replace `EnumerableSet` with a `mapping(address => uint256) userActiveMask` in `RewardsController`.
- [ ] In `_processSingleUpdate`, set or clear the bit at the collection’s index based on final NFT and token balances.
- [ ] Refactor `claimRewardsForAll` to:
  - Loop over `userActiveMask[user]` using bit scan.
  - For each set bit, fetch the associated collection.
  - Apply reward logic as before.

---

## 6. Inline Multicall Payouts

**Goal:** Eliminate repeated `LendingManager.transferYield` calls per collection and replace with a single batched call.

### Principle

In the current design, `claimRewardsForAll` issues a separate call for each collection’s reward. This wastes gas and increases call overhead. Instead, we can calculate all due amounts first and then issue a single batched transfer.

### To-Do

- [ ] Implement `transferYieldBatch(address[] collections, uint256[] amounts, uint256 total, address to)` in `LendingManager`.
- [ ] In `claimRewardsForAll`, build arrays of:
  - Active collections
  - Calculated `totalDuePerCollection` values
- [ ] Sum all values to `totalReward`
- [ ] Make one call to `transferYieldBatch(colls, amounts, totalReward, user)`
- [ ] Remove per-collection `transferYield` logic and adjust state updates
- [ ] Emit a single `RewardsClaimedForAll` event with breakdown if needed

---

## 9. Efficient Signature Validation with `ECDSA.tryRecover`

**Goal:** Minimize revert-based failures during signature checks and improve error aggregation.

### Principle

Instead of calling `ECDSA.recover` (which reverts on error), use `ECDSA.tryRecover` which returns a success flag and result. This lets us collect validation results for an entire batch and fail once with context.

### To-Do

- [ ] Refactor all signature verification logic to use `ECDSA.tryRecover` instead of `recover`.
- [ ] For batch updates, validate all signatures in a loop:
  ```solidity
  (address signer, ECDSA.RecoverError err) = ECDSA.tryRecover(digest, signature);
  ```
- [ ] If `err != ECDSA.RecoverError.NoError` or `signer != expectedSigner`, track a `bool allValid = false`
- [ ] After the loop, do a single `require(allValid, "Invalid signature(s)")`
- [ ] Optionally, emit events for failed indices for monitoring/debugging

---

