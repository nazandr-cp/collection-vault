// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRewardsController Interface
 * @notice Interface for managing user rewards, NFT multipliers, and reward distribution.
 * @dev Supports signature-based and batch balance updates, and role-based updater authorization.
 */
interface IRewardsController {
    // --- Enums ---
    enum RewardBasis {
        DEPOSIT,
        BORROW
    } // Added enum

    /**
     * @notice Tracks user state for a collection (NFTs and deposits).
     */
    struct UserCollectionTracking {
        uint256 lastUpdateBlock;
        uint256 lastNFTBalance;
        uint256 lastBalance; // Renamed from lastDepositBalance
        uint256 lastUserRewardIndex;
    }

    /**
     * @notice Single user/collection balance update for batch processing.
     * @param user User address.
     * @param collection NFT collection address.
     * @param blockNumber Block number of the update.
     * @param nftDelta Change in NFT balance.
     * @param balanceDelta Change in deposit balance.
     */
    struct UserBalanceUpdateData {
        address user;
        address collection;
        uint256 blockNumber;
        int256 nftDelta;
        int256 balanceDelta; // Renamed from depositDelta
    }

    /**
     * @notice Single collection balance update for a user (simulation or batch).
     * @param collection NFT collection address.
     * @param blockNumber Block number of the update.
     * @param nftDelta Change in NFT balance.
     * @param balanceDelta Change in deposit balance.
     */
    struct BalanceUpdateData {
        address collection;
        uint256 blockNumber;
        int256 nftDelta;
        int256 balanceDelta; // Renamed from depositDelta
    }

    // --- Events ---
    event NFTCollectionAdded(address indexed collection, uint256 beta, RewardBasis rewardBasis); // Added rewardBasis
    event NFTCollectionRemoved(address indexed collection);
    event BetaUpdated(address indexed collection, uint256 oldBeta, uint256 newBeta);
    event RewardsClaimedForCollection(address indexed user, address indexed collection, uint256 amount);
    event RewardsClaimedForAll(address indexed user, uint256 totalAmount);
    event AuthorizedUpdaterChanged(address indexed oldUpdater, address indexed newUpdater);
    event NFTDataUpdaterAddressSet(address indexed updaterAddress);

    /**
     * @dev Emitted when a batch of balance updates (NFT or deposit) is processed successfully via signature.
     * @param numUpdates The number of updates processed in the batch.
     */
    event BalanceUpdatesProcessed(address indexed signer, uint256 nonce, uint256 numUpdates);

    /**
     * @dev Emitted when a batch of balance updates (NFT or deposit) is processed successfully via signature for a single user.
     * @param user The address of the user to process updates for.
     * @param nonce The nonce of the signer.
     * @param numUpdates The number of updates processed in the batch.
     */
    event UserBalanceUpdatesProcessed(address indexed user, uint256 nonce, uint256 numUpdates);

    // --- Balance Update Functions (Signature Based) ---

    /**
     * @notice Process a batch of signed balance updates for multiple users/collections.
     * @param signer Authorized updater address.
     * @param updates Array of UserBalanceUpdateData.
     * @param signature EIP-712 signature from signer (covers updates and nonce).
     */
    function processBalanceUpdates(address signer, UserBalanceUpdateData[] calldata updates, bytes calldata signature)
        external;

    /**
     * @notice Process a batch of signed balance updates for a single user across collections.
     * @param signer Authorized updater address.
     * @param user User address.
     * @param updates Array of BalanceUpdateData.
     * @param signature EIP-712 signature from signer (covers updates and nonce).
     */
    function processUserBalanceUpdates(
        address signer,
        address user,
        BalanceUpdateData[] calldata updates,
        bytes calldata signature
    ) external;

    // --- Claiming Functions ---

    /**
     * @notice Claim accrued rewards for the caller and a single NFT collection.
     * @param nftCollection NFT collection address.
     */
    function claimRewardsForCollection(address nftCollection) external;

    /**
     * @notice Claim accrued rewards for the caller across all tracked NFT collections.
     */
    function claimRewardsForAll() external;

    // --- View Functions ---

    /**
     * @notice Preview total pending rewards for a user across multiple collections, with optional simulated updates.
     * @param user User address.
     * @param nftCollections Array of NFT collection addresses.
     * @param simulatedUpdates Array of future updates (must be sorted by blockNumber).
     * @return pendingReward Total claimable reward across specified collections.
     */
    function previewRewards(
        address user,
        address[] calldata nftCollections,
        BalanceUpdateData[] calldata simulatedUpdates
    ) external returns (uint256 pendingReward); // Removed 'view'

    /**
     * @notice Get stored tracking info for a user across multiple collections.
     * @param user User address.
     * @param nftCollections Array of NFT collection addresses.
     * @return Array of UserCollectionTracking structs for each collection.
     */
    function getUserCollectionTracking(address user, address[] calldata nftCollections)
        external
        view
        returns (UserCollectionTracking[] memory);

    /**
     * @notice Get all currently whitelisted NFT collections.
     * @return Array of NFT collection addresses.
     */
    function getWhitelistedCollections() external view returns (address[] memory);

    /**
     * @notice Get the beta coefficient for a specific collection.
     * @param nftCollection NFT collection address.
     * @return Beta value for the collection.
     */
    function getCollectionBeta(address nftCollection) external view returns (uint256);

    /**
     * @notice Get the list of NFT collections a user is actively tracked for.
     * @param user User address.
     * @return Array of NFT collection addresses.
     */
    function getUserNFTCollections(address user) external view returns (address[] memory);

    // --- Admin Functions --- //

    /**
     * @notice Add a new NFT collection to the whitelist and set its beta coefficient.
     * @param collection NFT collection address.
     * @param beta Reward coefficient for this collection.
     * @param rewardBasis Basis for reward calculation (DEPOSIT or BORROW).
     */
    function addNFTCollection(address collection, uint256 beta, RewardBasis rewardBasis) external; // Added rewardBasis

    /**
     * @notice Remove an NFT collection from the whitelist.
     * @param collection NFT collection address.
     */
    function removeNFTCollection(address collection) external;

    /**
     * @notice Update the beta coefficient for a whitelisted NFT collection.
     * @param collection NFT collection address.
     * @param newBeta New reward coefficient.
     */
    function updateBeta(address collection, uint256 newBeta) external;

    /**
     * @notice Get the reward basis for a specific collection.
     * @param nftCollection NFT collection address.
     * @return Reward basis for the collection.
     */
    function getCollectionRewardBasis(address nftCollection) external view returns (RewardBasis); // Added function
}
