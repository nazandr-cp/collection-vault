Initialization
[ ] test_Initialize_CorrectState: Verify all state variables (owner, lendingManager, vault, authorizedUpdater, rewardToken, cToken via LM, globalRewardIndex > 0, epochDuration == 0) are set correctly after initialize.
[ ] test_Revert_Initialize_ZeroLendingManager: Ensure initialization reverts if _lendingManagerAddress is address(0).
[ ] test_Revert_Initialize_ZeroVault: Ensure initialization reverts if _vaultAddress is address(0).
[ ] test_Revert_Initialize_ZeroUpdater: Ensure initialization reverts if _authorizedUpdater is address(0).
[ ] test_Revert_Initialize_VaultAssetMismatch: Ensure initialization reverts if vault.asset() does not match lendingManager.asset().
[ ] test_Revert_Initialize_AlreadyInitialized: Ensure calling initialize again on an already initialized proxy reverts.
Admin Functions (Happy Path)
[ ] test_SetAuthorizedUpdater_Success: Call setAuthorizedUpdater as owner, verify the state change, and check for the AuthorizedUpdaterChanged event.
[ ] test_AddNFTCollection_Success: Call addNFTCollection as owner, verify the collection is whitelisted and its beta, rewardBasis, and rewardSharePercentage are stored correctly. Check for the NFTCollectionAdded event.
[ ] test_RemoveNFTCollection_Success: Call removeNFTCollection as owner for an existing collection, verify it's removed from the whitelist and associated state is cleared. Check for the NFTCollectionRemoved event.
[ ] test_UpdateBeta_Success: Call updateBeta as owner, verify the beta value is updated, and check for the BetaUpdated event.
[ ] test_SetCollectionRewardSharePercentage_Success: Call setCollectionRewardSharePercentage as owner, verify the rewardSharePercentage is updated, and check for the CollectionRewardShareUpdated event.
[ ] test_SetEpochDuration_Success: Call setEpochDuration as owner with a non-zero value, verify the epochDuration state variable is updated.
Admin Functions (Reverts)
[ ] test_Revert_AdminFunctions_NotOwner: Test that setAuthorizedUpdater, addNFTCollection, removeNFTCollection, updateBeta, setCollectionRewardSharePercentage, setEpochDuration revert with OwnableUnauthorizedAccount when called by a non-owner.
[ ] test_Revert_SetAuthorizedUpdater_ZeroAddress: Ensure setAuthorizedUpdater reverts if _newUpdater is address(0).
[ ] test_Revert_AddNFTCollection_ZeroAddress: Ensure addNFTCollection reverts if collection is address(0).
[ ] test_Revert_AddNFTCollection_AlreadyExists: Ensure addNFTCollection reverts if the collection is already whitelisted.
[ ] test_Revert_AddNFTCollection_InvalidShare: Ensure addNFTCollection reverts if rewardSharePercentage > MAX_REWARD_SHARE_PERCENTAGE.
[ ] test_Revert_RemoveNFTCollection_NotWhitelisted: Ensure removeNFTCollection reverts if the collection is not whitelisted.
[ ] test_Revert_UpdateBeta_NotWhitelisted: Ensure updateBeta reverts if the collection is not whitelisted.
[ ] test_Revert_SetCollectionRewardSharePercentage_NotWhitelisted: Ensure setCollectionRewardSharePercentage reverts if the collection is not whitelisted.
[ ] test_Revert_SetCollectionRewardSharePercentage_InvalidShare: Ensure setCollectionRewardSharePercentage reverts if newSharePercentage > MAX_REWARD_SHARE_PERCENTAGE.
[ ] test_Revert_SetEpochDuration_ZeroDuration: Ensure setEpochDuration reverts if newDuration is 0.
View Functions
[ ] test_GetCollectionBeta_Success: Call getCollectionBeta for a whitelisted collection and verify the returned value.
[ ] test_Revert_GetCollectionBeta_NotWhitelisted: Ensure getCollectionBeta reverts for a non-whitelisted collection.
[ ] test_GetCollectionRewardBasis_Success: Call getCollectionRewardBasis for whitelisted collections and verify the returned values.
[ ] test_Revert_GetCollectionRewardBasis_NotWhitelisted: Ensure getCollectionRewardBasis reverts for a non-whitelisted collection.
[ ] test_CollectionRewardSharePercentages_Success: Read collectionRewardSharePercentages directly for a whitelisted collection and verify the value.
[ ] test_GetUserNFTCollections_Empty: Call getUserNFTCollections for a user with no activity, verify empty array.
[ ] test_GetUserNFTCollections_Single: Process one update, call getUserNFTCollections, verify single collection returned.
[ ] test_GetUserNFTCollections_Multiple: Process updates for multiple collections, call getUserNFTCollections, verify all active collections returned.
[ ] test_GetUserNFTCollections_AfterRemoval: Process updates, then zero out balance/NFTs for one collection, call getUserNFTCollections, verify the collection is removed from the list.
[ ] test_IsCollectionWhitelisted: Check isCollectionWhitelisted returns true for whitelisted and false for non-whitelisted collections.
[ ] test_GetWhitelistedCollections: Call getWhitelistedCollections, verify initial collections, add one, verify updated list.
[ ] test_UserNFTData_Initial: Call userNFTData for a new user/collection, verify all returned values are 0.
[ ] test_UserNFTData_AfterUpdate: Process a simple update, call userNFTData, verify correct lastRewardIndex, accruedReward (0), lastNFTBalance, lastBalance, lastUpdateBlock.
[ ] test_CalculateBoost: Verify calculateBoost returns 0 for 0 NFTs, beta for 1 NFT, nftBalance * beta for multiple NFTs (below cap).
Simple Balance Update
[ ] test_ProcessUserBalanceUpdates_Single_Success: Use processUserBalanceUpdates with a single update for a new user/collection. Verify userNFTData state, authorizedUpdaterNonce increment, and UserBalanceUpdatesProcessed event emission.
Simple Claim
[ ] test_ClaimRewardsForCollection_Simple_Success: Process a single update, advance time, accrue interest (cToken.accrueInterest), preview rewards (ensure > 0), provide sufficient yield to LM, claim for the collection. Verify RewardsClaimedForCollection event, correct token transfer to user, and userNFTData state reset (accruedReward = 0, index/block updated).
Setup
Requires deploying RewardsController (V1) via TransparentUpgradeableProxy and ProxyAdmin.
Requires a RewardsControllerV2 implementation contract (can be identical to V1 for state preservation tests, or have minor changes for functionality tests).
State Preservation
[ ] test_Upgrade_PreserveAdminState:
Deploy V1 via proxy, initialize.
Record owner, authorized updater, epoch duration.
Deploy V2 implementation.
Use ProxyAdmin (owned by ADMIN) to upgrade the proxy to V2.
Verify owner, authorized updater, epoch duration remain unchanged on the proxy instance.
[ ] test_Upgrade_PreserveCollectionState:
Deploy V1, initialize, add Collection A and Collection B with specific beta/basis/share.
Upgrade proxy to V2.
Verify Collection A and B are still whitelisted with the same beta/basis/share using view functions (isCollectionWhitelisted, getCollectionBeta, etc.).
[ ] test_Upgrade_PreserveUserRewardState:
Deploy V1, initialize, add Collection A.
Process updates for User X / Collection A at block N.
Accrue time/interest to block N+100.
Record userNFTData for User X / Collection A (last index, accrued reward, balances, block).
Upgrade proxy to V2.
Verify userNFTData for User X / Collection A remains unchanged immediately after upgrade.
Claim rewards using the V2 instance. Verify claim is successful based on the state preserved from V1.
Functionality Change
[ ] test_Upgrade_FunctionalityChange:
Create RewardsControllerV2 with a modified internal logic (e.g., slightly different calculateBoost implementation or a new view function). Ensure storage layout compatibility.
Deploy V1 via proxy, perform some actions.
Upgrade proxy to V2.
Call the function with modified logic (e.g., previewRewards which uses calculateBoost, or the new view function). Verify the V2 logic is now active.
Reverts
[ ] test_Revert_Upgrade_NonAdmin: Attempt to call upgrade on ProxyAdmin from an address other than the admin. Verify revert.
[ ] test_Revert_Upgrade_ZeroImplementation: Attempt to upgrade to address(0). Verify revert.
[ ] test_Revert_Upgrade_NonContractImplementation: Attempt to upgrade to an EOA address. Verify revert.
Note: Storage layout compatibility issues are harder to test directly in Foundry unless specific storage slots are known and checked, but testing state preservation provides indirect confirmation.