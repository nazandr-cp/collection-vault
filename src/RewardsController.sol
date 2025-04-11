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
// import {INFTDataUpdater} from "./interfaces/INFTDataUpdater.sol"; // Interface not strictly needed here if only address is stored

/**
 * @title RewardsController
 * @notice Manages reward calculation and distribution, incorporating NFT-based bonus multipliers.
 * @dev Implements IRewardsController. Tracks user NFT balances, calculates yield (base + bonus),
 *      and distributes rewards by pulling base yield from the LendingManager.
 */
contract RewardsController is IRewardsController, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- Constants --- //
    uint256 private constant PRECISION_FACTOR = 1e18; // For fixed-point math if needed

    // --- State Variables --- //

    ILendingManager public immutable lendingManager;
    IERC20 public immutable rewardToken; // The token distributed as rewards (should be same as LM asset)
    INFTRegistry public nftRegistry; // Address of the NFT registry/oracle
    // address public nftDataUpdater; // Optional: Store address if needed for auth checks

    // NFT Collection Management
    EnumerableSet.AddressSet private _whitelistedCollections;
    mapping(address => uint256) public collectionBetas; // collection => beta (reward coefficient)

    // User Reward Tracking
    // user => (collection => UserNFTInfo)
    mapping(address => mapping(address => UserNFTInfo)) public userNFTData;
    // Optional: Track which collections a user has interacted with for efficient iteration in claimAll
    // user => EnumerableSet.AddressSet (collections user is active in)
    mapping(address => EnumerableSet.AddressSet) private _userActiveCollections;

    // Global Reward State (Simplified Example - assumes yield accrues linearly based on LM balance)
    uint256 public globalRewardIndex; // Similar to Compound's supplyIndex, tracks reward per unit of underlying
    uint256 public lastDistributionBlock;

    // --- Events (Defined in IRewardsController) --- //

    // --- Errors --- //
    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidBetaValue();
    error CallerNotOwnerOrUpdater(); // If using specific updater auth
    error ArrayLengthMismatch();
    error InsufficientYieldFromLendingManager();
    error NoRewardsToClaim();
    error NormalizationError(); // If normalization fails
    error NFTRegistryNotSet();

    // --- Modifiers --- //
    modifier onlyWhitelistedCollection(address collection) {
        if (!_whitelistedCollections.contains(collection)) {
            revert CollectionNotWhitelisted(collection);
        }
        _;
    }

    // --- Constructor --- //
    constructor(address initialOwner, address _lendingManagerAddress, address _nftRegistryAddress)
        Ownable(initialOwner)
    {
        if (_lendingManagerAddress == address(0) || _nftRegistryAddress == address(0)) revert AddressZero();
        lendingManager = ILendingManager(_lendingManagerAddress);
        rewardToken = lendingManager.asset(); // Rewards are paid in the underlying token
        if (address(rewardToken) == address(0)) revert AddressZero(); // LM must return valid asset

        nftRegistry = INFTRegistry(_nftRegistryAddress); // Set NFT Registry

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
        // Emit an event if desired
    }

    /**
     * @notice Adds a new NFT collection to the whitelist and sets its beta coefficient.
     * @param collection The address of the NFT collection.
     * @param beta The reward coefficient (e.g., scaled by PRECISION_FACTOR).
     */
    function addNFTCollection(address collection, uint256 beta) external override onlyOwner {
        if (collection == address(0)) revert AddressZero();
        // require(beta > 0, "Beta must be positive"); // Add validation as needed
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
        // Consider cleanup of userNFTData for this collection if necessary (gas intensive)
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
        // require(newBeta > 0, "Beta must be positive");
        uint256 oldBeta = collectionBetas[collection];
        collectionBetas[collection] = newBeta;
        emit BetaUpdated(collection, oldBeta, newBeta);
    }

    // --- NFT Update Functions (Callable by NFTDataUpdater or Owner) --- //

    /**
     * @notice Updates the NFT balance for a user and collection, triggering reward state update.
     * @dev Needs access control (e.g., check msg.sender == nftDataUpdater or owner).
     */
    function updateNFTBalance(address user, address nftCollection, uint256 currentBalance)
        external
        override
        onlyWhitelistedCollection(nftCollection)
    // modifier onlyUpdaterOrOwner() // Add modifier if needed
    {
        // require(msg.sender == nftDataUpdater || msg.sender == owner(), "Caller not authorized");

        // Update global rewards first (before user state)
        _updateGlobalRewardIndex();

        // Update user's specific reward state for this collection
        _updateUserRewardState(user, nftCollection, currentBalance);

        // Add collection to user's active set if not already present
        _userActiveCollections[user].add(nftCollection);
    }

    /**
     * @notice Batch update for NFT balances.
     */
    function updateNFTBalances(address user, address[] calldata nftCollections, uint256[] calldata currentBalances)
        external
        override
    // modifier onlyUpdaterOrOwner()
    {
        // require(msg.sender == nftDataUpdater || msg.sender == owner(), "Caller not authorized");
        uint256 len = nftCollections.length;
        if (len != currentBalances.length) revert ArrayLengthMismatch();

        // Update global rewards first (before user state)
        _updateGlobalRewardIndex();

        for (uint256 i = 0; i < len; ++i) {
            address collection = nftCollections[i];
            // Ensure collection is whitelisted before processing
            if (_whitelistedCollections.contains(collection)) {
                uint256 balance = currentBalances[i];
                _updateUserRewardState(user, collection, balance);
                // Add collection to user's active set if not already present
                _userActiveCollections[user].add(collection);
            } else {
                // Optional: Emit an event or handle non-whitelisted updates
            }
        }
    }

    // --- Internal Reward Calculation Logic (Lazy Update) --- //

    /**
     * @notice Updates the global reward index based on yield from the LendingManager.
     * @dev Calculates yield generated since the last update and increases the index.
     *      This assumes base yield accrues linearly based on LM balance and R0.
     *      A more accurate model might involve Compound's actual exchange rate changes.
     */
    function _updateGlobalRewardIndex() internal {
        uint256 blockDelta = block.number - lastDistributionBlock;
        if (blockDelta == 0) {
            return; // No blocks passed, no new yield
        }

        // Get current base reward rate from Lending Manager
        // uint256 baseRewardPerBlock = lendingManager.getBaseRewardPerBlock(); // Unused for now
        // uint256 totalBaseReward = baseRewardPerBlock * blockDelta; // Unused for now

        // Placeholder logic - uses total assets directly
        uint256 totalManagedAssets = lendingManager.totalAssets();

        if (totalManagedAssets > 0) {
            // Increase = (totalBaseReward * PRECISION_FACTOR) / totalManagedAssets
            // uint256 indexIncrease = (totalBaseReward * PRECISION_FACTOR) / totalManagedAssets; // Commented out - depends on totalBaseReward
            // globalRewardIndex += indexIncrease; // Commented out
            // --- Replace with placeholder logic if needed --- //
            // Example: Simplistic index increase based on time only (remove later)
            globalRewardIndex += blockDelta * 1; // Placeholder
        }

        lastDistributionBlock = block.number;
    }

    /**
     * @notice Updates the reward state (accrued base + bonus) for a specific user and collection.
     * @dev This is the core lazy update function called on interactions or explicit updates.
     * @param user The user address.
     * @param collection The NFT collection address.
     * @param currentNFTBalance The user's *current* NFT balance for the collection.
     */
    function _updateUserRewardState(address user, address collection, uint256 currentNFTBalance) internal {
        UserNFTInfo storage userInfo = userNFTData[user][collection];
        uint256 lastBlock = userInfo.lastUpdateBlock;
        uint256 currentBlock = block.number;
        uint256 blockDelta = currentBlock - lastBlock;

        console.log("-- Contract Log: _updateUserRewardState --");
        console.log("User:", user);
        console.log("Collection:", collection);
        console.log("Current Block:", currentBlock);
        console.log("Last Update Block (before calc):", lastBlock);
        console.log("Block Delta:", blockDelta);
        console.log("Current NFT Balance:", currentNFTBalance);
        console.log("Last NFT Balance (before calc):", userInfo.lastNFTBalance);
        console.log("Accrued Bonus (before calc):", userInfo.accruedBonus);

        if (blockDelta == 0 && userInfo.lastNFTBalance == currentNFTBalance) {
            if (lastBlock == 0) userInfo.lastUpdateBlock = currentBlock;
            console.log("No time passed, no balance change. Returning.");
            return;
        }

        // --- 1. Calculate Accrued Base Reward --- //
        // Base reward depends on the global index change and the user's effective "stake" (shares)
        // THIS IS A SIMPLIFICATION - In ERC4626, base yield accrues to the *vault* shares.
        // The RewardsController handles the *bonus* distribution on top of the base ERC4626 yield.
        // Let's rethink: Base reward is handled implicitly by ERC4626 totalAssets increase.
        // RewardsController *only* calculates and distributes the *bonus* part based on NFTs.

        // --- 2. Calculate Accrued Bonus Reward --- //
        uint256 accruedBonusAmount = 0;
        uint256 lastBalance = userInfo.lastNFTBalance;
        uint256 beta = collectionBetas[collection];

        if (blockDelta > 0 && beta > 0 && lastBalance > 0) {
            // Only accrue bonus if they had NFTs previously
            // Calculate base yield generated during the period (using the global rate for simplicity)
            // This base yield is what the bonus multiplier applies to.
            // uint256 baseRewardPerBlock = lendingManager.getBaseRewardPerBlock(); // Get current rate // Unused for now

            // We need totalAssets to figure out the proportion
            // THIS IS STILL COMPLEX - let's simplify the bonus calculation for now.
            // Assume bonus = beta * normalized_nft_balance * block_delta * some_base_factor
            // Let base_factor be related to the global yield rate?

            // Simplified Bonus Logic: bonus_per_block = beta * lastNFTBalance (needs normalization/scaling)
            // This is very basic, needs refinement based on spec: ΔNFT * β * normalize()
            // int256 deltaNFT = int256(currentNFTBalance) - int256(lastBalance); // Unused for now
            // TODO: Implement normalization function - how to handle negative delta?
            // For now, let's assume bonus applies only when balance > 0 and uses lastBalance.
            if (lastBalance > 0) {
                // Simple bonus: beta * balance * time (needs scaling)
                // Let's use a placeholder calculation - needs proper definition
                uint256 bonusPerBlock = (beta * lastBalance * PRECISION_FACTOR) / PRECISION_FACTOR; // Needs scaling factor
                accruedBonusAmount = bonusPerBlock * blockDelta;
                console.log("Calculated Bonus Per Block:", bonusPerBlock);
                console.log("Calculated Accrued Bonus Amount:", accruedBonusAmount);
            }
        }

        // Update user info
        userInfo.accruedBonus += accruedBonusAmount;
        userInfo.lastUpdateBlock = currentBlock;
        userInfo.lastNFTBalance = currentNFTBalance;

        console.log("Accrued Bonus (after calc):", userInfo.accruedBonus);
        console.log("Last Update Block (after calc):", userInfo.lastUpdateBlock);
        console.log("Last NFT Balance (after calc):", userInfo.lastNFTBalance);

        emit NFTBalanceUpdated(user, collection, currentNFTBalance, lastBalance, currentBlock);
    }

    // --- Claim Functions --- //

    /**
     * @notice Claims the accrued bonus rewards for a specific user and a single NFT collection.
     * @param nftCollection The address of the NFT collection to claim rewards for.
     */
    function claimRewardsForCollection(address nftCollection)
        external
        override
        nonReentrant
        onlyWhitelistedCollection(nftCollection)
    {
        address user = msg.sender;
        if (address(nftRegistry) == address(0)) revert NFTRegistryNotSet();

        // 1. Update global reward state (affects base calculation if done here, but primarily for bonus consistency)
        _updateGlobalRewardIndex();

        // 2. Fetch current NFT balance and update user's reward state for this collection
        uint256 currentBalance = _getCurrentNFTBalance(user, nftCollection);
        _updateUserRewardState(user, nftCollection, currentBalance);

        // 3. Get total accruedBonus for the collection
        UserNFTInfo storage userInfo = userNFTData[user][nftCollection];
        uint256 bonusToClaim = userInfo.accruedBonus;

        if (bonusToClaim == 0) {
            revert NoRewardsToClaim();
        }

        // 4. Reset accruedBonus for the collection BEFORE transfer
        userInfo.accruedBonus = 0;

        // 5. Request bonus payout from LendingManager
        // LM's transferYield should handle getting the underlying tokens (e.g., via redeem)
        bool success = lendingManager.transferYield(bonusToClaim, user);
        if (!success) {
            // Revert state change if transfer fails
            userInfo.accruedBonus = bonusToClaim; // Restore bonus
            revert InsufficientYieldFromLendingManager(); // Or a more specific error from LM
        }

        // 6. Emit event
        emit RewardsClaimedForCollection(user, nftCollection, bonusToClaim);
    }

    /**
     * @notice Claims the accrued bonus rewards for a specific user across all their active/whitelisted NFT collections.
     */
    function claimRewardsForAll() external override nonReentrant {
        address user = msg.sender;
        if (address(nftRegistry) == address(0)) revert NFTRegistryNotSet();

        // 1. Update global reward state
        _updateGlobalRewardIndex();

        uint256 totalBonusToClaim = 0;
        address[] memory activeCollections = _userActiveCollections[user].values();
        uint256 numCollections = activeCollections.length;

        if (numCollections == 0) {
            revert NoRewardsToClaim(); // User has no active collections tracked
        }

        // 2. Iterate through user's active collections, update state, and sum bonuses
        for (uint256 i = 0; i < numCollections; ++i) {
            address collection = activeCollections[i];
            // Double-check if collection is still whitelisted (could be removed)
            if (_whitelistedCollections.contains(collection)) {
                // 3. Fetch current balance and update user state
                uint256 currentBalance = _getCurrentNFTBalance(user, collection);
                _updateUserRewardState(user, collection, currentBalance);

                // 4. Add accrued bonus to total and prepare for reset
                totalBonusToClaim += userNFTData[user][collection].accruedBonus;
            }
        }

        if (totalBonusToClaim == 0) {
            revert NoRewardsToClaim();
        }

        // 5. Reset accruedBonus for all *processed* collections BEFORE transfer
        // We do this in a separate loop to avoid partial resets if the transfer fails mid-loop
        for (uint256 i = 0; i < numCollections; ++i) {
            address collection = activeCollections[i];
            // Only reset if it was whitelisted and potentially contributed
            if (_whitelistedCollections.contains(collection)) {
                userNFTData[user][collection].accruedBonus = 0;
            }
        }

        // 6. Request total bonus payout from LendingManager
        bool success = lendingManager.transferYield(totalBonusToClaim, user);
        if (!success) {
            // Revert the reset - THIS IS DIFFICULT TO DO EFFICIENTLY
            // A snapshot mechanism or re-calculating might be needed for atomicity.
            // For now, we revert, but the state is partially modified (bonuses zeroed).
            // Consider patterns like Checks-Effects-Interactions carefully.
            revert InsufficientYieldFromLendingManager();
        }

        // 7. Emit event
        emit RewardsClaimedForAll(user, totalBonusToClaim);
    }

    // --- View Functions --- //

    /**
     * @notice Calculates the pending bonus rewards for a specific user and collection without claiming.
     * @dev Simulates the state update to return the currently claimable bonus.
     *      Base reward is handled implicitly by the vault.
     */
    function getPendingRewards(address user, address nftCollection)
        external
        view
        override
        onlyWhitelistedCollection(nftCollection)
        returns (uint256 pendingBaseReward, uint256 pendingBonusReward)
    {
        if (address(nftRegistry) == address(0)) return (0, 0); // Cannot calculate without registry

        UserNFTInfo memory userInfo = userNFTData[user][nftCollection];
        uint256 lastBlock = userInfo.lastUpdateBlock;
        uint256 blockDelta = block.number - lastBlock;

        // Simulate current NFT balance fetch
        // uint256 currentNFTBalance = _getCurrentNFTBalance(user, nftCollection); // Commented out - unused

        uint256 accruedBonusAmount = 0;
        uint256 lastBalance = userInfo.lastNFTBalance;
        uint256 beta = collectionBetas[nftCollection];

        // Simulate the bonus calculation logic from _updateUserRewardState
        if (blockDelta > 0 && beta > 0 && lastBalance > 0) {
            // int256 deltaNFT = int256(currentNFTBalance) - int256(lastBalance); // Unused for now
            // Placeholder logic - align with _updateUserRewardState's final logic
            if (lastBalance > 0) {
                uint256 bonusPerBlock = (beta * lastBalance * PRECISION_FACTOR) / PRECISION_FACTOR; // Needs scaling factor adjustment
                accruedBonusAmount = bonusPerBlock * blockDelta;
            }
        }

        pendingBaseReward = 0; // Base reward is implicit in vault shares
        pendingBonusReward = userInfo.accruedBonus + accruedBonusAmount;

        return (pendingBaseReward, pendingBonusReward);
    }

    function getUserNFTInfo(address user, address nftCollection) external view override returns (UserNFTInfo memory) {
        return userNFTData[user][nftCollection];
    }

    function getWhitelistedCollections() external view override returns (address[] memory) {
        return _whitelistedCollections.values();
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

    // --- Helper Functions --- //

    /**
     * @dev Placeholder function to get the current NFT balance.
     * Replace with actual call to NFT Registry/Oracle.
     */
    function _getCurrentNFTBalance(address user, address collection) internal view returns (uint256) {
        if (address(nftRegistry) == address(0)) {
            // If no registry set, cannot determine balance
            // Returning 0 might be misleading, but necessary for simulation
            // Consider reverting or specific handling
            return 0;
        }
        // Assumes INFTRegistry has a balanceOf(user, collectionId) function
        return nftRegistry.balanceOf(user, collection);
    }

    /**
     * @dev Placeholder for NFT balance change normalization.
     * TODO: Define the actual normalization logic (absolute, percent, capped, etc.).
     */
    function _normalizeDelta(int256 deltaNFT) internal pure returns (uint256 normalizedValue) {
        // Example: Simple absolute value calculation for int256
        uint256 absDelta = uint256(deltaNFT >= 0 ? deltaNFT : -deltaNFT);

        // Apply scaling or capping as per specification
        // require(absDelta < SOME_MAX_VALUE, "Delta too large");
        // TODO: Define the actual normalization logic
        if (absDelta > 1000) revert NormalizationError(); // Placeholder capping

        return absDelta; // Placeholder: Returns absolute value, capped
    }
}
