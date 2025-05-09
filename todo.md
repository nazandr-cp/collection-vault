# TODO: Fix Reward Distribution & Data-Fresh Claim Protection

> **Scope:** `RewardsController.sol`, `LendingManager.sol`, `ERC4626Vault.sol` interfaces, tests, deployment scripts  
> **Goal:** Remove the "stair‑step" exploit, enforce up‑to‑date balance checks on every claim, and harden the codebase for main‑net deployment.

---

## 1  Segmented Reward Accrual (Critical)

| Ref | Task                                                 | Description                                                                                                                                                |
| --- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.1 | **Implement true segmented calculation**             | Replace the single‑interval formula in `_getRawPendingRewards*` with an algorithm that slices the period into segments between each balance/NFT update.    |
| 1.2 | Introduce `RewardSnapshot` storage                   | On every `processBalanceUpdates` append `{index, block}` snapshots (or include them in the signed payload) so claims can iterate over historical segments. |
| 1.3 | Refactor `claim*` to iterate snapshots               | Calculate and sum each segment’s reward, then delete processed snapshots to save gas.                                                                      |
| 1.4 | Add `MAX_SNAPSHOTS` guard                            | `require(userSnapshots.length ≤ MAX_SNAPSHOTS, “…”)` to prevent grief‑gas.                                                                                 |
| 1.5 | Unit test: _buy → claim → sell → claim_ in one block | Total reward must be ≤ 1 wei difference versus theoretical value.                                                                                          |

---

## 2  Fresh‑Data Claim Guard (High)

| Ref | Task                        | Description                                                                            |
| --- | --------------------------- | -------------------------------------------------------------------------------------- |
| 2.1 | **Global update nonce**     | Increment `globalUpdateNonce` on every authorized balance batch.                       |
| 2.2 | Track `userLastSyncedNonce` | Update this value for each user after their balances are successfully updated.         |
| 2.3 | Add guard in `claim*`       | `require(userLastSyncedNonce == globalUpdateNonce, "STALE_BALANCES");`                 |
| 2.4 | Helper `syncAndClaim(...)`  | Combines a signed update batch and immediate claim into one transaction for better UX. |
| 2.5 | Event `StaleClaimAttempt`   | Emit on failed claims for off‑chain alerting.                                          |

---

## 3  Security & Maintenance Hardening

| Ref | Task                                                                                                                   | Priority | Notes                                                              |
| --- | ---------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------ |
| 3.1 | Add `ReentrancyGuard` & `nonReentrant` to LM fund‑moving functions                                                     | High     | Defence‑in‑depth.                                                  |
| 3.2 | Remove `console.sol` imports                                                                                           | High     | Prevents main‑net compile failure, reduces bytecode.               |
| 3.3 | Declare & emit missing events (`BalanceUpdatesProcessed`, `AuthorizedUpdaterChanged`, `CollectionConfigChanged`, etc.) | Medium   | Improves audit trail.                                              |
| 3.4 | Handle dust in `transferYieldBatch`                                                                                    | Low      | Accumulate sub‑wei dust in a global bucket and sweep periodically. |
| 3.5 | Gas‑bomb protection on large batches                                                                                   | Low      | Limit batch length or gas‑profile off‑chain aggregator.            |

---

## 4  Compilation Fixes

* Ensure every `emit X(...)` has a matching `event X(...)` declaration.  
* Run `forge build --optimize --evm-version paris` without warnings.

---


## 6  Test Matrix (Must Pass)

| ID  | Scenario                               | Expected Outcome                         |
| --- | -------------------------------------- | ---------------------------------------- |
| T‑1 | Stair‑step exploit regression          | No excess rewards beyond 1 wei rounding. |
| T‑2 | Claim with stale nonce                 | Reverts with `STALE_BALANCES`.           |
| T‑3 | `syncAndClaim` gas efficiency          | Completes in ≤ 105% gas of separate txs. |
| T‑4 | Partial `transferYield` (yield < owed) | Deficit stored in `accruedReward`.       |
| T‑5 | Snapshot overflow (`> MAX_SNAPSHOTS`)  | Transaction reverts.                     |


