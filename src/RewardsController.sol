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
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";

/**
 * @title RewardsController (Upgradeable)
 * @notice Manages reward calculation and distribution, incorporating NFT-based bonus multipliers.
 * @dev Implements IRewardsController. Tracks user NFT balances, calculates yield (base + bonus),
 *      and distributes rewards by pulling base yield from the LendingManager. Uses EIP-712 for signed balance updates.
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
     */
    struct UserRewardState {
        uint256 lastRewardIndex; // Global index at the last update for this user/collection
        uint256 accruedReward; // Total rewards accumulated since last claim
        uint256 lastNFTBalance; // NFT balance at the last update
        uint256 lastBalance; // Relevant balance (deposit or borrow) at the last update
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
    uint256 private constant MAX_REWARD_SHARE_PERCENTAGE = 10000; // 100.00%

    // State variables
    ILendingManager public lendingManager;
    IERC4626 public vault;
    IERC20 public rewardToken; // The token distributed as rewards (must be same as LM asset)
    CTokenInterface internal cToken;
    address public authorizedUpdater;

    // NFT Collection Management
    EnumerableSet.AddressSet private _whitelistedCollections;
    mapping(address => uint256) public collectionBetas; // collection => beta (reward coefficient)
    mapping(address => IRewardsController.RewardBasis) public collectionRewardBasis;
    mapping(address => uint256) public collectionRewardSharePercentages; // collection => rewardSharePercentage (e.g., 6000 for 60.00%)

    // User Reward Tracking
    mapping(address => mapping(address => UserRewardState)) internal userRewardState;
    mapping(address => EnumerableSet.AddressSet) private _userActiveCollections;
    mapping(address => uint256) public authorizedUpdaterNonce; // Nonce per authorized updater for replay protection

    // Global Reward State
    uint256 public globalRewardIndex;

    // --- Epoch & Scaling State ---
    uint256 public epochDuration; // Duration of each reward epoch in seconds

    // --- Events ---
    // Note: Events are inherited from IRewardsController.
    event NFTBalanceUpdateProcessed(
        address indexed user, address indexed collection, uint256 blockNumber, int256 nftDelta, uint256 finalNFTBalance
    );
    event BalanceUpdateProcessed(
        address indexed user, address indexed collection, uint256 blockNumber, int256 balanceDelta, uint256 finalBalance
    );
    event YieldTransferCapped(address indexed user, uint256 calculatedReward, uint256 transferredAmount);
    event CollectionRewardShareUpdated(address indexed collection, uint256 oldSharePercentage, uint256 newSharePercentage);

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
    error InvalidEpochDuration();
    error InvalidRewardSharePercentage();

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
        address _authorizedUpdater,
        uint256 _initialEpochDuration
    ) public initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("RewardsController", "1");

        if (_lendingManagerAddress == address(0)) revert AddressZero();
        if (_vaultAddress == address(0)) revert AddressZero();
        if (_authorizedUpdater == address(0)) revert AddressZero();
        if (_initialEpochDuration == 0) revert InvalidEpochDuration();

        lendingManager = ILendingManager(_lendingManagerAddress);
        vault = IERC4626(_vaultAddress);

        if (address(lendingManager) == address(0)) revert AddressZero();
        if (address(vault) == address(0)) revert AddressZero();

        IERC20 _rewardToken = lendingManager.asset();
        if (address(_rewardToken) == address(0)) revert AddressZero();

        address _vaultAsset = vault.asset();
        if (_vaultAsset == address(0)) revert AddressZero();
        if (_vaultAsset != address(_rewardToken)) revert VaultMismatch();

        rewardToken = _rewardToken;
        authorizedUpdater = _authorizedUpdater;

        address _cTokenAddress = address(lendingManager.cToken());
        if (_cTokenAddress == address(0)) revert AddressZero();
        cToken = CTokenInterface(_cTokenAddress);
        if (address(cToken) == address(0)) revert AddressZero();

        uint256 initialExchangeRate = cToken.exchangeRateStored();
        // The cToken exchange rate serves as the base global index.
        globalRewardIndex = initialExchangeRate;

        epochDuration = _initialEpochDuration;
    }

    function setAuthorizedUpdater(address _newUpdater) external onlyOwner {
        if (_newUpdater == address(0)) revert AddressZero();
        address oldUpdater = authorizedUpdater;
        authorizedUpdater = _newUpdater;
        emit AuthorizedUpdaterChanged(oldUpdater, _newUpdater);
    }

    function addNFTCollection(address collection, uint256 beta, IRewardsController.RewardBasis rewardBasis, uint256 rewardSharePercentage)
        external
        override
        onlyOwner
    {
        if (collection == address(0)) revert AddressZero();
        if (_whitelistedCollections.contains(collection)) revert CollectionAlreadyExists(collection);
        if (rewardSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) revert InvalidRewardSharePercentage();

        _whitelistedCollections.add(collection);
        collectionBetas[collection] = beta;
        collectionRewardBasis[collection] = rewardBasis;
        collectionRewardSharePercentages[collection] = rewardSharePercentage;

        emit NFTCollectionAdded(collection, beta, rewardBasis, rewardSharePercentage);
    }

    function removeNFTCollection(address collection) external override onlyOwner {
        require(_whitelistedCollections.contains(collection), "RC: Collection not whitelisted");

        _whitelistedCollections.remove(collection);
        delete collectionBetas[collection];
        delete collectionRewardBasis[collection];
        delete collectionRewardSharePercentages[collection];

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

    // --- Epoch & Scaling Admin Functions ---

    /**
     * @notice Set the duration for reward epochs.
     * @inheritdoc IRewardsController
     */
    function setEpochDuration(uint256 newDuration) external onlyOwner {
        if (newDuration == 0) revert InvalidEpochDuration();
        uint256 oldDuration = epochDuration;
        epochDuration = newDuration;
        // Consider adding an event if needed for off-chain tracking
    }

    /**
     * @notice Set the percentage of lending yield allocated to rewards for a specific collection.
     * @inheritdoc IRewardsController
     */
    function setCollectionRewardSharePercentage(address collection, uint256 newSharePercentage) external override onlyOwner onlyWhitelistedCollection(collection) {
        if (newSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) revert InvalidRewardSharePercentage();
        uint256 oldSharePercentage = collectionRewardSharePercentages[collection];
        collectionRewardSharePercentages[collection] = newSharePercentage;
        emit CollectionRewardShareUpdated(collection, oldSharePercentage, newSharePercentage);
    }

    // --- Balance Update Processing --- //

    /**
     * @notice Processes a batch of signed balance updates (NFT and/or deposit) for multiple users/collections.
     * @dev Uses authorized updater's nonce. Emits BalanceUpdatesProcessed.
     */
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
        int256 depositDelta,
        bytes calldata signature
    ) external nonReentrant {
        address signer = authorizedUpdater;

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

        emit BalanceUpdateProcessed(
            user,
            collection,
            blockNumber,
            depositDelta,
            userRewardState[user][collection].lastBalance
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
                    updates[i].balanceDelta
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
                    updates[i].balanceDelta
                )
            );
        }
        return keccak256(abi.encodePacked(encodedUpdates));
    }

    // --- Core Update Logic --- //

    /**
     * @dev Processes a single balance update, updating user state but not calculating rewards.
     *      Handles out-of-order updates and updates active collection list.
     */
    function _processSingleUpdate(
        address user,
        address collection,
        uint256 updateBlock,
        int256 nftDelta,
        int256 balanceDelta
    ) internal {
        UserRewardState storage info = userRewardState[user][collection];

        // Handle updates arriving out of order or for blocks already processed
        if (updateBlock < info.lastUpdateBlock) {
            // Allow updates for the *current* block even if lastUpdateBlock is the same
            if (updateBlock != block.number) {
                revert UpdateOutOfOrder(user, collection, updateBlock, info.lastUpdateBlock);
            }
        }

        // If this is the first update or the update is for a future block relative to the last state update
        if (info.lastUpdateBlock == 0 || updateBlock > info.lastUpdateBlock) {
            // Rewards are calculated lazily in _getPendingRewards... functions.
            // Set the user's index and block to the current global state
            info.lastRewardIndex = globalRewardIndex; // Record the index corresponding to this update block
            info.lastUpdateBlock = updateBlock; // Record the block number of this update
        }

        // Apply deltas to the stored state
        info.lastNFTBalance = _applyDelta(info.lastNFTBalance, nftDelta);
        info.lastBalance = _applyDelta(info.lastBalance, balanceDelta);

        // Emit events
        if (nftDelta != 0) {
            emit NFTBalanceUpdateProcessed(user, collection, updateBlock, nftDelta, info.lastNFTBalance);
        }
        if (balanceDelta != 0) {
            emit BalanceUpdateProcessed(user, collection, updateBlock, balanceDelta, info.lastBalance);
        }

        // Update active collections list based on final state
        if (info.lastNFTBalance > 0 || info.lastBalance > 0) {
            _userActiveCollections[user].add(collection);
        } else {
            _userActiveCollections[user].remove(collection);
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

    /**
     * @notice Calculates the raw, unscaled reward for a specific period based on index change and balances.
     * @dev Applies the collection's reward share percentage.
     * @param nftCollection The collection address.
     * @param indexDelta The change in the global index during the period.
     * @param lastRewardIndex The global index at the *start* of the period.
     * @param nftBalanceDuringPeriod The user's NFT balance held constant during the period.
     * @param balanceDuringPeriod The user's deposit/borrow balance held constant during the period.
     * @param rewardSharePercentage The reward share percentage for this specific collection.
     * @return rawReward The raw reward for the period, incorporating the share percentage.
     */
    function _calculateRewardsWithDelta(
        address nftCollection,
        uint256 indexDelta,
        uint256 lastRewardIndex,
        uint256 nftBalanceDuringPeriod,
        uint256 balanceDuringPeriod,
        uint256 rewardSharePercentage
    ) internal view returns (uint256 rawReward) {
        if (nftBalanceDuringPeriod == 0 || indexDelta == 0 || balanceDuringPeriod == 0 || lastRewardIndex == 0) {
            return 0;
        }

        // Calculate base reward from yield (change in exchange rate)
        uint256 yieldReward = (balanceDuringPeriod * indexDelta) / lastRewardIndex;

        // Apply the collection's reward share percentage to the yield reward
        uint256 allocatedYieldReward = (yieldReward * rewardSharePercentage) / MAX_REWARD_SHARE_PERCENTAGE;

        uint256 beta = collectionBetas[nftCollection];
        uint256 boostFactor = calculateBoost(nftBalanceDuringPeriod, beta);

        // Bonus reward is calculated as a percentage of the *allocated* base reward
        uint256 bonusReward = (allocatedYieldReward * boostFactor) / PRECISION_FACTOR;
        rawReward = allocatedYieldReward + bonusReward;

        return rawReward;
    }

    /**
     * @notice Calculates the current global index based on the cToken exchange rate.
     * @dev Calls `accrueInterest` on the cToken to update the rate before reading it.
     *      The exchange rate itself represents the index.
     * @return currentIndex The current exchange rate stored in the cToken contract after interest accrual.
     */
    function _calculateGlobalIndexAt() internal returns (uint256 currentIndex) {
        uint256 accrualResult = cToken.accrueInterest();
        accrualResult; // Silence compiler warning

        currentIndex = cToken.exchangeRateStored();
        return currentIndex;
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
                lastBalance: internalInfo.lastBalance,
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
     * @dev Calculates raw rewards using per-collection share percentages.
     */
    function previewRewards(
        address user,
        address[] calldata nftCollections,
        BalanceUpdateData[] calldata simulatedUpdates
    ) external override returns (uint256 pendingReward) {
        // Note: This function modifies state by calling _calculateGlobalIndexAt -> accrueInterest
        if (nftCollections.length == 0) {
            return 0;
        }

        uint256 totalRawPendingReward = 0;
        for (uint256 i = 0; i < nftCollections.length; i++) {
            address collection = nftCollections[i];
            if (!isCollectionWhitelisted(collection)) {
                revert CollectionNotWhitelisted(collection);
            }
            totalRawPendingReward += _getRawPendingRewardsSingleCollection(user, collection, simulatedUpdates);
        }

        pendingReward = totalRawPendingReward;

        return pendingReward;
    }

    function isCollectionWhitelisted(address collection) public view returns (bool) {
        return _whitelistedCollections.contains(collection);
    }

    function getWhitelistedCollections() external view override returns (address[] memory) {
        return _whitelistedCollections.values();
    }

    // --- Claiming Functions ---

    function claimRewardsForCollection(
        address nftCollection,
        BalanceUpdateData[] calldata simulatedUpdates
    ) external override nonReentrant onlyWhitelistedCollection(nftCollection) {
        address user = msg.sender;

        // 1. Calculate raw pending rewards (includes share percentage)
        uint256 rawReward = _getRawPendingRewardsSingleCollection(user, nftCollection, simulatedUpdates);

        // 2. Update global index state *before* transfers and user state update
        uint256 indexAtClaim = _calculateGlobalIndexAt();
        globalRewardIndex = indexAtClaim;

        // 3. Request yield transfer from LendingManager
        uint256 amountActuallyTransferred = 0;
        if (rawReward > 0) {
            amountActuallyTransferred = lendingManager.transferYield(rawReward, address(this));
        }

        // 4. Check if LM transferred less than requested
        if (amountActuallyTransferred < rawReward) {
            emit YieldTransferCapped(user, rawReward, amountActuallyTransferred);
        }

        // 5. Update user state
        UserRewardState storage info = userRewardState[user][nftCollection];
        info.accruedReward = 0; // Reset accrued reward
        info.lastRewardIndex = indexAtClaim;
        info.lastUpdateBlock = block.number;

        // 6. Transfer the amount actually received from LM to the user
        emit RewardsClaimedForCollection(user, nftCollection, amountActuallyTransferred);

        if (amountActuallyTransferred > 0) {
            rewardToken.safeTransfer(user, amountActuallyTransferred);
        }
    }

    function claimRewardsForAll(BalanceUpdateData[] calldata simulatedUpdates) external override nonReentrant {
        address user = msg.sender;
        address[] memory collectionsToClaim = _userActiveCollections[user].values();
        if (collectionsToClaim.length == 0) revert NoRewardsToClaim();

        // 1. Calculate total raw pending rewards across all collections
        uint256 totalRawRewards = 0;
        for (uint256 i = 0; i < collectionsToClaim.length; i++) {
            address collection = collectionsToClaim[i];
            totalRawRewards += _getRawPendingRewardsSingleCollection(user, collection, simulatedUpdates);
        }

        // 2. Update global index state
        uint256 indexAtClaim = _calculateGlobalIndexAt();
        globalRewardIndex = indexAtClaim;

        // 3. Request yield transfer from LendingManager, capped by available yield
        uint256 lmTotalAssets = lendingManager.totalAssets();
        uint256 lmPrincipal = lendingManager.totalPrincipalDeposited();
        uint256 maxAvailableYield = (lmTotalAssets > lmPrincipal) ? lmTotalAssets - lmPrincipal : 0;
        uint256 amountToRequest = Math.min(totalRawRewards, maxAvailableYield);

        uint256 amountActuallyTransferred = 0;
        if (amountToRequest > 0) {
            amountActuallyTransferred = lendingManager.transferYield(amountToRequest, address(this));
        }

        // 4. Check if LM transferred less than requested
        if (amountActuallyTransferred < amountToRequest) {
            emit YieldTransferCapped(user, amountToRequest, amountActuallyTransferred);
        }

        // 5. Update user state for ALL claimed collections
        for (uint256 i = 0; i < collectionsToClaim.length; i++) {
            address collection = collectionsToClaim[i];
            UserRewardState storage info = userRewardState[user][collection];
            info.accruedReward = 0;
            info.lastRewardIndex = indexAtClaim;
            info.lastUpdateBlock = block.number;
        }

        // 6. Transfer the total amount actually received from LM to the user
        emit RewardsClaimedForAll(user, amountActuallyTransferred);

        if (amountActuallyTransferred > 0) {
            rewardToken.safeTransfer(user, amountActuallyTransferred);
        }
    }

    // --- Reward Calculation --- //

    /**
     * @notice Calculates the total raw, unscaled pending rewards for a single user/collection.
     * @dev Iterates through stored state and simulated updates to calculate rewards period by period.
     *      Calls _calculateGlobalIndexAt to get index values for specific blocks.
     *      Uses the collection's specific rewardSharePercentage.
     * @param user The user address.
     * @param nftCollection The NFT collection address.
     * @param simulatedUpdates Array of future updates to simulate (must be sorted by blockNumber).
     * @return totalRawReward The total raw reward accrued up to the current block, including simulations and share percentage.
     */
    function _getRawPendingRewardsSingleCollection(
        address user, address nftCollection, BalanceUpdateData[] memory simulatedUpdates
    ) internal returns (uint256 totalRawReward) {
        UserRewardState memory currentState = userRewardState[user][nftCollection];
        uint256 currentNFTBalance = currentState.lastNFTBalance;
        uint256 currentBalance = currentState.lastBalance;
        uint256 lastProcessedBlock = currentState.lastUpdateBlock;
        uint256 lastProcessedIndex = currentState.lastRewardIndex;
        totalRawReward = currentState.accruedReward; // Should be 0
        uint256 collectionSharePercentage = collectionRewardSharePercentages[nftCollection];

        // --- Process Simulated Updates ---
        uint256 simIndex = 0;
        while (simIndex < simulatedUpdates.length) {
            BalanceUpdateData memory update = simulatedUpdates[simIndex];

            if (update.collection != nftCollection) {
                simIndex++;
                continue;
            }
            if (update.blockNumber < lastProcessedBlock) {
                revert SimulationUpdateOutOfOrder(update.blockNumber, lastProcessedBlock);
            }
            if (update.blockNumber == lastProcessedBlock && update.blockNumber != 0) {
                 currentNFTBalance = _applyDeltaSimulated(currentNFTBalance, update.nftDelta);
                 currentBalance = _applyDeltaSimulated(currentBalance, update.balanceDelta);
                 simIndex++;
                 continue;
            }

            // Calculate rewards for the period ending *before* this simulated update
            if (update.blockNumber > lastProcessedBlock) {
                uint256 indexAtPeriodEnd = _calculateGlobalIndexAt();
                uint256 indexDelta = 0;
                if (indexAtPeriodEnd > lastProcessedIndex) {
                    indexDelta = indexAtPeriodEnd - lastProcessedIndex;
                }

                uint256 rewardForPeriod = _calculateRewardsWithDelta(
                    nftCollection,
                    indexDelta,
                    lastProcessedIndex,
                    currentNFTBalance,
                    currentBalance,
                    collectionSharePercentage
                );
                totalRawReward += rewardForPeriod;
                lastProcessedIndex = indexAtPeriodEnd;
                lastProcessedBlock = update.blockNumber;
            }

            // Apply the simulated deltas
            currentNFTBalance = _applyDeltaSimulated(currentNFTBalance, update.nftDelta);
            currentBalance = _applyDeltaSimulated(currentBalance, update.balanceDelta);

            simIndex++;
        }

        // --- Calculate Final Period (from last update/sim block to current block) ---
        uint256 currentBlock = block.number;
        if (currentBlock > lastProcessedBlock) {
            uint256 indexAtPeriodEnd = _calculateGlobalIndexAt();
            uint256 indexDelta = 0;
            if (indexAtPeriodEnd > lastProcessedIndex) {
                indexDelta = indexAtPeriodEnd - lastProcessedIndex;
            }

            uint256 rewardForPeriod = _calculateRewardsWithDelta(
                nftCollection,
                indexDelta,
                lastProcessedIndex,
                currentNFTBalance,
                currentBalance,
                collectionSharePercentage
            );
            totalRawReward += rewardForPeriod;
        }

        // Return the total raw reward calculated across all periods
        return totalRawReward;
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
     * @dev Not part of the standard interface.
     */
    function userNFTData(address user, address collection)
        external
        view
        returns (
            uint256 lastRewardIndex,
            uint256 accruedReward,
            uint256 lastNFTBalance,
            uint256 lastBalance,
            uint256 lastUpdateBlock
        )
    {
        UserRewardState storage info = userRewardState[user][collection];
        lastRewardIndex = info.lastRewardIndex;
        accruedReward = info.accruedReward;
        lastNFTBalance = info.lastNFTBalance;
        lastBalance = info.lastBalance;
        lastUpdateBlock = info.lastUpdateBlock;
    }

    // --- Internal Helper Functions ---

    /**
     * @notice Calculates the epoch ID (start timestamp) for a given timestamp.
     */
    function _getEpochId(uint256 timestamp) internal view returns (uint256) {
        if (epochDuration == 0) return 0; // Avoid division by zero
        return timestamp - (timestamp % epochDuration);
    }

    // --- Storage Gap ---
    // Gap ensures storage layout remains compatible during upgrades.
    // Previous gap: 45. Removed 4 slots, Added 1 slot. Net change: -3. New gap: 45 + 3 = 48.
    uint256[48] private __gap;
}
