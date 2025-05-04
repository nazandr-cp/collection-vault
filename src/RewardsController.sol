// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {console} from "forge-std/console.sol";
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

    struct UserRewardState {
        uint256 lastRewardIndex;
        uint256 accruedReward;
        uint256 lastNFTBalance;
        uint256 lastBalance;
        uint256 lastUpdateBlock;
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
    uint256 public globalRewardIndex; // Represents the cToken exchange rate

    // --- Events ---
    event NFTBalanceUpdateProcessed(
        address indexed user, address indexed collection, uint256 blockNumber, int256 nftDelta, uint256 finalNFTBalance
    );
    event BalanceUpdateProcessed(
        address indexed user, address indexed collection, uint256 blockNumber, int256 balanceDelta, uint256 finalBalance
    );

    // --- Errors ---
    error BalanceUpdateUnderflow(uint256 currentValue, uint256 deltaMagnitude);
    error UpdateOutOfOrder(address user, address collection, uint256 updateBlock, uint256 lastProcessedBlock);
    error UserMismatch(address expectedUser, address actualUser);
    error VaultMismatch();
    error SimulationNFTUpdateUnderflow(uint256 currentValue, uint256 deltaMagnitude); // Added simulation error

    modifier onlyWhitelistedCollection(address collection) {
        if (!_whitelistedCollections.contains(collection)) {
            revert IRewardsController.CollectionNotWhitelisted(collection); // Use inherited error
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

        if (_lendingManagerAddress == address(0)) revert IRewardsController.AddressZero(); // Use inherited error
        if (_vaultAddress == address(0)) revert IRewardsController.AddressZero(); // Use inherited error
        if (_authorizedUpdater == address(0)) revert IRewardsController.AddressZero(); // Use inherited error

        lendingManager = ILendingManager(_lendingManagerAddress);
        vault = IERC4626(_vaultAddress);

        if (address(lendingManager) == address(0)) revert IRewardsController.AddressZero(); // Use inherited error
        if (address(vault) == address(0)) revert IRewardsController.AddressZero(); // Use inherited error

        IERC20 _rewardToken = lendingManager.asset();
        if (address(_rewardToken) == address(0)) revert IRewardsController.AddressZero(); // Use inherited error

        address _vaultAsset = vault.asset();
        if (_vaultAsset == address(0)) revert IRewardsController.AddressZero(); // Use inherited error
        if (_vaultAsset != address(_rewardToken)) revert VaultMismatch();

        rewardToken = _rewardToken;
        authorizedUpdater = _authorizedUpdater;

        address _cTokenAddress = address(lendingManager.cToken());
        if (_cTokenAddress == address(0)) revert IRewardsController.AddressZero(); // Use inherited error
        cToken = CTokenInterface(_cTokenAddress);
        if (address(cToken) == address(0)) revert IRewardsController.AddressZero(); // Use inherited error

        uint256 initialExchangeRate = cToken.exchangeRateStored();
        // The cToken exchange rate serves as the base global index.
        globalRewardIndex = initialExchangeRate;
    }

    function setAuthorizedUpdater(address _newUpdater) external override onlyOwner {
        if (_newUpdater == address(0)) revert IRewardsController.AddressZero(); // Use inherited error
        address oldUpdater = authorizedUpdater;
        authorizedUpdater = _newUpdater;
        emit AuthorizedUpdaterChanged(oldUpdater, _newUpdater);
    }

    function addNFTCollection(
        address collection,
        uint256 beta,
        IRewardsController.RewardBasis rewardBasis,
        uint256 rewardSharePercentage
    ) external override onlyOwner {
        if (collection == address(0)) revert IRewardsController.AddressZero(); // Use inherited error
        if (_whitelistedCollections.contains(collection)) revert IRewardsController.CollectionAlreadyExists(collection); // Use inherited error
        if (rewardSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) {
            revert IRewardsController.InvalidRewardSharePercentage();
        } // Use inherited error

        _whitelistedCollections.add(collection);
        collectionBetas[collection] = beta;
        collectionRewardBasis[collection] = rewardBasis;
        collectionRewardSharePercentages[collection] = rewardSharePercentage;

        emit NFTCollectionAdded(collection, beta, rewardBasis, rewardSharePercentage);
    }

    function removeNFTCollection(address collection) external override onlyOwner {
        // Use inherited error via modifier
        if (!_whitelistedCollections.contains(collection)) {
            revert IRewardsController.CollectionNotWhitelisted(collection);
        }

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

    function setCollectionRewardSharePercentage(address collection, uint256 newSharePercentage)
        external
        override
        onlyOwner
        onlyWhitelistedCollection(collection)
    {
        if (newSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) revert IRewardsController.InvalidRewardSharePercentage();
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
        if (updates.length == 0) revert IRewardsController.EmptyBatch(); // Use inherited error

        if (signer != authorizedUpdater) {
            revert IRewardsController.InvalidSignature(); // Use inherited error
        }

        uint256 nonce = authorizedUpdaterNonce[signer];

        bytes32 updatesHash = _hashUserBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATES_TYPEHASH, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert IRewardsController.InvalidSignature(); // Use inherited error
        }

        authorizedUpdaterNonce[signer]++;

        for (uint256 i = 0; i < updates.length; i++) {
            UserBalanceUpdateData memory update = updates[i];
            if (!_whitelistedCollections.contains(update.collection)) {
                revert IRewardsController.CollectionNotWhitelisted(update.collection); // Use inherited error
            }
            _processSingleUpdate(
                update.user, update.collection, update.blockNumber, update.nftDelta, update.balanceDelta
            );
        }

        emit BalanceUpdatesProcessed(signer, nonce, updates.length); // Align event emission with interface (count)
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
        if (updates.length == 0) revert IRewardsController.EmptyBatch(); // Use inherited error

        if (signer != authorizedUpdater) {
            revert IRewardsController.InvalidSignature(); // Use inherited error
        }

        uint256 nonce = authorizedUpdaterNonce[signer];

        bytes32 updatesHash = _hashBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert IRewardsController.InvalidSignature(); // Use inherited error
        }

        authorizedUpdaterNonce[signer]++;

        for (uint256 i = 0; i < updates.length; i++) {
            if (!_whitelistedCollections.contains(updates[i].collection)) {
                revert IRewardsController.CollectionNotWhitelisted(updates[i].collection); // Use inherited error
            }
            _processSingleUpdate(
                user, updates[i].collection, updates[i].blockNumber, updates[i].nftDelta, updates[i].balanceDelta
            );
        }

        emit UserBalanceUpdatesProcessed(user, nonce, updates.length); // Align event emission with interface (count)
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
            revert IRewardsController.InvalidSignature(); // Use inherited error
        }

        authorizedUpdaterNonce[signer]++;

        if (!_whitelistedCollections.contains(collection)) {
            revert IRewardsController.CollectionNotWhitelisted(collection); // Use inherited error
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
            revert IRewardsController.InvalidSignature(); // Use inherited error
        }

        authorizedUpdaterNonce[signer]++;

        if (!_whitelistedCollections.contains(collection)) {
            revert IRewardsController.CollectionNotWhitelisted(collection); // Use inherited error
        }

        _processSingleUpdate(user, collection, blockNumber, 0, depositDelta);

        emit BalanceUpdateProcessed(
            user, collection, blockNumber, depositDelta, userRewardState[user][collection].lastBalance
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
     * @notice Processes a single balance update (NFT and/or deposit/borrow).
     * @dev Updates the user's state (balances, last update block, last index). Does NOT calculate rewards here.
     *      Handles out-of-order updates. Updates the user's active collection list.
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
            // Revert if the update block is in the past relative to the last processed block for this user/collection.
            // Same-block updates are handled implicitly because updateBlock == info.lastUpdateBlock in that case.
            revert UpdateOutOfOrder(user, collection, updateBlock, info.lastUpdateBlock);
        }

        // If this is the first update or the update is for a future block relative to the last state update
        if (info.lastUpdateBlock == 0 || updateBlock > info.lastUpdateBlock) {
            // Rewards are calculated lazily in _getRawPendingRewardsSingleCollection.
            // Set the user's index and block to the current global state.
            info.lastRewardIndex = globalRewardIndex; // Record the index corresponding to this update block
            info.lastUpdateBlock = updateBlock; // Record the block number of this update
        }
        // If updateBlock == info.lastUpdateBlock (and potentially == block.number),
        // we don't update index/block again, just apply deltas below.

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
            // If both balances become zero, remove from active list
            _userActiveCollections[user].remove(collection);
        }
    }

    function _applyDelta(uint256 value, int256 delta) internal pure returns (uint256) {
        if (delta >= 0) {
            return value + uint256(delta);
        } else {
            uint256 absDelta = uint256(-delta);
            if (absDelta > value) {
                // Ensure revert happens if delta magnitude exceeds current value
                revert BalanceUpdateUnderflow(value, absDelta);
            }
            // If delta magnitude is not greater, subtraction is safe
            return value - absDelta;
        }
    }

    /**
     * @notice Calculates the raw reward for a specific period based on index change and balances.
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
        // If user has no NFTs from this collection during the period, they get no reward for it.
        if (nftBalanceDuringPeriod == 0) {
            return 0;
        }

        if (indexDelta == 0 || balanceDuringPeriod == 0 || lastRewardIndex == 0) {
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
        // Not view anymore
        uint256 accrualResult = cToken.accrueInterest(); // Accrue interest HERE
        accrualResult; // Silence compiler warning

        currentIndex = cToken.exchangeRateStored(); // Read the updated rate
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

    // Helper to check whitelist status (Moved before first usage)
    function isCollectionWhitelisted(address collection) public view returns (bool) {
        return _whitelistedCollections.contains(collection);
    }

    /**
     * @notice Retrieves the stored reward state for a specific user and collection.
     * @dev Added for testing purposes.
     * @param user The user address.
     * @param collection The collection address.
     * @return state The UserRewardState struct for the user and collection.
     */
    function getUserRewardState(address user, address collection)
        external
        view
        returns (UserRewardState memory state)
    {
        return userRewardState[user][collection];
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
            revert IRewardsController.CollectionsArrayEmpty(); // Use inherited error
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
        address[] calldata nftCollections, // Keep as calldata
        BalanceUpdateData[] calldata simulatedUpdates // Keep as calldata
    ) external override returns (uint256 pendingReward) {
        // Keep external, remove view for now
        // REMOVED: Accrue interest ONCE at the beginning of the public function
        // uint256 accrualResult = cToken.accrueInterest();
        // accrualResult; // Silence compiler warning

        // Changed visibility to external override
        if (nftCollections.length == 0) {
            return 0;
        }

        // --- Out of Order Check for Simulations (moved to beginning) ---
        for (uint256 _i = 0; _i < simulatedUpdates.length; _i++) {
            BalanceUpdateData memory _update = simulatedUpdates[_i];
            // Ensure simulation block is not before the last *actual* processed block for that collection
            uint256 _lastProcessed = userRewardState[user][_update.collection].lastUpdateBlock;
            if (_update.blockNumber < _lastProcessed) {
                revert SimulationUpdateOutOfOrder(_update.blockNumber, _lastProcessed);
            }
        }
        // --- End Out of Order Check ---

        uint256 totalRawPendingReward = 0;

        // Calculate the current index ONCE (includes accrual via _calculateGlobalIndexAt)
        uint256 currentIndex = _calculateGlobalIndexAt(); // Reads the rate AFTER accrual

        for (uint256 i = 0; i < nftCollections.length; i++) {
            address collection = nftCollections[i];
            if (!isCollectionWhitelisted(collection)) {
                revert IRewardsController.CollectionNotWhitelisted(collection);
            }
            // Pass the pre-calculated currentIndex and use the correct
            // Correctly add only the reward amount (first element of the returned tuple)
            (uint256 rewardForCollection,) =
                _getRawPendingRewardsSingleCollection(user, collection, simulatedUpdates, currentIndex);
            totalRawPendingReward += rewardForCollection;
        }

        pendingReward = totalRawPendingReward;

        return pendingReward;
    }

    // Re-added implementation for getWhitelistedCollections
    function getWhitelistedCollections() external view override returns (address[] memory) {
        return _whitelistedCollections.values();
    }

    // --- Claiming Functions --- //

    function claimRewardsForCollection(address nftCollection, BalanceUpdateData[] calldata simulatedUpdates)
        external
        override
        nonReentrant
        onlyWhitelistedCollection(nftCollection) // Apply modifier here
    {
        address user = msg.sender;
        // REMOVED: _requireCollectionWhitelisted(nftCollection); // Remove internal call
        // REMOVED: Accrue interest call (now done implicitly in _calculateGlobalIndexAt)

        // Calculate index ONCE (includes accrual)
        uint256 currentIndex = _calculateGlobalIndexAt();

        // Get state and previous deficit
        UserRewardState storage info = userRewardState[user][nftCollection];
        uint256 previousDeficit = info.accruedReward;

        // Calculate raw rewards for the current period
        (uint256 rewardForPeriod, uint256 indexUsed) = _getRawPendingRewardsSingleCollection(
            user,
            nftCollection,
            simulatedUpdates,
            currentIndex // Pass current index
        );

        // Calculate total amount due (new rewards + old deficit)
        uint256 totalDue = rewardForPeriod + previousDeficit;

        // Handle zero reward case
        if (totalDue == 0) {
            // Update state even if no reward is claimed
            info.accruedReward = 0; // Reset any previous deficit
            info.lastRewardIndex = indexUsed; // Use the index from calculation
            info.lastUpdateBlock = block.number; // Update to current block
            emit RewardsClaimedForCollection(user, nftCollection, 0);
            return; // Exit after state update and emit
        }

        // Request yield transfer from LendingManager for the total amount due
        uint256 actualYieldReceived = lendingManager.transferYield(totalDue, user);

        // Check if yield was capped based on totalDue
        if (actualYieldReceived < totalDue) {
            emit YieldTransferCapped(user, totalDue, actualYieldReceived);
        }

        // Update user state using the index from the reward calculation
        // Pass totalDue as the 'totalRawReward' parameter to the update function
        _updateUserRewardStateAfterClaim(user, nftCollection, actualYieldReceived, totalDue, indexUsed);

        emit RewardsClaimedForCollection(user, nftCollection, actualYieldReceived);
    }

    function claimRewardsForAll(BalanceUpdateData[] calldata simulatedUpdates) external override nonReentrant {
        address user = msg.sender;
        // REMOVED: Accrue interest call (now done implicitly in _calculateGlobalIndexAt)
        address[] memory collections = _userActiveCollections[user].values();
        if (collections.length == 0) {
            emit RewardsClaimedForAll(user, 0);
            return;
        }

        uint256 totalRewardToRequest = 0; // Represents totalDue across all collections
        uint256[] memory individualRewards = new uint256[](collections.length); // Stores totalDue per collection
        uint256[] memory indicesUsed = new uint256[](collections.length); // Store indices used

        // Calculate index ONCE (includes accrual)
        uint256 currentIndex = _calculateGlobalIndexAt();

        // Calculate total rewards across all collections
        for (uint256 i = 0; i < collections.length; i++) {
            address collection = collections[i];
            UserRewardState storage info = userRewardState[user][collection]; // Get state for deficit
            uint256 previousDeficit = info.accruedReward;

            (uint256 rewardForPeriod, uint256 indexUsed) =
                _getRawPendingRewardsSingleCollection(user, collection, simulatedUpdates, currentIndex);

            uint256 totalDueForCollection = rewardForPeriod + previousDeficit;
            individualRewards[i] = totalDueForCollection; // Store total due for this collection
            indicesUsed[i] = indexUsed; // Store the index used for this collection
            totalRewardToRequest += totalDueForCollection; // Accumulate total due across all collections
        }

        // Handle zero total reward case
        if (totalRewardToRequest == 0) {
            // Update state for all active collections even if no total reward is claimed
            for (uint256 i = 0; i < collections.length; i++) {
                UserRewardState storage info = userRewardState[user][collections[i]];
                info.accruedReward = 0; // Reset any previous deficit
                info.lastRewardIndex = indicesUsed[i]; // Use the index calculated for this collection
                info.lastUpdateBlock = block.number; // Update to current block
            }
            emit RewardsClaimedForAll(user, 0);
            return; // Exit after state update and emit
        }

        // Request yield transfer for the total amount
        uint256 totalYieldReceived = lendingManager.transferYield(totalRewardToRequest, user);
        uint256 finalTotalClaimed = totalYieldReceived; // Amount user actually gets

        // Check if the total yield was capped
        if (finalTotalClaimed < totalRewardToRequest) {
            emit YieldTransferCapped(user, totalRewardToRequest, finalTotalClaimed);
        }

        // Distribute the received yield proportionally and update state for each collection
        for (uint256 i = 0; i < collections.length; i++) {
            address collection = collections[i];
            UserRewardState storage info = userRewardState[user][collection];
            uint256 totalDueForThisCollection = individualRewards[i]; // This is totalDue

            // Determine the new deficit for this specific collection based on proportional capping
            uint256 deficitForCollection = 0;
            if (totalRewardToRequest > 0 && finalTotalClaimed < totalRewardToRequest) { // Check if capped
                // Calculate the portion of the *shortfall* attributable to this collection
                uint256 totalShortfall = totalRewardToRequest - finalTotalClaimed;
                // Use SafeCast to prevent potential overflow issues with large numbers, though unlikely here
                // Deficit = (TotalDueForCollection * TotalShortfall) / TotalRewardToRequest
                deficitForCollection = Math.mulDiv(totalDueForThisCollection, totalShortfall, totalRewardToRequest);
            }
            // If not capped (finalTotalClaimed >= totalRewardToRequest), deficit remains 0.

            info.accruedReward = deficitForCollection; // Store the new deficit
            info.lastRewardIndex = indicesUsed[i]; // Update index
            info.lastUpdateBlock = block.number; // Update block
        }

        // REMOVED complex dust handling logic

        emit RewardsClaimedForAll(user, finalTotalClaimed);
    }

    /**
     * @notice Calculates the total raw pending rewards for a user across a single collection, considering simulated updates.
     * @dev Iterates through time segments defined by updates, calculating rewards for each segment.
     *      Does NOT include previously accrued deficit in the returned value.
     * @param user The user address.
     * @param nftCollection The collection address.
     * @param simulatedUpdates Optional array of simulated future balance updates.
     * @param currentIndex The current global index (cToken exchange rate) after accrual.
     * @return totalRawReward The total raw reward accumulated across all segments SINCE LAST UPDATE (excludes deficit).
     * @return calculatedIndex The index used for the calculation (which is the input currentIndex).
     */
    function _getRawPendingRewardsSingleCollection(
        address user,
        address nftCollection,
        BalanceUpdateData[] calldata simulatedUpdates, // Assuming sorted by blockNumber
        uint256 currentIndex // Pass the already calculated current index
    ) internal view returns (uint256 totalRawReward, uint256 calculatedIndex) {
        UserRewardState storage info = userRewardState[user][nftCollection];
        uint256 rewardSharePercentage = collectionRewardSharePercentages[nftCollection];

        // Initialize segment variables from stored state
        uint256 segmentStartBlock = info.lastUpdateBlock;
        uint256 segmentStartIndex = info.lastRewardIndex; // Index at the beginning of the whole period
        uint256 segmentNFTBalance = info.lastNFTBalance;
        uint256 segmentBalance = info.lastBalance;

        // Start with zero, do NOT include previous deficit here.
        totalRawReward = 0;

        // Process simulated future updates segment by segment
        for (uint256 i = 0; i < simulatedUpdates.length; i++) {
            BalanceUpdateData memory update = simulatedUpdates[i];

            // --- Validation Checks (moved earlier) ---
            if (update.blockNumber < info.lastUpdateBlock) {
                revert SimulationUpdateOutOfOrder(update.blockNumber, info.lastUpdateBlock);
            }
            if (update.blockNumber < segmentStartBlock) {
                revert SimulationUpdateOutOfOrder(update.blockNumber, segmentStartBlock);
            }
            // --- End Validation Checks ---

            // Calculate rewards for the segment ending *before* this update
            // Only calculate if the index has actually increased and time has passed
            // Use the index delta for the *entire period* (`currentIndex - segmentStartIndex`)
            // but apply it to the balances held *during this specific segment*.
            if (currentIndex > segmentStartIndex && update.blockNumber > segmentStartBlock) {
                uint256 indexDelta = currentIndex - segmentStartIndex;

                // Calculate reward for the segment [segmentStartBlock, update.blockNumber)
                // using balances *before* the update.
                totalRawReward += _calculateRewardsWithDelta(
                    nftCollection,
                    indexDelta, // Use total index delta
                    segmentStartIndex, // Use initial index for the whole period
                    segmentNFTBalance, // Balance *during* this segment
                    segmentBalance, // Balance *during* this segment
                    rewardSharePercentage
                );
            }

            // --- Apply simulated deltas for the *next* segment, checking underflow first ---
            if (update.nftDelta < 0) {
                uint256 absNftDelta = uint256(-update.nftDelta);
                if (absNftDelta > segmentNFTBalance) {
                    revert SimulationNFTUpdateUnderflow(segmentNFTBalance, absNftDelta);
                }
            }
            if (update.balanceDelta < 0) {
                uint256 absBalanceDelta = uint256(-update.balanceDelta);
                if (absBalanceDelta > segmentBalance) {
                    revert SimulationBalanceUpdateUnderflow(segmentBalance, absBalanceDelta);
                }
            }
            segmentNFTBalance = _applyDelta(segmentNFTBalance, update.nftDelta);
            segmentBalance = _applyDelta(segmentBalance, update.balanceDelta);
            // --- End Apply simulated deltas ---

            // Update segment start block for the next iteration
            segmentStartBlock = update.blockNumber;
            // DO NOT update segmentStartIndex here. It remains info.lastRewardIndex.
        }

        // Calculate reward for the final segment (from last update/simulation to current block)
        if (currentIndex > segmentStartIndex && block.number > segmentStartBlock) {
            uint256 indexDelta = currentIndex - segmentStartIndex;
            totalRawReward += _calculateRewardsWithDelta(
                nftCollection,
                indexDelta, // Use total index delta
                segmentStartIndex, // Use initial index for the whole period
                segmentNFTBalance, // Use the balance *after* all simulations
                segmentBalance, // Use the balance *after* all simulations
                rewardSharePercentage
            );
        }

        calculatedIndex = currentIndex; // Return the index that was used
    }


    /**
     * @notice Updates the user's reward state after a successful claim.
     * @dev Resets or calculates accrued reward (deficit), updates last index and last update block.
     * @param user The user address.
     * @param nftCollection The collection address.
     * @param claimedAmount The amount actually claimed (might be capped).
     * @param totalDue The total amount calculated as due (new rewards + previous deficit).
     * @param indexUsedForClaim The global index used during the claim calculation.
     */
    function _updateUserRewardStateAfterClaim(
        address user,
        address nftCollection,
        uint256 claimedAmount,
        uint256 totalDue, // Renamed from totalRawReward for clarity
        uint256 indexUsedForClaim // Added parameter
    ) internal {
        // REMOVED: Redundant currentIndex calculation
        UserRewardState storage info = userRewardState[user][nftCollection];

        // If claimed amount is less than total amount due (due to capping),
        // store the difference (shortfall) as the new accrued reward (deficit).
        if (claimedAmount < totalDue) {
            info.accruedReward = totalDue - claimedAmount;
        } else {
            // If claimed amount meets or exceeds the total due (shouldn't exceed), clear the deficit.
            info.accruedReward = 0;
        }

        // Update the last processed index and block
        info.lastRewardIndex = indexUsedForClaim; // Use the index passed in
        info.lastUpdateBlock = block.number;
    }

    uint256 public epochDuration;

    /**
     * @notice Sets the duration of a reward epoch.
     * @dev Placeholder implementation. Actual logic might be needed depending on requirements.
     * @param newDuration The new epoch duration (e.g., in blocks or seconds).
     */
    function setEpochDuration(uint256 newDuration) external override onlyOwner {
        if (newDuration == 0) revert IRewardsController.InvalidEpochDuration();
        epochDuration = newDuration;
    }

    // --- Storage Gap --- //
    uint256[47] private __gap;
}
