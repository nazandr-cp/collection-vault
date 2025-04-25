// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "forge-std/console.sol"; // Removed duplicate
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import "forge-std/console.sol";

/**
 * @title RewardsController (Upgradeable)
 * @notice Manages reward calculation and distribution, incorporating NFT-based bonus multipliers.
 * @dev Implements IRewardsController. Tracks user NFT balances, calculates yield (base + bonus),
 *      and distributes rewards by pulling base yield from the LendingManager. Uses EIP-712 for signed balance updates (single and batch).
 *      Upgradeable using the Transparent Proxy pattern.
 */
contract RewardsController is
    Initializable,
    IRewardsController,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
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
        uint256 lastBalance; // Relevant balance (deposit or borrow) at the last update - Renamed from lastDepositAmount
        uint256 lastUpdateBlock; // Block number of the last update
    }

    // Multi-User Batch Update
    bytes32 public constant USER_BALANCE_UPDATE_DATA_TYPEHASH = keccak256(
        "UserBalanceUpdateData(address user,address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)"
    );
    bytes32 public constant BALANCE_UPDATES_TYPEHASH =
        keccak256("BalanceUpdates(UserBalanceUpdateData[] updates,uint256 nonce)");

    // Single-User Batch Update
    bytes32 public constant BALANCE_UPDATE_DATA_TYPEHASH =
        keccak256("BalanceUpdateData(address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)");
    bytes32 public constant USER_BALANCE_UPDATES_TYPEHASH =
        keccak256("UserBalanceUpdates(address user,BalanceUpdateData[] updates,uint256 nonce)");

    uint256 private constant PRECISION_FACTOR = 1e18;

    // State variables
    ILendingManager public lendingManager;
    IERC4626 public vault;
    IERC20 public rewardToken; // The token distributed as rewards (must be same as LM asset)
    CTokenInterface internal cToken;
    address public authorizedUpdater;

    // NFT Collection Management
    EnumerableSet.AddressSet private _whitelistedCollections;
    mapping(address => uint256) public collectionBetas; // collection => beta (reward coefficient)
    mapping(address => IRewardsController.RewardBasis) public collectionRewardBasis; // Use fully qualified enum name

    // User Reward Tracking
    mapping(address => mapping(address => UserRewardState)) internal userRewardState;
    mapping(address => EnumerableSet.AddressSet) private _userActiveCollections;
    mapping(address => uint256) public authorizedUpdaterNonce; // Nonce per authorized updater for replay protection

    // Global Reward State
    uint256 public globalRewardIndex;
    uint256 public lastDistributionBlock;
    uint256 public baseRewardRate; // Additional base reward rate per deposit per index unit change (scaled by PRECISION_FACTOR)

    // --- Events ---
    // Note: Events are inherited from IRewardsController.
    event NFTBalanceUpdateProcessed(
        address indexed user, address indexed collection, uint256 blockNumber, int256 nftDelta, uint256 finalNFTBalance
    );
    event BalanceUpdateProcessed(
        address indexed user, address indexed collection, uint256 blockNumber, int256 balanceDelta, uint256 finalBalance
    ); // Renamed from DepositUpdateProcessed
    event BaseRewardRateUpdated(uint256 oldRate, uint256 newRate); // Added event
    event YieldTransferCapped(address indexed user, uint256 calculatedReward, uint256 transferredAmount); // Added event for transparency

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

    function initialize(
        address initialOwner,
        address _lendingManagerAddress,
        address _vaultAddress,
        address _authorizedUpdater
    ) public initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("RewardsController", "1");

        if (_lendingManagerAddress == address(0)) revert AddressZero();
        if (_vaultAddress == address(0)) revert AddressZero();
        if (_authorizedUpdater == address(0)) revert AddressZero();

        lendingManager = ILendingManager(_lendingManagerAddress);
        vault = IERC4626(_vaultAddress);

        // --- Assertions Start ---
        if (address(lendingManager) == address(0)) revert AddressZero(); // Check LM interface cast
        if (address(vault) == address(0)) revert AddressZero(); // Check Vault interface cast

        IERC20 _rewardToken = lendingManager.asset();
        if (address(_rewardToken) == address(0)) revert AddressZero(); // Check LM.asset()

        address _vaultAsset = vault.asset();
        if (_vaultAsset == address(0)) revert AddressZero(); // Check Vault.asset()
        if (_vaultAsset != address(_rewardToken)) revert VaultMismatch();
        // --- Assertions End ---

        rewardToken = _rewardToken;
        authorizedUpdater = _authorizedUpdater;

        lastDistributionBlock = block.number;
        address _cTokenAddress = address(lendingManager.cToken());
        if (_cTokenAddress == address(0)) revert AddressZero(); // Check LM.cToken()
        cToken = CTokenInterface(_cTokenAddress);
        if (address(cToken) == address(0)) revert AddressZero(); // Check cToken interface cast

        uint256 initialExchangeRate = cToken.exchangeRateStored();
        // TODO: Decide on scaling/normalization for the index if needed.
        globalRewardIndex = initialExchangeRate;
    }

    function setAuthorizedUpdater(address _newUpdater) external onlyOwner {
        // Removed override
        if (_newUpdater == address(0)) revert AddressZero();
        address oldUpdater = authorizedUpdater;
        authorizedUpdater = _newUpdater;
        emit AuthorizedUpdaterChanged(oldUpdater, _newUpdater);
    }

    // Use fully qualified enum name in parameter
    function addNFTCollection(address collection, uint256 beta, IRewardsController.RewardBasis rewardBasis)
        external
        onlyOwner
    {
        if (collection == address(0)) revert AddressZero();
        if (_whitelistedCollections.contains(collection)) revert CollectionAlreadyExists(collection);

        _whitelistedCollections.add(collection); // Use EnumerableSet add
        collectionBetas[collection] = beta;
        collectionRewardBasis[collection] = rewardBasis; // Store reward basis

        emit NFTCollectionAdded(collection, beta, rewardBasis); // Emit updated event
    }

    function removeNFTCollection(address collection) external onlyOwner {
        require(_whitelistedCollections.contains(collection), "RC: Collection not whitelisted"); // Use EnumerableSet contains

        _whitelistedCollections.remove(collection); // Use EnumerableSet remove
        delete collectionBetas[collection];
        delete collectionRewardBasis[collection]; // Clean up reward basis

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

    /**
     * @notice Sets the additional base reward rate.
     * @param _newRate The new base reward rate, scaled by PRECISION_FACTOR.
     */
    function setBaseRewardRate(uint256 _newRate) external onlyOwner {
        uint256 oldRate = baseRewardRate;
        baseRewardRate = _newRate;
        emit BaseRewardRateUpdated(oldRate, _newRate);
    }

    // --- Balance Update Processing --- //

    /**
     * @notice Processes a batch of signed balance updates (NFT and/or deposit) for multiple users/collections.
     * @dev Uses authorized updater's nonce. Emits BalanceUpdatesProcessed.
     */
    // Added 'address signer' parameter to match interface
    function processBalanceUpdates(address signer, UserBalanceUpdateData[] calldata updates, bytes calldata signature)
        external
        override
        nonReentrant
    {
        if (updates.length == 0) revert EmptyBatch();

        if (signer != authorizedUpdater) {
            revert InvalidSignature();
        }

        uint256 nonce = authorizedUpdaterNonce[signer];

        bytes32 updatesHash = _hashUserBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATES_TYPEHASH, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }

        authorizedUpdaterNonce[signer]++;

        for (uint256 i = 0; i < updates.length; i++) {
            UserBalanceUpdateData memory update = updates[i];
            if (!_whitelistedCollections.contains(update.collection)) {
                revert CollectionNotWhitelisted(update.collection);
            }
            _processSingleUpdate(
                update.user, update.collection, update.blockNumber, update.nftDelta, update.balanceDelta
            );
        }

        emit BalanceUpdatesProcessed(signer, nonce, updates.length);
    }

    /**
     * @notice Processes a batch of signed balance updates (NFT and/or deposit) for a single user across multiple collections.
     * @dev Uses authorized updater's nonce. Emits UserBalanceUpdatesProcessed.
     */
    // Added 'address signer' parameter to match interface
    function processUserBalanceUpdates(
        address signer,
        address user,
        BalanceUpdateData[] calldata updates,
        bytes calldata signature
    ) external override nonReentrant {
        if (updates.length == 0) revert EmptyBatch();

        if (signer != authorizedUpdater) {
            revert InvalidSignature();
        }

        uint256 nonce = authorizedUpdaterNonce[signer];

        bytes32 updatesHash = _hashBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }

        authorizedUpdaterNonce[signer]++;

        for (uint256 i = 0; i < updates.length; i++) {
            if (!_whitelistedCollections.contains(updates[i].collection)) {
                revert CollectionNotWhitelisted(updates[i].collection);
            }
            // Use balanceDelta instead of depositDelta
            _processSingleUpdate(
                user, updates[i].collection, updates[i].blockNumber, updates[i].nftDelta, updates[i].balanceDelta
            );
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
        int256 depositDelta, // Keep param name for test function signature consistency
        bytes calldata signature
    ) external nonReentrant {
        address signer = authorizedUpdater;

        // Hash using BALANCE_UPDATE_DATA_TYPEHASH with 0 for nftDelta and depositDelta for balanceDelta
        bytes32 structHash =
            keccak256(abi.encode(BALANCE_UPDATE_DATA_TYPEHASH, collection, blockNumber, 0, depositDelta));

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert InvalidSignature();
        }

        // Nonce increment was missing here, adding it back
        // uint256 nonce = authorizedUpdaterNonce[signer]; // <-- Remove unused variable
        authorizedUpdaterNonce[signer]++;

        if (!_whitelistedCollections.contains(collection)) {
            revert CollectionNotWhitelisted(collection);
        }

        // Call _processSingleUpdate with 0 for nftDelta and depositDelta for balanceDelta
        _processSingleUpdate(user, collection, blockNumber, 0, depositDelta);

        // Emit the renamed event with correct parameters
        emit BalanceUpdateProcessed(
            user,
            collection,
            blockNumber,
            depositDelta,
            userRewardState[user][collection].lastBalance // Use lastBalance
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
                    updates[i].balanceDelta // Use balanceDelta
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
                    updates[i].balanceDelta // Use balanceDelta
                )
            );
        }
        return keccak256(abi.encodePacked(encodedUpdates));
    }

    // --- Core Update Logic --- //

    // Updated parameter name: balanceDelta
    function _processSingleUpdate(
        address user,
        address collection,
        uint256 updateBlock,
        int256 nftDelta,
        int256 balanceDelta // Renamed from depositDelta
    ) internal {
        UserRewardState storage info = userRewardState[user][collection];

        // Handle updates arriving out of order or for blocks already processed
        if (updateBlock < info.lastUpdateBlock) {
            // Allow updates for the *current* block even if lastUpdateBlock is the same
            // This handles multiple updates within the same block (e.g., deposit + NFT transfer)
            if (updateBlock != block.number) {
                revert UpdateOutOfOrder(user, collection, updateBlock, info.lastUpdateBlock);
            }
            // If updateBlock == block.number == info.lastUpdateBlock, proceed to apply deltas below
        }

        // If this is the first update or the update is for a future block
        if (info.lastUpdateBlock == 0 || updateBlock > info.lastUpdateBlock) {
            // Update global index up to the block *before* the update if necessary
            // If the update is for a block later than the last distribution, update the global index.
            if (updateBlock > lastDistributionBlock) {
                _updateGlobalRewardIndexTo(updateBlock);
            }

            // If it's not the very first update, calculate rewards for the period ended
            if (info.lastUpdateBlock != 0) {
                uint256 indexDeltaForPeriod = globalRewardIndex - info.lastRewardIndex;
                // Pass lastBalance instead of lastDepositAmount
                uint256 rewardForPeriod = _calculateRewardsWithDelta(
                    collection, indexDeltaForPeriod, info.lastRewardIndex, info.lastNFTBalance, info.lastBalance
                );
                info.accruedReward += rewardForPeriod;
            }

            // Set the user's index and block to the current global state *after* potential update
            info.lastRewardIndex = globalRewardIndex;
            info.lastUpdateBlock = updateBlock;
        }
        // If updateBlock == info.lastUpdateBlock (and potentially == block.number),
        // we don't recalculate rewards or update index/block, just apply deltas.

        // Apply deltas to the stored state
        info.lastNFTBalance = _applyDelta(info.lastNFTBalance, nftDelta);
        info.lastBalance = _applyDelta(info.lastBalance, balanceDelta); // Update lastBalance

        // Emit events (Consider combining into one event?)
        if (nftDelta != 0) {
            emit NFTBalanceUpdateProcessed(user, collection, updateBlock, nftDelta, info.lastNFTBalance);
        }
        if (balanceDelta != 0) {
            // Use the renamed event
            emit BalanceUpdateProcessed(user, collection, updateBlock, balanceDelta, info.lastBalance);
        }

        // Update active collections list based on final state
        if (info.lastNFTBalance > 0 || info.lastBalance > 0) {
            _userActiveCollections[user].add(collection); // Idempotent add
        } else {
            _userActiveCollections[user].remove(collection); // Idempotent remove
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
        uint256 lastRewardIndex, // <-- Add lastRewardIndex (previous exchange rate)
        uint256 nftBalanceDuringPeriod,
        uint256 balanceDuringPeriod // Renamed from depositAmountDuringPeriod
    ) internal view returns (uint256 reward) {
        // If user has no NFTs from this collection during the period, they get no reward for it.
        if (nftBalanceDuringPeriod == 0) {
            return 0;
        }

        if (indexDelta == 0 || balanceDuringPeriod == 0 || lastRewardIndex == 0) {
            return 0;
        }

        // Calculate base reward from yield (change in exchange rate)
        uint256 yieldReward = (balanceDuringPeriod * indexDelta) / lastRewardIndex;

        // Calculate additional base reward based on the configurable rate
        uint256 additionalBaseReward = 0;
        if (baseRewardRate > 0) {
            // Scale similarly to yield reward: deposit * indexDelta * rate / (lastIndex * precision)
            additionalBaseReward =
                (balanceDuringPeriod * indexDelta * baseRewardRate) / (lastRewardIndex * PRECISION_FACTOR);
        }

        uint256 totalBaseReward = yieldReward + additionalBaseReward;

        // NFT balance check is now at the top, so we know nftBalanceDuringPeriod > 0 here.
        uint256 beta = collectionBetas[nftCollection];
        uint256 boostFactor = calculateBoost(nftBalanceDuringPeriod, beta);

        // Bonus reward is calculated as a percentage of the *total* base reward
        uint256 bonusReward = (totalBaseReward * boostFactor) / PRECISION_FACTOR;
        reward = totalBaseReward + bonusReward;

        return reward;
    }

    /**
     * @notice Calculates the current global index based on the cToken exchange rate.
     * @dev Calls `accrueInterest` on the cToken to update the rate before reading it.
     *      The exchange rate itself represents the index.
     * @param targetBlock The block number to calculate the index for (unused in this implementation,
     *                    as exchange rate reflects current state after accrual).
     * @return currentIndex The current exchange rate stored in the cToken contract.
     */
    function _calculateGlobalIndexAt(uint256 targetBlock) internal returns (uint256 currentIndex) {
        targetBlock; // Silence unused parameter warning

        uint256 accrualResult = cToken.accrueInterest();
        accrualResult; // Silence compiler warning

        currentIndex = cToken.exchangeRateStored();
        return currentIndex;
    }

    /**
     * @notice Updates the global reward index and last distribution block up to the specified target block.
     * @dev Reads the current reward rate from the LendingManager to calculate the index increase.
     */
    function _updateGlobalRewardIndexTo(uint256 targetBlock) internal {
        if (targetBlock <= lastDistributionBlock) {
            return;
        }

        uint256 newGlobalIndex = _calculateGlobalIndexAt(targetBlock);

        if (newGlobalIndex != globalRewardIndex) {
            globalRewardIndex = newGlobalIndex;
        }

        lastDistributionBlock = targetBlock;
    }

    /**
     * @notice Updates the global reward index up to the current block number.
     * @dev Convenience wrapper around _updateGlobalRewardIndexTo.
     */
    function updateGlobalRewardIndex() public {
        _updateGlobalRewardIndexTo(block.number);
    }

    // --- Public View Functions --- //

    function calculateBoost(uint256 nftBalance, uint256 beta) public pure returns (uint256 boostFactor) {
        if (nftBalance == 0) return 0;

        boostFactor = nftBalance * beta;

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
                lastBalance: internalInfo.lastBalance, // Use renamed field
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

    // Use fully qualified enum name in return type
    function getCollectionRewardBasis(address nftCollection)
        external
        view
        override
        onlyWhitelistedCollection(nftCollection)
        returns (IRewardsController.RewardBasis)
    {
        return collectionRewardBasis[nftCollection];
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
    ) external override returns (uint256 pendingReward) {
        // Added 'override' back
        if (nftCollections.length == 0) {
            return 0;
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
        return _whitelistedCollections.contains(collection); // Use EnumerableSet contains
    }

    function getWhitelistedCollections() external view override returns (address[] memory) {
        return _whitelistedCollections.values(); // Return values from the EnumerableSet
    }

    function claimRewardsForCollection(
        address nftCollection,
        BalanceUpdateData[] calldata simulatedUpdates // Added simulatedUpdates parameter
    ) external override nonReentrant onlyWhitelistedCollection(nftCollection) {
        address user = msg.sender;

        // Calculate pending rewards based on index up to current block *before* updating global state
        // Pass simulatedUpdates to the calculation
        uint256 totalReward = _getPendingRewardsSingleCollection(user, nftCollection, simulatedUpdates);

        // Allow claiming 0 rewards to update internal state, but skip transfers if reward is 0.
        // if (totalReward == 0) {
        //     revert NoRewardsToClaim();
        // }

        // Now update the global index state *before* transfers and user state update
        updateGlobalRewardIndex(); // Updated internal call
        uint256 indexAtClaim = globalRewardIndex; // Capture index *after* global update

        // 4. Request yield transfer from LendingManager (only if there's something to claim)
        uint256 amountActuallyTransferred = 0;
        if (totalReward > 0) {
            amountActuallyTransferred = lendingManager.transferYield(totalReward, address(this));
        }

        // Check if LM transferred less than expected (due to capping)
        uint256 rewardDeficit = 0;

        if (amountActuallyTransferred < totalReward) {
            emit YieldTransferCapped(user, totalReward, amountActuallyTransferred); // Emit event if capped
            rewardDeficit = totalReward - amountActuallyTransferred;
            console.log("RC.claim: Yield capped. Deficit=%s", rewardDeficit); // <-- Change back to console.log
                // Use the actual amount transferred for the user transfer
                // totalReward = amountActuallyTransferred; // No longer needed, use amountActuallyTransferred directly
        }

        // 5. Update user state
        console.log( // <-- Change back to console.log
            "RC.claim: Updating state. accruedReward=%s, lastIdx=%s, lastBlock=%s",
            rewardDeficit,
            indexAtClaim,
            block.number
        );
        UserRewardState storage info = userRewardState[user][nftCollection];
        // Store the unpaid amount (deficit). It will be added to future calculations.
        info.accruedReward = rewardDeficit;
        // Update the index to mark rewards accounted for up to this point
        info.lastRewardIndex = indexAtClaim;
        // Also update the last update block to the current claim block
        info.lastUpdateBlock = block.number;

        // 6. Transfer the (potentially capped) amount to the user
        // Emit the event regardless of the amount transferred
        emit RewardsClaimedForCollection(user, nftCollection, amountActuallyTransferred); // Corrected event name

        // Transfer only if there's an amount > 0
        if (amountActuallyTransferred > 0) {
            rewardToken.safeTransfer(user, amountActuallyTransferred);
        }
    }

    function claimRewardsForAll(BalanceUpdateData[] calldata simulatedUpdates) external override nonReentrant {
        // Keep override
        // Added simulatedUpdates parameter
        address user = msg.sender;
        address[] memory collectionsToClaim = _userActiveCollections[user].values();
        if (collectionsToClaim.length == 0) revert NoRewardsToClaim();

        // Use arrays to store pending rewards per collection temporarily
        uint256[] memory pendingRewardsPerCollection = new uint256[](collectionsToClaim.length);
        uint256 totalRewardsToSend = 0;

        // Calculate pending rewards for each collection *before* updating global state
        for (uint256 i = 0; i < collectionsToClaim.length; i++) {
            address collection = collectionsToClaim[i];
            // Pass simulatedUpdates to the calculation
            uint256 rewardForCollection = _getPendingRewardsSingleCollection(user, collection, simulatedUpdates);
            pendingRewardsPerCollection[i] = rewardForCollection; // Store reward by index
            totalRewardsToSend += rewardForCollection;
        }
        console.logString("RC.claimAll: User=");
        console.logAddress(msg.sender);
        console.logString(" Calculated totalRewardsToSend=");
        console.logUint(totalRewardsToSend); // Log total calculated

        if (totalRewardsToSend == 0) revert NoRewardsToClaim();

        // Now update the global index state *before* transfers and user state update
        updateGlobalRewardIndex(); // Updated internal call
        uint256 indexAtClaim = globalRewardIndex;
        console.logString("RC.claimAll: User=");
        console.logAddress(msg.sender);
        console.logString(" indexAtClaim=");
        console.logUint(indexAtClaim); // Log index

        // --- Start: Cap reward request based on LM available yield ---
        uint256 lmTotalAssets = lendingManager.totalAssets();
        uint256 lmPrincipal = lendingManager.totalPrincipalDeposited();
        uint256 maxAvailableYield = (lmTotalAssets > lmPrincipal) ? lmTotalAssets - lmPrincipal : 0;

        // Cap the total rewards requested from LM
        uint256 amountToRequest = Math.min(totalRewardsToSend, maxAvailableYield);
        uint256 knownDeficitBeforeTransfer = totalRewardsToSend - amountToRequest; // Deficit due to capping before LM call
        console.logString("RC.claimAll: User=");
        console.logAddress(msg.sender);
        console.logString(" maxAvailableYield=");
        console.logUint(maxAvailableYield);
        console.logString(" amountToRequest=");
        console.logUint(amountToRequest);
        console.logString(" knownDeficitBeforeTransfer=");
        console.logUint(knownDeficitBeforeTransfer); // Log capping details
        // --- End: Cap reward request ---

        uint256 amountActuallyTransferred = 0;
        if (amountToRequest > 0) {
            // Request the potentially capped amount from LM
            console.logString("RC.claimAll: User=");
            console.logAddress(msg.sender);
            console.logString(" Calling LM.transferYield with amount=");
            console.logUint(amountToRequest); // Log LM call amount
            amountActuallyTransferred = lendingManager.transferYield(amountToRequest, address(this));
            console.logString("RC.claimAll: User=");
            console.logAddress(msg.sender);
            console.logString(" LM.transferYield returned amount=");
            console.logUint(amountActuallyTransferred); // Log LM return amount
        }

        // Check for unexpected shortfall during LM transfer (amount received < amount requested)
        uint256 shortfallDuringTransfer = 0;
        if (amountActuallyTransferred < amountToRequest) {
            // This indicates an issue within LM.redeem or unexpected state change after our check
            shortfallDuringTransfer = amountToRequest - amountActuallyTransferred;
            // Use the YieldTransferCapped event to log this unexpected shortfall
            emit YieldTransferCapped(user, amountToRequest, amountActuallyTransferred);
        }

        uint256 totalAmountToPayUser = amountActuallyTransferred; // User receives what LM actually sent
        uint256 totalDeficit = knownDeficitBeforeTransfer + shortfallDuringTransfer; // Total unpaid reward
        console.logString("RC.claimAll: User=");
        console.logAddress(msg.sender);
        console.logString(" shortfallDuringTransfer=");
        console.logUint(shortfallDuringTransfer);
        console.logString(" totalDeficit=");
        console.logUint(totalDeficit);
        console.logString(" totalAmountToPayUser=");
        console.logUint(totalAmountToPayUser); // Log deficit details

        // Distribute the deficit proportionally back to the collections' accruedReward state
        if (totalDeficit > 0 && totalRewardsToSend > 0) {
            console.logString("RC.claimAll: User=");
            console.logAddress(msg.sender);
            console.logString(" Distributing deficit..."); // Log deficit path
            // Calculate the ratio of the total deficit to the original total calculated reward
            uint256 deficitRatio = (totalDeficit * PRECISION_FACTOR) / totalRewardsToSend;
            console.logString("RC.claimAll: User=");
            console.logAddress(msg.sender);
            console.logString(" deficitRatio (1e18)=");
            console.logUint(deficitRatio); // Log deficit ratio

            for (uint256 i = 0; i < collectionsToClaim.length; i++) {
                address collection = collectionsToClaim[i];
                uint256 rewardForThisCollection = pendingRewardsPerCollection[i];
                // Calculate the deficit portion for this collection
                uint256 deficitForThisCollection = (rewardForThisCollection * deficitRatio) / PRECISION_FACTOR;
                console.logString("RC.claimAll: User=");
                console.logAddress(msg.sender);
                console.logString(" Collection=");
                console.logAddress(collection);
                console.logString(" rewardForThisCollection=");
                console.logUint(rewardForThisCollection);
                console.logString(" deficitForThisCollection=");
                console.logUint(deficitForThisCollection); // Log per-collection deficit

                UserRewardState storage info = userRewardState[user][collection];
                // Store the unpaid portion as the new accrued reward
                info.accruedReward = deficitForThisCollection;
                // Update the index and block number, marking rewards processed up to this point
                info.lastRewardIndex = indexAtClaim;
                info.lastUpdateBlock = block.number; // Also update block number on claim
                console.logString("RC.claimAll: User=");
                console.logAddress(msg.sender);
                console.logString(" Collection=");
                console.logAddress(collection);
                console.logString(" FINAL info.accruedReward=");
                console.logUint(info.accruedReward); // Log final state in deficit path
            }
        } else {
            console.logString("RC.claimAll: User=");
            console.logAddress(msg.sender);
            console.logString(" No deficit or zero total rewards. Resetting accruedReward."); // Log no-deficit path
            // No deficit, reset accrued reward for all claimed collections
            for (uint256 i = 0; i < collectionsToClaim.length; i++) {
                address collection = collectionsToClaim[i];
                UserRewardState storage info = userRewardState[user][collection];
                info.accruedReward = 0; // Fully claimed
                info.lastRewardIndex = indexAtClaim;
                info.lastUpdateBlock = block.number; // Also update block number on claim
                console.logString("RC.claimAll: User=");
                console.logAddress(msg.sender);
                console.logString(" Collection=");
                console.logAddress(collection);
                console.logString(" FINAL info.accruedReward=");
                console.logUint(info.accruedReward); // Log final state in no-deficit path
            }
        }

        // Transfer the total amount actually received from LM to the user
        if (totalAmountToPayUser > 0) {
            rewardToken.safeTransfer(user, totalAmountToPayUser);
            // Emit one event for the aggregate claim
            emit RewardsClaimedForAll(user, totalAmountToPayUser);
        } else if (totalRewardsToSend > 0) {
            // If rewards were calculated but nothing was paid (due to capping or LM issue), still emit event with 0
            emit RewardsClaimedForAll(user, 0);
        }
        // If totalRewardsToSend was 0 initially, NoRewardsToClaim would have reverted earlier.
    }

    // --- Reward Calculation & Claiming --- //

    // Restored full function definition
    // Updated parameter name: simulatedUpdates
    // Updated internal variable names: simBalance
    function _getPendingRewardsSingleCollection(
        address user,
        address nftCollection,
        BalanceUpdateData[] memory simulatedUpdates
    ) internal returns (uint256 pendingReward) {
        // Removed 'view'
        console.logString("_getPendingRewardsSingleCollection START: User=");
        console.logAddress(user);
        console.logString(" Collection=");
        console.logAddress(nftCollection);

        UserRewardState memory currentState = userRewardState[user][nftCollection];
        uint256 currentNFTBalance = currentState.lastNFTBalance;
        uint256 currentBalance = currentState.lastBalance; // Use currentBalance
        uint256 lastProcessedBlock = currentState.lastUpdateBlock;
        uint256 lastProcessedIndex = currentState.lastRewardIndex;
        uint256 accruedRewardSoFar = currentState.accruedReward; // Start with previously accrued reward

        console.logString(" -> Initial State: lastIdx=");
        console.logUint(lastProcessedIndex);
        console.logString(" accruedReward=");
        console.logUint(accruedRewardSoFar);
        console.logString(" lastNFTBal=");
        console.logUint(currentNFTBalance);
        console.logString(" lastBal=");
        console.logUint(currentBalance);
        console.logString(" lastBlock=");
        console.logUint(lastProcessedBlock);

        // Apply simulated updates if any
        if (simulatedUpdates.length > 0) {
            console.logString(" -> Processing simulated updates...");
            for (uint256 i = 0; i < simulatedUpdates.length; i++) {
                BalanceUpdateData memory update = simulatedUpdates[i];

                // Ensure simulated updates are for the correct collection and are in order
                if (update.collection != nftCollection) continue; // Skip updates for other collections
                if (update.blockNumber < lastProcessedBlock) {
                    revert SimulationUpdateOutOfOrder(update.blockNumber, lastProcessedBlock);
                }

                console.logString(" --> Sim Update [");
                console.logUint(i);
                console.logString("]: block=");
                console.logUint(update.blockNumber);
                console.logString(" nftDelta=");
                console.logInt(update.nftDelta);
                console.logString(" balDelta=");
                console.logInt(update.balanceDelta);

                // Calculate rewards up to the block *before* this simulated update
                if (update.blockNumber > lastProcessedBlock) {
                    console.logString(" ---> Calculating rewards for period [");
                    console.logUint(lastProcessedBlock);
                    console.logString(" -> ");
                    console.logUint(update.blockNumber);
                    console.logString("]");
                    uint256 indexAtSimUpdateBlock = _calculateGlobalIndexAt(update.blockNumber); // Simulate index at that block
                    uint256 indexDelta = indexAtSimUpdateBlock - lastProcessedIndex;
                    console.logString(" ----> indexAtSimUpdateBlock=");
                    console.logUint(indexAtSimUpdateBlock);
                    console.logString(" lastProcessedIndex=");
                    console.logUint(lastProcessedIndex);
                    console.logString(" indexDelta=");
                    console.logUint(indexDelta);
                    uint256 rewardForPeriod = _calculateRewardsWithDelta(
                        nftCollection,
                        indexDelta,
                        lastProcessedIndex,
                        currentNFTBalance,
                        currentBalance // Use currentBalance
                    );
                    console.logString(" ----> rewardForPeriod=");
                    console.logUint(rewardForPeriod);
                    accruedRewardSoFar += rewardForPeriod;
                    console.logString(" ----> accruedRewardSoFar=");
                    console.logUint(accruedRewardSoFar);
                    lastProcessedIndex = indexAtSimUpdateBlock;
                    lastProcessedBlock = update.blockNumber;
                    console.logString(" ----> Updated lastProcessedIndex=");
                    console.logUint(lastProcessedIndex);
                    console.logString(" lastProcessedBlock=");
                    console.logUint(lastProcessedBlock);
                } else {
                    console.logString(" ---> Skipping reward calc (update.blockNumber <= lastProcessedBlock)");
                }

                // Apply the simulated deltas
                uint256 oldNFTBalance = currentNFTBalance;
                uint256 oldBalance = currentBalance;
                currentNFTBalance = _applyDeltaSimulated(currentNFTBalance, update.nftDelta);
                currentBalance = _applyDeltaSimulated(currentBalance, update.balanceDelta); // Apply to currentBalance
                console.logString(" ---> Applied Deltas: oldNFTBal=");
                console.logUint(oldNFTBalance);
                console.logString(" -> newNFTBal=");
                console.logUint(currentNFTBalance);
                console.logString(" | oldBal=");
                console.logUint(oldBalance);
                console.logString(" -> newBal=");
                console.logUint(currentBalance);
            }
        } else {
            console.logString(" -> No simulated updates to process.");
        }

        // Calculate rewards from the last processed block (real or simulated) up to the current block
        uint256 currentBlock = block.number;
        console.logString(" -> Calculating final period rewards: lastProcessedBlock=");
        console.logUint(lastProcessedBlock);
        console.logString(" currentBlock=");
        console.logUint(currentBlock);
        if (currentBlock > lastProcessedBlock) {
            uint256 currentIndex = _calculateGlobalIndexAt(currentBlock); // Get index at current block
            uint256 indexDelta = currentIndex - lastProcessedIndex;
            console.logString(" --> currentIndex=");
            console.logUint(currentIndex);
            console.logString(" lastProcessedIndex=");
            console.logUint(lastProcessedIndex);
            console.logString(" indexDelta=");
            console.logUint(indexDelta);
            uint256 rewardForFinalPeriod = _calculateRewardsWithDelta(
                nftCollection,
                indexDelta,
                lastProcessedIndex,
                currentNFTBalance,
                currentBalance // Use currentBalance
            );
            console.logString(" --> rewardForFinalPeriod=");
            console.logUint(rewardForFinalPeriod);
            accruedRewardSoFar += rewardForFinalPeriod;
        } else {
            console.logString(" -> Skipping final period reward calc (currentBlock <= lastProcessedBlock)");
        }

        console.logString("_getPendingRewardsSingleCollection END: User=");
        console.logAddress(user);
        console.logString(" Collection=");
        console.logAddress(nftCollection);
        console.logString(" FINAL pendingReward=");
        console.logUint(accruedRewardSoFar);
        return accruedRewardSoFar;
    }

    /**
     * @notice Helper function to apply a delta in simulations, reverting on underflow.
     */
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

    /**
     * @notice Exposes the internal user reward state for testing.
     * @dev Not part of the standard interface. Returns lastBalance instead of lastDepositAmount.
     */
    function userNFTData(address user, address collection)
        external
        view
        returns (
            uint256 lastRewardIndex,
            uint256 accruedReward,
            uint256 lastNFTBalance,
            uint256 lastBalance, // Renamed from lastDepositAmount
            uint256 lastUpdateBlock
        )
    {
        UserRewardState storage info = userRewardState[user][collection];
        lastRewardIndex = info.lastRewardIndex;
        accruedReward = info.accruedReward;
        lastNFTBalance = info.lastNFTBalance;
        lastBalance = info.lastBalance; // Return renamed field
        lastUpdateBlock = info.lastUpdateBlock;
        // Return values are implicitly handled by named returns
    }

    // --- Storage Gap --- //
    // Added storage gap for upgradeability
    uint256[49] private __gap;
}
