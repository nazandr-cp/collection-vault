/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";

contract RewardsController is
    Initializable,
    IRewardsController,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using BitMaps for BitMaps.BitMap;

    struct UserRewardState {
        uint32 lastUpdateBlock;
        uint32 lastNFTBalance;
        uint128 lastBalance;
        uint128 accruedReward;
        uint256 lastRewardIndex;
    }

    struct CollectionConfig {
        uint96 beta;
        uint16 rewardSharePercentage;
    }

    struct ClaimData {
        address collectionAddress;
        uint256 individualReward;
        uint256 indexUsed;
    }

    /// @notice Represents a snapshot of a user's reward-relevant state at a specific point in time (blockNumber and rewardIndex).
    // struct RewardSnapshot is now defined in IRewardsController.sol
    // The parameters blockNumber, nftBalance, balance, and rewardIndex are part of the RewardSnapshot struct.

    bytes32 public constant BALANCE_UPDATES_ARRAYS_TYPEHASH = keccak256(
        "BalanceUpdates(address[] users,address[] collections,uint256[] blockNumbers,int256[] nftDeltas,int256[] balanceDeltas,uint256 nonce)"
    );

    // bytes32 public constant BALANCE_UPDATE_DATA_TYPEHASH = // Removed as per new design
    //     keccak256("BalanceUpdateData(address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)");
    // bytes32 public constant USER_BALANCE_UPDATES_TYPEHASH = // Removed as per new design
    //     keccak256("UserBalanceUpdates(address user,BalanceUpdateData[] updates,uint256 nonce)");

    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private constant MAX_REWARD_SHARE_PERCENTAGE = 10000;
    uint8 private constant MAX_COLLECTIONS_BITMAP = 255;
    /// @dev Soft-cap on the number of snapshots stored per user per collection to prevent gas griefing.
    uint256 private constant MAX_SNAPSHOTS = 50;
    uint256 public constant MAX_BATCH_UPDATES = 250;
    uint256 public constant MAX_SNAPSHOTS_PER_CLAIM = 100;

    ILendingManager public lendingManager;
    IERC4626 public vault;
    IERC20 public rewardToken;
    CTokenInterface internal cToken;
    address public authorizedUpdater;

    EnumerableSet.AddressSet private _whitelistedCollections;
    mapping(address => IRewardsController.RewardBasis) public collectionRewardBasis;
    mapping(address => CollectionConfig) public collectionConfigs;

    mapping(address => uint256) public collectionBitIndices;
    address[256] public bitIndexToCollection;
    uint256 public nextBitIndex;

    mapping(address => mapping(address => UserRewardState)) internal userRewardState;
    mapping(address => BitMaps.BitMap) internal userActiveMasks;
    mapping(address => uint256) public authorizedUpdaterNonce;
    /// @notice Stores historical snapshots of user's state for each collection.
    /// @dev Snapshots are used to calculate rewards for past segments when a user claims.
    /// @dev mapping: user (address) => collection (address) => array of IRewardsController.RewardSnapshot
    mapping(address => mapping(address => IRewardsController.RewardSnapshot[])) public userSnapshots;

    uint256 public globalRewardIndex;

    /// @notice Global nonce incremented on each batch of balance updates.
    uint64 public globalUpdateNonce;
    /// @notice Tracks the globalUpdateNonce at which a user's balance state was last synced.
    mapping(address => uint64) public userLastSyncedNonce;
    /// @notice Accumulates small reward amounts (dust) that couldn't be precisely distributed due to integer division.
    uint256 public globalDustBucket;

    event SingleUpdateProcessed(
        address indexed user,
        address indexed collection,
        uint256 blockNumber,
        int256 nftDelta,
        uint32 finalNFTBalance,
        int256 balanceDelta,
        uint128 finalBalance
    );

    /// @notice Emitted when a user (param `user`) attempts to claim rewards with an outdated nonce (param `userNonce`),
    ///         when a newer nonce (param `expectedNonce`) was expected.

    error BalanceUpdateUnderflow(uint256 currentValue, uint256 deltaMagnitude);
    error UpdateOutOfOrder(address user, address collection, uint256 updateBlock, uint256 lastProcessedBlock);
    error VaultMismatch();
    error SimulationNFTUpdateUnderflow(uint256 currentValue, uint256 deltaMagnitude);
    error RewardsControllerInvalidInitialOwner(address owner);
    error InvalidBetaValue(uint256 beta);
    error MaxCollectionsReached(uint256 currentMaxIndex, uint8 limit);

    modifier onlyWhitelistedCollection(address collection) {
        if (!_whitelistedCollections.contains(collection)) {
            revert IRewardsController.CollectionNotWhitelisted(collection);
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address _lendingManagerAddress,
        address _vaultAddress,
        address _authorizedUpdater
    ) public initializer {
        if (initialOwner == address(0)) revert RewardsControllerInvalidInitialOwner(address(0));
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("RewardsController", "1");
        __Pausable_init();

        if (_lendingManagerAddress == address(0)) revert IRewardsController.AddressZero();
        if (_vaultAddress == address(0)) revert IRewardsController.AddressZero();
        if (_authorizedUpdater == address(0)) revert IRewardsController.AddressZero();

        lendingManager = ILendingManager(_lendingManagerAddress);
        vault = IERC4626(_vaultAddress);

        IERC20 _rewardToken = lendingManager.asset();
        if (address(_rewardToken) == address(0)) revert IRewardsController.AddressZero();

        address _vaultAsset = vault.asset();
        if (_vaultAsset == address(0)) revert IRewardsController.AddressZero();
        if (_vaultAsset != address(_rewardToken)) revert VaultMismatch();

        rewardToken = _rewardToken;
        authorizedUpdater = _authorizedUpdater;

        address _cTokenAddress = address(lendingManager.cToken());
        if (_cTokenAddress == address(0)) revert IRewardsController.AddressZero();
        cToken = CTokenInterface(_cTokenAddress);

        uint256 initialExchangeRate = cToken.exchangeRateStored();
        // Initialize global index with the starting exchange rate.
        globalRewardIndex = initialExchangeRate;
    }

    function setAuthorizedUpdater(address _newUpdater) external override onlyOwner whenNotPaused {
        if (_newUpdater == address(0)) revert IRewardsController.AddressZero();
        address oldUpdater = authorizedUpdater;
        authorizedUpdater = _newUpdater;
        emit AuthorizedUpdaterChanged(oldUpdater, _newUpdater, owner());
    }

    function addNFTCollection(
        address collection,
        uint256 beta,
        IRewardsController.RewardBasis rewardBasis,
        uint256 rewardSharePercentage
    ) external override onlyOwner whenNotPaused {
        if (collection == address(0)) revert IRewardsController.AddressZero();
        if (_whitelistedCollections.contains(collection)) revert IRewardsController.CollectionAlreadyExists(collection);
        if (rewardSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) {
            revert IRewardsController.InvalidRewardSharePercentage();
        }
        if (beta > type(uint96).max) revert InvalidBetaValue(beta);
        if (nextBitIndex > MAX_COLLECTIONS_BITMAP) {
            revert MaxCollectionsReached(nextBitIndex, MAX_COLLECTIONS_BITMAP);
        }

        _whitelistedCollections.add(collection);
        collectionRewardBasis[collection] = rewardBasis;
        collectionConfigs[collection] =
            CollectionConfig({beta: uint96(beta), rewardSharePercentage: uint16(rewardSharePercentage)});

        collectionBitIndices[collection] = nextBitIndex;
        bitIndexToCollection[nextBitIndex] = collection;
        nextBitIndex++;

        emit NFTCollectionAdded(collection, beta, rewardBasis, rewardSharePercentage);
        emit CollectionConfigChanged(
            collection,
            0, // oldBeta
            uint96(beta), // newBeta
            0, // oldRewardSharePercentage
            uint16(rewardSharePercentage), // newRewardSharePercentage
            RewardBasis.DEPOSIT, // oldRewardBasis (assuming default or not applicable for new)
            rewardBasis, // newRewardBasis
            owner()
        );
    }

    function removeNFTCollection(address collection) external override onlyOwner whenNotPaused {
        if (!_whitelistedCollections.contains(collection)) {
            revert IRewardsController.CollectionNotWhitelisted(collection);
        }

        _whitelistedCollections.remove(collection);
        delete collectionRewardBasis[collection];
        delete collectionConfigs[collection];

        uint256 bitIndex = collectionBitIndices[collection];
        if (bitIndex < nextBitIndex && bitIndexToCollection[bitIndex] == collection) {
            bitIndexToCollection[bitIndex] = address(0);
        }
        delete collectionBitIndices[collection];

        emit NFTCollectionRemoved(collection);
        CollectionConfig memory removedConfig = collectionConfigs[collection]; // Temp store before delete
        RewardBasis removedRewardBasis = collectionRewardBasis[collection]; // Temp store before delete
        emit CollectionConfigChanged(
            collection,
            removedConfig.beta, // oldBeta
            0, // newBeta
            removedConfig.rewardSharePercentage, // oldRewardSharePercentage
            0, // newRewardSharePercentage
            removedRewardBasis, // oldRewardBasis
            RewardBasis.DEPOSIT, // newRewardBasis (assuming default or not applicable for removed)
            owner()
        );
    }

    function updateBeta(address collection, uint256 newBeta)
        external
        override
        onlyOwner
        onlyWhitelistedCollection(collection)
        whenNotPaused
    {
        if (newBeta > type(uint96).max) revert InvalidBetaValue(newBeta);
        CollectionConfig storage config = collectionConfigs[collection];
        uint256 oldBeta = config.beta;
        config.beta = uint96(newBeta);
        emit BetaUpdated(collection, oldBeta, newBeta);
        emit CollectionConfigChanged(
            collection,
            uint96(oldBeta),
            uint96(newBeta),
            config.rewardSharePercentage, // oldRewardSharePercentage (unchanged)
            config.rewardSharePercentage, // newRewardSharePercentage (unchanged)
            collectionRewardBasis[collection], // oldRewardBasis (unchanged)
            collectionRewardBasis[collection], // newRewardBasis (unchanged)
            owner()
        );
    }

    function setCollectionRewardSharePercentage(address collection, uint256 newSharePercentage)
        external
        override
        onlyOwner
        onlyWhitelistedCollection(collection)
        whenNotPaused
    {
        if (newSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) revert IRewardsController.InvalidRewardSharePercentage();
        CollectionConfig storage config = collectionConfigs[collection];
        uint256 oldSharePercentage = config.rewardSharePercentage;
        config.rewardSharePercentage = uint16(newSharePercentage);
        emit CollectionRewardShareUpdated(collection, oldSharePercentage, newSharePercentage);
        emit CollectionConfigChanged(
            collection,
            config.beta, // oldBeta (unchanged)
            config.beta, // newBeta (unchanged)
            uint16(oldSharePercentage),
            uint16(newSharePercentage),
            collectionRewardBasis[collection], // oldRewardBasis (unchanged)
            collectionRewardBasis[collection], // newRewardBasis (unchanged)
            owner()
        );
    }

    function processBalanceUpdates(
        address signer,
        address[] calldata users,
        address[] calldata collections,
        uint256[] calldata blockNumbers,
        int256[] calldata nftDeltas,
        int256[] calldata balanceDeltas,
        bytes calldata signature
    ) external override nonReentrant whenNotPaused {
        uint256 numUpdates = users.length;
        require(numUpdates <= MAX_BATCH_UPDATES, "BATCH_TOO_LARGE");
        if (numUpdates == 0) revert IRewardsController.EmptyBatch();
        if (
            collections.length != numUpdates || blockNumbers.length != numUpdates || nftDeltas.length != numUpdates
                || balanceDeltas.length != numUpdates
        ) {
            revert IRewardsController.ArrayLengthMismatch();
        }

        if (signer != authorizedUpdater) {
            revert IRewardsController.InvalidSignature();
        }

        uint256 nonce = authorizedUpdaterNonce[signer];

        bytes32 structHash = keccak256(
            abi.encode(
                BALANCE_UPDATES_ARRAYS_TYPEHASH,
                keccak256(abi.encodePacked(users)),
                keccak256(abi.encodePacked(collections)),
                keccak256(abi.encodePacked(blockNumbers)),
                keccak256(abi.encodePacked(nftDeltas)),
                keccak256(abi.encodePacked(balanceDeltas)),
                nonce
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        bytes memory signatureBytes = signature;
        (address recoveredSigner, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signatureBytes);

        if (err != ECDSA.RecoverError.NoError || recoveredSigner != signer) {
            revert IRewardsController.InvalidSignature();
        }

        authorizedUpdaterNonce[signer]++;
        globalUpdateNonce++;

        for (uint256 i = 0; i < numUpdates;) {
            address currentCollection = collections[i];
            if (!_whitelistedCollections.contains(currentCollection)) {
                revert IRewardsController.CollectionNotWhitelisted(currentCollection);
            }
            _processSingleUpdate(users[i], currentCollection, blockNumbers[i], nftDeltas[i], balanceDeltas[i]);
            unchecked {
                ++i;
            }
        }

        emit BalanceUpdatesProcessed(signer, nonce, numUpdates);
    }

    // function processUserBalanceUpdates( // Removed as per new design (relies on BalanceUpdateData)
    //     address signer,
    //     address user,
    //     BalanceUpdateData[] calldata updates,
    //     bytes calldata signature
    // ) external override nonReentrant whenNotPaused {
    //     uint256 numUpdates = updates.length;
    //     require(numUpdates <= MAX_BATCH_UPDATES, "BATCH_TOO_LARGE");
    //     if (numUpdates == 0) revert IRewardsController.EmptyBatch();
    //     // Allow empty updates to pass through for nonce management / signature verification. // Re-enabled for test

    //     if (signer != authorizedUpdater) {
    //         revert IRewardsController.InvalidSignature();
    //     }

    //     uint256 nonce = authorizedUpdaterNonce[signer];

    //     bytes32 updatesHash = _hashBalanceUpdates(updates);
    //     bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
    //     bytes32 digest = _hashTypedDataV4(structHash);
    //     bytes memory signatureBytes = signature;
    //     (address recoveredSigner, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signatureBytes);

    //     if (err != ECDSA.RecoverError.NoError || recoveredSigner != signer) {
    //         revert IRewardsController.InvalidSignature();
    //     }

    //     if (numUpdates > 0) {
    //         authorizedUpdaterNonce[signer]++;
    //         globalUpdateNonce++;

    //         uint256 uLen = updates.length; // Same as numUpdates
    //         for (uint256 i = 0; i < uLen;) {
    //             BalanceUpdateData memory currentUpdate = updates[i];
    //             if (!_whitelistedCollections.contains(currentUpdate.collection)) {
    //                 revert IRewardsController.CollectionNotWhitelisted(currentUpdate.collection);
    //             }
    //             _processSingleUpdate(
    //                 user,
    //                 currentUpdate.collection,
    //                 currentUpdate.blockNumber,
    //                 currentUpdate.nftDelta,
    //                 currentUpdate.balanceDelta
    //             );
    //             unchecked {
    //                 ++i;
    //             }
    //         }
    //         emit UserBalanceUpdatesProcessed(user, nonce, uLen);
    //     } else {
    //         // If numUpdates is 0, the signature was still validated against the current nonce.
    //         // We do not increment authorizedUpdaterNonce[signer] or globalUpdateNonce.
    //         // We can still emit an event indicating the call was processed, with 0 updates.
    //         emit UserBalanceUpdatesProcessed(user, nonce, 0);
    //         // User's own userLastSyncedNonce is NOT updated here, as this function's primary purpose
    //         // is to process updates from an authorized updater FOR a user.
    //         // Syncing a user's nonce without actual updates is better handled by syncAndClaim.
    //     }
    // }

    // function _hashBalanceUpdates(BalanceUpdateData[] calldata updates) internal pure returns (bytes32) { // Removed as per new design
    //     uint256 numUpdates = updates.length;
    //     bytes32[] memory encodedUpdates = new bytes32[](numUpdates);
    //     for (uint256 i = 0; i < numUpdates;) {
    //         BalanceUpdateData memory currentUpdate = updates[i];
    //         encodedUpdates[i] = keccak256(
    //             abi.encode(
    //                 BALANCE_UPDATE_DATA_TYPEHASH,
    //                 currentUpdate.collection,
    //                 currentUpdate.blockNumber,
    //                 currentUpdate.nftDelta,
    //                 currentUpdate.balanceDelta
    //             )
    //         );
    //         unchecked {
    //             ++i;
    //         }
    //     }
    //     return keccak256(abi.encodePacked(encodedUpdates));
    // }

    function _processSingleUpdate(
        address user,
        address collection,
        uint256 updateBlock,
        int256 nftDelta,
        int256 balanceDelta
    ) internal {
        UserRewardState storage info = userRewardState[user][collection];

        if (updateBlock < info.lastUpdateBlock) {
            revert UpdateOutOfOrder(user, collection, updateBlock, info.lastUpdateBlock);
        }

        if (info.lastUpdateBlock == 0 || updateBlock > info.lastUpdateBlock) {
            // Create snapshot *before* applying deltas to info.lastNFTBalance and info.lastBalance
            // This snapshot represents the state for the segment ending at updateBlock.
            if (info.lastUpdateBlock > 0) {
                // Only create a snapshot if there was a previous state
                // This snapshot captures the state *before* the current update's deltas are applied.
                IRewardsController.RewardSnapshot memory newSnapshot = IRewardsController.RewardSnapshot({
                    collection: collection,
                    index: info.lastRewardIndex,
                    blockNumber: info.lastUpdateBlock,
                    nftBalance: info.lastNFTBalance, // Balance *during* the segment ending now
                    balance: info.lastBalance // Balance *during* the segment ending now
                });

                IRewardsController.RewardSnapshot[] storage snapshots = userSnapshots[user][collection];
                if (snapshots.length >= MAX_SNAPSHOTS) {
                    revert IRewardsController.MaxSnapshotsReached(user, collection, MAX_SNAPSHOTS);
                }
                snapshots.push(newSnapshot);
            }

            info.lastRewardIndex = globalRewardIndex; // Update to current global index for the *new* state
            if (updateBlock > type(uint32).max) revert("RewardsController: updateBlock overflows uint32");
            info.lastUpdateBlock = uint32(updateBlock); // This is the start of the new segment
        }

        uint256 newNFTBalance = _applyDelta(info.lastNFTBalance, nftDelta);
        if (newNFTBalance > type(uint32).max) revert("RewardsController: newNFTBalance overflows uint32");
        info.lastNFTBalance = uint32(newNFTBalance);

        uint256 newBalance = _applyDelta(info.lastBalance, balanceDelta);
        if (newBalance > type(uint128).max) revert("RewardsController: newBalance overflows uint128");
        info.lastBalance = uint128(newBalance);

        // If it's the very first update for this user/collection, create an initial snapshot.
        // This ensures that the period from deployment/initialization up to the first balance update
        // can be calculated if there was a balance.
        if (
            userSnapshots[user][collection].length == 0 && (info.lastNFTBalance > 0 || info.lastBalance > 0)
                && info.lastUpdateBlock > 0
        ) {
            // This initial snapshot captures the state *after* the first update's deltas are applied,
            // representing the state for the very first segment.
            IRewardsController.RewardSnapshot memory initialSnapshot = IRewardsController.RewardSnapshot({
                collection: collection,
                index: info.lastRewardIndex, // Index at the start of this first segment
                blockNumber: info.lastUpdateBlock, // Block number at the start of this first segment
                nftBalance: info.lastNFTBalance, // NFT balance *during* this first segment
                balance: info.lastBalance // Balance *during* this first segment
            });
            userSnapshots[user][collection].push(initialSnapshot);
        }

        userLastSyncedNonce[user] = globalUpdateNonce;

        emit SingleUpdateProcessed(
            user, collection, updateBlock, nftDelta, info.lastNFTBalance, balanceDelta, info.lastBalance
        );

        uint256 bitIndex = collectionBitIndices[collection];
        if (info.lastNFTBalance > 0 || info.lastBalance > 0) {
            userActiveMasks[user].set(bitIndex);
        } else {
            userActiveMasks[user].unset(bitIndex);
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
        uint256 lastRewardIndex,
        uint256 nftBalanceDuringPeriod,
        uint256 balanceDuringPeriod,
        uint256 rewardSharePercentage
    ) internal view returns (uint256 rawReward) {
        if (nftBalanceDuringPeriod == 0) {
            return 0;
        }

        if (indexDelta == 0 || balanceDuringPeriod == 0 || lastRewardIndex == 0) {
            return 0;
        }

        uint256 yieldReward = (balanceDuringPeriod * indexDelta) / lastRewardIndex;

        uint256 beta = collectionConfigs[nftCollection].beta;
        uint256 boostFactor = calculateBoost(nftBalanceDuringPeriod, beta);

        uint256 bonusReward = (yieldReward * boostFactor) / PRECISION_FACTOR;
        uint256 totalYieldWithBoost = yieldReward + bonusReward;

        rawReward = (totalYieldWithBoost * rewardSharePercentage) / MAX_REWARD_SHARE_PERCENTAGE;

        return rawReward;
    }

    function _calculateAndUpdateGlobalIndex() public whenNotPaused returns (uint256 currentIndex) {
        uint256 accrualResult = cToken.accrueInterest();
        // accrualResult is not directly used; accrueInterest updates cToken's internal state.
        accrualResult; // Prevents unused variable warning if compiler is strict

        currentIndex = cToken.exchangeRateStored();
        globalRewardIndex = currentIndex;
        return currentIndex;
    }

    function calculateBoost(uint256 nftBalance, uint256 beta) public pure returns (uint256 boostFactor) {
        if (nftBalance == 0) return 0;

        boostFactor = nftBalance * beta;

        uint256 maxBoostFactor = PRECISION_FACTOR * 9;
        if (boostFactor > maxBoostFactor) {
            boostFactor = maxBoostFactor;
        }
        return boostFactor;
    }

    function isCollectionWhitelisted(address collection) public view returns (bool) {
        return _whitelistedCollections.contains(collection);
    }

    function getUserRewardState(address user, address collection)
        external
        view
        returns (UserRewardState memory state)
    {
        return userRewardState[user][collection];
    }

    function getUserCollectionTracking(address user, address[] calldata nftCollections)
        external
        view
        override
        returns (UserCollectionTracking[] memory trackingInfo)
    {
        uint256 numCollections = nftCollections.length;
        if (numCollections == 0) {
            revert IRewardsController.CollectionsArrayEmpty();
        }
        trackingInfo = new UserCollectionTracking[](numCollections);
        for (uint256 i = 0; i < numCollections;) {
            address collection = nftCollections[i];
            UserRewardState storage internalInfo = userRewardState[user][collection];
            trackingInfo[i] = UserCollectionTracking({
                lastUpdateBlock: internalInfo.lastUpdateBlock,
                lastNFTBalance: internalInfo.lastNFTBalance,
                lastBalance: internalInfo.lastBalance,
                lastUserRewardIndex: internalInfo.lastRewardIndex
            });
            unchecked {
                ++i;
            }
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
        return collectionConfigs[nftCollection].beta;
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

    function getCollectionRewardSharePercentage(address collection)
        external
        view
        onlyWhitelistedCollection(collection)
        returns (uint256)
    {
        return collectionConfigs[collection].rewardSharePercentage;
    }

    function getUserNFTCollections(address user) external view override returns (address[] memory) {
        BitMaps.BitMap storage mask = userActiveMasks[user];
        uint256 setBitsCount = 0;
        for (uint256 i = 0; i < nextBitIndex; ++i) {
            if (mask.get(i)) {
                if (bitIndexToCollection[i] != address(0)) {
                    setBitsCount++;
                }
            }
        }

        if (setBitsCount == 0) {
            return new address[](0);
        }

        address[] memory activeCollections = new address[](setBitsCount);
        uint256 counter = 0;
        for (uint256 i = 0; i < nextBitIndex; ++i) {
            if (mask.get(i)) {
                address collection = bitIndexToCollection[i];
                if (collection != address(0)) {
                    activeCollections[counter] = collection;
                    counter++;
                }
            }
            if (counter == setBitsCount) break;
        }
        return activeCollections;
    }

    function previewRewards(address user, address[] calldata nftCollections)
        external
        view
        override
        returns (uint256 pendingReward)
    {
        uint256 numNftCollections = nftCollections.length;
        if (numNftCollections == 0) {
            return 0;
        }

        // Loop for simulatedUpdates validation is removed.
        // Synchronization is expected to be handled before calling preview or claim functions.

        uint256 totalRawPendingReward = 0;
        uint256 currentIndex = globalRewardIndex; // Use the current stored global index for preview

        uint256 cLen = nftCollections.length;
        for (uint256 i = 0; i < cLen;) {
            address collection = nftCollections[i];
            if (!isCollectionWhitelisted(collection)) {
                revert IRewardsController.CollectionNotWhitelisted(collection);
            }
            // Call _getRawPendingRewardsSingleCollection without simulatedUpdates
            (uint256 rewardForCollection,) = _getRawPendingRewardsSingleCollection(user, collection, currentIndex);
            totalRawPendingReward += rewardForCollection;
            unchecked {
                ++i;
            }
        }

        pendingReward = totalRawPendingReward;
        return pendingReward;
    }

    function getWhitelistedCollections() external view override returns (address[] memory) {
        return _whitelistedCollections.values();
    }

    function getUserSnapshotsLength(address user, address collection) external view override returns (uint256) {
        return userSnapshots[user][collection].length;
    }

    // START --- NEW CLAIMING FUNCTIONS ---
    function claimRewardsForCollection(address _collection, address _user)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 totalClaimedAmount)
    {
        if (!_whitelistedCollections.contains(_collection)) {
            revert IRewardsController.CollectionNotWhitelisted(_collection);
        }
        if (_user == address(0)) revert IRewardsController.AddressZero();

        // Ensure user's state is up-to-date with global state.
        // This is a critical step. If the user's balance data is stale (i.e., not reflecting the latest
        // global updates processed by the authorized updater), their reward calculation might be incorrect.
        // The `userLastSyncedNonce` tracks the `globalUpdateNonce` at which the user's data was last consistent.
        // If `userLastSyncedNonce[user]` != `globalUpdateNonce`, it implies there are pending balance updates
        // from the authorized updater that haven't been reflected in this user's snapshot data yet.
        // The spec implies that `syncAndClaim` was handling this.
        // For the new model, the expectation is that the user's state *is* synced before calling claim.
        // This might be handled off-chain or by a separate sync function if needed.
        // For now, we'll proceed with the assumption that the caller ensures state is synced,
        // or we add a check similar to the old one.
        // The spec: "The claim functions will first ensure that the snapshot data for the user and collection(s) is synchronized."
        // This implies the claim function itself should handle or trigger synchronization.
        // However, the new function signatures do not include parameters for signed updates.
        // This suggests a design where synchronization is a prerequisite or handled by a different mechanism.
        // Re-evaluating: The spec says "ensure ... synchronized". This could mean reverting if not synced.
        if (userLastSyncedNonce[_user] != globalUpdateNonce) {
            emit StaleClaimAttempt(_user, userLastSyncedNonce[_user], globalUpdateNonce);
            revert("STALE_BALANCES_SYNC_REQUIRED"); // Or a more specific error
        }

        // 1. Update Global Reward Index
        uint256 currentGlobalIdx = _calculateAndUpdateGlobalIndex();

        // 2. Calculate rewards for the user and the specific collection.
        // This internal function will handle snapshot processing and reward calculation.
        totalClaimedAmount = _calculateAndClaimRewardsForCollection(_user, _collection, currentGlobalIdx);

        emit RewardsClaimedForCollection(_user, _collection, totalClaimedAmount);
        return totalClaimedAmount;
    }

    function claimRewardsForAllCollections(address _user)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 grandTotalClaimedAmount)
    {
        if (_user == address(0)) revert IRewardsController.AddressZero();

        if (userLastSyncedNonce[_user] != globalUpdateNonce) {
            emit StaleClaimAttempt(_user, userLastSyncedNonce[_user], globalUpdateNonce);
            revert("STALE_BALANCES_SYNC_REQUIRED");
        }

        // 1. Update Global Reward Index (once for all collections in this transaction)
        uint256 currentGlobalIdx = _calculateAndUpdateGlobalIndex();
        grandTotalClaimedAmount = 0;

        address[] memory activeCollections = getUserNFTCollections(_user);
        if (activeCollections.length == 0) {
            // No rewards to claim if the user is not active in any collection.
            // RewardsClaimedForAll event is not emitted here as per spec (only RewardsClaimedForCollection)
            return 0;
        }

        uint256 totalRewardToRequestFromLendingManager = 0;
        ClaimData[] memory claims = new ClaimData[](activeCollections.length);

        // First pass: Calculate all rewards to determine total to request from LendingManager
        for (uint256 i = 0; i < activeCollections.length; i++) {
            address collection = activeCollections[i];
            UserRewardState storage info = userRewardState[_user][collection];
            uint256 previousDeficit = info.accruedReward;

            // This function will now only calculate, not claim directly from LM
            (uint256 rewardForPeriod, uint256 indexUsed) =
                _getRawPendingRewardsSingleCollection(_user, collection, currentGlobalIdx);

            uint256 totalDueForCollection = rewardForPeriod + previousDeficit;
            claims[i] = ClaimData({
                collectionAddress: collection,
                individualReward: totalDueForCollection,
                indexUsed: indexUsed
            });
            totalRewardToRequestFromLendingManager += totalDueForCollection;
        }

        if (totalRewardToRequestFromLendingManager == 0) {
            for (uint256 i = 0; i < activeCollections.length; i++) {
                address collection = claims[i].collectionAddress;
                UserRewardState storage info = userRewardState[_user][collection];
                info.accruedReward = 0;
                info.lastRewardIndex = claims[i].indexUsed;
                if (block.number > type(uint32).max) revert("RewardsController: block.number overflows uint32");
                info.lastUpdateBlock = uint32(block.number);
                delete userSnapshots[_user][collection]; // Clear snapshots after processing
                // Emit event even for 0 claim to signify processing
                emit RewardsClaimedForCollection(_user, collection, 0);
            }
            return 0;
        }

        // Request total batch transfer from LendingManager
        uint256 totalYieldReceived = lendingManager.transferYield(totalRewardToRequestFromLendingManager, _user);
        // The spec for ILendingManager.transferYield implies it transfers the full amount or reverts.
        // If it can transfer less, we need to handle apportionment.
        // Assuming it transfers `totalYieldReceived <= totalRewardToRequestFromLendingManager`

        uint256 actuallyClaimedAndDistributed = 0;

        // Second pass: Distribute received yield and update states
        for (uint256 i = 0; i < activeCollections.length; i++) {
            address collection = claims[i].collectionAddress;
            uint256 totalDueForThisCollection = claims[i].individualReward;
            uint256 indexUsed = claims[i].indexUsed;
            UserRewardState storage info = userRewardState[_user][collection];

            uint256 amountToDistributeToCollection;
            if (totalRewardToRequestFromLendingManager == 0) {
                // Avoid division by zero
                amountToDistributeToCollection = 0;
            } else {
                // Apportion the received yield based on the collection's share of the total due
                amountToDistributeToCollection =
                    Math.mulDiv(totalDueForThisCollection, totalYieldReceived, totalRewardToRequestFromLendingManager);
            }

            if (amountToDistributeToCollection > totalDueForThisCollection) {
                // Should not happen if mulDiv is correct and totalYieldReceived <= totalRewardToRequestFromLendingManager
                amountToDistributeToCollection = totalDueForThisCollection;
            }

            _updateUserRewardStateAfterClaim(
                _user, collection, amountToDistributeToCollection, totalDueForThisCollection, indexUsed
            );
            delete userSnapshots[_user][collection]; // Clear snapshots after processing

            emit RewardsClaimedForCollection(_user, collection, amountToDistributeToCollection);
            actuallyClaimedAndDistributed += amountToDistributeToCollection;
        }

        // If there's a difference due to rounding or partial transfer from LM, it remains as dust or deficit.
        // The `_updateUserRewardStateAfterClaim` handles deficit.
        // Any overall positive dust (totalYieldReceived > actuallyClaimedAndDistributed due to rounding down in mulDiv)
        // could be added to globalDustBucket if desired, though current logic doesn't explicitly do this for batch.
        // For simplicity, we assume LendingManager transfers what it can, and we distribute that proportionally.

        grandTotalClaimedAmount = actuallyClaimedAndDistributed;
        return grandTotalClaimedAmount;
    }

    // Placeholder for the internal function that will contain the core logic
    // for calculating and effecting the claim for a single collection.
    function _calculateAndClaimRewardsForCollection(address _user, address _collection, uint256 _currentGlobalIndex)
        internal
        returns (uint256 claimedAmount)
    {
        UserRewardState storage info = userRewardState[_user][_collection];
        uint256 previousDeficit = info.accruedReward;

        (uint256 rewardForPeriod, uint256 indexUsed) =
            _getRawPendingRewardsSingleCollection(_user, _collection, _currentGlobalIndex);

        uint256 totalDue = rewardForPeriod + previousDeficit;

        if (totalDue == 0) {
            _updateUserRewardStateAfterClaim(_user, _collection, 0, 0, indexUsed);
            delete userSnapshots[_user][_collection];
            return 0;
        }

        uint256 actualYieldReceived = lendingManager.transferYield(totalDue, _user);

        if (actualYieldReceived < totalDue) {
            // This case should ideally be handled by LendingManager reverting or by a batch transfer mechanism
            // that allows partial success. If transferYield can return less without reverting,
            // then the deficit logic in _updateUserRewardStateAfterClaim is crucial.
            emit YieldTransferCapped(_user, _collection, totalDue, actualYieldReceived);
        }

        _updateUserRewardStateAfterClaim(_user, _collection, actualYieldReceived, totalDue, indexUsed);
        delete userSnapshots[_user][_collection]; // Clear snapshots after processing

        return actualYieldReceived;
    }

    // END --- NEW CLAIMING FUNCTIONS ---

    function claimMultiple(address nftCollection, uint256[] calldata snapshotIDs) public nonReentrant whenNotPaused {
        require(snapshotIDs.length <= MAX_SNAPSHOTS_PER_CLAIM, "TOO_MANY_SNAPSHOTS");
        address user = msg.sender;

        if (userLastSyncedNonce[user] != globalUpdateNonce) {
            emit StaleClaimAttempt(user, userLastSyncedNonce[user], globalUpdateNonce);
            revert("STALE_BALANCES");
        }

        // TODO: Implement actual logic for claiming based on snapshotIDs (Item 2.2 Paginate bitmap traversal)
        // This function is a placeholder for now, focusing on the MAX_SNAPSHOTS_PER_CLAIM check.
        // Full implementation would involve processing snapshotIDs to calculate and transfer rewards.

        emit RewardsClaimedForCollection(user, nftCollection, 0); // Placeholder emit
    }

    // syncAndClaim is removed as per refactor.
    // The new model expects synchronization to be handled prior to or at the beginning of claim calls,
    // or potentially by a separate dedicated sync function if complex off-chain state is involved.
    // The current implementation of new claim functions includes a check for `userLastSyncedNonce`.

    function _getRawPendingRewardsSingleCollection( // Signature changed to remove simulatedUpdates
    address user, address nftCollection, uint256 currentGlobalIndex)
        internal
        view
        returns (uint256 totalRawReward, uint256 finalCalculatedIndex)
    {
        UserRewardState storage currentUserState = userRewardState[user][nftCollection];
        IRewardsController.RewardSnapshot[] storage snapshots = userSnapshots[user][nftCollection];
        uint256 numSnapshots = snapshots.length;
        uint256 rewardSharePercentage = collectionConfigs[nftCollection].rewardSharePercentage;

        totalRawReward = 0;

        // Iterate over stored historical snapshots to calculate rewards for past, completed segments.
        for (uint256 i = 0; i < numSnapshots; ++i) {
            IRewardsController.RewardSnapshot memory histSnapshot = snapshots[i];

            uint256 histSegmentNftBalance = histSnapshot.nftBalance;
            uint256 histSegmentBalance = histSnapshot.balance;
            uint256 histSegmentStartIndex = histSnapshot.index;
            uint256 histSegmentEndIndex;

            if (i + 1 < numSnapshots) {
                histSegmentEndIndex = snapshots[i + 1].index;
            } else {
                histSegmentEndIndex = currentUserState.lastRewardIndex;
            }

            if (histSegmentEndIndex > histSegmentStartIndex) {
                uint256 indexDelta = histSegmentEndIndex - histSegmentStartIndex;
                totalRawReward += _calculateRewardsWithDelta(
                    nftCollection,
                    indexDelta,
                    histSegmentStartIndex,
                    histSegmentNftBalance,
                    histSegmentBalance,
                    rewardSharePercentage
                );
            }
        }

        // Balances for the "live" segment are taken directly from the current user state.
        // Synchronization of this state is assumed to have happened before calling claim functions.
        uint256 finalSegmentNftBalance = currentUserState.lastNFTBalance;
        uint256 finalSegmentBalance = currentUserState.lastBalance;

        // Calculate reward for the final segment (from last actual update/snapshot up to currentGlobalIndex)
        if (currentGlobalIndex > currentUserState.lastRewardIndex) {
            uint256 indexDelta = currentGlobalIndex - currentUserState.lastRewardIndex;
            totalRawReward += _calculateRewardsWithDelta(
                nftCollection,
                indexDelta,
                currentUserState.lastRewardIndex, // Starting index for this final segment
                finalSegmentNftBalance, // Current state balances
                finalSegmentBalance, // Current state balances
                rewardSharePercentage
            );
        }

        finalCalculatedIndex = currentGlobalIndex;
        return (totalRawReward, finalCalculatedIndex);
    }

    function _updateUserRewardStateAfterClaim(
        address user,
        address nftCollection,
        uint256 claimedAmount,
        uint256 totalDue,
        uint256 indexUsedForClaim
    ) internal {
        UserRewardState storage info = userRewardState[user][nftCollection];

        if (claimedAmount < totalDue) {
            uint256 newAccruedReward = totalDue - claimedAmount;
            info.accruedReward = uint128(newAccruedReward);
        } else {
            info.accruedReward = 0;
        }

        info.lastRewardIndex = indexUsedForClaim;
        info.lastUpdateBlock = uint32(block.number);
    }

    uint256 public epochDuration;

    function setEpochDuration(uint256 newDuration) external override onlyOwner whenNotPaused {
        if (newDuration == 0) revert IRewardsController.InvalidEpochDuration();
        uint256 oldDuration = epochDuration;
        epochDuration = newDuration;
        emit EpochDurationChanged(oldDuration, newDuration, owner());
    }

    function updateGlobalIndex() external whenNotPaused {
        _calculateAndUpdateGlobalIndex();
    }

    function sweepDust(address recipient) external override onlyOwner nonReentrant whenNotPaused {
        if (recipient == address(0)) revert AddressZero();
        uint256 dustAmount = globalDustBucket;
        if (dustAmount == 0) {
            return;
        }

        globalDustBucket = 0;
        bool success = rewardToken.transfer(recipient, dustAmount);
        if (success) {
            emit DustSwept(recipient, dustAmount);
        } else {
            globalDustBucket = dustAmount;
        }
    }

    // --- Pausable Functions ---

    /**
     * @notice Pauses the contract.
     * @dev This function can only be called by the owner.
     * All pausable functions will revert when the contract is paused.
     * Emits a {Paused} event.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev This function can only be called by the owner.
     * All pausable functions will resume normal operation when unpaused.
     * Emits an {Unpaused} event.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    uint256[37] private __gap; // Adjusted gap due to new state variable from PausableUpgradeable
}
