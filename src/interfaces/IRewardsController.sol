// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILendingManager} from "./ILendingManager.sol";

/**
 * @title IRewardsController Interface
 * @notice Interface for the RewardsController contract, defining its external functions, structs, events, and errors.
 */
interface IRewardsController {
    // Enums
    enum RewardBasis {
        DEPOSIT,
        BORROW
    }

    // Structs
    struct BalanceUpdateData {
        address collection;
        uint256 blockNumber;
        int256 nftDelta;
        int256 balanceDelta;
    }

    struct UserCollectionTracking {
        uint256 lastUpdateBlock;
        uint256 lastNFTBalance;
        uint256 lastBalance;
        uint256 lastUserRewardIndex;
    }

    /// @notice Represents a snapshot of a user's reward-relevant state at a specific point in time (blockNumber and rewardIndex).
    /// @param blockNumber The block number when this state segment began.
    /// @param nftBalance The user's NFT balance during this segment.
    /// @param balance The user's token balance (e.g., LP tokens) during this segment.
    /// @param rewardIndex The global reward index at the start of this segment (at blockNumber).
    struct RewardSnapshot {
        address collection;
        uint256 index;
        uint256 blockNumber;
    }

    // Events
    event AuthorizedUpdaterChanged(address indexed oldUpdater, address indexed newUpdater, address indexed admin);
    event NFTCollectionAdded(
        address indexed collection, uint256 beta, RewardBasis rewardBasis, uint256 rewardSharePercentage
    );
    event NFTCollectionRemoved(address indexed collection);
    event BetaUpdated(address indexed collection, uint256 oldBeta, uint256 newBeta);
    event CollectionRewardShareUpdated(
        address indexed collection, uint256 oldSharePercentage, uint256 newSharePercentage
    );
    event BalanceUpdatesProcessed(address indexed signer, uint256 nonce, uint256 count);
    event UserBalanceUpdatesProcessed(address indexed user, uint256 nonce, uint256 count);
    event RewardsClaimedForCollection(address indexed user, address indexed collection, uint256 amount);
    event RewardsClaimedForAll(address indexed user, uint256 totalAmount);
    event YieldTransferCapped(
        address indexed user, address indexed collection, uint256 calculatedReward, uint256 transferredAmount
    );
    event StaleClaimAttempt(address indexed user, uint64 expectedNonce, uint64 userNonce);
    event EpochDurationChanged(uint256 oldDuration, uint256 newDuration, address indexed changedBy);
    event CollectionConfigChanged(
        address indexed collection,
        uint96 oldBeta,
        uint96 newBeta,
        uint16 oldRewardSharePercentage,
        uint16 newRewardSharePercentage,
        IRewardsController.RewardBasis oldRewardBasis,
        IRewardsController.RewardBasis newRewardBasis,
        address indexed admin
    );
    event DustSwept(address indexed recipient, uint256 amount);

    // Errors
    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidSignature();
    error InvalidNonce(uint256 expectedNonce, uint256 actualNonce);
    error ArrayLengthMismatch();
    error InsufficientYieldFromLendingManager();
    error NoRewardsToClaim();
    error EmptyBatch();
    error SimulationUpdateOutOfOrder(uint256 updateBlock, uint256 lastProcessedBlock);
    error SimulationBalanceUpdateUnderflow(uint256 currentValue, uint256 deltaMagnitude);
    error SimulationBlockInPast(uint256 lastBlock, uint256 simBlock);
    error CollectionsArrayEmpty();
    error InvalidEpochDuration();
    error InvalidRewardSharePercentage();
    error MaxSnapshotsReached(address user, address collection, uint256 limit);

    // State Variable Getters
    function lendingManager() external view returns (ILendingManager);
    function vault() external view returns (IERC4626);
    function rewardToken() external view returns (IERC20);
    function authorizedUpdater() external view returns (address);
    function collectionRewardBasis(address collection) external view returns (RewardBasis rewardBasis);
    function authorizedUpdaterNonce(address updater) external view returns (uint256 nonce);
    function globalRewardIndex() external view returns (uint256 index);
    function epochDuration() external view returns (uint256 duration);
    function globalUpdateNonce() external view returns (uint64);
    function userLastSyncedNonce(address user) external view returns (uint64);

    // Admin Functions
    function setAuthorizedUpdater(address _newUpdater) external;
    function addNFTCollection(address collection, uint256 beta, RewardBasis rewardBasis, uint256 rewardSharePercentage)
        external;
    function removeNFTCollection(address collection) external;
    function updateBeta(address collection, uint256 newBeta) external;
    function setEpochDuration(uint256 newDuration) external;
    function setCollectionRewardSharePercentage(address collection, uint256 newSharePercentage) external;
    function sweepDust(address recipient) external;

    // Balance Update Processing
    function processBalanceUpdates(
        address signer,
        address[] calldata users,
        address[] calldata collections,
        uint256[] calldata blockNumbers,
        int256[] calldata nftDeltas,
        int256[] calldata balanceDeltas,
        bytes calldata signature
    ) external;
    function processUserBalanceUpdates(
        address signer,
        address user,
        BalanceUpdateData[] calldata updates,
        bytes calldata signature
    ) external;

    // View Functions
    function calculateBoost(uint256 nftBalance, uint256 beta) external pure returns (uint256 boostFactor);
    function getUserCollectionTracking(address user, address[] calldata nftCollections)
        external
        view
        returns (UserCollectionTracking[] memory trackingInfo);
    function getCollectionBeta(address nftCollection) external view returns (uint256);
    function getCollectionRewardBasis(address nftCollection) external view returns (RewardBasis);
    function getCollectionRewardSharePercentage(address collection) external view returns (uint256);
    function getUserNFTCollections(address user) external view returns (address[] memory collections);
    function previewRewards(
        address user,
        address[] calldata nftCollections,
        BalanceUpdateData[] calldata simulatedUpdates
    ) external returns (uint256 pendingReward);
    function isCollectionWhitelisted(address collection) external view returns (bool);
    function getWhitelistedCollections() external view returns (address[] memory collections);
    function getUserSnapshotsLength(address user, address collection) external view returns (uint256);

    // Claiming Functions
    function claimRewardsForCollection(address nftCollection, BalanceUpdateData[] calldata simulatedUpdates) external;
    function claimRewardsForAll(BalanceUpdateData[] calldata simulatedUpdates) external;
    function syncAndClaim(
        address signer,
        BalanceUpdateData[] calldata updates,
        bytes calldata signature,
        BalanceUpdateData[] calldata simulatedUpdatesForClaim
    ) external;
}
