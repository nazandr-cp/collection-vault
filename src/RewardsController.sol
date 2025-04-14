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

    uint256 private constant PRECISION_FACTOR = 1e18;

    ILendingManager public immutable lendingManager;
    IERC4626VaultMinimal public immutable vault;
    IERC20 public immutable rewardToken; // The token distributed as rewards (must be same as LM asset)
    address public authorizedUpdater;

    // NFT Collection Management
    EnumerableSet.AddressSet private _whitelistedCollections;
    mapping(address => uint256) public collectionBetas; // collection => beta (reward coefficient)

    // User Reward Tracking
    mapping(address => mapping(address => UserRewardState)) internal userRewardState;
    mapping(address => EnumerableSet.AddressSet) private _userActiveCollections;
    mapping(address => uint256) public authorizedUpdaterNonce; // Nonce per authorized updater for replay protection

    // Global Reward State
    uint256 public globalRewardIndex;
    uint256 public lastDistributionBlock;

    // --- Events ---
    // Note: Events are inherited from IRewardsController.
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
    error UserMismatch(address expectedUser, address actualUser);
    error CollectionsArrayEmpty();

    modifier onlyWhitelistedCollection(address collection) {
        if (!_whitelistedCollections.contains(collection)) {
            revert CollectionNotWhitelisted(collection);
        }
        _;
    }

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

    // --- Balance Update Processing --- //

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

        address signer = authorizedUpdater;
        uint256 nonce = authorizedUpdaterNonce[signer]; // Use signer's nonce for replay protection

        bytes32 updatesHash = _hashUserBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATES_TYPEHASH, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }
        if (recoveredSigner != authorizedUpdater) {
            revert InvalidSignature();
        }
        authorizedUpdaterNonce[signer]++;

        for (uint256 i = 0; i < updates.length; i++) {
            UserBalanceUpdateData memory update = updates[i];
            if (!_whitelistedCollections.contains(update.collection)) {
                revert CollectionNotWhitelisted(update.collection);
            }
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

        address signer = authorizedUpdater;
        uint256 nonce = authorizedUpdaterNonce[signer]; // Use signer's nonce for replay protection

        bytes32 updatesHash = _hashBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }
        if (recoveredSigner != authorizedUpdater) {
            revert InvalidSignature();
        }
        authorizedUpdaterNonce[signer]++;

        for (uint256 i = 0; i < updates.length; i++) {
            BalanceUpdateData memory update = updates[i];
            if (!_whitelistedCollections.contains(update.collection)) {
                revert CollectionNotWhitelisted(update.collection);
            }
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
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATE_DATA_TYPEHASH, collection, blockNumber, nftDelta, 0));

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
            keccak256(abi.encode(BALANCE_UPDATE_DATA_TYPEHASH, collection, blockNumber, 0, depositDelta));

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

    // --- Core Update Logic --- //

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
        BalanceUpdateData[] memory simulatedUpdates
    ) internal view returns (uint256 pendingReward) {
        UserRewardState storage info = userRewardState[user][nftCollection];

        // Initialize simulation state from stored state
        uint256 simTotalReward = info.accruedReward;
        uint256 simNftBalance = info.lastNFTBalance;
        uint256 simDepositAmount = info.lastDepositAmount;
        uint256 simLastProcessedBlock = info.lastUpdateBlock;
        uint256 simLastRewardIndex = info.lastRewardIndex;

        // Handle initialization case (no prior updates for user/collection)
        if (simLastProcessedBlock == 0) {
            // Determine the starting index based on the first simulation block or last global update
            uint256 startingBlockForIndex = (
                simulatedUpdates.length > 0 && simulatedUpdates[0].blockNumber < lastDistributionBlock
            ) ? simulatedUpdates[0].blockNumber : lastDistributionBlock;

            if (startingBlockForIndex < lastDistributionBlock) {
                simLastRewardIndex = _calculateGlobalIndexAt(startingBlockForIndex);
                simLastProcessedBlock = startingBlockForIndex;
            } else {
                simLastRewardIndex = globalRewardIndex;
                simLastProcessedBlock = lastDistributionBlock;
            }
            // If simulations exist, ensure the start block/index reflect the first simulation
            if (simulatedUpdates.length > 0) {
                simLastProcessedBlock = simulatedUpdates[0].blockNumber;
                simLastRewardIndex = _calculateGlobalIndexAt(simLastProcessedBlock);
            }
        }

        // Process simulated updates
        for (uint256 i = 0; i < simulatedUpdates.length; i++) {
            BalanceUpdateData memory update = simulatedUpdates[i];

            if (update.collection != nftCollection) {
                // This should not happen if called correctly by the public function filtering updates
                continue;
            }

            if (update.blockNumber < simLastProcessedBlock) {
                revert SimulationUpdateOutOfOrder(update.blockNumber, simLastProcessedBlock);
            }

            // Accrue rewards up to the block of the current simulated update
            if (update.blockNumber > simLastProcessedBlock) {
                uint256 globalIndexAtSimUpdateBlock = _calculateGlobalIndexAt(update.blockNumber);
                uint256 indexDeltaForPeriod = globalIndexAtSimUpdateBlock - simLastRewardIndex;

                if (indexDeltaForPeriod > 0) {
                    uint256 rewardPeriod =
                        _calculateRewardsWithDelta(nftCollection, indexDeltaForPeriod, simNftBalance, simDepositAmount);
                    simTotalReward += rewardPeriod;
                }
                simLastRewardIndex = globalIndexAtSimUpdateBlock;
            }

            // Apply deltas from the simulated update
            simNftBalance = _applyDeltaSimulated(simNftBalance, update.nftDelta);
            simDepositAmount = _applyDeltaSimulated(simDepositAmount, update.depositDelta);
            simLastProcessedBlock = update.blockNumber;
        }

        // Calculate final rewards (from last update/initial state up to current block)
        uint256 currentBlock = block.number;
        uint256 finalGlobalIndex = _calculateGlobalIndexAt(currentBlock);

        if (currentBlock > simLastProcessedBlock && finalGlobalIndex > simLastRewardIndex) {
            uint256 finalIndexDelta = finalGlobalIndex - simLastRewardIndex;
            uint256 finalReward =
                _calculateRewardsWithDelta(nftCollection, finalIndexDelta, simNftBalance, simDepositAmount);
            simTotalReward += finalReward;
        }

        return simTotalReward;
    }

    function _applyDeltaSimulated(uint256 value, int256 delta) internal pure returns (uint256) {
        if (delta >= 0) {
            return value + uint256(delta);
        } else {
            uint256 absDelta = uint256(-delta);
            if (absDelta > value) {
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

    // --- Public View Functions --- //

    function calculateBoost(uint256 nftBalance, uint256 beta) public pure returns (uint256 boostFactor) {
        if (nftBalance == 0) return 0; // No boost if no NFTs

        // Assuming beta is scaled by PRECISION_FACTOR (e.g., 0.1e18 means 10% bonus per NFT).
        // boostFactor represents the total *bonus* multiplier to be applied to the base reward.
        boostFactor = nftBalance * beta;

        // Cap the boost factor (e.g., max 900% bonus = 9 * 1e18)
        uint256 maxBoostFactor = PRECISION_FACTOR * 9; // Cap bonus at 900%
        if (boostFactor > maxBoostFactor) {
            boostFactor = maxBoostFactor;
        }
        return boostFactor;
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
            UserRewardState storage internalInfo = userRewardState[user][collection];
            trackingInfo[i] = UserCollectionTracking({
                lastUpdateBlock: internalInfo.lastUpdateBlock,
                lastNFTBalance: internalInfo.lastNFTBalance,
                lastDepositBalance: internalInfo.lastDepositAmount,
                lastUserRewardIndex: internalInfo.lastRewardIndex
            });
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
            return 0; // Return 0 if no collections specified
        }

        uint256 totalPendingReward = 0;
        for (uint256 i = 0; i < nftCollections.length; i++) {
            address collection = nftCollections[i];
            if (!isCollectionWhitelisted(collection)) {
                continue; // Skip non-whitelisted collections
            }
            // Internal function will filter simulated updates by collection
            totalPendingReward += _getPendingRewardsSingleCollection(user, collection, simulatedUpdates);
        }

        return totalPendingReward;
    }

    // Helper to check whitelist status (used in previewRewards)
    function isCollectionWhitelisted(address collection) public view returns (bool) {
        return _whitelistedCollections.contains(collection);
    }

    function getWhitelistedCollections() external view override returns (address[] memory) {
        return _whitelistedCollections.values();
    }

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
     * @notice Exposes the internal user reward state for testing.
     * @dev Not part of the standard interface.
     */
    function userNFTData(address user, address collection)
        external
        view
        returns (
            uint256 lastRewardIndex,
            uint256 accruedReward,
            uint256 accruedBonusRewardState, // Not tracked separately, returns 0
            uint256 lastNFTBalance,
            uint256 lastDepositAmount,
            uint256 lastUpdateBlock
        )
    {
        UserRewardState storage info = userRewardState[user][collection];
        return (
            info.lastRewardIndex,
            info.accruedReward,
            0,
            info.lastNFTBalance,
            info.lastDepositAmount,
            info.lastUpdateBlock
        );
    }
}
