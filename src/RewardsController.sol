/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
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
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";

contract RewardsController is
    Initializable,
    IRewardsController,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
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

    bytes32 public constant BALANCE_UPDATES_ARRAYS_TYPEHASH = keccak256(
        "BalanceUpdates(address[] users,address[] collections,uint256[] blockNumbers,int256[] nftDeltas,int256[] balanceDeltas,uint256 nonce)"
    );

    bytes32 public constant BALANCE_UPDATE_DATA_TYPEHASH =
        keccak256("BalanceUpdateData(address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)");
    bytes32 public constant USER_BALANCE_UPDATES_TYPEHASH =
        keccak256("UserBalanceUpdates(address user,BalanceUpdateData[] updates,uint256 nonce)");

    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private constant MAX_REWARD_SHARE_PERCENTAGE = 10000;
    uint8 private constant MAX_COLLECTIONS_BITMAP = 255;

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

    uint256 public globalRewardIndex;

    event SingleUpdateProcessed(
        address indexed user,
        address indexed collection,
        uint256 blockNumber,
        int256 nftDelta,
        uint32 finalNFTBalance,
        int256 balanceDelta,
        uint128 finalBalance
    );

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

    function setAuthorizedUpdater(address _newUpdater) external override onlyOwner {
        if (_newUpdater == address(0)) revert IRewardsController.AddressZero();
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
    }

    function removeNFTCollection(address collection) external override onlyOwner {
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
    }

    function updateBeta(address collection, uint256 newBeta)
        external
        override
        onlyOwner
        onlyWhitelistedCollection(collection)
    {
        if (newBeta > type(uint96).max) revert InvalidBetaValue(newBeta);
        CollectionConfig storage config = collectionConfigs[collection];
        uint256 oldBeta = config.beta;
        config.beta = uint96(newBeta);
        emit BetaUpdated(collection, oldBeta, newBeta);
    }

    function setCollectionRewardSharePercentage(address collection, uint256 newSharePercentage)
        external
        override
        onlyOwner
        onlyWhitelistedCollection(collection)
    {
        if (newSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) revert IRewardsController.InvalidRewardSharePercentage();
        CollectionConfig storage config = collectionConfigs[collection];
        uint256 oldSharePercentage = config.rewardSharePercentage;
        config.rewardSharePercentage = uint16(newSharePercentage);
        emit CollectionRewardShareUpdated(collection, oldSharePercentage, newSharePercentage);
    }

    function processBalanceUpdates(
        address signer,
        address[] calldata users,
        address[] calldata collections,
        uint256[] calldata blockNumbers,
        int256[] calldata nftDeltas,
        int256[] calldata balanceDeltas,
        bytes calldata signature
    ) external override nonReentrant {
        uint256 numUpdates = users.length;
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

    function processUserBalanceUpdates(
        address signer,
        address user,
        BalanceUpdateData[] calldata updates,
        bytes calldata signature
    ) external override nonReentrant {
        uint256 numUpdates = updates.length;
        if (numUpdates == 0) revert IRewardsController.EmptyBatch();

        if (signer != authorizedUpdater) {
            revert IRewardsController.InvalidSignature();
        }

        uint256 nonce = authorizedUpdaterNonce[signer];

        bytes32 updatesHash = _hashBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        bytes memory signatureBytes = signature;
        (address recoveredSigner, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signatureBytes);

        if (err != ECDSA.RecoverError.NoError || recoveredSigner != signer) {
            revert IRewardsController.InvalidSignature();
        }

        authorizedUpdaterNonce[signer]++;

        uint256 uLen = updates.length;
        for (uint256 i = 0; i < uLen;) {
            BalanceUpdateData memory currentUpdate = updates[i];
            if (!_whitelistedCollections.contains(currentUpdate.collection)) {
                revert IRewardsController.CollectionNotWhitelisted(currentUpdate.collection);
            }
            _processSingleUpdate(
                user,
                currentUpdate.collection,
                currentUpdate.blockNumber,
                currentUpdate.nftDelta,
                currentUpdate.balanceDelta
            );
            unchecked {
                ++i;
            }
        }

        emit UserBalanceUpdatesProcessed(user, nonce, uLen);
    }

    function _hashBalanceUpdates(BalanceUpdateData[] calldata updates) internal pure returns (bytes32) {
        uint256 numUpdates = updates.length;
        bytes32[] memory encodedUpdates = new bytes32[](numUpdates);
        for (uint256 i = 0; i < numUpdates;) {
            BalanceUpdateData memory currentUpdate = updates[i];
            encodedUpdates[i] = keccak256(
                abi.encode(
                    BALANCE_UPDATE_DATA_TYPEHASH,
                    currentUpdate.collection,
                    currentUpdate.blockNumber,
                    currentUpdate.nftDelta,
                    currentUpdate.balanceDelta
                )
            );
            unchecked {
                ++i;
            }
        }
        return keccak256(abi.encodePacked(encodedUpdates));
    }

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
            info.lastRewardIndex = globalRewardIndex;
            if (updateBlock > type(uint32).max) revert("RewardsController: updateBlock overflows uint32");
            info.lastUpdateBlock = uint32(updateBlock);
        }

        uint256 newNFTBalance = _applyDelta(info.lastNFTBalance, nftDelta);
        if (newNFTBalance > type(uint32).max) revert("RewardsController: newNFTBalance overflows uint32");
        info.lastNFTBalance = uint32(newNFTBalance);

        uint256 newBalance = _applyDelta(info.lastBalance, balanceDelta);
        if (newBalance > type(uint128).max) revert("RewardsController: newBalance overflows uint128");
        info.lastBalance = uint128(newBalance);

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

    function _calculateAndUpdateGlobalIndex() internal returns (uint256 currentIndex) {
        uint256 accrualResult = cToken.accrueInterest();
        accrualResult;

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

    function previewRewards(
        address user,
        address[] calldata nftCollections,
        BalanceUpdateData[] calldata simulatedUpdates
    ) external view override returns (uint256 pendingReward) {
        uint256 numNftCollections = nftCollections.length;
        if (numNftCollections == 0) {
            return 0;
        }

        uint256 numSimulatedUpdates = simulatedUpdates.length;
        for (uint256 _i = 0; _i < numSimulatedUpdates;) {
            BalanceUpdateData memory _update = simulatedUpdates[_i];
            UserRewardState storage _info = userRewardState[user][_update.collection];
            uint256 _lastProcessed = _info.lastUpdateBlock;
            if (_update.blockNumber < _lastProcessed) {
                revert SimulationUpdateOutOfOrder(_update.blockNumber, _lastProcessed);
            }
            unchecked {
                ++_i;
            }
        }
        uint256 totalRawPendingReward = 0;

        uint256 currentIndex = globalRewardIndex;

        uint256 cLen = nftCollections.length;
        for (uint256 i = 0; i < cLen;) {
            address collection = nftCollections[i];
            if (!isCollectionWhitelisted(collection)) {
                revert IRewardsController.CollectionNotWhitelisted(collection);
            }
            (uint256 rewardForCollection,) =
                _getRawPendingRewardsSingleCollection(user, collection, simulatedUpdates, currentIndex);
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

    function claimRewardsForCollection(address nftCollection, BalanceUpdateData[] calldata simulatedUpdates)
        external
        override
        nonReentrant
        onlyWhitelistedCollection(nftCollection)
    {
        address user = msg.sender;

        uint256 currentIndex = _calculateAndUpdateGlobalIndex();

        UserRewardState storage info = userRewardState[user][nftCollection];
        uint256 previousDeficit = info.accruedReward;

        (uint256 rewardForPeriod, uint256 indexUsed) =
            _getRawPendingRewardsSingleCollection(user, nftCollection, simulatedUpdates, currentIndex);

        uint256 totalDue = rewardForPeriod + previousDeficit;

        if (totalDue == 0) {
            info.accruedReward = 0;
            info.lastRewardIndex = indexUsed;
            if (block.number > type(uint32).max) revert("RewardsController: block.number overflows uint32");
            info.lastUpdateBlock = uint32(block.number);
            emit RewardsClaimedForCollection(user, nftCollection, 0);
            return;
        }

        uint256 actualYieldReceived = lendingManager.transferYield(totalDue, user);

        if (actualYieldReceived < totalDue) {
            emit YieldTransferCapped(user, totalDue, actualYieldReceived);
        }

        _updateUserRewardStateAfterClaim(user, nftCollection, actualYieldReceived, totalDue, indexUsed);

        emit RewardsClaimedForCollection(user, nftCollection, actualYieldReceived);
    }

    function claimRewardsForAll(BalanceUpdateData[] calldata simulatedUpdates) external override nonReentrant {
        address user = msg.sender;
        BitMaps.BitMap storage mask = userActiveMasks[user];
        uint256 localNextBitIndex = nextBitIndex;

        if (localNextBitIndex == 0) {
            emit RewardsClaimedForAll(user, 0);
            return;
        }

        ClaimData[] memory claims = new ClaimData[](localNextBitIndex);
        uint256 actualActiveCollectionCount = 0;
        uint256 totalRewardToRequest = 0;
        uint32 bn = uint32(block.number);

        uint256 currentIndex = _calculateAndUpdateGlobalIndex();

        for (uint256 i = 0; i < localNextBitIndex;) {
            bool isMaskSet = mask.get(i);

            if (isMaskSet) {
                address collectionFromBitIndex = bitIndexToCollection[i];

                if (collectionFromBitIndex == address(0)) {
                    mask.unset(i);
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                UserRewardState storage info = userRewardState[user][collectionFromBitIndex];
                uint256 previousDeficit = info.accruedReward;

                (uint256 rewardForPeriod, uint256 indexUsedForCalc) =
                    _getRawPendingRewardsSingleCollection(user, collectionFromBitIndex, simulatedUpdates, currentIndex);

                uint256 totalDueForCollection = rewardForPeriod + previousDeficit;

                claims[actualActiveCollectionCount] = ClaimData({
                    collectionAddress: collectionFromBitIndex,
                    individualReward: totalDueForCollection,
                    indexUsed: indexUsedForCalc
                });
                totalRewardToRequest += totalDueForCollection;
                actualActiveCollectionCount++;
            }
            unchecked {
                ++i;
            }
        }

        if (actualActiveCollectionCount == 0) {
            emit RewardsClaimedForAll(user, 0);
            return;
        }

        if (totalRewardToRequest == 0) {
            for (uint256 i = 0; i < actualActiveCollectionCount;) {
                UserRewardState storage info = userRewardState[user][claims[i].collectionAddress];
                info.accruedReward = 0;
                info.lastRewardIndex = claims[i].indexUsed;
                info.lastUpdateBlock = bn;
                unchecked {
                    ++i;
                }
            }
            emit RewardsClaimedForAll(user, 0);
            return;
        }

        address[] memory collectionsToTransfer = new address[](actualActiveCollectionCount);
        uint256[] memory amountsToTransfer = new uint256[](actualActiveCollectionCount);
        for (uint256 i = 0; i < actualActiveCollectionCount;) {
            collectionsToTransfer[i] = claims[i].collectionAddress;
            amountsToTransfer[i] = claims[i].individualReward;
            unchecked {
                ++i;
            }
        }

        uint256 totalYieldReceived =
            lendingManager.transferYieldBatch(collectionsToTransfer, amountsToTransfer, totalRewardToRequest, user);

        if (totalYieldReceived < totalRewardToRequest) {
            emit YieldTransferCapped(user, totalRewardToRequest, totalYieldReceived);
        }

        if (totalYieldReceived >= totalRewardToRequest) {
            for (uint256 i = 0; i < actualActiveCollectionCount;) {
                UserRewardState storage info = userRewardState[user][claims[i].collectionAddress];
                info.accruedReward = 0;
                info.lastRewardIndex = claims[i].indexUsed;
                info.lastUpdateBlock = bn;
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i = 0; i < actualActiveCollectionCount;) {
                UserRewardState storage info = userRewardState[user][claims[i].collectionAddress];
                uint256 totalDueForThisCollection = claims[i].individualReward;

                uint256 deficitForCollection = Math.mulDiv(
                    totalDueForThisCollection, (totalRewardToRequest - totalYieldReceived), totalRewardToRequest
                );

                if (deficitForCollection <= 1 && totalDueForThisCollection > 0) {
                    deficitForCollection = 0;
                }
                info.accruedReward = uint128(deficitForCollection);
                info.lastRewardIndex = claims[i].indexUsed;
                info.lastUpdateBlock = bn;
                unchecked {
                    ++i;
                }
            }
        }
        emit RewardsClaimedForAll(user, totalYieldReceived);
    }

    function _getRawPendingRewardsSingleCollection(
        address user,
        address nftCollection,
        BalanceUpdateData[] memory simulatedUpdates,
        uint256 currentIndex
    ) internal view returns (uint256 totalRawReward, uint256 calculatedIndex) {
        UserRewardState storage info = userRewardState[user][nftCollection];

        if (block.number <= info.lastUpdateBlock) {
            return (0, currentIndex);
        }

        uint256 rewardSharePercentage = collectionConfigs[nftCollection].rewardSharePercentage;

        uint256 segmentStartIndex = info.lastRewardIndex;
        uint256 segmentNFTBalance = info.lastNFTBalance;
        uint256 segmentBalance = info.lastBalance;

        totalRawReward = 0;

        uint256 numSimulatedUpdates_2 = simulatedUpdates.length;
        for (uint256 i = 0; i < numSimulatedUpdates_2;) {
            BalanceUpdateData memory update = simulatedUpdates[i];

            if (update.blockNumber < info.lastUpdateBlock) {
                revert SimulationUpdateOutOfOrder(update.blockNumber, info.lastUpdateBlock);
            }

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
            unchecked {
                ++i;
            }
        }

        if (currentIndex > segmentStartIndex) {
            uint256 indexDelta = currentIndex - segmentStartIndex;
            totalRawReward = _calculateRewardsWithDelta(
                nftCollection, indexDelta, segmentStartIndex, segmentNFTBalance, segmentBalance, rewardSharePercentage
            );
        }

        calculatedIndex = currentIndex;
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

    function setEpochDuration(uint256 newDuration) external override onlyOwner {
        if (newDuration == 0) revert IRewardsController.InvalidEpochDuration();
        epochDuration = newDuration;
    }

    function updateUserRewardStateForTesting(
        address user,
        address collection,
        uint256 blockNumber,
        uint256 rewardIndex,
        uint256 accruedRewardParam
    ) external {
        UserRewardState storage info = userRewardState[user][collection];
        if (blockNumber > type(uint32).max) revert("RewardsController: blockNumber overflows uint32 in testing");
        info.lastUpdateBlock = uint32(blockNumber);
        info.lastRewardIndex = rewardIndex;
        if (accruedRewardParam > type(uint128).max) {
            revert("RewardsController: accruedRewardParam overflows uint128 in testing");
        }
        info.accruedReward = uint128(accruedRewardParam);
    }

    /**
     * @notice Externally callable function to trigger an update of the globalRewardIndex.
     * Useful for ensuring the index is current before view calls in testing scenarios
     * or if an external system needs to ensure the index reflects latest cToken state.
     */
    function updateGlobalIndex() external {
        _calculateAndUpdateGlobalIndex();
    }

    uint256[39] private __gap;
}
