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
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";

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

    // --- Structs ---
    struct CollectionConfig {
        IRewardsController.RewardBasis rewardBasis;
        uint96 beta;
        uint16 rewardSharePercentage;
    }

    // --- Constants ---
    bytes32 public constant CLAIM_REWARD_TYPEHASH =
        keccak256(
            "ClaimReward(address collection,address recipient,uint256 rewardAmount,uint256 nonce)"
        );

    bytes32 public constant CLAIM_ALL_REWARDS_TYPEHASH =
        keccak256(
            "ClaimAllRewards(address recipient,bytes32 collectionsHash,bytes32 rewardAmountsHash,uint256 nonce)"
        );

    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private constant MAX_REWARD_SHARE_PERCENTAGE = 10000;
    uint256 private constant MAX_BETA = 10000; // 100% in basis points

    // --- State Variables ---
    ILendingManager public override lendingManager;
    IERC4626 public override vault;
    IERC20 public override rewardToken;
    CTokenInterface internal cToken;
    address public override trustedSigner;
    uint16 public maxRewardSharePercentage = 10000; // Default to MAX_REWARD_SHARE_PERCENTAGE

    EnumerableSet.AddressSet private _whitelistedCollections;
    mapping(address => CollectionConfig) public collectionConfigs;
    mapping(address => mapping(address => uint256)) internal _userClaimedNonces;
    mapping(address => uint256) internal _globalUserNonces; // New mapping for simplified nonce handling
    // Global nonces are per-user instead of per-user-per-collection
    // This simplifies nonce management across multiple collections

    uint256 public override epochDuration;

    uint64 public override globalUpdateNonce;
    uint256 public globalDustBucket;

    // --- Modifiers ---
    modifier onlyWhitelistedCollection(address collection) {
        if (!_whitelistedCollections.contains(collection)) {
            revert IRewardsController.CollectionNotWhitelisted(collection);
        }
        _;
    }

    // --- Constructor & Initializer ---
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        address _lendingManagerAddress,
        address _vaultAddress,
        address _trustedSigner
    ) public initializer {
        if (initialOwner == address(0)) {
            revert RewardsControllerInvalidInitialOwner(address(0));
        }
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("RewardsController", "1");
        __Pausable_init();

        if (_lendingManagerAddress == address(0)) {
            revert IRewardsController.AddressZero();
        }
        if (_vaultAddress == address(0)) {
            revert IRewardsController.AddressZero();
        }
        if (_trustedSigner == address(0)) {
            revert IRewardsController.AddressZero();
        }

        lendingManager = ILendingManager(_lendingManagerAddress);
        vault = IERC4626(_vaultAddress);

        IERC20 _rewardToken = lendingManager.asset();
        if (address(_rewardToken) == address(0)) {
            revert IRewardsController.AddressZero();
        }

        address _vaultAsset = vault.asset();
        if (_vaultAsset == address(0)) revert IRewardsController.AddressZero();
        if (_vaultAsset != address(_rewardToken)) revert VaultMismatch();

        rewardToken = _rewardToken;
        trustedSigner = _trustedSigner;

        address _cTokenAddress = address(lendingManager.cToken());
        if (_cTokenAddress == address(0)) {
            revert IRewardsController.AddressZero();
        }
        cToken = CTokenInterface(_cTokenAddress);
    }

    function globalRewardIndex() external view override returns (uint256) {
        return 0; // Implement or adjust as needed
    }

    function userLastSyncedNonce(
        address
    ) external view override returns (uint64) {
        return 0; // Implement or adjust as needed
    }

    // --- State Variable Getters ---
    function userClaimedNonces(
        address user,
        address collection
    ) external view override returns (uint256) {
        return _userClaimedNonces[user][collection];
    }

    /**
     * @notice Returns the current global nonce for a user
     * @dev Used for simplified nonce handling, a user's nonce increases with each successful claim
     * @param user Address of the user
     * @return The current global nonce for the user
     */
    function getUserGlobalNonce(
        address user
    ) external view override returns (uint256) {
        return _globalUserNonces[user];
    }

    function collectionRewardBasis(
        address collection
    )
        external
        view
        override
        onlyWhitelistedCollection(collection)
        returns (IRewardsController.RewardBasis)
    {
        return collectionConfigs[collection].rewardBasis;
    }

    // --- Admin Functions ---
    function setTrustedSigner(
        address _newSigner
    ) external onlyOwner whenNotPaused {
        if (_newSigner == address(0)) revert IRewardsController.AddressZero();
        address oldSigner = trustedSigner;
        trustedSigner = _newSigner;
        emit TrustedSignerUpdated(oldSigner, _newSigner, owner());
    }

    function addNFTCollection(
        address collection,
        uint256 beta,
        IRewardsController.RewardBasis rewardBasis,
        uint256 rewardSharePercentage
    ) external override onlyOwner whenNotPaused {
        if (collection == address(0)) revert IRewardsController.AddressZero();
        if (_whitelistedCollections.contains(collection)) {
            revert IRewardsController.CollectionAlreadyExists(collection);
        }
        if (rewardSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) {
            revert IRewardsController.InvalidRewardSharePercentage();
        }
        if (beta > MAX_BETA) {
            revert IRewardsController.InvalidBetaValue(beta);
        }

        _whitelistedCollections.add(collection);
        collectionConfigs[collection] = CollectionConfig({
            rewardBasis: rewardBasis,
            beta: uint96(beta),
            rewardSharePercentage: uint16(rewardSharePercentage)
        });

        // Set the reward share percentage in the collections vault as well
        ICollectionsVault(address(vault)).setCollectionRewardSharePercentage(
            collection,
            uint16(rewardSharePercentage)
        );

        emit NFTCollectionAdded(
            collection,
            beta,
            rewardBasis,
            rewardSharePercentage
        );
    }

    function removeNFTCollection(
        address collection
    )
        external
        override
        onlyOwner
        whenNotPaused
        onlyWhitelistedCollection(collection)
    {
        _whitelistedCollections.remove(collection);
        delete collectionConfigs[collection];

        // Reset the reward share percentage in the collections vault
        ICollectionsVault(address(vault)).setCollectionRewardSharePercentage(
            collection,
            0
        );

        emit NFTCollectionRemoved(collection);
    }

    function updateBeta(
        address collection,
        uint256 newBeta
    )
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
    }

    function setEpochDuration(
        uint256 newDuration
    ) external override onlyOwner whenNotPaused {
        if (newDuration == 0) revert IRewardsController.InvalidEpochDuration();
        uint256 oldDuration = epochDuration;
        epochDuration = newDuration;
        emit EpochDurationChanged(oldDuration, newDuration, owner());
    }

    function setCollectionRewardSharePercentage(
        address collection,
        uint256 newSharePercentage
    )
        external
        override
        onlyOwner
        onlyWhitelistedCollection(collection)
        whenNotPaused
    {
        if (newSharePercentage > MAX_REWARD_SHARE_PERCENTAGE) {
            revert IRewardsController.InvalidRewardSharePercentage();
        }
        CollectionConfig storage config = collectionConfigs[collection];
        uint256 oldSharePercentage = config.rewardSharePercentage;
        config.rewardSharePercentage = uint16(newSharePercentage);

        // Update the reward share percentage in the collections vault as well
        ICollectionsVault(address(vault)).setCollectionRewardSharePercentage(
            collection,
            uint16(newSharePercentage)
        );

        emit CollectionRewardShareUpdated(
            collection,
            oldSharePercentage,
            newSharePercentage
        );
    }

    function setMaxRewardSharePercentage(
        uint16 newMaxSharePercentage
    ) external onlyOwner whenNotPaused {
        if (
            newMaxSharePercentage == 0 ||
            newMaxSharePercentage > MAX_REWARD_SHARE_PERCENTAGE
        ) {
            revert IRewardsController.InvalidRewardSharePercentage();
        }
        uint16 oldMaxSharePercentage = maxRewardSharePercentage;
        maxRewardSharePercentage = newMaxSharePercentage;
        emit MaxRewardSharePercentageUpdated(
            oldMaxSharePercentage,
            newMaxSharePercentage
        );
    }

    function sweepDust(
        address recipient
    ) external override onlyOwner nonReentrant whenNotPaused {
        if (recipient == address(0)) revert IRewardsController.AddressZero();
        uint256 dustAmount = globalDustBucket;
        if (dustAmount == 0) {
            return;
        }

        globalDustBucket = 0;
        // Using safeTransfer to be consistent, though rewardToken.transfer was used before.
        // Assuming rewardToken is a standard ERC20.
        rewardToken.safeTransfer(recipient, dustAmount);
        emit DustSwept(recipient, dustAmount);
        // safeTransfer will revert if the transfer fails.
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // --- View Functions ---
    function getCollectionData(
        address collection
    )
        external
        view
        override
        onlyWhitelistedCollection(collection)
        returns (
            uint256 beta,
            IRewardsController.RewardBasis rewardBasis,
            uint256 rewardSharePercentage
        )
    {
        CollectionConfig storage config = collectionConfigs[collection];
        return (config.beta, config.rewardBasis, config.rewardSharePercentage);
    }

    /**
     * @notice Calculates the boost factor based on NFT balance and beta value
     * @dev Uses Math.mulDiv for safe multiplication to prevent overflow
     * @param nftBalance Number of NFTs the user holds
     * @param beta Boost coefficient set for the collection (scaled by MAX_BETA)
     * @return boostFactor The calculated boost factor (capped at 900%)
     */
    function calculateBoost(
        uint256 nftBalance,
        uint256 beta
    ) external pure override returns (uint256 boostFactor) {
        if (nftBalance == 0) return 0;

        // Beta is uint256, ensure consistency with stored uint96 or cast appropriately
        // Using Math.mulDiv for safe multiplication to prevent overflow
        boostFactor = Math.mulDiv(nftBalance, beta, MAX_BETA);

        uint256 maxBoost = PRECISION_FACTOR * 9; // Max boost is 900%
        if (boostFactor > maxBoost) {
            boostFactor = maxBoost;
        }
        return boostFactor;
    }

    function getCollectionBeta(
        address nftCollection
    )
        external
        view
        override
        onlyWhitelistedCollection(nftCollection)
        returns (uint256)
    {
        return collectionConfigs[nftCollection].beta;
    }

    function getCollectionRewardBasis(
        address nftCollection
    )
        external
        view
        override
        onlyWhitelistedCollection(nftCollection)
        returns (IRewardsController.RewardBasis)
    {
        return collectionConfigs[nftCollection].rewardBasis;
    }

    function getCollectionRewardSharePercentage(
        address collection
    )
        external
        view
        override
        onlyWhitelistedCollection(collection)
        returns (uint256)
    {
        return collectionConfigs[collection].rewardSharePercentage;
    }

    function isCollectionWhitelisted(
        address collection
    ) external view override returns (bool) {
        return _whitelistedCollections.contains(collection);
    }

    function getWhitelistedCollections()
        external
        view
        override
        returns (address[] memory collections)
    {
        return _whitelistedCollections.values();
    }

    // --- Claiming Functions ---
    /**
     * @notice Claims rewards for a single NFT collection
     * @dev Uses the global user nonce for validation and EIP-712 for signature verification
     * @dev The _signer parameter is kept for backward compatibility but validation uses contract's trustedSigner
     * @param _collection Address of the NFT collection to claim rewards for
     * @param _recipient Address that will receive the rewards
     * @param _rewardAmount Amount of reward tokens to claim
     * @param _nonce A unique number that must be greater than the user's current global nonce
     * @param _signature EIP-712 signature from the trusted signer
     */
    function claimRewardsForCollection(
        address _collection,
        address _recipient,
        uint256 _rewardAmount,
        uint256 _nonce,
        bytes calldata _signature
    )
        external
        override
        nonReentrant
        whenNotPaused
        onlyWhitelistedCollection(_collection)
    {
        if (_collection == address(0)) revert IRewardsController.AddressZero();
        if (_recipient == address(0)) revert IRewardsController.AddressZero();

        // Removed the _signer parameter check as we'll verify against trusted signer directly

        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_REWARD_TYPEHASH,
                _collection,
                _recipient,
                _rewardAmount,
                _nonce
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);

        if (recoveredSigner != trustedSigner || recoveredSigner == address(0)) {
            revert IRewardsController.InvalidSignature();
        }

        uint256 lastGlobalNonce = _globalUserNonces[_recipient];
        if (_nonce <= lastGlobalNonce) {
            revert IRewardsController.InvalidNonce(_nonce, lastGlobalNonce);
        }
        _globalUserNonces[_recipient] = _nonce;

        // For backward compatibility, also update the collection-specific nonce
        _userClaimedNonces[_recipient][_collection] = _nonce;

        if (_rewardAmount > 0) {
            address[] memory collections = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            collections[0] = _collection;
            amounts[0] = _rewardAmount;
            ICollectionsVault(address(vault)).transferYieldBatch(
                collections,
                amounts,
                _rewardAmount,
                _recipient
            );
        }

        emit RewardsClaimed(_recipient, _collection, _rewardAmount, _nonce);
        emit RewardsIssued(_recipient, _collection, _rewardAmount, _nonce);
    }

    /**
     * @notice Claims rewards for multiple NFT collections in a single transaction
     * @dev Uses the global user nonce for validation and EIP-712 for signature verification
     * @dev The _signer parameter is kept for backward compatibility but validation uses contract's trustedSigner
     * @dev Emits individual RewardsIssued events for each collection and a single BatchRewardsIssued event
     * @param _recipient Address that will receive the rewards
     * @param _rewardAmountPerCollection Array of reward amounts for each collection
     * @param _collections Array of collection addresses to claim rewards for
     * @param _totalRewardAmount Sum of all reward amounts, used in signature verification
     * @param _nonce A unique number that must be greater than the user's current global nonce
     * @param _signature EIP-712 signature from the trusted signer
     */
    function claimRewardsForAllCollections(
        address _recipient,
        uint256[] calldata _rewardAmountPerCollection,
        address[] calldata _collections,
        uint256 _totalRewardAmount, // Used in signature
        uint256 _nonce,
        bytes calldata _signature
    ) external override nonReentrant whenNotPaused {
        if (_recipient == address(0)) revert IRewardsController.AddressZero();

        // Removed the _signer parameter check as we'll verify against trusted signer directly

        if (_collections.length != _rewardAmountPerCollection.length) {
            revert IRewardsController.ArrayLengthMismatch();
        }
        if (_collections.length == 0) {
            revert IRewardsController.CollectionsArrayEmpty();
        }

        // First, verify the global user nonce
        uint256 lastGlobalNonce = _globalUserNonces[_recipient];
        if (_nonce <= lastGlobalNonce) {
            revert IRewardsController.InvalidNonce(_nonce, lastGlobalNonce);
        }

        // The off-chain signature generation must match the hashing done here.
        bytes32 collectionsHash = keccak256(abi.encodePacked(_collections));
        bytes32 rewardAmountsHash = keccak256(
            abi.encodePacked(_totalRewardAmount)
        );

        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_ALL_REWARDS_TYPEHASH,
                _recipient,
                collectionsHash,
                rewardAmountsHash, // Ensure this matches what's signed
                _nonce
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);

        if (recoveredSigner != trustedSigner || recoveredSigner == address(0)) {
            revert IRewardsController.InvalidSignature();
        }

        // Set the new global nonce
        _globalUserNonces[_recipient] = _nonce;

        uint256 calculatedTotalRewardsToClaim = 0;
        for (uint256 i = 0; i < _collections.length; i++) {
            address collection = _collections[i];
            if (collection == address(0)) {
                revert IRewardsController.AddressZero();
            }
            if (!_whitelistedCollections.contains(collection)) {
                revert IRewardsController.CollectionNotWhitelisted(collection);
            }

            // Check if there's a collection-specific nonce that's higher than the provided nonce
            // This is for backward compatibility
            uint256 lastClaimedNonce = _userClaimedNonces[_recipient][
                collection
            ];
            if (_nonce <= lastClaimedNonce) {
                revert IRewardsController.InvalidNonce(
                    _nonce,
                    lastClaimedNonce
                );
            }

            uint256 rewardAmount = _rewardAmountPerCollection[i];
            calculatedTotalRewardsToClaim += rewardAmount;
        }

        // Verify calculatedTotalRewardsToClaim against _totalRewardAmount as a cross-check
        if (calculatedTotalRewardsToClaim != _totalRewardAmount) {
            revert IRewardsController.ArrayLengthMismatch();
        }

        // Prepare batch transfer of collection yield rewards
        if (calculatedTotalRewardsToClaim > 0) {
            // Create a batch transfer of yield via the Collections Vault
            ICollectionsVault(address(vault)).transferYieldBatch(
                _collections,
                _rewardAmountPerCollection,
                calculatedTotalRewardsToClaim,
                _recipient
            );
        }

        // Update nonces and emit events for each collection
        for (uint256 i = 0; i < _collections.length; i++) {
            address collection = _collections[i];
            uint256 rewardAmount = _rewardAmountPerCollection[i];

            // Update nonce for each collection as part of the "all collections" claim
            _userClaimedNonces[_recipient][collection] = _nonce;

            emit RewardsClaimed(_recipient, collection, rewardAmount, _nonce);
            emit RewardsIssued(_recipient, collection, rewardAmount, _nonce);
        }

        // Emit batch event
        emit BatchRewardsIssued(
            _recipient,
            _collections,
            _rewardAmountPerCollection,
            _nonce
        );
    }

    // --- Gap for Upgradeability ---
    uint256[30] private __gap;
}
