# RewardsController.sol Testing Plan

This document outlines the testing plan for the `RewardsController.sol` smart contract. It is based on the structure and functionalities of the contract and refers to `test/RewardsController/RewardsController_Test_Base.sol` for the foundational test setup.

## 1. Initialization and Configuration

This section covers tests for the initial setup, ownership, and core configuration parameters of the `RewardsController` contract.

### 1.1. Deployment and `initialize()`
-   **Proxy Deployment:**
    -   Verify the contract can be deployed as a proxy.
    -   Verify the implementation contract can be deployed.
-   **`initialize()` Function:**
    -   Test successful initialization of the contract via the proxy with valid parameters (e.g., `_owner`, `_lendingManager`, `_tokenVault`, `_authorizedUpdater`, `_maxRewardSharePercentage`).
    -   Test that `initialize()` can only be called once on the implementation.
    -   Test that `initialize()` can only be called once on the proxy.
    -   Test revert if `_lendingManager` is address zero.
    -   Test revert if `_tokenVault` is address zero.
    -   Test revert if `_authorizedUpdater` is address zero.
    -   Test revert if `_maxRewardSharePercentage` is zero or greater than `MAX_REWARD_SHARE_PERCENTAGE_LIMIT`.

### 1.2. Ownership and Admin Roles
-   **`owner()`:**
    -   Verify the `owner()` is correctly set upon initialization.
-   **`transferOwnership(address newOwner)`:**
    -   Test successful ownership transfer by the current owner.
    -   Verify `newOwner` becomes the new owner.
    -   Test revert if called by a non-owner.
    -   Test revert if `newOwner` is address zero.
    -   Verify `OwnershipTransferred` event is emitted.
-   **`renounceOwnership()`:**
    -   Test successful ownership renouncement by the current owner.
    -   Verify owner is set to address zero.
    -   Test revert if called by a non-owner.
    -   Verify `OwnershipTransferred` event is emitted.

### 1.3. Core Contract Addresses
-   **`setLendingManager(address _lendingManager)`:**
    -   Test successful update by the owner.
    -   Verify `getLendingManager()` returns the new address.
    -   Test revert if called by a non-owner.
    -   Test revert if `_lendingManager` is address zero.
    -   Verify `LendingManagerUpdated` event is emitted.
-   **`setTokenVault(address _tokenVault)`:**
    -   Test successful update by the owner.
    -   Verify `getTokenVault()` returns the new address.
    -   Test revert if called by a non-owner.
    -   Test revert if `_tokenVault` is address zero.
    -   Verify `TokenVaultUpdated` event is emitted.

### 1.4. Managing NFT Collections
-   **`addNFTCollection(address collection, uint96 beta, RewardBasis rewardBasis, uint16 rewardSharePercentage)`:**
    -   Test successful addition of a new collection by the owner.
    -   Verify `collectionConfigs(collection)` stores correct parameters.
    -   Verify `isCollectionWhitelisted(collection)` returns `true`.
    -   Test revert if called by a non-owner.
    -   Test revert if `collection` is address zero.
    -   Test revert if `collection` is already whitelisted.
    -   Test revert if `rewardSharePercentage` is greater than `maxRewardSharePercentage`.
    -   Test revert if `rewardBasis` is an invalid enum value.
    -   Verify `NFTCollectionAdded` event is emitted.
-   **`updateNFTCollection(address collection, uint96 beta, RewardBasis rewardBasis, uint16 rewardSharePercentage)`:**
    -   Test successful update of an existing collection by the owner.
    -   Verify `collectionConfigs(collection)` reflects updated parameters.
    -   Test revert if called by a non-owner.
    -   Test revert if `collection` is not whitelisted.
    -   Test revert if `rewardSharePercentage` is greater than `maxRewardSharePercentage`.
    -   Test revert if `rewardBasis` is an invalid enum value.
    -   Verify `NFTCollectionUpdated` event is emitted.
-   **`removeNFTCollection(address collection)`:**
    -   Test successful removal of a collection by the owner.
    -   Verify `isCollectionWhitelisted(collection)` returns `false`.
    -   Verify `collectionConfigs(collection)` are reset/zeroed.
    -   Test revert if called by a non-owner.
    -   Test revert if `collection` is not whitelisted.
    -   Verify `NFTCollectionRemoved` event is emitted.

### 1.5. Managing `authorizedUpdater`
-   **`setAuthorizedUpdater(address _newAuthorizedUpdater)`:**
    -   Test successful update by the owner.
    -   Verify `getAuthorizedUpdater()` returns the new address.
    -   Verify `authorizedUpdaterNonce` is incremented.
    -   Test revert if called by a non-owner.
    -   Test revert if `_newAuthorizedUpdater` is address zero.
    -   Verify `AuthorizedUpdaterUpdated` event is emitted.
-   **`getAuthorizedUpdaterNonce(address updater)`:**
    -   Verify returns correct nonce for the current `authorizedUpdater`.
    -   Verify returns 0 for an address that was never an `authorizedUpdater` or whose nonce was not explicitly set.

### 1.6. Managing `maxRewardSharePercentage`
-   **`setMaxRewardSharePercentage(uint16 _maxRewardSharePercentage)`:**
    -   Test successful update by the owner.
    -   Verify `getMaxRewardSharePercentage()` returns the new value.
    -   Test revert if called by a non-owner.
    -   Test revert if `_maxRewardSharePercentage` is zero.
    -   Test revert if `_maxRewardSharePercentage` is greater than `MAX_REWARD_SHARE_PERCENTAGE_LIMIT`.
    -   Test scenario where existing collections have `rewardSharePercentage` higher than the new `_maxRewardSharePercentage` (should this be allowed or restricted?).
    -   Verify `MaxRewardSharePercentageUpdated` event is emitted.

## 2. Reward Calculation Logic

This section covers tests for the reward calculation mechanisms.

### 2.1. `_calculateUserWeight(address user, address collectionAddress)` (Internal, tested via `syncAccount`)
-   Test with `user` or `collectionAddress` as `address(0)`, expected weight = 0.
-   Test `ERC721` collection type:
    -   `nftBalanceOf` returns 0, expected weight = 0 (or `PRECISION_FACTOR` if `nValue > 0` and no specific weight function).
    -   `nftBalanceOf` returns > 0, verify weight calculation based on `WeightFunctionType` (LINEAR, EXPONENTIAL, or default).
-   Test `ERC1155` collection type:
    -   `balanceOf(user, 0)` returns 0, expected weight = 0.
    -   `balanceOf(user, 0)` returns > 0, verify weight calculation.
-   Test `DEPOSIT` basis:
    -   `balanceOf(user)` returns 0, expected weight = 0.
    -   `balanceOf(user)` returns > 0, verify weight calculation.
-   Test `BORROW` basis:
    -   Placeholder for borrow balance, currently returns 0. Test that it returns 0.
-   Test `FIXED_POOL` basis:
    -   `_fixedPoolCollectionBalances[collectionAddress]` is 0, expected weight = 0.
    -   `_fixedPoolCollectionBalances[collectionAddress]` is > 0, expected weight = `PRECISION_FACTOR`.
-   Test `LINEAR` weight function: `g(N) = 1 + k*N`.
    -   Vary `nValue` and `wf.p1` (k).
    -   Test edge cases: `nValue` = 0, large `nValue`.
-   Test `EXPONENTIAL` weight function: `g(N) = (1+r)^N`.
    -   Vary `nValue` and `wf.p1` (r).
    -   Test edge cases: `nValue` = 0, large `nValue` (potential overflow).
-   Test `DEFAULT` weight function: `nValue > 0` gives `PRECISION_FACTOR`, else 0.
-   Test `weight` capping at `type(uint128).max`.

### 2.2. `_accrueUserRewards(address forVault, address user, address collectionAddress)` (Internal, tested via `_updateUserWeightAndAccrueRewards`)
-   Verify `account.accrued` is correctly updated based on `account.weight`, `vaultStore.globalRPW`, and `collectionShare`.
-   Verify `account.rewardDebt` is correctly updated.
-   Test with zero `account.weight`.
-   Test with zero `vaultStore.globalRPW`.
-   Test with zero `collectionShare`.

### 2.3. `_updateVaultTotalWeight(address forVault, uint128 oldUserWeight, uint128 newUserWeight)` (Internal, tested via `_updateUserWeightAndAccrueRewards`)
-   Verify `vaultStore.totalWeight` is correctly updated.
-   Test with `oldUserWeight` = 0, `newUserWeight` > 0.
-   Test with `oldUserWeight` > 0, `newUserWeight` = 0.
-   Test with `oldUserWeight` > 0, `newUserWeight` > 0.

### 2.4. `_updateUserWeightAndAccrueRewards(address forVault, address user, address collectionAddress)` (Internal, tested via `syncAccount`)
-   Verify that `_accrueUserRewards` is called first.
-   Verify `account.weight` is updated to `newWeight` calculated by `_calculateUserWeight`.
-   Verify `vaultStore.totalWeight` is updated via `_updateVaultTotalWeight`.
-   Verify `account.rewardDebt` is correctly re-calculated based on the `newWeight` and current `globalRPW`.
-   Test scenarios where `oldWeight == newWeight` (should still accrue, but not update weight/totalWeight).

### 2.5. `syncAccount(address user, address collectionAddress)`
-   Test successful synchronization:
    -   Verify `_updateUserWeightAndAccrueRewards` is called.
    -   Verify `AccountStorageData` for the user and `InternalVaultInfo` for the vault are updated.
-   Test revert if `_vault` is `address(0)`.

### 2.6. `refreshRewardPerBlock(address forVault)`
-   Test successful refresh:
    -   Verify `rewardPerBlock` is calculated based on `currentYield` and `blocksDelta`.
    -   Verify `globalRPW` is calculated based on `rewardPerBlock` and `totalWeight`.
    -   Verify `lastUpdateBlock` and `lastAssetsBalance` are updated.
    -   Verify `RewardPerBlockUpdated` event is emitted.
-   Test revert if `forVault` is not the main `_vault`.
-   Test `currentYield` calculation:
    -   `currentBalance >= vaultStore.lastAssetsBalance`.
    -   `currentBalance < vaultStore.lastAssetsBalance` (yield should be 0).
-   Test `blocksDelta`:
    -   `blocksDelta > 0`: `newRewardPerBlock` is calculated.
    -   `blocksDelta == 0` (e.g., called twice in the same block): `newRewardPerBlock` should be 0, and it should be a no-op or handle gracefully without reverting.
-   Test `globalRPW` calculation when `vaultStore.totalWeight == 0`:
    -   Ensure `globalRPW` is correctly set to 0.
    -   Ensure no division by zero error occurs.
-   Test `rewardPerBlock` updates based on yield and `blocksDelta` (or is 0 if `blocksDelta` is 0).

## 3. Reward Claiming Mechanisms

This section covers tests for the reward claiming functions, including signature verification and event emissions.

### 3.1. `claimLazy(IRewardsController.Claim[] calldata claims, bytes calldata signature)`
-   **Successful Claims:**
    -   Claim with a valid EIP-712 signature from the `_claimSigner`.
    -   Verify `RewardClaimed` event is emitted with correct parameters for each claim.
    -   Verify correct total amount of reward token is transferred to `msg.sender`.
    -   Verify `account.nonce` is incremented after each successful claim item.
    -   Verify `account.accrued` is reset to 0 after claiming.
    -   Claim when `amountForThisClaim` is 0 (should succeed, no transfer, event emitted if `amountForThisClaim` was > 0 before reset).
-   **Revert Conditions:**
    -   Invalid signature (wrong signer, tampered data, wrong nonce).
    -   `recoveredSigner` is `address(0)`.
    -   `user` in claim is `address(0)`.
    -   `block.timestamp > currentClaim.deadline`.
    -   `currentClaim.nonce != account.nonce`.
    -   `collection` is not whitelisted.
-   **Fixed Pool Logic:**
    -   Test claiming from a `FIXED_POOL` collection:
        -   `amountForThisClaim <= _fixedPoolCollectionBalances[collection]`: full claim, balance decreases.
        -   `amountForThisClaim > _fixedPoolCollectionBalances[collection]`: claim only available balance, balance becomes 0.
        -   `_fixedPoolCollectionBalances[collection]` is 0: `amountForThisClaim` becomes 0, no transfer.
-   **`_updateUserWeightAndAccrueRewards` interaction:**
    -   Test `claimLazy` scenario: User's underlying position changes, `refreshRewardPerBlock` (keeper) has *not* run since. User calls `claimLazy`. Verify rewards are calculated based *only* on accruals up to the current block of the `claimLazy` transaction, ensuring no unearned/future rewards are paid. This implies `_updateUserWeightAndAccrueRewards` should be called *before* calculating `amountForThisClaim`.
-   **`nonReentrant` guard:**
    -   Simulate a re-entrant call from a malicious `_vault` contract during the yield transfer step. Verify transaction reverts.
-   **Event Emission:**
    -   `RewardClaimed(vaultAddress, user, amountForThisClaim)`.
-   **Token Transfers and Balance Updates:**
    -   Verify `IERC20(IERC4626(vaultAddress).asset()).safeTransfer(msg.sender, totalAmountToClaim)` is called.
    -   Verify `msg.sender`'s token balance increases by `totalAmountToClaim`.

### 3.2. `updateTrustedSigner(address newSigner)`
-   Test successful update by the owner.
-   Verify `_claimSigner` is updated.
-   Verify `TrustedSignerUpdated` event is emitted.
-   Test revert if called by a non-owner.
-   Test revert if `newSigner == address(0)`.
-   Test behavior if called multiple times with the same `newSigner` (e.g., via multicall) - should succeed idempotently (current design).

## 4. Signature Verification and Updater Logic

This section focuses on the EIP-712 signature scheme and nonce management.

### 4.1. EIP-712 Domain Separator and Typehashes
-   **`EIP712_DOMAIN_SEPARATOR()`:**
    -   Verify it's correctly computed based on chain ID and contract address.
    -   Test that it changes if the chain ID changes (if feasible in tests).
-   **`CLAIM_TYPEHASH`:**
    -   Verify its value matches the expected EIP-712 typehash for the `Claim` struct.

### 4.2. Internal Signature Verification (Implicitly tested via `claimLazy`)
-   Ensure test cases for `claimLazy` cover:
    -   Valid signatures.
    -   Signatures from incorrect signers.
    -   Signatures with tampered data (account, collection, secondsUser, secondsColl, incRPS, yieldSlice, nonce, deadline).
    -   Signatures with an incorrect nonce (not matching `account.nonce`).
    -   Signatures generated against a different domain separator.

### 4.3. Nonce Management for `AccountStorageData`
-   Verify `account.nonce` is correctly incremented after a successful claim item in `claimLazy`.
-   Test that a used nonce cannot be reused for the same account.

## 5. View Functions and State Variables

This section covers tests for all public view functions and state variable accessors, reflecting the new storage structures.

-   **`collectionConfigs(address collection)`:** (Removed, replaced by individual mappings)
-   **`collectionRewardBasis(address collection)`:**
    -   Verify returns correct `RewardBasis` for a whitelisted collection.
    -   Verify returns default/zero for non-whitelisted collection.
-   **`isCollectionWhitelisted(address collection)`:**
    -   Verify returns `true` for added collections.
    -   Verify returns `false` for non-added or removed collections.
-   **`oracle()`:**
    -   Verify returns the `_priceOracle` address set during construction.
-   **`vault()`:**
    -   Verify returns the `_vault` address set during initialization.
    -   **ABI Compatibility**: Ensure `vault()` signature remains unchanged.
-   **`userNonce(address vaultAddress, address userAddress)`:**
    -   Verify returns the correct `nonce` from `_accountStorage[vaultAddress][userAddress].nonce`.
-   **`userSecondsPaid(address vaultAddress, address userAddress)`:**
    -   Verify returns the correct `secondsPaid` from `_accountStorage[vaultAddress][userAddress].secondsPaid`.
-   **`vaults(address vaultAddress)`:**
    -   Verify returns correct `rewardPerBlock`, `globalRPW`, `totalWeight`, `lastUpdateBlock` from `_vaultsData[vaultAddress]`.
    -   Verify collection-specific fields (`linK`, `expR`, `useExp`, `cToken`, `nft`, `weightByBorrow`) are returned as default values (0 or false).
-   **`vaultInfo(address vaultAddress)`:**
    -   Verify it correctly calls `vaults(vaultAddress)` and returns the same `VaultInfo`.
-   **`acc(address vaultAddress, address userAddress)`:**
    -   Verify returns correct `weight`, `rewardDebt`, `accrued` from `_accountStorage[vaultAddress][userAddress]`.
-   **`paused()`:**
    -   Verify returns `true` when paused, `false` when unpaused.

## 6. Access Control

This section ensures that functions requiring specific roles (e.g., `onlyOwner`) are properly protected.

-   **Verification of `onlyOwner` Modifiers:**
    -   For each function with `onlyOwner` (e.g., `whitelistCollection`, `removeCollection`, `updateCollectionPercentageShare`, `setWeightFunction`, `updateTrustedSigner`, `pause`, `unpause`, `transferOwnership`, `renounceOwnership`):
        -   Test successful execution by the owner.
        -   Test revert when called by a non-owner account.
-   **Access Control for Signature-Gated Functions:**
    -   This is implicitly tested via the `claimLazy` function.
    -   Ensure tests confirm that only a message signed by the current `_claimSigner` (with the correct nonce) can successfully execute these functions.

## 7. Proxy and Upgradeability (Basic Checks)

This section includes basic checks related to the proxy pattern.

-   **Correct Proxy Setup and Initialization:**
    -   Verify that state variables are set on the proxy's storage, not the implementation's, after `initialize()` is called on the proxy.
    -   Verify that calling `initialize()` on the raw implementation contract works but does not affect the proxy's state (unless it's the first call to initialize the implementation itself).
-   **Basic Interaction Through the Proxy:**
    -   Confirm that calls to functions (e.g., view functions, simple state-changing functions) through the proxy interact with the proxy's storage and logic.
-   **(Note on Full Upgradeability Tests):**
    -   Acknowledge that full upgradeability tests (deploying V2, upgrading, and checking storage layout compatibility) are typically more extensive and might be in a separate test suite. For this plan, focus on the correct initial proxy setup.
    -   Test that `UPGRADE_INTERFACE_VERSION` is set correctly.

## 8. Edge Cases and Stress Scenarios

This section covers less common scenarios and potential stress points.

-   **Interactions with `ICollectionsVault`:**
    -   `IERC4626(forVault).asset()` returns `address(0)` or invalid asset.
    -   `IERC20(asset).balanceOf(address(this))` returns unexpected values.
    -   `ICollectionsVault` is a malicious contract (basic interaction checks).
-   **Large Number of Claims in `claimLazy`:**
    -   Test with a reasonably large array of claims to check for gas limits or unexpected behavior.
    -   Consider if there's a practical limit imposed by block gas limits.
-   **Gas Consumption for Key Functions:**
    -   Measure gas usage for:
        -   `whitelistCollection`, `removeCollection`, `updateCollectionPercentageShare`, `setWeightFunction`.
        -   `claimLazy` (with varying numbers of claims).
        -   `syncAccount`.
        -   `refreshRewardPerBlock`.
        -   `userNonce`, `userSecondsPaid`, `vaults`, `acc`.
-   **Zero Address Inputs:**
    -   Re-verify all functions that take address parameters for proper handling of `address(0)` where not explicitly allowed (e.g., `collectionAddress` in `whitelistCollection`, `user` in `syncAccount`).
-   **Maximum Values:**
    -   Test with `sharePercentageBps` at `MAX_REWARD_SHARE_PERCENTAGE`.
    -   Test with `_totalCollectionShareBps` reaching `MAX_REWARD_SHARE_PERCENTAGE`.
-   **Timestamp Dependencies:**
    -   Confirm `block.timestamp` is used correctly for `claim.deadline` in `claimLazy`.
-   **`_totalCollectionShareBps` guard:**
    -   Test `whitelistCollection` or `updateCollectionPercentageShare` calls that attempt to make `_totalCollectionShareBps > MAX_REWARD_SHARE_PERCENTAGE` revert with `InvalidRewardSharePercentage` (e.g., add 6000 BPS, then attempt to add 5000 BPS).
-   **ERC165 checks in `whitelistCollection`:**
    -   Test `ERC721` and `ERC1155` collections with valid and invalid interfaces.

This testing plan should guide the creation of specific test files such as `Admin.t.sol`, `Calculation.t.sol`, `Claiming.t.sol`, `Signature.t.sol`, and `View.t.sol`, all inheriting from `RewardsController_Test_Base.sol`.