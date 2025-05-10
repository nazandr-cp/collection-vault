# TODO: Final Polish Tasks for Rewards System

> **Scope:** `RewardsController.sol`, `LendingManager.sol`, migration script, documentation, SDK  
> **Goal:** Address remaining medium/low risk hardening items before last audit or staging deploy.

---

## 1  Batch Update Size Guard (Medium)

| Ref | Task                                | Description                                                        |
| --- | ----------------------------------- | ------------------------------------------------------------------ |
| 1.1 | Add `MAX_BATCH_UPDATES` constant    | e.g. `uint256 public constant MAX_BATCH_UPDATES = 250;`            |
| 1.2 | Enforce in `processBalanceUpdates*` | `require(updates.length <= MAX_BATCH_UPDATES, "BATCH_TOO_LARGE");` |
| 1.3 | Unit test overflow case             | Ensure explicit revert message when batch exceeds limit.           |

---

## 2  Indexed Snapshot Metadata (Medium)

| Ref | Task                                       | Description                                                                                 |
| --- | ------------------------------------------ | ------------------------------------------------------------------------------------------- |
| 2.1 | Add `collection` field to `RewardSnapshot` | Make it `struct RewardSnapshot { address collection; uint256 index; uint256 blockNumber; }` |
| 2.2 | Populate in `processBalanceUpdates`        | Include `collection` when appending snapshots.                                              |
| 2.3 | Update events/types                        | Reflect new field in events and TypeScript interfaces.                                      |

---

## 4  Storage Gap Adjustment (Low)

| Ref | Task                                    | Description                                                                      |
| --- | --------------------------------------- | -------------------------------------------------------------------------------- |
| 4.1 | Increase `__gap` in `RewardsController` | Add one extra slot for `globalDustBucket` addition: `uint256[39] private __gap;` |
| 4.2 | Document storage layout                 | Update upgrade guide to reflect new gap size.                                    |


