// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.2.0/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin-contracts-5.2.0/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin-contracts-5.2.0/utils/math/Math.sol";
import {EIP712} from "@openzeppelin-contracts-5.2.0/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin-contracts-5.2.0/utils/cryptography/ECDSA.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {IERC4626VaultMinimal} from "./interfaces/IERC4626VaultMinimal.sol";

/**
 * @title RewardsController
 * @notice Manages reward calculation and distribution, incorporating NFT-based bonus multipliers.
 * @dev Implements IRewardsController. Tracks user NFT balances, calculates yield (base + bonus),
 *      and distributes rewards by pulling base yield from the LendingManager. Uses EIP-712 for signed balance updates (single and batch).
 */
contract RewardsController is IRewardsController, Ownable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- Local Structs --- //
    /**
     * @notice Struct to hold reward tracking data per user per collection.
     * @dev Mirrors relevant fields needed for internal logic, distinct from IRewardsController.UserNFTInfo if necessary.
     */
    struct UserRewardState {
        uint256 lastRewardIndex; // Global index at the last update for this user/collection
        uint256 accruedReward; // Total rewards accumulated since last claim
        uint256 lastNFTBalance; // NFT balance at the last update
        uint256 lastDepositAmount; // Deposit amount at the last update
        uint256 lastUpdateBlock; // Block number of the last update
    }

    // --- EIP-712 Type Hashes ---
    // Multi-User Batch Update
    bytes32 public constant USER_BALANCE_UPDATE_DATA_TYPEHASH = keccak256(
        "UserBalanceUpdateData(address user,address collection,uint256 blockNumber,int256 nftDelta,int256 depositDelta)"
    );
    bytes32 public constant BALANCE_UPDATES_TYPEHASH =
        keccak256("BalanceUpdates(UserBalanceUpdateData[] updates,uint256 nonce)");

    // Single-User Batch Update
    bytes32 public constant BALANCE_UPDATE_DATA_TYPEHASH =
        keccak256("BalanceUpdateData(address collection,uint256 blockNumber,int256 nftDelta,int256 depositDelta)");
    bytes32 public constant USER_BALANCE_UPDATES_TYPEHASH =
        keccak256("UserBalanceUpdates(address user,BalanceUpdateData[] updates,uint256 nonce)");

    // --- Constants --- //
    uint256 private constant PRECISION_FACTOR = 1e18;

    // --- State Variables --- //

    ILendingManager public immutable lendingManager;
    IERC4626VaultMinimal public immutable vault;
    IERC20 public immutable rewardToken; // The token distributed as rewards (should be same as LM asset)
    address public authorizedUpdater; // Address authorized to submit signed balance updates

    // NFT Collection Management
    EnumerableSet.AddressSet private _whitelistedCollections;
    mapping(address => uint256) public collectionBetas; // collection => beta (reward coefficient)

    // User Reward Tracking
    mapping(address => mapping(address => UserRewardState)) internal userRewardState; // Renamed for clarity
    mapping(address => EnumerableSet.AddressSet) private _userActiveCollections;
    mapping(address => uint256) public authorizedUpdaterNonce; // Nonce per authorized updater for replay protection on batch updates

    // Global Reward State
    uint256 public globalRewardIndex;
    uint256 public lastDistributionBlock;

    // --- Events --- //
    // Note: Events are inherited from the IRewardsController interface.
    // Additional internal events can be added if needed, but interface events should be emitted correctly.
    // Removed specific update processed events in favor of batch events from interface.
    event NFTBalanceUpdateProcessed(
        address indexed user, address indexed collection, uint256 blockNumber, int256 nftDelta, uint256 finalNFTBalance
    );
    event DepositUpdateProcessed(
        address indexed user,
        address indexed collection,
        uint256 blockNumber,
        int256 depositDelta,
        uint256 finalDepositAmount
    );

    // --- Errors --- //
    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidSignature();
    error InvalidNonce(uint256 expectedNonce, uint256 actualNonce);
    error ArrayLengthMismatch();
    error InsufficientYieldFromLendingManager();
    error NoRewardsToClaim();
    error NormalizationError();
    error VaultMismatch();
    error BalanceUpdateUnderflow(uint256 currentValue, uint256 deltaMagnitude);
    error UpdateOutOfOrder(address user, address collection, uint256 updateBlock, uint256 lastProcessedBlock);
    error EmptyBatch();
    error SimulationUpdateOutOfOrder(uint256 updateBlock, uint256 lastProcessedBlock);
    error SimulationBalanceUpdateUnderflow(uint256 currentValue, uint256 deltaMagnitude);
    error SimulationBlockInPast(uint256 lastBlock, uint256 simBlock);
    error UserMismatch(address expectedUser, address actualUser); // Added for single-user batch check
    error CollectionsArrayEmpty(); // Added for preview/get view functions

    // --- Modifiers --- //
    modifier onlyWhitelistedCollection(address collection) {
        if (!_whitelistedCollections.contains(collection)) {
            revert CollectionNotWhitelisted(collection);
        }
        _;
    }

    // --- Constructor --- //
    constructor(address initialOwner, address _lendingManagerAddress, address _vaultAddress, address _authorizedUpdater)
        Ownable(initialOwner)
        EIP712("RewardsController", "1")
    {
        if (_lendingManagerAddress == address(0) || _vaultAddress == address(0) || _authorizedUpdater == address(0)) {
            revert AddressZero();
        }

        lendingManager = ILendingManager(_lendingManagerAddress);
        vault = IERC4626VaultMinimal(_vaultAddress);
        rewardToken = lendingManager.asset();

        if (address(rewardToken) == address(0)) revert AddressZero();
        if (vault.asset() != address(rewardToken)) revert VaultMismatch();

        authorizedUpdater = _authorizedUpdater;

        lastDistributionBlock = block.number;
        globalRewardIndex = PRECISION_FACTOR;
    }

    // --- Admin Functions --- //

    function setAuthorizedUpdater(address _newUpdater) external override onlyOwner {
        if (_newUpdater == address(0)) revert AddressZero();
        address oldUpdater = authorizedUpdater;
        authorizedUpdater = _newUpdater;
        emit AuthorizedUpdaterChanged(oldUpdater, _newUpdater);
    }

    function addNFTCollection(address collection, uint256 beta) external override onlyOwner {
        if (collection == address(0)) revert AddressZero();
        if (!_whitelistedCollections.add(collection)) {
            revert CollectionAlreadyExists(collection);
        }
        collectionBetas[collection] = beta;
        emit NFTCollectionAdded(collection, beta);
    }

    function removeNFTCollection(address collection)
        external
        override
        onlyOwner
        onlyWhitelistedCollection(collection)
    {
        _whitelistedCollections.remove(collection);
        delete collectionBetas[collection];
        emit NFTCollectionRemoved(collection);
    }

    function updateBeta(address collection, uint256 newBeta)
        external
        override
        onlyOwner
        onlyWhitelistedCollection(collection)
    {
        uint256 oldBeta = collectionBetas[collection];
        collectionBetas[collection] = newBeta;
        emit BetaUpdated(collection, oldBeta, newBeta);
    }

    // --- Balance Update Processing (with Signatures) --- //

    /**
     * @notice Processes a batch of signed balance updates (NFT and/or deposit) for multiple users/collections.
     * @dev Uses authorized updater's nonce. Emits BalanceUpdatesProcessed.
     */
    function processBalanceUpdates(UserBalanceUpdateData[] calldata updates, bytes calldata signature)
        external
        override
        nonReentrant
    {
        if (updates.length == 0) revert EmptyBatch();

        address signer = authorizedUpdater; // Expect signature from the authorized updater
        uint256 nonce = authorizedUpdaterNonce[signer]; // Use signer (updater) nonce for batch replay protection

        bytes32 updatesHash = _hashUserBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATES_TYPEHASH, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }
        if (recoveredSigner != authorizedUpdater) {
            revert InvalidSignature(); // Explicit check against current authorized updater
        }
        authorizedUpdaterNonce[signer]++; // Increment signer (updater) nonce

        for (uint256 i = 0; i < updates.length; i++) {
            UserBalanceUpdateData memory update = updates[i];
            if (!_whitelistedCollections.contains(update.collection)) {
                revert CollectionNotWhitelisted(update.collection);
            }
            // Process update internally
            _processSingleUpdate(
                update.user, update.collection, update.blockNumber, update.nftDelta, update.depositDelta
            );
        }

        emit BalanceUpdatesProcessed(signer, nonce, updates.length);
    }

    /**
     * @notice Processes a batch of signed balance updates (NFT and/or deposit) for a single user across multiple collections.
     * @dev Uses authorized updater's nonce. Emits UserBalanceUpdatesProcessed.
     */
    function processUserBalanceUpdates(address user, BalanceUpdateData[] calldata updates, bytes calldata signature)
        external
        override
        nonReentrant
    {
        if (updates.length == 0) revert EmptyBatch();

        address signer = authorizedUpdater; // Expect signature from the authorized updater
        uint256 nonce = authorizedUpdaterNonce[signer]; // Use signer (updater) nonce for batch replay protection

        bytes32 updatesHash = _hashBalanceUpdates(updates);
        // Note: Hashing includes the 'user' address as specified in USER_BALANCE_UPDATES_TYPEHASH
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }
        if (recoveredSigner != authorizedUpdater) {
            revert InvalidSignature(); // Explicit check against current authorized updater
        }
        authorizedUpdaterNonce[signer]++; // Increment signer (updater) nonce

        for (uint256 i = 0; i < updates.length; i++) {
            BalanceUpdateData memory update = updates[i];
            if (!_whitelistedCollections.contains(update.collection)) {
                revert CollectionNotWhitelisted(update.collection);
            }
            // Process update internally for the specified user
            _processSingleUpdate(user, update.collection, update.blockNumber, update.nftDelta, update.depositDelta);
        }

        emit UserBalanceUpdatesProcessed(user, nonce, updates.length);
    }

    /**
     * @notice Process a single NFT balance update for a user and collection with signature verification
     * @dev Used by tests for individual update verification
     */
    function processNFTBalanceUpdate(
        address user,
        address collection,
        uint256 blockNumber,
        int256 nftDelta,
        bytes calldata signature
    ) external nonReentrant {
        address signer = authorizedUpdater;

        // Build the message to verify
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATE_DATA_TYPEHASH, collection, blockNumber, nftDelta, 0)); // Removed user, nonce, added 0 for depositDelta placeholder

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }

        authorizedUpdaterNonce[signer]++;

        if (!_whitelistedCollections.contains(collection)) {
            revert CollectionNotWhitelisted(collection);
        }

        _processSingleUpdate(user, collection, blockNumber, nftDelta, 0);

        emit NFTBalanceUpdateProcessed(
            user, collection, blockNumber, nftDelta, userRewardState[user][collection].lastNFTBalance
        );
    }

    /**
     * @notice Process a single deposit balance update for a user and collection with signature verification
     * @dev Used by tests for individual update verification
     */
    function processDepositUpdate(
        address user,
        address collection,
        uint256 blockNumber,
        int256 depositDelta,
        bytes calldata signature
    ) external nonReentrant {
        address signer = authorizedUpdater;

        // Build the message to verify
        bytes32 structHash =
            keccak256(abi.encode(BALANCE_UPDATE_DATA_TYPEHASH, collection, blockNumber, 0, depositDelta)); // Removed user, nonce, added 0 for nftDelta placeholder

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }

        authorizedUpdaterNonce[signer]++;

        if (!_whitelistedCollections.contains(collection)) {
            revert CollectionNotWhitelisted(collection);
        }

        _processSingleUpdate(user, collection, blockNumber, 0, depositDelta);

        emit DepositUpdateProcessed(
            user, collection, blockNumber, depositDelta, userRewardState[user][collection].lastDepositAmount
        );
    }

    // --- Hashing Helpers for Batches ---

    function _hashUserBalanceUpdates(UserBalanceUpdateData[] calldata updates) internal pure returns (bytes32) {
        bytes32[] memory encodedUpdates = new bytes32[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            encodedUpdates[i] = keccak256(
                abi.encode(
                    USER_BALANCE_UPDATE_DATA_TYPEHASH,
                    updates[i].user,
                    updates[i].collection,
                    updates[i].blockNumber,
                    updates[i].nftDelta,
                    updates[i].depositDelta
                )
            );
        }
        return keccak256(abi.encodePacked(encodedUpdates));
    }

    function _hashBalanceUpdates(BalanceUpdateData[] calldata updates) internal pure returns (bytes32) {
        bytes32[] memory encodedUpdates = new bytes32[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            encodedUpdates[i] = keccak256(
                abi.encode(
                    BALANCE_UPDATE_DATA_TYPEHASH,
                    updates[i].collection,
                    updates[i].blockNumber,
                    updates[i].nftDelta,
                    updates[i].depositDelta
                )
            );
        }
        return keccak256(abi.encodePacked(encodedUpdates));
    }

    // --- Internal Update Logic --- //

    function _processSingleUpdate(
        address user,
        address collection,
        uint256 updateBlock,
        int256 nftDelta,
        int256 depositDelta
    ) internal {
        UserRewardState storage info = userRewardState[user][collection];

        if (updateBlock < info.lastUpdateBlock) {
            if (!(updateBlock == block.number)) {
                revert UpdateOutOfOrder(user, collection, updateBlock, info.lastUpdateBlock);
            }
        }

        if (info.lastUpdateBlock == 0) {
            if (updateBlock > lastDistributionBlock) {
                _updateGlobalRewardIndexTo(updateBlock);
            }
            info.lastRewardIndex = globalRewardIndex;
            info.lastUpdateBlock = updateBlock;
        } else if (updateBlock > info.lastUpdateBlock) {
            _updateGlobalRewardIndexTo(updateBlock);

            uint256 indexDeltaForPeriod = globalRewardIndex - info.lastRewardIndex;
            uint256 rewardForPeriod =
                _calculateRewardsWithDelta(collection, indexDeltaForPeriod, info.lastNFTBalance, info.lastDepositAmount);

            info.accruedReward += rewardForPeriod;

            info.lastRewardIndex = globalRewardIndex;
            info.lastUpdateBlock = updateBlock;
        }

        info.lastNFTBalance = _applyDelta(info.lastNFTBalance, nftDelta);
        info.lastDepositAmount = _applyDelta(info.lastDepositAmount, depositDelta);
        if (info.lastNFTBalance > 0 || info.lastDepositAmount > 0) {
            if (!_userActiveCollections[user].contains(collection)) {
                _userActiveCollections[user].add(collection);
            }
        } else {
            if (_userActiveCollections[user].contains(collection)) {
                _userActiveCollections[user].remove(collection);
            }
        }
    }

    function _applyDelta(uint256 value, int256 delta) internal pure returns (uint256) {
        if (delta >= 0) {
            return value + uint256(delta);
        } else {
            uint256 absDelta = uint256(-delta);
            if (absDelta > value) {
                revert BalanceUpdateUnderflow(value, absDelta);
            }
            return value - absDelta;
        }
    }

    function _calculateRewardsWithDelta(
        address nftCollection,
        uint256 indexDelta,
        uint256 nftBalanceDuringPeriod,
        uint256 depositAmountDuringPeriod
    ) internal view returns (uint256 reward) {
        if (indexDelta == 0 || depositAmountDuringPeriod == 0) {
            return 0;
        }

        uint256 baseReward = (depositAmountDuringPeriod * indexDelta) / PRECISION_FACTOR;

        if (nftBalanceDuringPeriod > 0) {
            uint256 beta = collectionBetas[nftCollection];
            uint256 boostFactor = calculateBoost(nftBalanceDuringPeriod, beta);

            uint256 bonusReward = (baseReward * boostFactor) / PRECISION_FACTOR;
            reward = baseReward + bonusReward;
        } else {
            reward = baseReward;
        }

        return reward;
    }

    function _calculateGlobalIndexAt(uint256 targetBlock) internal view returns (uint256) {
        if (targetBlock <= lastDistributionBlock) {
            return globalRewardIndex; // Return stored index if target is in the past or present
        }
        // Calculate index increase from last distribution block to target block
        uint256 blockDelta = targetBlock - lastDistributionBlock;
        uint256 ratePerBlock = PRECISION_FACTOR; // Assuming rate is 1e18 per block for simplicity
        uint256 indexIncrease = blockDelta * ratePerBlock;
        return globalRewardIndex + indexIncrease;
    }

    /**
     * @notice Internal function to calculate pending rewards for a SINGLE collection, handling simulated updates.
     * @dev Used by public previewRewards and claim functions.
     */
    function _getPendingRewardsSingleCollection(
        address user,
        address nftCollection,
        BalanceUpdateData[] memory simulatedUpdates // Changed from calldata to memory
    ) internal view returns (uint256 pendingReward) {
        UserRewardState storage info = userRewardState[user][nftCollection];

        // --- Initialize Simulation State from Stored State ---
        uint256 simTotalReward = info.accruedReward; // Start with already accrued rewards
        uint256 simNftBalance = info.lastNFTBalance;
        uint256 simDepositAmount = info.lastDepositAmount;
        uint256 simLastProcessedBlock = info.lastUpdateBlock;
        uint256 simLastRewardIndex = info.lastRewardIndex;

        // --- Handle Initialization Case (No prior updates for user/collection) ---
        if (simLastProcessedBlock == 0) {
            // User has never interacted with this collection via updates.
            // Their reward calculation starts effectively from the point they *would* have interacted,
            // or from the beginning of the simulation if that's earlier.
            // We need a starting index. Use the global index at the *start* of the simulation or current block if no simulation.
            uint256 startingBlockForIndex = (
                simulatedUpdates.length > 0 && simulatedUpdates[0].blockNumber < lastDistributionBlock
            ) ? simulatedUpdates[0].blockNumber : lastDistributionBlock; // Or should it be block.number if no simulations?

            // If the first sim block is *before* the last global update, calculate index at that point
            if (startingBlockForIndex < lastDistributionBlock) {
                simLastRewardIndex = _calculateGlobalIndexAt(startingBlockForIndex);
                simLastProcessedBlock = startingBlockForIndex; // Simulation effectively starts here for reward calc
            } else {
                simLastRewardIndex = globalRewardIndex; // Start from current global index
                simLastProcessedBlock = lastDistributionBlock; // Simulation starts from last global update
            }
            // If the first simulation block IS the start, override the above:
            if (simulatedUpdates.length > 0) {
                simLastProcessedBlock = simulatedUpdates[0].blockNumber;
                simLastRewardIndex = _calculateGlobalIndexAt(simLastProcessedBlock);
            }
        }

        // --- Process Simulated Updates ---
        for (uint256 i = 0; i < simulatedUpdates.length; i++) {
            BalanceUpdateData memory update = simulatedUpdates[i];

            // Check simulation update collection matches the function scope
            if (update.collection != nftCollection) {
                // This shouldn't happen if called correctly by the public function filtering updates
                // but good to be defensive. Could revert or skip.
                continue; // Skip updates not for this collection
            }

            // Ensure simulation updates are in order relative to the simulation's progress
            if (update.blockNumber < simLastProcessedBlock) {
                // Revert SimulationUpdateOutOfOrder(); // Use updated error
                revert SimulationUpdateOutOfOrder(update.blockNumber, simLastProcessedBlock);
            }

            // Accrue rewards *up to* the block of the current simulated update
            if (update.blockNumber > simLastProcessedBlock) {
                uint256 globalIndexAtSimUpdateBlock = _calculateGlobalIndexAt(update.blockNumber);
                uint256 indexDeltaForPeriod = globalIndexAtSimUpdateBlock - simLastRewardIndex;

                if (indexDeltaForPeriod > 0) {
                    // Calculate rewards based on the balance *before* this simulated update
                    uint256 rewardPeriod =
                        _calculateRewardsWithDelta(nftCollection, indexDeltaForPeriod, simNftBalance, simDepositAmount);
                    simTotalReward += rewardPeriod;
                }
                // Update the simulation's index checkpoint
                simLastRewardIndex = globalIndexAtSimUpdateBlock;
            }

            // Apply the deltas from the simulated update
            simNftBalance = _applyDeltaSimulated(simNftBalance, update.nftDelta);
            simDepositAmount = _applyDeltaSimulated(simDepositAmount, update.depositDelta);
            // Update the simulation's last processed block
            simLastProcessedBlock = update.blockNumber;
        }

        // --- Calculate Final Rewards (from last sim update/initial state up to current block) ---
        uint256 currentBlock = block.number;
        uint256 finalGlobalIndex = _calculateGlobalIndexAt(currentBlock);

        if (currentBlock > simLastProcessedBlock && finalGlobalIndex > simLastRewardIndex) {
            uint256 finalIndexDelta = finalGlobalIndex - simLastRewardIndex;
            // Calculate rewards based on the balance *after* the last simulated update (or initial state if no sims)
            uint256 finalReward =
                _calculateRewardsWithDelta(nftCollection, finalIndexDelta, simNftBalance, simDepositAmount);
            simTotalReward += finalReward;
        }
        // Edge case: If the last processed block IS the current block, and no rewards were previously accrued
        // but the user *had* a balance, calculate potential rewards from their last known index up to now.
        // This handles users who haven't had an update recently but are eligible for rewards accrued since their last update.
        // Note: This might double-count if _processSingleUpdate already handles this implicitly before claim. Review needed.
        // Let's refine the logic: The loop above calculates rewards *between* updates. The final step calculates rewards
        // from the last update (real or simulated) up to the current block.
        // else if (
        //     currentBlock == simLastProcessedBlock && info.accruedReward == 0 && simTotalReward == 0
        //         && (simNftBalance > 0 || simDepositAmount > 0) // Use simulated balances here
        // ) {
        //     uint256 initialIndex = simLastRewardIndex; // Already holds the correct starting index for this final period
        //     if (finalGlobalIndex > initialIndex) {
        //         uint256 finalIndexDelta = finalGlobalIndex - initialIndex;
        //         uint256 finalReward =
        //             _calculateRewardsWithDelta(nftCollection, finalIndexDelta, simNftBalance, simDepositAmount);
        //         simTotalReward += finalReward;
        //     }
        // }

        return simTotalReward;
    }

    function _applyDeltaSimulated(uint256 value, int256 delta) internal pure returns (uint256) {
        if (delta >= 0) {
            return value + uint256(delta);
        } else {
            uint256 absDelta = uint256(-delta);
            if (absDelta > value) {
                // revert SimulationUnderflow(); // Use updated error
                revert SimulationBalanceUpdateUnderflow(value, absDelta);
            }
            return value - absDelta;
        }
    }

    function _updateGlobalRewardIndexTo(uint256 targetBlock) internal {
        if (targetBlock <= lastDistributionBlock) {
            return;
        }
        uint256 currentGlobalIndex = _calculateGlobalIndexAt(targetBlock);
        globalRewardIndex = currentGlobalIndex;
        lastDistributionBlock = targetBlock;
    }

    function _updateGlobalRewardIndex() internal {
        _updateGlobalRewardIndexTo(block.number);
    }

    // --- Public View / Calculation Functions --- //

    function calculateBoost(uint256 nftBalance, uint256 beta) public pure returns (uint256 boostFactor) {
        if (nftBalance == 0) return 0; // No boost if no NFTs

        // Simple linear boost: boost = balance * beta / precision
        // Ensure beta itself is scaled correctly (e.g., 1e18 means 100% boost per NFT? Check definition)
        // Assuming beta is scaled by 1e18, where 1e18 = 1x multiplier effect *per NFT*.
        boostFactor = (nftBalance * beta); // Removed / PRECISION_FACTOR if beta is already scaled

        // Example: beta = 0.1e18 (10% bonus per NFT), balance = 5
        // boostFactor = 5 * 0.1e18 = 0.5e18 (50% total bonus multiplier)

        // Cap the *bonus* part? Or the total factor? Interface implies total boost factor.
        // Let's assume beta represents the *additional* reward percentage per NFT, scaled by 1e18.
        // So, boostFactor calculated above represents the total *bonus* multiplier (0.5e18 = 50% bonus).
        // The final reward = base + base * boostFactor / PRECISION_FACTOR

        // Let's redefine `boostFactor` to be the value used in the _calculateRewardsWithDelta formula:
        // bonusReward = (baseReward * boostFactor) / PRECISION_FACTOR;
        // If beta = 0.1e18 means 10% bonus per NFT:
        // boostFactor should = nftBalance * beta
        boostFactor = nftBalance * beta;

        // Cap the boost factor (e.g., max 900% bonus = 9 * 1e18)
        uint256 maxBoostFactor = PRECISION_FACTOR * 9; // Represents 900% bonus
        if (boostFactor > maxBoostFactor) {
            boostFactor = maxBoostFactor;
        }
        return boostFactor; // This is the value to multiply base reward by and divide by PRECISION
    }

    /**
     * @notice Retrieves the stored reward tracking information for a user across multiple specified collections.
     * @inheritdoc IRewardsController
     */
    function getUserCollectionTracking(address user, address[] calldata nftCollections)
        external
        view
        override
        returns (UserCollectionTracking[] memory trackingInfo)
    {
        if (nftCollections.length == 0) {
            revert CollectionsArrayEmpty();
        }
        trackingInfo = new UserCollectionTracking[](nftCollections.length);
        for (uint256 i = 0; i < nftCollections.length; i++) {
            address collection = nftCollections[i];
            // Check if collection is whitelisted? Interface doesn't specify, but seems sensible.
            // if (!_whitelistedCollections.contains(collection)) {
            //     // Handle error or return default struct? Returning default for now.
            //     trackingInfo[i] = UserCollectionTracking({
            //         lastUpdateBlock: 0,
            //         lastNFTBalance: 0,
            //         lastDepositBalance: 0,
            //         lastUserRewardIndex: 0
            //     });
            // } else {
            // UserRewardState storage internalInfo = userNFTData[user][collection]; // Use renamed state variable
            UserRewardState storage internalInfo = userRewardState[user][collection];
            trackingInfo[i] = UserCollectionTracking({
                lastUpdateBlock: internalInfo.lastUpdateBlock,
                lastNFTBalance: internalInfo.lastNFTBalance,
                lastDepositBalance: internalInfo.lastDepositAmount, // Map from internal state
                lastUserRewardIndex: internalInfo.lastRewardIndex
            });
            // }
        }
        return trackingInfo;
    }

    function getCollectionBeta(address nftCollection)
        external
        view
        override
        onlyWhitelistedCollection(nftCollection)
        returns (uint256)
    {
        return collectionBetas[nftCollection];
    }

    function getUserNFTCollections(address user) external view override returns (address[] memory) {
        return _userActiveCollections[user].values();
    }

    /**
     * @notice Preview total pending rewards for a user across multiple specified collections, optionally simulating future updates.
     * @inheritdoc IRewardsController
     */
    function previewRewards(
        address user,
        address[] calldata nftCollections,
        BalanceUpdateData[] calldata simulatedUpdates
    ) external view override returns (uint256 pendingReward) {
        if (nftCollections.length == 0) {
            // If no collections specified, return 0 or revert? Returning 0.
            return 0;
        }

        uint256 totalPendingReward = 0;
        for (uint256 i = 0; i < nftCollections.length; i++) {
            address collection = nftCollections[i];
            if (!isCollectionWhitelisted(collection)) {
                // Check whitelist status
                // Skip non-whitelisted collections
                continue;
            }
            // Pass all, internal function will filter by collection.
            totalPendingReward += _getPendingRewardsSingleCollection(user, collection, simulatedUpdates);
        }

        pendingReward = totalPendingReward; // Assign to return variable
        return pendingReward;
    }

    // This function is specific to this contract, not part of the interface
    function isCollectionWhitelisted(address collection) public view returns (bool) {
        return _whitelistedCollections.contains(collection);
    }

    function getWhitelistedCollections() external view override returns (address[] memory) {
        return _whitelistedCollections.values();
    }

    // --- Claiming Functions --- //

    function claimRewardsForCollection(address nftCollection)
        external
        override
        nonReentrant
        onlyWhitelistedCollection(nftCollection)
    {
        address user = msg.sender;

        _updateGlobalRewardIndex();

        uint256 totalReward = _getPendingRewardsSingleCollection(user, nftCollection, new BalanceUpdateData[](0));

        if (totalReward == 0) {
            revert NoRewardsToClaim();
        }

        UserRewardState storage info = userRewardState[user][nftCollection];
        info.accruedReward = 0;
        info.lastRewardIndex = globalRewardIndex;
        info.lastUpdateBlock = block.number;

        if (totalReward > 0) {
            lendingManager.transferYield(totalReward, address(this));
        }

        rewardToken.safeTransfer(user, totalReward);

        emit RewardsClaimedForCollection(user, nftCollection, totalReward);
    }

    function claimRewardsForAll() external override nonReentrant {
        address user = msg.sender;
        address[] memory activeCollections = _userActiveCollections[user].values();
        uint256 totalRewardsToSend = 0;

        if (activeCollections.length == 0) {
            revert NoRewardsToClaim();
        }

        _updateGlobalRewardIndex();

        for (uint256 i = 0; i < activeCollections.length; i++) {
            address collection = activeCollections[i];

            uint256 collectionTotalReward =
                _getPendingRewardsSingleCollection(user, collection, new BalanceUpdateData[](0));

            if (collectionTotalReward > 0) {
                totalRewardsToSend += collectionTotalReward;

                UserRewardState storage info = userRewardState[user][collection];
                info.accruedReward = 0;
                info.lastRewardIndex = globalRewardIndex;
                info.lastUpdateBlock = block.number;

                emit RewardsClaimedForCollection(user, collection, collectionTotalReward);
            }
        }

        if (totalRewardsToSend == 0) {
            bool hasClaimable = false;
            for (uint256 i = 0; i < activeCollections.length; i++) {
                uint256 rewardCheck =
                    _getPendingRewardsSingleCollection(user, activeCollections[i], new BalanceUpdateData[](0));
                if (rewardCheck > 0) {
                    hasClaimable = true;
                    break;
                }
            }
            if (!hasClaimable) revert NoRewardsToClaim();
            revert("Reward calculation mismatch");
        }

        if (totalRewardsToSend > 0) {
            lendingManager.transferYield(totalRewardsToSend, address(this));
        }

        rewardToken.safeTransfer(user, totalRewardsToSend);

        emit RewardsClaimedForAll(user, totalRewardsToSend);
    }

    /**
     * @notice Exposes the userRewardState for a specific user and collection (added for testing)
     * @dev This function is needed by tests to verify balance updates
     */
    function userNFTData(address user, address collection)
        external
        view
        returns (
            uint256 lastRewardIndex,
            uint256 accruedReward,
            uint256 accruedBonusRewardState, // Not tracked separately in this implementation, will return 0
            uint256 lastNFTBalance,
            uint256 lastDepositAmount,
            uint256 lastUpdateBlock
        )
    {
        UserRewardState storage info = userRewardState[user][collection];
        return (
            info.lastRewardIndex,
            info.accruedReward,
            0, // Contract doesn't track base vs bonus separately
            info.lastNFTBalance,
            info.lastDepositAmount,
            info.lastUpdateBlock
        );
    }

    // --- Fallback Functions --- //
    // receive() external payable {} // Keep commented unless needed
    // fallback() external payable {} // Keep commented unless needed
}
