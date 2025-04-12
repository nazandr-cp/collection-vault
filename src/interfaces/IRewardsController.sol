// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRewardsController Interface
 * @notice Defines the functions for managing user rewards, NFT bonus multipliers, and reward distribution.
 */
interface IRewardsController {
    /**
     * @notice Struct to hold NFT tracking data per user per collection.
     */
    struct UserNFTInfo {
        uint256 lastUpdateBlock;
        uint256 lastNFTBalance;
        uint256 lastUserRewardIndex;
    }

    // --- Events ---
    event NFTCollectionAdded(address indexed collection, uint256 beta);
    event NFTCollectionRemoved(address indexed collection);
    event BetaUpdated(address indexed collection, uint256 oldBeta, uint256 newBeta);
    event RewardsClaimedForCollection(address indexed user, address indexed collection, uint256 amount);
    event RewardsClaimedForAll(address indexed user, uint256 totalAmount);
    event NFTBalanceUpdated(
        address indexed user, address indexed collection, uint256 newBalance, uint256 lastBalance, uint256 blockNumber
    );

    // --- Functions --- //

    /**
     * @notice Updates the NFT balance for a specific user and collection.
     * @dev Typically called by the NFTDataUpdater contract.
     *      This triggers the lazy update of the user's bonus coefficient for this collection.
     * @param user The user whose balance is being updated.
     * @param nftCollection The address of the NFT collection.
     * @param currentBalance The user's current balance in the NFT collection.
     */
    function updateNFTBalance(address user, address nftCollection, uint256 currentBalance) external;

    /**
     * @notice Updates NFT balances for multiple collections for a single user.
     * @dev Batch version of updateNFTBalance.
     * @param user The user whose balances are being updated.
     * @param nftCollections Array of NFT collection addresses.
     * @param currentBalances Array of corresponding current balances.
     */
    function updateNFTBalances(address user, address[] calldata nftCollections, uint256[] calldata currentBalances)
        external;

    /**
     * @notice Claims the accrued rewards for a specific user and a single NFT collection.
     * @dev Calculates both base yield and NFT bonus yield for the collection since the last claim/update.
     *      Transfers the total reward to the user.
     * @param nftCollection The address of the NFT collection to claim rewards for.
     */
    function claimRewardsForCollection(address nftCollection) external;

    /**
     * @notice Claims the accrued rewards for a specific user across all their tracked NFT collections.
     * @dev Aggregates rewards from all collections where the user has holdings and/or accrued bonuses.
     *      Transfers the total reward to the user.
     */
    function claimRewardsForAll() external;

    /**
     * @notice Calculates the pending rewards for a specific user and collection without claiming.
     * @param user The user address.
     * @param nftCollection The collection address.
     * @return pendingBaseReward The base reward accrued since the last update.
     * @return pendingBonusReward The bonus reward accrued based on NFT holdings since the last update.
     */
    function getPendingRewards(address user, address nftCollection)
        external
        view
        returns (uint256 pendingBaseReward, uint256 pendingBonusReward);

    /**
     * @notice Retrieves the stored NFT tracking information for a user and collection.
     * @param user The user address.
     * @param nftCollection The collection address.
     * @return UserNFTInfo struct containing last update block, last balance, and accrued bonus.
     */
    function getUserNFTInfo(address user, address nftCollection) external view returns (UserNFTInfo memory);

    /**
     * @notice Retrieves the list of all currently whitelisted NFT collections.
     * @return An array of NFT collection addresses.
     */
    function getWhitelistedCollections() external view returns (address[] memory);

    /**
     * @notice Retrieves the beta coefficient for a specific collection.
     * @param nftCollection The collection address.
     * @return The beta value for the collection.
     */
    function getCollectionBeta(address nftCollection) external view returns (uint256);

    /**
     * @notice Retrieves the list of collections a user is actively being tracked for (e.g., holds NFTs or has interacted).
     * @param user The user address.
     * @return An array of NFT collection addresses the user is tracked for.
     */
    function getUserNFTCollections(address user) external view returns (address[] memory);

    // --- Admin Functions --- //

    /**
     * @notice Adds a new NFT collection to the whitelist and sets its beta coefficient.
     * @dev Only callable by the owner/admin.
     * @param collection The address of the NFT collection.
     * @param beta The reward coefficient for this collection.
     */
    function addNFTCollection(address collection, uint256 beta) external;

    /**
     * @notice Removes an NFT collection from the whitelist.
     * @dev Only callable by the owner/admin.
     * @param collection The address of the NFT collection.
     */
    function removeNFTCollection(address collection) external;

    /**
     * @notice Updates the beta coefficient for an existing whitelisted NFT collection.
     * @dev Only callable by the owner/admin.
     * @param collection The address of the NFT collection.
     * @param newBeta The new reward coefficient.
     */
    function updateBeta(address collection, uint256 newBeta) external;
}
