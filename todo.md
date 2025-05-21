* # TODO: Contract Improvements



## 2. Add Overflow Protection in `calculateBoost`

* Replace `nftBalance * beta` with `Math.mulDiv(nftBalance, beta, SCALE)` or equivalent
* Add new unit tests covering boundary cases

## 3. Improve Trusted Signer Management

* Store a single `trustedSigner` in contract storage
* In `ECDSA.recover`, verify against this fixed address instead of one provided in the transaction
* Add a function to update the trusted signer with an emitted event

## 4. Emit Events for Parameter Changes

* Emit `CollectionRewardShareUpdated(collection, oldShare, newShare)` in `setCollectionRewardSharePercentage`
* Emit `CollectionBetaUpdated(collection, oldBeta, newBeta)` when updating the beta factor

## 5. Log Issued Rewards

* Add `RewardsIssued(address indexed user, address indexed collection, uint256 amount, uint256 nonce)` event in `claimRewardsForCollection`
* In `claimRewardsForAllCollections`, emit an event for each collection or use a batch event `BatchRewardsIssued(user, collections[], amounts[], nonce)`
* Optionally: maintain aggregated statistics per user/collection in mappings and expose view functions

## 6. Simplify Nonce Handling

* Reevaluate nonce scheme for batch and single claims

## 7. Update Documentation and Tests

* Provide example EIP-712 payloads for each `claimRewards*` method
* Add unit and integration tests for new events and logic

---
