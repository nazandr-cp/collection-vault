// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.2.0/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin-contracts-5.2.0/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin-contracts-5.2.0/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {INFTRegistry} from "./interfaces/INFTRegistry.sol";
import {IERC4626VaultMinimal} from "./interfaces/IERC4626VaultMinimal.sol";

/**
 * @title RewardsController
 * @notice Manages reward calculation and distribution, incorporating NFT-based bonus multipliers.
 * @dev Implements IRewardsController. Tracks user NFT balances, calculates yield (base + bonus),
 *      and distributes rewards by pulling base yield from the LendingManager.
 */
contract RewardsController is IRewardsController, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- Local Structs --- //
    /**
     * @notice Struct to hold reward tracking data per user per collection.
     * @dev Mirrors relevant fields needed for internal logic, distinct from IRewardsController.UserNFTInfo if necessary.
     */
    struct UserRewardState {
        uint256 accruedBaseReward; // Store base and bonus separately
        uint256 accruedBonusReward;
        uint256 lastRewardIndex;
        uint256 lastNFTBalance;
        uint256 lastDepositAmount;
        uint256 lastUpdateBlock; // Track block number of last update
    }

    // --- Constants --- //
    uint256 private constant PRECISION_FACTOR = 1e18;

    // --- State Variables --- //

    ILendingManager public immutable lendingManager;
    IERC4626VaultMinimal public immutable vault;
    IERC20 public immutable rewardToken; // The token distributed as rewards (should be same as LM asset)
    INFTRegistry public nftRegistry; // Address of the NFT registry/oracle
    // address public nftDataUpdater; // Optional: Store address if needed for auth checks

    // NFT Collection Management
    EnumerableSet.AddressSet private _whitelistedCollections;
    mapping(address => uint256) public collectionBetas; // collection => beta (reward coefficient)

    // User Reward Tracking
    mapping(address => mapping(address => UserRewardState)) public userNFTData; // Use local struct
    mapping(address => EnumerableSet.AddressSet) private _userActiveCollections;

    // Global Reward State
    uint256 public globalRewardIndex;
    uint256 public lastDistributionBlock;

    // --- Errors --- //
    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidBetaValue();
    error CallerNotOwnerOrUpdater();
    error ArrayLengthMismatch();
    error InsufficientYieldFromLendingManager();
    error NoRewardsToClaim();
    error NormalizationError();
    error NFTRegistryNotSet();
    error VaultMismatch();

    // --- Events --- //
    // Events are inherited from IRewardsController

    // --- Modifiers --- //
    modifier onlyWhitelistedCollection(address collection) {
        if (!_whitelistedCollections.contains(collection)) {
            revert CollectionNotWhitelisted(collection);
        }
        _;
    }

    // --- Constructor --- //
    constructor(
        address initialOwner,
        address _lendingManagerAddress,
        address _nftRegistryAddress,
        address _vaultAddress
    ) Ownable(initialOwner) {
        if (_lendingManagerAddress == address(0) || _nftRegistryAddress == address(0) || _vaultAddress == address(0)) {
            revert AddressZero();
        }

        lendingManager = ILendingManager(_lendingManagerAddress);
        vault = IERC4626VaultMinimal(_vaultAddress);
        rewardToken = lendingManager.asset();

        if (address(rewardToken) == address(0)) revert AddressZero();
        if (vault.asset() != address(rewardToken)) revert VaultMismatch();

        nftRegistry = INFTRegistry(_nftRegistryAddress);

        lastDistributionBlock = block.number;
        globalRewardIndex = PRECISION_FACTOR;
    }

    // --- Admin Functions --- //

    /**
     * @notice Sets the address of the NFT Registry contract.
     */
    function setNFTRegistry(address _nftRegistryAddress) external onlyOwner {
        if (_nftRegistryAddress == address(0)) revert AddressZero();
        nftRegistry = INFTRegistry(_nftRegistryAddress);
    }

    /**
     * @notice Adds a new NFT collection to the whitelist and sets its beta coefficient.
     * @param collection The address of the NFT collection.
     * @param beta The reward coefficient (e.g., scaled by PRECISION_FACTOR).
     */
    function addNFTCollection(address collection, uint256 beta) external override onlyOwner {
        if (collection == address(0)) revert AddressZero();
        if (!_whitelistedCollections.add(collection)) {
            revert CollectionAlreadyExists(collection);
        }
        collectionBetas[collection] = beta;
        emit NFTCollectionAdded(collection, beta);
    }

    /**
     * @notice Removes an NFT collection from the whitelist.
     */
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

    /**
     * @notice Updates the beta coefficient for an existing whitelisted NFT collection.
     */
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

    // --- NFT Update Functions --- //

    /**
     * @notice Updates the NFT balance for a user and collection, triggering reward state update.
     */
    function updateNFTBalance(address user, address nftCollection, uint256 newNFTBalance)
        external
        override
        onlyWhitelistedCollection(nftCollection)
    {
        // require(msg.sender == nftDataUpdater || msg.sender == owner(), "Caller not authorized");

        uint256 currentDeposit = vault.deposits(user, nftCollection);
        // Fetch last balance *before* updating state
        uint256 lastBalance = userNFTData[user][nftCollection].lastNFTBalance;
        _updateGlobalRewardIndex();
        _updateUserRewardState(user, nftCollection, newNFTBalance, currentDeposit);
        _userActiveCollections[user].add(nftCollection);
        emit NFTBalanceUpdated(user, nftCollection, newNFTBalance, lastBalance, block.number);
    }

    /**
     * @notice Batch update for NFT balances.
     */
    function updateNFTBalances(address user, address[] calldata nftCollections, uint256[] calldata newNFTBalances)
        external
        override
    {
        // require(msg.sender == nftDataUpdater || msg.sender == owner(), "Caller not authorized");
        uint256 len = nftCollections.length;
        if (len != newNFTBalances.length) revert ArrayLengthMismatch();

        _updateGlobalRewardIndex();

        for (uint256 i = 0; i < len; ++i) {
            address collection = nftCollections[i];
            if (_whitelistedCollections.contains(collection)) {
                uint256 newBalance = newNFTBalances[i];
                uint256 currentDeposit = vault.deposits(user, collection);
                // Fetch last balance *before* updating state
                uint256 lastBalance = userNFTData[user][collection].lastNFTBalance;
                _updateUserRewardState(user, collection, newBalance, currentDeposit);
                _userActiveCollections[user].add(collection);
                emit NFTBalanceUpdated(user, collection, newBalance, lastBalance, block.number);
            }
        }
    }

    // --- Internal Reward Calculation Logic --- //

    /**
     * @notice Updates the global reward index based on time passed.
     * @dev Placeholder logic: Index increases linearly with blocks. Replace with actual yield logic.
     */
    function _updateGlobalRewardIndex() internal {
        uint256 blockDelta = block.number - lastDistributionBlock;
        if (blockDelta == 0) {
            return;
        }
        // Placeholder logic: Index increases by 1 (scaled) per block.
        globalRewardIndex += blockDelta * PRECISION_FACTOR;
        lastDistributionBlock = block.number;
    }

    /**
     * @notice Updates a user's reward state for a specific NFT collection.
     * @dev Calculates accrued rewards since the last update and stores the current state.
     */
    function _updateUserRewardState(
        address user,
        address nftCollection,
        uint256 newNFTBalance,
        uint256 currentDeposit // Pass deposit amount explicitly
    ) internal {
        UserRewardState storage info = userNFTData[user][nftCollection]; // Use local struct

        // --- Calculate rewards for the period ending now ---
        (uint256 baseReward, uint256 bonusReward) =
            _calculateAccruedRewards(nftCollection, info.lastRewardIndex, info.lastNFTBalance, info.lastDepositAmount);

        info.accruedBaseReward += baseReward;
        info.accruedBonusReward += bonusReward;

        // --- Update state for the *next* period ---
        info.lastRewardIndex = globalRewardIndex;
        info.lastNFTBalance = newNFTBalance; // Update with the new balance for the *next* period
        info.lastDepositAmount = currentDeposit; // Update with the deposit amount for the *next* period
        info.lastUpdateBlock = block.number; // Store current block number
    }

    /**
     * @notice Calculates the rewards accrued for a user's position since the last update.
     * @dev Uses the global index delta and the user's previous state (balance, deposit).
     */
    function _calculateAccruedRewards(
        address nftCollection, // Need collection to get beta
        uint256 lastUserIndex,
        uint256 lastNFTBalance,
        uint256 lastDepositAmount
    ) internal view returns (uint256 baseReward, uint256 bonusReward) {
        uint256 indexDelta = globalRewardIndex - lastUserIndex;
        // Return 0 rewards if index hasn't changed or if the user had no NFTs in the last period
        if (indexDelta == 0 || lastNFTBalance == 0) {
            return (0, 0);
        }

        // Calculate base reward only if conditions above are met
        baseReward = (lastDepositAmount * indexDelta) / PRECISION_FACTOR;

        // Bonus reward calculation remains conditional on lastNFTBalance > 0
        if (lastNFTBalance > 0) {
            uint256 beta = collectionBetas[nftCollection]; // Fetches the beta for the specific collection
            uint256 boostFactor = calculateBoost(lastNFTBalance, beta); // Calculate boost factor (scaled by 1e18)

            // Bonus reward = baseReward * boostFactor / precision
            bonusReward = (baseReward * boostFactor) / PRECISION_FACTOR;
        } else {
            // This case should technically not be reached due to the check above, but kept for clarity
            bonusReward = 0;
        }

        return (baseReward, bonusReward);
    }

    // --- Claiming --- //

    /**
     * @notice Claims accumulated rewards for a specific user and NFT collection.
     * @dev Updates reward state, pulls yield from LendingManager, and transfers rewards. Requires user to hold NFTs.
     */
    function claimRewardsForCollection(address nftCollection)
        external
        override
        nonReentrant
        onlyWhitelistedCollection(nftCollection)
    {
        address user = msg.sender;
        if (nftRegistry == INFTRegistry(address(0))) revert NFTRegistryNotSet();

        // Check if user currently holds any NFTs for this collection before proceeding
        uint256 currentNFTBalanceCheck = nftRegistry.balanceOf(user, nftCollection);
        if (currentNFTBalanceCheck == 0) {
            revert NoRewardsToClaim(); // Revert if user has no NFTs in this collection currently
        }

        // 1. Update Global Index
        _updateGlobalRewardIndex();

        // 2. Update User State and get total accrued reward
        // Fetch current NFT balance and deposit amount for the *final* update
        uint256 currentNFTBalance = nftRegistry.balanceOf(user, nftCollection); // Use balanceOf (re-fetch for state update)
        uint256 currentDeposit = vault.deposits(user, nftCollection);

        _updateUserRewardState(user, nftCollection, currentNFTBalance, currentDeposit); // Update using current values
        uint256 rewardAmount =
            userNFTData[user][nftCollection].accruedBaseReward + userNFTData[user][nftCollection].accruedBonusReward;

        // Reset *before* potential failure points (transfer/yield pull)
        userNFTData[user][nftCollection].accruedBaseReward = 0;
        userNFTData[user][nftCollection].accruedBonusReward = 0;

        if (rewardAmount == 0) {
            // If rewards were 0 after update, no need to revert, just exit cleanly.
            // Revert here only if the state *before* update showed rewards.
            // However, simpler to just revert if amount is 0 after update & reset.
            revert NoRewardsToClaim();
        }

        // 4. Check available yield in Lending Manager (optional but good practice)
        // This check is simplistic. A robust system might track distributable yield separately.
        // uint256 availableYield = lendingManager.getAvailableYield(); // Hypothetical function
        // if (rewardAmount > availableYield) {
        //     revert InsufficientYieldFromLendingManager();
        // }

        // 5. Pull yield from Lending Manager to this contract
        // Assume LM allows this controller to pull yield. Requires LM interface/implementation.
        bool success = lendingManager.transferYield(rewardAmount, address(this)); // Call transferYield to this contract
        if (!success) {
            // Revert state changes if pull fails? Or just revert the transfer?
            // Reverting only the transfer is simpler but leaves state updated.
            // For now, revert the whole transaction.
            revert InsufficientYieldFromLendingManager(); // Use a more specific error if LM provides one
        }

        // 6. Transfer Reward to User
        rewardToken.safeTransfer(user, rewardAmount);

        emit RewardsClaimedForCollection(user, nftCollection, rewardAmount); // Emit event AFTER successful transfer
    }

    /**
     * @notice Claims rewards for all collections a user has interacted with.
     * @dev Iterates through the user's active collections and calls claimReward internally (conceptually).
     *      Actual implementation avoids reentrancy by calculating total and doing one pull/transfer.
     */
    function claimRewardsForAll() external override nonReentrant {
        address user = msg.sender;
        if (nftRegistry == INFTRegistry(address(0))) revert NFTRegistryNotSet();

        // 1. Update Global Index (once)
        _updateGlobalRewardIndex();

        uint256 totalRewardAmount = 0;
        EnumerableSet.AddressSet storage activeCollections = _userActiveCollections[user];
        uint256 numActiveCollections = activeCollections.length();

        // 2. Calculate total rewards across all active collections
        for (uint256 i = 0; i < numActiveCollections; ++i) {
            address collection = activeCollections.at(i);
            // Fetch current state for final update calculation
            uint256 currentNFTBalance = nftRegistry.balanceOf(user, collection); // Use balanceOf
            uint256 currentDeposit = vault.deposits(user, collection);

            // Update state and add accrued reward to total
            _updateUserRewardState(user, collection, currentNFTBalance, currentDeposit);
            totalRewardAmount +=
                userNFTData[user][collection].accruedBaseReward + userNFTData[user][collection].accruedBonusReward;
            // Reset accrued reward for this collection (Do this *after* loop, before transfers)
            userNFTData[user][collection].accruedBaseReward = 0;
            userNFTData[user][collection].accruedBonusReward = 0;
        }

        // Reset all rewards *before* transfers/yield pull
        for (uint256 i = 0; i < numActiveCollections; ++i) {
            address collection = activeCollections.at(i);
            userNFTData[user][collection].accruedBaseReward = 0;
            userNFTData[user][collection].accruedBonusReward = 0;
        }

        if (totalRewardAmount == 0) {
            revert NoRewardsToClaim();
        }

        // 4. Check available yield (optional)
        // uint256 availableYield = lendingManager.getAvailableYield();
        // if (totalRewardAmount > availableYield) {
        //     revert InsufficientYieldFromLendingManager();
        // }

        // 5. Pull total yield from Lending Manager
        bool success = lendingManager.transferYield(totalRewardAmount, address(this)); // Call transferYield to this contract
        if (!success) {
            revert InsufficientYieldFromLendingManager();
        }

        // 6. Transfer total reward to User
        rewardToken.safeTransfer(user, totalRewardAmount);

        emit RewardsClaimedForAll(user, totalRewardAmount); // Emit event AFTER successful transfer
    }

    // --- View Functions --- //

    /**
     * @notice Checks if an NFT collection is whitelisted.
     */
    function isCollectionWhitelisted(address collection) external view returns (bool) {
        return _whitelistedCollections.contains(collection);
    }

    /**
     * @notice Returns the list of all whitelisted NFT collections.
     */
    function getWhitelistedCollections() external view override returns (address[] memory) {
        return _whitelistedCollections.values();
    }

    /**
     * @notice Calculates the pending rewards for a user and collection without updating state.
     * @dev Simulates the reward calculation based on current global index and user's last state.
     */
    function getPendingRewards(address user, address nftCollection)
        external
        view
        override
        onlyWhitelistedCollection(nftCollection)
        returns (uint256 pendingBaseReward, uint256 pendingBonusReward)
    {
        // Simulate global index update to current block
        uint256 blockDelta = block.number - lastDistributionBlock;
        uint256 currentGlobalIndex = globalRewardIndex;
        if (blockDelta > 0) {
            // Apply placeholder logic
            currentGlobalIndex += blockDelta * PRECISION_FACTOR;
            /* // Original logic (replace placeholder if needed)
            uint256 totalManagedAssets = lendingManager.totalAssets();
            if (totalManagedAssets > 0) {
                // uint256 baseRewardPerBlock = lendingManager.getBaseRewardPerBlock();
                // uint256 totalBaseReward = baseRewardPerBlock * blockDelta;
                // uint256 indexIncrease = (totalBaseReward * PRECISION_FACTOR) / totalManagedAssets;
                // currentGlobalIndex += indexIncrease;
                currentGlobalIndex += blockDelta * 1; // Placeholder
            }
            */
        }

        UserRewardState storage info = userNFTData[user][nftCollection]; // Use local struct

        // Calculate potential new rewards based on the simulated current index
        uint256 indexDelta = currentGlobalIndex - info.lastRewardIndex;
        if (indexDelta == 0) {
            // No new rewards accrued, return currently stored amounts
            return (info.accruedBaseReward, info.accruedBonusReward);
        }

        // Calculate newly accrued rewards based on the *last* state and the *simulated* indexDelta
        uint256 newlyAccruedBase = (info.lastDepositAmount * indexDelta) / PRECISION_FACTOR;
        uint256 newlyAccruedBonus = 0;

        if (info.lastNFTBalance > 0) {
            uint256 beta = collectionBetas[nftCollection];
            uint256 boostFactor = calculateBoost(info.lastNFTBalance, beta);
            newlyAccruedBonus = (newlyAccruedBase * boostFactor) / PRECISION_FACTOR;
        }

        // Total pending = stored accrued + newly accrued (simulated)
        pendingBaseReward = info.accruedBaseReward + newlyAccruedBase;
        pendingBonusReward = info.accruedBonusReward + newlyAccruedBonus;
        return (pendingBaseReward, pendingBonusReward);
    }

    /**
     * @notice Calculates the NFT boost factor based on balance and beta.
     * @dev Placeholder implementation. Replace with actual boost logic.
     */
    function calculateBoost(uint256 nftBalance, uint256 beta) public pure returns (uint256 boostFactor) {
        // Placeholder: Boost is proportional to NFT balance and beta
        // Ensure results are scaled correctly (e.g., by PRECISION_FACTOR)
        // Example: boostFactor = (nftBalance * beta * BOOST_SCALAR) / PRECISION_FACTOR;
        // Need to define BOOST_SCALAR or adjust beta scaling.
        // For now, return 0 boost.
        // Assume beta is scaled by 1e18. Boost factor should also be scaled by 1e18.
        // E.g., boostFactor = 0.1 * 1e18 for 10% boost.
        boostFactor = nftBalance * beta; // Beta is already scaled by 1e18, representing boost per NFT
        if (boostFactor > PRECISION_FACTOR * 10) {
            // Add a sanity cap (e.g., 10x boost max)
            boostFactor = PRECISION_FACTOR * 10;
        }
        return boostFactor; // Return boost factor scaled by PRECISION_FACTOR
    }

    /**
     * @notice Retrieves the stored NFT tracking information for a user and collection.
     * @dev Implements the IRewardsController interface function.
     *      Note: Returns the interface struct, which might differ from internal state representation.
     */
    function getUserNFTInfo(address user, address nftCollection)
        external
        view
        override
        returns (IRewardsController.UserNFTInfo memory)
    {
        // Returns the *interface* struct, not the internal UserRewardState
        // Map internal state fields to the interface struct fields as needed.
        UserRewardState storage internalInfo = userNFTData[user][nftCollection];
        return IRewardsController.UserNFTInfo({
            lastUpdateBlock: internalInfo.lastUpdateBlock, // Return tracked block
            lastNFTBalance: internalInfo.lastNFTBalance,
            lastUserRewardIndex: internalInfo.lastRewardIndex // Map internal index name
                // Note: accruedReward is not part of the interface struct
        });
    }

    /**
     * @notice Retrieves the beta coefficient for a specific collection.
     * @dev Implements the IRewardsController interface function.
     */
    function getCollectionBeta(address nftCollection)
        external
        view
        override
        onlyWhitelistedCollection(nftCollection)
        returns (uint256)
    {
        return collectionBetas[nftCollection];
    }

    /**
     * @notice Retrieves the list of collections a user is actively being tracked for.
     * @dev Implements the IRewardsController interface function.
     */
    function getUserNFTCollections(address user) external view override returns (address[] memory) {
        return _userActiveCollections[user].values();
    }

    // --- Helper/Private Functions (Optional) --- //

    // Add any internal helper functions if needed, e.g., for complex boost calculations.
}
