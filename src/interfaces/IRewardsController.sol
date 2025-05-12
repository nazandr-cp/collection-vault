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

    //
    // Events
    //
    event NFTCollectionAdded(
        address indexed collection, uint256 beta, RewardBasis rewardBasis, uint256 rewardSharePercentage
    );
    event NFTCollectionRemoved(address indexed collection);
    event BetaUpdated(address indexed collection, uint256 oldBeta, uint256 newBeta);
    event CollectionRewardShareUpdated(
        address indexed collection, uint256 oldSharePercentage, uint256 newSharePercentage
    );
    event RewardsClaimed(address indexed user, address indexed collection, uint256 rewardAmount, uint256 nonce);
    event RewardsIssued(address indexed user, address indexed collection, uint256 amount, uint256 nonce);
    event BatchRewardsIssued(address indexed user, address[] collections, uint256[] amounts, uint256 nonce);
    event TrustedSignerUpdated(address oldSigner, address newSigner, address indexed changedBy);
    event EpochDurationChanged(uint256 oldDuration, uint256 newDuration, address indexed changedBy);
    event DustSwept(address indexed recipient, uint256 amount);
    event MaxRewardSharePercentageUpdated(uint256 oldMaxRewardSharePercentage, uint256 newMaxRewardSharePercentage);

    //
    // Errors
    //
    error BalanceUpdateUnderflow(uint256 currentValue, uint256 deltaMagnitude);
    error UpdateOutOfOrder(address user, address collection, uint256 updateBlock, uint256 lastProcessedBlock);
    error VaultMismatch();
    error RewardsControllerInvalidInitialOwner(address owner);
    error InvalidBetaValue(uint256 beta);
    error InvalidEpochDuration();

    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidSignature();
    error InvalidNonce(uint256 providedNonce, uint256 lastClaimedNonce);
    error ArrayLengthMismatch();
    error InsufficientYieldFromLendingManager();
    error CollectionsArrayEmpty();
    error InvalidRewardSharePercentage();
    error ExcessiveRewardAmount(address collection, uint256 requested, uint256 maxAllowed);

    //
    // State Variable Getters
    //
    function lendingManager() external view returns (ILendingManager);

    function vault() external view returns (IERC4626);

    function rewardToken() external view returns (IERC20);

    function trustedSigner() external view returns (address);

    function collectionRewardBasis(address collection) external view returns (RewardBasis rewardBasis);

    function epochDuration() external view returns (uint256 duration);

    function globalUpdateNonce() external view returns (uint64);

    function globalRewardIndex() external view returns (uint256);

    function userLastSyncedNonce(address user) external view returns (uint64);

    function userClaimedNonces(address user, address collection) external view returns (uint256);

    function getUserGlobalNonce(address user) external view returns (uint256);

    function maxRewardSharePercentage() external view returns (uint16);

    //
    // Admin Functions
    //
    function setTrustedSigner(address _newSigner) external;

    function addNFTCollection(address collection, uint256 beta, RewardBasis rewardBasis, uint256 rewardSharePercentage)
        external;

    function removeNFTCollection(address collection) external;

    function updateBeta(address collection, uint256 newBeta) external;

    function setEpochDuration(uint256 newDuration) external;

    function setCollectionRewardSharePercentage(address collection, uint256 newSharePercentage) external;

    function sweepDust(address recipient) external;

    //
    // View Functions
    //
    function getCollectionData(address collection)
        external
        view
        returns (uint256 beta, RewardBasis rewardBasis, uint256 rewardSharePercentage);

    function calculateBoost(uint256 nftBalance, uint256 beta) external pure returns (uint256 boostFactor);

    function getCollectionBeta(address nftCollection) external view returns (uint256);

    function getCollectionRewardBasis(address nftCollection) external view returns (RewardBasis);

    function getCollectionRewardSharePercentage(address collection) external view returns (uint256);

    function isCollectionWhitelisted(address collection) external view returns (bool);

    function getWhitelistedCollections() external view returns (address[] memory collections);

    //
    // Claiming Functions
    //
    function claimRewardsForCollection(
        address _collection,
        address _recipient,
        uint256 _rewardAmount,
        uint256 _nonce,
        bytes calldata _signature
    ) external;

    function claimRewardsForAllCollections(
        address _recipient,
        uint256[] calldata _rewardAmountPerCollection,
        address[] calldata _collections,
        uint256 _totalRewardAmount,
        uint256 _nonce,
        bytes calldata _signature
    ) external;
}
