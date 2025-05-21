/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";

import {console} from "forge-std/console.sol";

contract RewardsController is
    Initializable,
    IRewardsController,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable, // ReentrancyGuardUpgradeable is already inherited, ReentrancyGuard is for non-upgradeable
    EIP712Upgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    /// @notice Contains internal information about a vault's reward state.
    /// @dev This struct mirrors `IRewardsController.VaultInfo` but is used for internal state management.
    struct InternalVaultInfo {
        /// @notice The amount of reward tokens generated per block for this vault.
        uint128 rewardPerBlock;
        /// @notice The global reward per unit of weight (per block).
        uint128 globalRPW;
        /// @notice The total accumulated weight of all users within this vault.
        uint128 totalWeight;
        /// @notice The block number when the vault's reward state was last updated.
        uint64 lastUpdateBlock;
        /// @notice The balance of the vault's asset at the last update, used to calculate yield.
        uint256 lastAssetsBalance;
    }

    /// @notice Stores internal account-specific data for reward calculation.
    /// @dev This struct consolidates fields from `IRewardsController.AccountInfo` and old `UserInfo`.
    struct AccountStorageData {
        /// @notice The calculated weight of the user's position in a specific collection.
        uint128 weight;
        /// @notice The accumulated reward debt for the user, used to track earned but unclaimed rewards.
        uint128 rewardDebt;
        /// @notice The total accrued rewards for the user, available for claiming.
        uint128 accrued;
        /// @notice A unique identifier for each claim, incremented after each successful claim.
        uint64 nonce;
        /// @notice The total seconds for which the user has been paid rewards.
        /// @dev This field's functional necessity should be reviewed.
        uint64 secondsPaid;
    }

    /// @notice The EIP-712 typehash for the `Claim` struct.
    /// @dev This typehash is used to verify signatures for reward claims.
    bytes32 private constant CLAIM_TYPEHASH = keccak256(
        "Claim(address account,address collection,uint256 secondsUser,uint256 secondsColl,uint256 incRPS,uint256 yieldSlice,uint256 nonce,uint256 deadline)"
    );
    /// @notice A precision factor used for fixed-point arithmetic, representing 1e18.
    uint256 private constant PRECISION_FACTOR = 1e18;
    /// @notice The maximum allowed percentage for collection reward shares, in Basis Points (10000 BPS = 100%).
    uint16 private constant MAX_REWARD_SHARE_PERCENTAGE = 10000;

    /// @notice The address of the price oracle used for emission caps.
    address internal immutable _priceOracle;
    /// @notice The address of the trusted signer for EIP-712 claim signatures.
    address internal _claimSigner;
    /// @notice The main collections vault contract.
    ICollectionsVault internal _vault;

    /// @notice Mapping from vault address to its internal reward information.
    mapping(address => InternalVaultInfo) internal _vaultsData;
    /// @notice Nested mapping from vault address to user address to their account storage data.
    mapping(address => mapping(address => AccountStorageData)) internal _accountStorage;

    /// @notice Mapping from collection address to its defined weight function.
    mapping(address => IRewardsController.WeightFunction) internal _collectionWeightFunctions;
    /// @notice Mapping from collection address to its reward share percentage in Basis Points (BPS).
    mapping(address => uint16) internal _collectionRewardSharePercentage;
    /// @notice The sum of all whitelisted collection reward share percentages in Basis Points (BPS).
    uint16 internal _totalCollectionShareBps;
    /// @notice Mapping from collection address to its reward basis (e.g., DEPOSIT, BORROW, FIXED_POOL).
    mapping(address => IRewardsController.RewardBasis) internal _collectionRewardBasis;
    /// @notice Mapping from collection address to its type (e.g., ERC721, ERC1155, ERC20).
    mapping(address => IRewardsController.CollectionType) internal _collectionType;
    /// @notice Flag indicating if a collection is whitelisted.
    mapping(address => bool) internal _isCollectionWhitelisted;
    /// @notice Stores balances for fixed pool collections.
    mapping(address => uint256) internal _fixedPoolCollectionBalances;

    /// @notice Thrown when a division by zero operation is attempted.
    error DivideByZero();

    /// @dev Initializes the RewardsController contract.
    /// @param priceOracleAddress_ The address of the price oracle.
    constructor(address priceOracleAddress_) {
        if (priceOracleAddress_ == address(0)) revert IRewardsController.AddressZero();
        _priceOracle = priceOracleAddress_;
        _disableInitializers();
    }

    /// @notice Initializes the RewardsController contract after deployment.
    /// @dev This function sets the initial owner, collections vault, and trusted claim signer.
    /// It also initializes the EIP-712 domain separator and sets the initial asset balance for the vault.
    /// @param initialOwner The address of the initial owner of the contract.
    /// @param vaultAddress_ The address of the `ICollectionsVault` contract.
    /// @param initialClaimSigner The address of the initial trusted signer for claims.
    function initialize(address initialOwner, ICollectionsVault vaultAddress_, address initialClaimSigner)
        public
        initializer
    {
        if (initialOwner == address(0) || address(vaultAddress_) == address(0) || initialClaimSigner == address(0)) {
            revert IRewardsController.AddressZero();
        }
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("RewardsController", "1"); // Domain separator for EIP712
        __Pausable_init();

        _vault = vaultAddress_;
        _claimSigner = initialClaimSigner;

        address vaultAsset_ = IERC4626(address(vaultAddress_)).asset();
        if (vaultAsset_ == address(0)) revert IRewardsController.VaultMismatch();

        // Initialize lastAssetsBalance for the main vault
        _vaultsData[address(vaultAddress_)].lastAssetsBalance = IERC20(vaultAsset_).balanceOf(address(this));
        _vaultsData[address(vaultAddress_)].lastUpdateBlock = uint64(block.number);
    }

    /// @notice Returns the address of the price oracle.
    /// @return The address of the price oracle.
    function oracle() external view override returns (address) {
        return _priceOracle;
    }

    /// @notice Returns the address of the main collections vault.
    /// @return The `ICollectionsVault` instance.
    function vault() external view override returns (ICollectionsVault) {
        return _vault;
    }

    /// @notice Whitelists a new collection and configures its reward parameters.
    /// @dev This function can only be called by the contract owner.
    /// It performs checks for zero address, existing whitelisting, ERC165 compliance for NFTs,
    /// and ensures that fixed pools have a 0% share. It also updates the total share BPS.
    /// @param collectionAddress The address of the collection to whitelist.
    /// @param collectionType The type of the collection (e.g., ERC721, ERC1155, ERC20).
    /// @param rewardBasis The basis for reward calculation (e.g., DEPOSIT, BORROW, FIXED_POOL).
    /// @param sharePercentageBps The percentage share of rewards allocated to this collection, in Basis Points.
    function whitelistCollection(
        address collectionAddress,
        IRewardsController.CollectionType collectionType,
        IRewardsController.RewardBasis rewardBasis,
        uint16 sharePercentageBps
    ) external override(IRewardsController) onlyOwner {
        if (collectionAddress == address(0)) revert IRewardsController.AddressZero();
        if (_isCollectionWhitelisted[collectionAddress]) {
            revert CollectionAlreadyExists(collectionAddress);
        }

        if (
            collectionType == IRewardsController.CollectionType.ERC721
                || collectionType == IRewardsController.CollectionType.ERC1155
        ) {
            // ERC165 check for NFT contracts
            bytes4 interfaceIdNFT;
            if (collectionType == IRewardsController.CollectionType.ERC721) {
                interfaceIdNFT = type(IERC721).interfaceId;
            } else {
                // ERC1155
                interfaceIdNFT = type(IERC1155).interfaceId;
            }
            if (!ERC165Checker.supportsInterface(collectionAddress, interfaceIdNFT)) {
                revert IRewardsController.InvalidCollectionInterface(collectionAddress, interfaceIdNFT);
            }
        }

        if (rewardBasis == IRewardsController.RewardBasis.FIXED_POOL && sharePercentageBps != 0) {
            revert InvalidRewardSharePercentage(sharePercentageBps);
        }

        if (_totalCollectionShareBps + sharePercentageBps > MAX_REWARD_SHARE_PERCENTAGE) {
            revert InvalidRewardSharePercentage(_totalCollectionShareBps + sharePercentageBps);
        }

        _collectionType[collectionAddress] = collectionType;
        _collectionRewardBasis[collectionAddress] = rewardBasis;
        _collectionRewardSharePercentage[collectionAddress] = sharePercentageBps;
        _totalCollectionShareBps += sharePercentageBps;
        _isCollectionWhitelisted[collectionAddress] = true; // Set the flag

        emit NewCollectionWhitelisted(collectionAddress, collectionType, rewardBasis, sharePercentageBps);
    }

    /// @notice Removes a whitelisted collection.
    /// @dev This function can only be called by the contract owner.
    /// It reverts if the collection is not whitelisted.
    /// It decreases the total collection share BPS and clears all associated data for the collection.
    /// Any remaining fixed pool balance for the collection is also cleared.
    /// @param collectionAddress The address of the collection to remove.
    function removeCollection(address collectionAddress) external override onlyOwner {
        if (!_isCollectionWhitelisted[collectionAddress]) {
            revert CollectionNotWhitelisted(collectionAddress);
        }

        uint16 shareToDecrease = _collectionRewardSharePercentage[collectionAddress];
        _totalCollectionShareBps -= shareToDecrease;

        delete _collectionType[collectionAddress];
        delete _collectionRewardBasis[collectionAddress];
        delete _collectionRewardSharePercentage[collectionAddress];
        delete _collectionWeightFunctions[collectionAddress];
        delete _isCollectionWhitelisted[collectionAddress]; // Clear the flag
        if (_fixedPoolCollectionBalances[collectionAddress] > 0) {
            // Consider what to do with remaining balance in fixed pool. Transfer out?
            delete _fixedPoolCollectionBalances[collectionAddress];
        }

        emit WhitelistCollectionRemoved(collectionAddress);
    }

    /// @notice Updates the reward percentage share for an existing whitelisted collection.
    /// @dev This function can only be called by the contract owner.
    /// It reverts if the collection is not whitelisted or if it's a fixed pool collection.
    /// It also checks if the new total share percentage exceeds the maximum allowed.
    /// @param collectionAddress The address of the collection to update.
    /// @param newSharePercentageBps The new percentage share for the collection, in Basis Points.
    function updateCollectionPercentageShare(address collectionAddress, uint16 newSharePercentageBps)
        external
        override(IRewardsController)
        onlyOwner
    {
        if (
            _collectionRewardSharePercentage[collectionAddress] == 0
                && _collectionType[collectionAddress] == IRewardsController.CollectionType.ERC721 /* check one field */
        ) {
            revert CollectionNotWhitelisted(collectionAddress);
        }
        if (_collectionRewardBasis[collectionAddress] == IRewardsController.RewardBasis.FIXED_POOL) {
            revert InvalidRewardSharePercentage(newSharePercentageBps); // Cannot set share for fixed pool
        }

        uint16 oldSharePercentageBps = _collectionRewardSharePercentage[collectionAddress];
        if (_totalCollectionShareBps - oldSharePercentageBps + newSharePercentageBps > MAX_REWARD_SHARE_PERCENTAGE) {
            revert InvalidRewardSharePercentage(
                _totalCollectionShareBps - oldSharePercentageBps + newSharePercentageBps
            );
        }

        _totalCollectionShareBps = _totalCollectionShareBps - oldSharePercentageBps + newSharePercentageBps;
        _collectionRewardSharePercentage[collectionAddress] = newSharePercentageBps;

        emit CollectionRewardShareUpdated(collectionAddress, oldSharePercentageBps, newSharePercentageBps);
    }

    /// @notice Sets the weight function for a whitelisted collection.
    /// @dev This function can only be called by the contract owner.
    /// It reverts if the collection is not whitelisted.
    /// @param collectionAddress The address of the collection to set the weight function for.
    /// @param weightFunction The `WeightFunction` struct containing the type and parameters of the weight function.
    function setWeightFunction(address collectionAddress, IRewardsController.WeightFunction calldata weightFunction)
        external
        override(IRewardsController)
        onlyOwner
    {
        if (
            _collectionRewardSharePercentage[collectionAddress] == 0
                && _collectionType[collectionAddress] == IRewardsController.CollectionType.ERC721 /* check one field */
        ) {
            revert CollectionNotWhitelisted(collectionAddress);
        }
        _collectionWeightFunctions[collectionAddress] = weightFunction;
        emit WeightFunctionSet(collectionAddress, weightFunction);
    }

    /// @notice Calculates the user's weight for a specific collection based on its type, reward basis, and weight function.
    /// @dev This internal function determines a user's participation weight, which influences reward accrual.
    /// It handles different collection types (ERC721, ERC1155, ERC20) and applies linear or exponential weight functions.
    /// @param user The address of the user.
    /// @param collectionAddress The address of the collection.
    /// @return The calculated weight of the user for the given collection, capped at `type(uint128).max`.
    function _calculateUserWeight(address user, address collectionAddress) internal view returns (uint128) {
        if (user == address(0) || collectionAddress == address(0)) {
            return 0;
        }

        IRewardsController.CollectionType collectionType = _collectionType[collectionAddress];
        IRewardsController.RewardBasis rewardBasis = _collectionRewardBasis[collectionAddress];
        IRewardsController.WeightFunction memory wf = _collectionWeightFunctions[collectionAddress];

        uint256 nValue; // Represents number of NFTs, cToken balance, or other metric

        if (collectionType == IRewardsController.CollectionType.ERC721) {
            nValue = IERC721(collectionAddress).balanceOf(user);
        } else if (collectionType == IRewardsController.CollectionType.ERC1155) {
            // For ERC1155, assuming a single token ID (e.g., 0) for simplicity.
            // In a real scenario, this might need to be dynamic or configured per collection.
            nValue = IERC1155(collectionAddress).balanceOf(user, 0);
        } else if (rewardBasis == IRewardsController.RewardBasis.DEPOSIT) {
            // Assuming collectionAddress is an ERC20 token representing deposits.
            nValue = IERC20(collectionAddress).balanceOf(user);
        } else if (rewardBasis == IRewardsController.RewardBasis.BORROW) {
            // This requires a specific cToken interface to get borrow balance.
            // For example, if using Compound's cTokens:
            // ICERC20(collectionAddress).borrowBalanceCurrent(user);
            // For now, this remains a placeholder as the specific interface is not provided.
            nValue = 0; // Placeholder for borrow balance
        } else if (rewardBasis == IRewardsController.RewardBasis.FIXED_POOL) {
            // For fixed pools, the weight might be a fixed value if the user has any balance.
            // This logic depends on how fixed pools are defined and managed.
            // If the user has any balance in the fixed pool, assign a base weight.
            // This needs more definition based on how fixed pools are managed.
            // For now, if the user has a non-zero balance in the fixed pool, they get a weight.
            if (_fixedPoolCollectionBalances[collectionAddress] > 0) {
                nValue = 1; // User is participating
            } else {
                nValue = 0;
            }
        } else {
            return 0; // Unknown basis or type
        }

        uint256 weight;
        if (wf.fnType == IRewardsController.WeightFunctionType.LINEAR) {
            // g(N) = 1 + k*N. p1 is k (scaled by PRECISION_FACTOR).
            weight = PRECISION_FACTOR + (uint256(wf.p1) * nValue) / PRECISION_FACTOR;
        } else if (wf.fnType == IRewardsController.WeightFunctionType.EXPONENTIAL) {
            // g(N) = (1+r)^N. p1 is r (scaled by PRECISION_FACTOR).
            // This is a simplified exponential calculation. For a robust solution,
            // consider using a fixed-point math library for power functions.
            // This calculation can be gas-intensive and prone to overflow for large N.
            // (1 + r)^N where r = wf.p1 / PRECISION_FACTOR
            // We calculate (PRECISION_FACTOR + wf.p1)^N / (PRECISION_FACTOR^(N-1))
            if (nValue == 0) {
                weight = PRECISION_FACTOR; // (1+r)^0 = 1
            } else {
                uint256 base = PRECISION_FACTOR + uint256(wf.p1);
                uint256 result = PRECISION_FACTOR; // Start with 1 (scaled)
                for (uint256 i = 0; i < nValue; i++) {
                    result = (result * base) / PRECISION_FACTOR;
                }
                weight = result;
            }
        } else {
            // Default: No specific weight function defined, or simple 1:1 weight based on nValue
            if (nValue > 0) {
                weight = PRECISION_FACTOR; // Basic weight if participating
            } else {
                weight = 0;
            }
        }

        if (weight > type(uint128).max) {
            return type(uint128).max;
        }
        return uint128(weight);
    }

    /// @notice Accrues rewards for a specific user in a given collection.
    /// @dev This internal function calculates and adds pending rewards to the user's accrued balance.
    /// It updates the user's `rewardDebt` to reflect the current state of rewards.
    /// @param forVault The address of the vault.
    /// @param user The address of the user.
    /// @param collectionAddress The address of the collection.
    function _accrueUserRewards(address forVault, address user, address collectionAddress) internal {
        AccountStorageData storage account = _accountStorage[forVault][user];
        InternalVaultInfo storage vaultStore = _vaultsData[forVault];

        uint256 currentGlobalRPW = vaultStore.globalRPW;
        uint256 collectionShare = _collectionRewardSharePercentage[collectionAddress];

        // Calculate the effective global RPW for this collection's share
        uint256 effectiveGlobalRPW = (currentGlobalRPW * collectionShare) / MAX_REWARD_SHARE_PERCENTAGE;

        // Calculate pending rewards based on the difference between current potential rewards and rewardDebt
        uint128 pending = uint128((account.weight * effectiveGlobalRPW) / PRECISION_FACTOR - account.rewardDebt);

        account.accrued += pending;

        // Update rewardDebt for future calculations based on the current globalRPW and collection share
        account.rewardDebt = uint128((account.weight * effectiveGlobalRPW) / PRECISION_FACTOR);
    }

    /// @notice Updates the total weight of a vault based on changes in a user's weight.
    /// @dev This internal function is called when a user's weight in a collection changes,
    /// ensuring the vault's total accumulated weight is accurately maintained.
    /// @param forVault The address of the vault.
    /// @param oldUserWeight The user's previous weight in the collection.
    /// @param newUserWeight The user's new weight in the collection.
    function _updateVaultTotalWeight(address forVault, uint128 oldUserWeight, uint128 newUserWeight) internal {
        InternalVaultInfo storage vaultStore = _vaultsData[forVault];
        vaultStore.totalWeight = vaultStore.totalWeight - oldUserWeight + newUserWeight;
    }

    /// @notice Accrues rewards for a user and updates their weight in a specific collection.
    /// @dev This internal function first accrues rewards based on the current weight,
    /// then recalculates the user's weight, updates the vault's total weight if necessary,
    /// and finally updates the user's reward debt.
    /// @param forVault The address of the vault.
    /// @param user The address of the user.
    /// @param collectionAddress The address of the collection.
    function _updateUserWeightAndAccrueRewards(address forVault, address user, address collectionAddress) internal {
        // Accrue rewards based on the user's current weight and the vault's globalRPW
        _accrueUserRewards(forVault, user, collectionAddress);

        AccountStorageData storage account = _accountStorage[forVault][user];
        uint128 oldWeight = account.weight;
        uint128 newWeight = _calculateUserWeight(user, collectionAddress);

        if (oldWeight != newWeight) {
            _updateVaultTotalWeight(forVault, oldWeight, newWeight);
            account.weight = newWeight;
            // After weight changes, rewardDebt needs to be re-calculated based on the new weight
            // and the current globalRPW to ensure future accruals are correct.
            // This is done by calling _accrueUserRewards again, which will update rewardDebt.
            // However, to avoid double-accrual, we need to ensure pending is 0 on this second call.
            // A simpler approach is to directly update rewardDebt here.
            uint256 currentGlobalRPW = _vaultsData[forVault].globalRPW;
            uint256 collectionShare = _collectionRewardSharePercentage[collectionAddress];
            uint256 effectiveGlobalRPW = (currentGlobalRPW * collectionShare) / MAX_REWARD_SHARE_PERCENTAGE;
            account.rewardDebt = uint128((newWeight * effectiveGlobalRPW) / PRECISION_FACTOR);
        }
    }

    // --- Public Functions for Sync and Refresh ---
    /// @notice Synchronizes a user's account data for a specific collection.
    /// @dev This function ensures that the user's weight and accrued rewards are up-to-date.
    /// It reverts if the main vault address is not set.
    /// @param user The address of the user to synchronize.
    /// @param collectionAddress The address of the collection for which to synchronize the user's account.
    function syncAccount(address user, address collectionAddress) external override(IRewardsController) {
        if (user == address(0)) revert IRewardsController.AddressZero();
        if (address(_vault) == address(0)) revert IRewardsController.VaultMismatch(); // Ensure vault is set
        if (!_isCollectionWhitelisted[collectionAddress]) {
            revert IRewardsController.CollectionNotWhitelisted(collectionAddress);
        }
        _updateUserWeightAndAccrueRewards(address(_vault), user, collectionAddress);
    }

    /// @notice Refreshes the reward per block calculation for a specific vault.
    /// @dev This function updates the `rewardPerBlock` and `globalRPW` based on the yield generated
    /// and the total weight of the vault. It handles division by zero and emits an event.
    /// Currently, it only supports refreshing the main `_vault`.
    /// @param forVault The address of the vault to refresh.
    /// @notice Refreshes the reward per block calculation for a specific vault.
    /// @dev This function updates the `rewardPerBlock` and `globalRPW` based on the yield generated
    /// and the total weight of the vault. It handles division by zero and emits an event.
    /// Currently, it only supports refreshing the main `_vault`.
    /// @param forVault The address of the vault to refresh.
    function refreshRewardPerBlock(address forVault) external override {
        if (forVault != address(_vault)) {
            // For now, only support refreshing for the main _vault.
            // Could be extended for multiple vaults if _vaultsData is used more generally.
            revert IRewardsController.VaultMismatch(); // Or a more specific error
        }

        InternalVaultInfo storage vaultStore = _vaultsData[forVault];
        IERC20 asset = IERC20(IERC4626(forVault).asset());
        uint256 currentBalance = asset.balanceOf(address(this));

        uint256 currentYield = 0;
        if (currentBalance >= vaultStore.lastAssetsBalance) {
            currentYield = currentBalance - vaultStore.lastAssetsBalance;
        } // else, yield is negative or 0, so newRewardPerBlock will be 0 or less if not capped.

        uint64 blocksDelta = uint64(block.number) - vaultStore.lastUpdateBlock;

        uint128 newRewardPerBlock = 0;
        if (blocksDelta > 0) {
            newRewardPerBlock = uint128(currentYield / blocksDelta);
            // Potential capping logic with _priceOracle can be added here
        }
        // If blocksDelta is 0, newRewardPerBlock remains 0, which is fine.

        vaultStore.rewardPerBlock = newRewardPerBlock;

        if (vaultStore.totalWeight > 0) {
            uint256 calculatedGlobalRPW = (uint256(newRewardPerBlock) * PRECISION_FACTOR) / vaultStore.totalWeight;
            if (calculatedGlobalRPW > type(uint128).max) {
                vaultStore.globalRPW = type(uint128).max;
            } else {
                vaultStore.globalRPW = uint128(calculatedGlobalRPW);
            }
        } else {
            vaultStore.globalRPW = 0; // Avoid division by zero
        }

        vaultStore.lastUpdateBlock = uint64(block.number);
        vaultStore.lastAssetsBalance = currentBalance;

        emit RewardPerBlockUpdated(forVault, newRewardPerBlock);
    }

    // --- Claiming ---
    /// @notice Allows users to claim accrued rewards for multiple collections in a single transaction.
    /// @dev This function is reentrancy-guarded and can be paused.
    /// It verifies an EIP-712 signature for batch claims, checks claim deadlines and nonces,
    /// updates user weights and accrues rewards, and handles fixed pool reward distribution.
    /// Rewards are transferred to the caller's address.
    /// @param claims An array of `IRewardsController.Claim` structs, each detailing a claim.
    /// @param signature The EIP-712 signature signed by the trusted claim signer.
    function claimLazy(IRewardsController.Claim[] calldata claims, bytes calldata signature)
        external
        override(IRewardsController)
        nonReentrant
        whenNotPaused
    {
        // For robust EIP-712 compliance with batch claims, it is highly recommended
        // to define a `ClaimBatch` struct in IRewardsController.sol and use its typehash.
        // Example: struct ClaimBatch { Claim[] claims; }
        // For now, we will hash all claims and verify a single signature over the combined hash.
        // This assumes the off-chain signer generates a signature over the keccak256 hash of the abi.encodePacked of all claims.
        // A more robust EIP-712 approach would involve a custom struct for the batch.

        bytes32 claimsHash = keccak256(abi.encode(claims));
        bytes32 digest = _hashTypedDataV4(claimsHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != _claimSigner || recoveredSigner == address(0)) {
            revert IRewardsController.InvalidSignature();
        }

        uint256 totalAmountToClaim = 0;
        address vaultAddress = address(_vault); // Assuming claims are always for the main vault

        for (uint256 i = 0; i < claims.length; i++) {
            IRewardsController.Claim calldata currentClaim = claims[i];
            address user = currentClaim.account;
            address collection = currentClaim.collection;

            if (user == address(0)) revert IRewardsController.AddressZero(); // User cannot be zero

            // Deadline check from the signed claim data
            if (block.timestamp > currentClaim.deadline) {
                revert IRewardsController.ClaimExpired();
            }

            AccountStorageData storage account = _accountStorage[vaultAddress][user];

            // Nonce check from the signed claim data against user's current nonce
            if (currentClaim.nonce != account.nonce) {
                revert IRewardsController.InvalidNonce(currentClaim.nonce, account.nonce);
            }

            if (!_isCollectionWhitelisted[collection]) {
                revert CollectionNotWhitelisted(collection);
            }

            _updateUserWeightAndAccrueRewards(vaultAddress, user, collection);

            uint256 amountForThisClaim = account.accrued;

            // Always reset accrued rewards to zero when processing a claim, regardless of the amount
            uint256 amountToTransfer = amountForThisClaim;

            if (amountForThisClaim > 0) {
                if (_collectionRewardBasis[collection] == IRewardsController.RewardBasis.FIXED_POOL) {
                    if (_fixedPoolCollectionBalances[collection] < amountForThisClaim) {
                        amountToTransfer = _fixedPoolCollectionBalances[collection]; // Claim only available
                        if (amountToTransfer == 0) {
                            // Even if no tokens to transfer, still zero out accrued rewards
                            account.accrued = 0;
                            emit RewardClaimed(vaultAddress, user, 0);
                            account.nonce++; // Increment nonce after successful processing
                            continue; // Skip adding to totalAmountToClaim
                        }
                    }
                    _fixedPoolCollectionBalances[collection] -= amountToTransfer;
                } else {
                    amountToTransfer = amountForThisClaim;
                }

                account.accrued = 0;
                totalAmountToClaim += amountToTransfer;
                emit RewardClaimed(vaultAddress, user, amountToTransfer);
            }
            account.nonce++; // Increment nonce after successful processing of this claim item
        }

        if (totalAmountToClaim > 0) {
            IERC20(IERC4626(vaultAddress).asset()).safeTransfer(msg.sender, totalAmountToClaim);
        }
    }

    // --- Admin Functions ---
    /// @notice Updates the address of the trusted signer for EIP-712 claims.
    /// @dev This function can only be called by the contract owner.
    /// It reverts if the `newSigner` address is the zero address.
    /// An event `TrustedSignerUpdated` is emitted upon successful update.
    /// @param newSigner The address of the new trusted signer.
    function updateTrustedSigner(address newSigner) external override(IRewardsController) onlyOwner {
        if (newSigner == address(0)) {
            revert CannotSetSignerToZeroAddress();
        }
        emit TrustedSignerUpdated(_claimSigner, newSigner, msg.sender);
        _claimSigner = newSigner;
    }

    /// @notice Returns the address of the trusted claim signer.
    /// @return The address of the trusted claim signer.
    function claimSigner() external view override returns (address) {
        return _claimSigner;
    }

    // --- View Functions for New Storage ---
    /// @notice Returns the current nonce for a user within a specific vault.
    /// @dev The nonce is incremented after each successful claim for a user.
    /// @param vaultAddress The address of the vault.
    /// @param userAddress The address of the user.
    /// @return nonce The current nonce of the user.
    function userNonce(address vaultAddress, address userAddress)
        external
        view
        override(IRewardsController)
        returns (uint64 nonce)
    {
        return _accountStorage[vaultAddress][userAddress].nonce;
    }

    /// @notice Returns the total seconds for which a user has been paid rewards in a specific vault.
    /// @dev This field's functional necessity should be reviewed.
    /// @param vaultAddress The address of the vault.
    /// @param userAddress The address of the user.
    /// @return secondsPaid The total seconds for which the user has been paid rewards.
    function userSecondsPaid(address vaultAddress, address userAddress)
        external
        view
        override
        returns (uint64 secondsPaid)
    {
        // This field might be deprecated or its usage re-evaluated.
        // Returning from AccountStorageData as per plan.
        return _accountStorage[vaultAddress][userAddress].secondsPaid;
    }

    /// @notice Returns the detailed information for a specific vault.
    /// @dev This function constructs an `IRewardsController.VaultInfo` struct from the internal `_vaultsData`.
    /// Note that some fields in `IRewardsController.VaultInfo` are collection-specific and are set to default values here.
    /// @param vaultAddress The address of the vault to query.
    /// @return A `IRewardsController.VaultInfo` struct containing the vault's reward state.
    function vaults(address vaultAddress) external view override returns (IRewardsController.VaultInfo memory) {
        InternalVaultInfo storage v = _vaultsData[vaultAddress];
        // The IRewardsController.VaultInfo struct contains fields (linK, expR, useExp, cToken, nft, weightByBorrow)
        // that are specific to individual collections and their weight functions, not the vault itself.
        // These fields cannot be populated from the general _vaultsData.
        // They are set to default values here to match the interface, but their meaningful values
        // would depend on a specific collection within the vault.
        return IRewardsController.VaultInfo({
            rewardPerBlock: v.rewardPerBlock,
            globalRPW: v.globalRPW,
            totalWeight: v.totalWeight,
            lastUpdateBlock: uint32(v.lastUpdateBlock), // Ensure cast is safe
            linK: 0, // Collection-specific, not applicable at vault level
            expR: 0, // Collection-specific, not applicable at vault level
            useExp: false, // Collection-specific, not applicable at vault level
            cToken: address(0), // Collection-specific, not applicable at vault level
            nft: address(0), // Collection-specific, not applicable at vault level
            weightByBorrow: false // Collection-specific, not applicable at vault level
        });
    }

    /// @notice Returns the account information for a specific user within a given vault.
    /// @param vaultAddress The address of the vault.
    /// @param userAddress The address of the user.
    /// @return An `IRewardsController.AccountInfo` struct.
    function acc(address vaultAddress, address userAddress)
        external
        view
        override
        returns (IRewardsController.AccountInfo memory)
    {
        AccountStorageData storage a = _accountStorage[vaultAddress][userAddress];
        return IRewardsController.AccountInfo({weight: a.weight, rewardDebt: a.rewardDebt, accrued: a.accrued});
    }

    /// @notice Returns the reward basis for a specific collection.
    /// @param collectionAddress The address of the collection.
    /// @return The `RewardBasis` enum value for the collection.
    function collectionRewardBasis(address collectionAddress)
        external
        view
        override
        returns (IRewardsController.RewardBasis)
    {
        return _collectionRewardBasis[collectionAddress];
    }

    /// @notice Returns whether a collection is whitelisted.
    /// @param collectionAddress The address of the collection.
    /// @return A boolean indicating if the collection is whitelisted.
    function isCollectionWhitelisted(address collectionAddress) external view override returns (bool) {
        return _isCollectionWhitelisted[collectionAddress];
    }

    /// @notice Sets the fixed pool collection balance for testing purposes.
    /// @dev This function is intended for testing and administrative purposes only.
    /// @param collectionAddress The address of the collection.
    /// @param amount The amount to set as the fixed pool balance.
    function setFixedPoolCollectionBalance(address collectionAddress, uint256 amount) external onlyOwner {
        _fixedPoolCollectionBalances[collectionAddress] = amount;
    }

    // --- Pausable Overrides ---
    /// @notice Pauses the contract, preventing certain operations.
    /// @dev This function can only be called by the contract owner.
    /// @notice Pauses the contract, preventing certain operations.
    /// @dev This function can only be called by the contract owner.
    function pause() external override onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, allowing previously restricted operations.
    /// @dev This function can only be called by the contract owner.
    /// @notice Unpauses the contract, allowing previously restricted operations.
    /// @dev This function can only be called by the contract owner.
    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @notice Returns the paused state of the contract.
    /// @return A boolean indicating whether the contract is paused (`true`) or not (`false`).
    function paused() public view override(IRewardsController, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    /// @notice Sets the accrued rewards for a specific user and vault.
    /// @dev This function is intended for testing and administrative purposes only.
    /// @param vaultAddress The address of the vault.
    /// @param userAddress The address of the user.
    /// @param amount The amount to set as accrued rewards.
    function setAccrued(address vaultAddress, address userAddress, uint128 amount) external onlyOwner {
        _accountStorage[vaultAddress][userAddress].accrued = amount;
    }

    /// @notice Returns the fixed pool collection balance for a given collection.
    /// @param collectionAddress The address of the collection.
    /// @return The fixed pool balance for the collection.

    function fixedPoolCollectionBalances(address collectionAddress) external view returns (uint256) {
        return _fixedPoolCollectionBalances[collectionAddress];
    }

    /// @notice Sets the main collections vault.
    /// @dev This function can only be called by the contract owner.
    /// @param newVaultAddress The address of the new `ICollectionsVault` contract.
    function setVault(ICollectionsVault newVaultAddress) external onlyOwner {
        if (address(newVaultAddress) == address(0)) revert IRewardsController.AddressZero();
        _vault = newVaultAddress;
        emit VaultUpdated(address(newVaultAddress));
    }

    // --- Old functions removed or functionality integrated elsewhere ---
    // lastAssets(), yieldLeft(), coll() are removed.
    // previewClaim() is removed as it's not in the new IRewardsController interface.
    // Internal function to hash a single claim for EIP-712
    /// @notice Hashes a single `Claim` struct for EIP-712 signature verification.
    /// @dev This internal function computes the EIP-712 digest for a given claim.
    /// @param claim The `IRewardsController.Claim` struct to hash.
    /// @return The EIP-712 digest of the claim.
    function _hashClaim(IRewardsController.Claim memory claim) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CLAIM_TYPEHASH,
                    claim.account,
                    claim.collection,
                    claim.secondsUser,
                    claim.secondsColl,
                    claim.incRPS,
                    claim.yieldSlice,
                    claim.nonce,
                    claim.deadline
                )
            )
        );
    }

    uint256[30] private __gap; // Keep gap for upgradeability
}
