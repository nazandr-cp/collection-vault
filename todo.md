# ToDo: Implementation Plan for Lending Suite

This file provides detailed steps and context for addressing each finding from the security audit. Each entry includes:

* **Rationale**: Why the change is necessary.
* **Files/Functions**: Where to implement it.
* **Implementation notes**: Code-level hints and test suggestions.

---

## 1. Critical

### 1.1 Prevent last-admin removal (C-1)

* **Rationale**: Without at least one `ADMIN_ROLE` holder, the contract becomes unmanageable—no upgrades or role adjustments possible.
* **Files/Functions**:

  * `LendingManager.sol`

    * Functions: `revokeAdminRole`, `revokeAdminRoleAsDefaultAdmin`
* **Implementation**:

  1. Change inheritance from `AccessControl` to `AccessControlEnumerable` to get `getRoleMemberCount`
  2. In both `revoke…` functions, add at the top:

     ```solidity
     require(
       getRoleMemberCount(ADMIN_ROLE) > 1,
       "LendingManager: cannot remove last admin"
     );
     ```
  3. Add unit tests:

     * Attempt revoking admins when count = 1 → expect revert.
     * Revoke when count > 1 → success and proper event emitted.

### 1.2 Disable uninitialized implementation (C-2)

* **Rationale**: Protect the implementation contract from ownable initialization by an attacker via direct calls.
* **Files/Functions**:

  * `RewardsController.sol` (implementation contract)
  * Constructor logic
* **Implementation**:

  1. In the implementation contract constructor (not the proxy), call:

     ```solidity
     constructor() {
       _disableInitializers();
     }
     ```
  2. Redeploy the implementation or, if deployed, use an EOA with `DEFAULT_ADMIN_ROLE` to call `disableInitializers()`.
  3. Add a test creating a new proxy pointing to this implementation and verify that `initialize()` reverts.

---

## 2. High

### 2.1 Bound batch-processing loops (H-1)

* **Rationale**: Prevent DoS by gas exhaustion on unbounded arrays in `transferYieldBatch`.
* **Files/Functions**:

  * `LendingManager.sol` → `transferYieldBatch(address[] collections, uint256[] amounts)`
* **Implementation**:

  1. Define `uint256 public constant MAX_BATCH_SIZE = 50;`
  2. At function start:

     ```solidity
     require(
       collections.length == amounts.length &&
       collections.length <= MAX_BATCH_SIZE,
       "LendingManager: batch size exceeds limit"
     );
     ```
  3. Write fuzz tests sending arrays of lengths 1, `MAX_BATCH_SIZE`, and `MAX_BATCH_SIZE + 1`.

### 2.2 Paginate bitmap traversal (H-2)

* **Rationale**: Snapshot claiming loops may iterate over large bitmaps, causing gas spikes.
* **Files/Functions**:

  * `RewardsController.sol` → `claimMultiple(uint256[] snapshotIds)` and internal helpers
* **Implementation**:

  1. Introduce `uint256 public constant MAX_SNAPSHOTS_PER_CLAIM = 100;`
  2. Enforce at `claimMultiple`:

     ```solidity
     require(
       snapshotIds.length <= MAX_SNAPSHOTS_PER_CLAIM,
       "RewardsController: too many snapshots"
     );
     ```
  3. Optionally provide a paginated view in the UI; update front-end to batch calls.
  4. Tests: passing 100 snapshots succeeds; 101 reverts.

### 2.3 Restrict vault allowances (H-3)

* **Rationale**: Infinite approvals allow compromised `LendingManager` to drain entire Vault.
* **Files/Functions**:

  * `ERC4626Vault.sol` → initialization & `deposit` logic
* **Implementation**:

  1. Remove `asset.safeApprove(lendingManager, type(uint256).max)` from constructor.
  2. In `deposit(uint256 assets)`, before calling `lendingManager.deposit(assets)`, do:

     ```solidity
     asset.safeApprove(lendingManager, assets);
     ```
  3. After `lendingManager` call, reset allowance to zero:

     ```solidity
     asset.safeApprove(lendingManager, 0);
     ```
  4. Tests:

     * Ensure allowance matches deposit amount during the call.
     * After call, allowance is zero.

### 2.4 Handle fee-on-transfer tokens (H-4)

* **Rationale**: Underlying tokens with transfer fees break `balanceBefore`/`balanceAfter` accounting.
* **Files/Functions**:

  * `LendingManager.sol` → all functions that `redeem` or `transfer`
* **Implementation**:

  1. After each external token operation, compute:

     ```solidity
     uint256 expectedAssets = principal + yield;
     require(totalAssets() == expectedAssets, "LendingManager: accounting mismatch");
     ```
  2. Add tests with a mock ERC-20 charging a 1% fee on transfer and ensure operations revert.

---

## 3. Medium

### 3.1 Improve share-precision math (M-1)

* **Rationale**: Rounding in `previewMint` and `previewDeposit` can advantage/disadvantage early users.
* **Files/Functions**:

  * `ERC4626Vault.sol` → `previewMint`, `previewDeposit`
* **Implementation**:

  1. Audit rounding direction (floor vs. ceil).
  2. Consider using `Math.mulDiv` to minimize drift.
  3. Tests: simulate low-liquidity deposits and verify share counts exactly reverse via `redeem`.


### 3.3 Guard asset transfers (M-3)

* **Rationale**: Using `msg.sender` as recipient trusts external contract behavior.
* **Files/Functions**:

  * `LendingManager.sol` → `withdrawFromLendingProtocol`
* **Implementation**:

  1. Instead of `asset.safeTransfer(msg.sender, amount)`, require explicit Vault address:

     ```solidity
     asset.safeTransfer(vaultAddress, amount);
     ```
  2. Add constructor arg or setter for `vaultAddress` and gas-optimized immutable storage.
  3. Tests: deploy fake vault that misbehaves; ensure funds only go to configured address.

### 3.4 Preserve principal audit trail (M-4)

* **Rationale**: Resetting `totalPrincipalDeposited` hides historical deposit data.
* **Files/Functions**:

  * Any function that writes to `totalPrincipalDeposited`
* **Implementation**:

  1. Remove manual zeroing logic; instead emit an event when exceptional resets occur:

     ```solidity
     event PrincipalReset(uint256 oldValue, address trigger);
     ```
  2. Write governance function for deliberate resets only.

### 3.5 Add circuit-breaker / pause (M-5)

* **Rationale**: Ability to halt critical functions during emergencies.
* **Files/Functions**:

  * All three contracts: `deposit`, `withdraw`, `transferYieldBatch`, `claim`, etc.
* **Implementation**:

  1. Inherit `Pausable` from OpenZeppelin.
  2. Add `whenNotPaused` modifier on all user-facing functions.
  3. Add `pause()`/`unpause()` functions restricted to `ADMIN_ROLE`.
  4. Tests: pausing should block calls; unpause restores functionality.



## 4. Low / Gas Optimizations

* **4.1 Use `unchecked` for simple loops (L-1)**

  * Wrap index increments in `unchecked { i++; }` in `for` loops.
* **4.2 Custom errors for `require` patterns (L-2)**

  * Replace `require(x, "msg")` with `if (!x) revert CustomError();` to save gas.
* **4.3 Mark constant addresses as `immutable` (L-3)**

  * Change `address public treasury;` to `address public immutable treasury;`
* **4.4 Pack storage variables (L-4)**

  * Group `uint128` + `uint128` into same slot where possible.
* **4.5 Consider narrower integer types (uint128) (L-5)**

  * Audit balances and counters; switch to `uint128` when <2^128.

*Implementation notes: these can be batched into a separate "Gas cleanup" PR.*

---

## 5. Informational / Best Practices

* **5.1 Events for all role grants/revocations (I-1)**

  * Ensure every call to `grantRole`/`revokeRole` has matching `RoleGranted`/`RoleRevoked` events.

* **5.2 Add NatSpec comments (I-2)**

  * Prefix functions with `/// @notice`, `/// @param`, `/// @return`, etc.



* **5.4 Formal reward-index invariants (I-4)**

  * Write property-based tests (e.g., using Foundry’s `ffi` or Hardhat-QuickCheck) to assert:

    ```text
    index[n+1] - index[n] == reward / totalShares
    ```

