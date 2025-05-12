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

### 2.1. `calculateBoost(uint256 nftBalance, uint96 beta)`
-   Test with `nftBalance` = 0, expected boost = 0.
-   Test with `nftBalance` > 0 and `beta` = 0, expected boost = 0.
-   Test with `nftBalance` > 0 and `beta` > 0, verify correct boost calculation (e.g., `beta` / `BPS_SCALER`).
-   Test with `nftBalance` > 0 and `beta` = `BPS_SCALER`, expected boost = 1 (or 10000 if scaled).
-   Test with large `nftBalance` and `beta` values.

### 2.2. Internal Reward Calculation (Indirect Testing)
-   Since `_calculateRewardsWithDelta` is internal, its logic will be tested indirectly via `getAccruedRewardsForCollection` and claim functions.
-   Focus on scenarios that trigger different paths within the internal calculation:
    -   User has NFT balance vs. no NFT balance.
    -   Collection `rewardBasis` is `DEPOSIT` vs. `BORROW`.
    -   User has positive deposit/borrow balance vs. zero balance in `CollectionsVault`.

### 2.3. `getAccruedRewardsForCollection(address user, address collection)`
-   **No Rewards Scenarios:**
    -   User has no deposit/borrow balance for the collection's `rewardBasis`.
    -   Collection is not whitelisted.
    -   `LendingManager` has zero yield for the underlying token.
    -   User has NFTs, but `beta` is 0 for the collection.
    -   User has deposit/borrow balance, but `rewardSharePercentage` is 0 for the collection.
-   **Rewards Based on 'DEPOSIT' Basis:**
    -   User has a deposit balance, has NFTs with `beta` > 0.
    -   User has a deposit balance, no NFTs.
    -   User has no deposit balance.
    -   Vary `rewardSharePercentage` and `beta`.
-   **Rewards Based on 'BORROW' Basis:**
    -   User has a borrow balance, has NFTs with `beta` > 0.
    -   User has a borrow balance, no NFTs.
    -   User has no borrow balance.
    -   Vary `rewardSharePercentage` and `beta`.
-   **Non-Whitelisted Collection:**
    -   Verify returns 0 rewards.
-   **User with/without NFTs:**
    -   Test calculation with `nftBalanceOf(user, collection)` returning 0.
    -   Test calculation with `nftBalanceOf(user, collection)` returning > 0.
-   **Interaction with `CollectionsVault`:**
    -   Mock `CollectionsVault` to return various deposit/borrow balances for the user and collection.
-   **Interaction with `LendingManager`:**
    -   Mock `LendingManager` to return various `getYieldGeneratedNoSideEffects` values.

### 2.4. `getAccruedRewardsForAllCollections(address user, address[] calldata collections)`
-   User has rewards in multiple specified collections.
-   User has rewards in a single specified collection.
-   User has no rewards in any specified collections.
-   One or more specified collections are not whitelisted.
-   Empty `collections` array.
-   `collections` array with duplicate entries.
-   Verify sum of individual `getAccruedRewardsForCollection` calls matches the result.

## 3. Reward Claiming Mechanisms

This section covers tests for the reward claiming functions, including signature verification and event emissions.

### 3.1. `claimRewardsForCollection(address recipient, address collection, uint256 rewardAmount, uint256 nonce, bytes calldata signature)`
-   **Successful Claims:**
    -   Claim with a valid EIP-712 signature from the `authorizedUpdater`.
    -   Verify `RewardsClaimedForCollection` event is emitted with correct parameters.
    -   Verify correct amount of reward token is transferred from `LendingManager` to the `recipient`.
    -   Verify `authorizedUpdaterNonce` for the updater is marked as used (implicitly, by checking `_isNonceUsedOrNext`).
    -   Claim when `rewardAmount` is 0 (should succeed, no transfer, event emitted).
-   **Revert Conditions:**
    -   Invalid signature (wrong signer, tampered data, wrong nonce).
    -   Used nonce.
    -   Signature from an address that is not the current `authorizedUpdater`.
    -   `collection` is not whitelisted.
    -   `rewardAmount` in signature does not match `rewardAmount` parameter.
    -   `recipient` in signature does not match `recipient` parameter.
    -   `collection` in signature does not match `collection` parameter.
    -   `LendingManager` has insufficient yield/funds to cover `rewardAmount` (test `YieldTransferCapped` event if applicable).
    -   `rewardAmount` is greater than the actual accrued rewards (should the signature be for the *claimable* amount or *requested* amount? Assuming signature is for requested amount and contract verifies against actual).
-   **Event Emission:**
    -   `RewardsClaimedForCollection(recipient, collection, rewardToken, actualClaimedAmount)`.
    -   `YieldTransferCapped(collection, rewardToken, requestedAmount, actualTransferredAmount)` if `LendingManager` cannot fulfill the full `rewardAmount`.
-   **Token Transfers and Balance Updates:**
    -   Verify `LendingManager.transferYield` is called with correct parameters.
    -   Verify recipient's token balance increases by `actualClaimedAmount`.
-   **Zero Reward Claims:**
    -   Test claiming 0 rewards successfully (no token transfer, event emitted).

### 3.2. `claimAllRewards(address recipient, address[] calldata collections, uint256[] calldata rewardAmounts, uint256 nonce, bytes calldata signature)`
-   **Successful Claims:**
    -   Claim for multiple collections with a valid EIP-712 signature.
    -   Verify `RewardsClaimedForAll` event is emitted.
    -   Verify multiple `RewardsClaimedForCollection` events are emitted (one for each collection with non-zero reward).
    -   Verify correct total token transfers.
    -   Claim when some `rewardAmounts` are 0.
    -   Claim when all `rewardAmounts` are 0.
-   **Revert Conditions:**
    -   Invalid signature.
    -   Used nonce.
    -   `collections` and `rewardAmounts` array lengths mismatch.
    -   One or more collections are not whitelisted.
    -   Signature data mismatch (recipient, collections, amounts).
    -   Insufficient total yield in `LendingManager` across all claims.
-   **Event Emission:**
    -   `RewardsClaimedForAll(recipient, totalRewardAmount)`.
    -   `RewardsClaimedForCollection` for each successfully claimed collection.
    -   `YieldTransferCapped` if applicable for any collection.
-   **Token Transfers for Multiple Collections:**
    -   Verify `LendingManager.transferYield` is called appropriately for each collection.
    -   Verify recipient's balance reflects the sum of all `actualClaimedAmounts`.
-   **Handling of Zero Rewards:**
    -   Test with some collections having 0 `rewardAmounts` in the input.
    -   Test with all collections having 0 `rewardAmounts`.

## 4. Signature Verification and Updater Logic

This section focuses on the EIP-712 signature scheme and nonce management.

### 4.1. EIP-712 Domain Separator and Typehashes
-   **`EIP712_DOMAIN_SEPARATOR()`:**
    -   Verify it's correctly computed based on chain ID and contract address.
    -   Test that it changes if the chain ID changes (if feasible in tests).
-   **`CLAIM_REWARD_TYPEHASH`:**
    -   Verify its value matches the expected EIP-712 typehash for the `ClaimRewardData` struct.
-   **`CLAIM_ALL_REWARDS_TYPEHASH`:**
    -   Verify its value matches the expected EIP-712 typehash for the `ClaimAllRewardsData` struct.

### 4.2. Internal Signature Verification (`_verifySignature`)
-   This is tested implicitly via the `claimRewardsForCollection` and `claimAllRewards` functions.
-   Ensure test cases for claim functions cover:
    -   Valid signatures.
    -   Signatures from incorrect signers.
    -   Signatures with tampered data (recipient, collection(s), amount(s), nonce).
    -   Signatures with an incorrect nonce (already used, or not the current `authorizedUpdaterNonce`).
    -   Signatures generated against a different domain separator.

### 4.3. Nonce Management for `authorizedUpdater`
-   **`_isNonceUsedOrNext(address signer, uint256 nonce)`:**
    -   Test with `nonce` < `authorizedUpdaterNonce[signer]` (should be considered used).
    -   Test with `nonce` == `authorizedUpdaterNonce[signer]` (should be considered next, valid for current claim).
    -   Test with `nonce` > `authorizedUpdaterNonce[signer]` (should be invalid for current claim).
-   Verify `authorizedUpdaterNonce` is correctly incremented when `setAuthorizedUpdater` is called.
-   Verify that after a successful claim, the used nonce cannot be reused for the same `authorizedUpdater`.
-   Test nonce behavior when `authorizedUpdater` changes: the nonce for the old updater should remain, and the new updater starts with its own nonce sequence.

## 5. View Functions and State Variables

This section covers tests for all public view functions and state variable accessors.

-   **`collectionConfigs(address collection)`:**
    -   Verify returns correct `beta`, `rewardBasis`, and `rewardSharePercentage` after `addNFTCollection` and `updateNFTCollection`.
    -   Verify returns zeroed/default values for non-whitelisted or removed collections.
-   **`collectionRewardBasis(address collection)`:**
    -   Verify returns correct `RewardBasis` for a whitelisted collection.
    -   Verify returns default/zero for non-whitelisted collection.
-   **`isCollectionWhitelisted(address collection)`:**
    -   Verify returns `true` for added collections.
    -   Verify returns `false` for non-added or removed collections.
-   **`getLendingManager()`:**
    -   Verify returns the address set during initialization or `setLendingManager`.
-   **`getTokenVault()`:**
    -   Verify returns the address set during initialization or `setTokenVault`.
-   **`getAuthorizedUpdater()`:**
    -   Verify returns the address set during initialization or `setAuthorizedUpdater`.
-   **`getMaxRewardSharePercentage()`:**
    -   Verify returns the value set during initialization or `setMaxRewardSharePercentage`.
-   **`EIP712_DOMAIN_SEPARATOR()` (already covered in 4.1)**

## 6. Access Control

This section ensures that functions requiring specific roles (e.g., `onlyOwner`) are properly protected.

-   **Verification of `onlyOwner` Modifiers:**
    -   For each function with `onlyOwner` (e.g., `setLendingManager`, `addNFTCollection`, `setAuthorizedUpdater`, `setMaxRewardSharePercentage`, `transferOwnership`, `renounceOwnership`):
        -   Test successful execution by the owner.
        -   Test revert when called by a non-owner account.
-   **Access Control for Signature-Gated Functions:**
    -   This is implicitly tested via the claim functions (`claimRewardsForCollection`, `claimAllRewards`).
    -   Ensure tests confirm that only a message signed by the current `authorizedUpdater` (with the correct nonce) can successfully execute these functions.

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

-   **Interactions with `LendingManager`:**
    -   `getYieldGeneratedNoSideEffects` returns 0.
    -   `transferYield` reverts or transfers less than requested (test `YieldTransferCapped` event).
    -   `LendingManager` is a malicious contract (basic interaction checks).
-   **Interactions with `CollectionsVault`:**
    -   `getBalance` (for deposit/borrow) returns 0 for a user.
    -   `nftBalanceOf` returns 0 for a user.
    -   `CollectionsVault` is a malicious contract (basic interaction checks).
-   **Large Number of Collections in `claimAllRewards`:**
    -   Test with a reasonably large array of collections to check for gas limits or unexpected behavior.
    -   Consider if there's a practical limit imposed by block gas limits.
-   **Gas Consumption for Key Functions:**
    -   Measure gas usage for:
        -   `addNFTCollection`, `updateNFTCollection`, `removeNFTCollection`.
        -   `claimRewardsForCollection`.
        -   `claimAllRewards` (with varying numbers of collections).
        -   `getAccruedRewardsForCollection`.
        -   `getAccruedRewardsForAllCollections`.
-   **Re-entrancy:**
    -   Analyze potential re-entrancy vectors, especially during `claimRewardsForCollection` or `claimAllRewards` if `LendingManager.transferYield` could call back into `RewardsController`. (Given the typical flow, direct re-entrancy seems less likely if `transferYield` is a simple token transfer, but good to consider).
    -   If `rewardToken` is an ERC777 or has hooks, consider implications.
-   **Zero Address Inputs:**
    -   Re-verify all functions that take address parameters for proper handling of `address(0)` where not explicitly allowed (e.g., `recipient` in claims, `collection` addresses).
-   **Maximum Values:**
    -   Test with `rewardSharePercentage` at `maxRewardSharePercentage`.
    -   Test with `beta` at its maximum reasonable value.
-   **Timestamp Dependencies:**
    -   Confirm no unintended reliance on `block.timestamp` for core reward logic if calculations are meant to be purely based on external state and signed messages.

This testing plan should guide the creation of specific test files such as `Admin.t.sol`, `Calculation.t.sol`, `Claiming.t.sol`, `Signature.t.sol`, and `View.t.sol`, all inheriting from `RewardsController_Test_Base.sol`.