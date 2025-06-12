// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICollectionsVault} from "./ICollectionsVault.sol";

interface IDebtSubsidizer {
    enum CollectionType {
        ERC721,
        ERC1155
    }

    enum RewardBasis {
        DEPOSIT,
        BORROW
    }

    enum WeightFunctionType {
        LINEAR,
        EXPONENTIAL
    }

    struct WeightFunction {
        WeightFunctionType fnType;
        int256 p1;
        int256 p2;
    }

    struct Subsidy {
        address account; // recipient of the subsidy
        address collection; // collection address
        address vault; // vault address where the yield is stored
        uint256 amount; // tokens to transfer — already calculated off-chain
        uint256 nonce; // protection against signature replay
        uint256 deadline; // signature validity deadline (block/time)
    }

    struct VaultInfo {
        address lendingManager; // lending manager address
        address cToken; // cToken address
    }

    event NewCollectionWhitelisted(
        address indexed vaultAddress,
        address indexed collectionAddress,
        CollectionType collectionType,
        RewardBasis rewardBasis,
        uint16 sharePercentage,
        WeightFunction weightFunction
    );
    event WhitelistCollectionRemoved(address indexed vaultAddress, address indexed collectionAddress);
    event CollectionYieldShareUpdated(
        address indexed vaultAddress,
        address indexed collectionAddress,
        uint16 oldSharePercentage,
        uint16 newSharePercentage
    );
    event WeightFunctionConfigUpdated(
        address indexed vaultAddress,
        address indexed collectionAddress,
        IDebtSubsidizer.WeightFunction oldWeightFunction,
        IDebtSubsidizer.WeightFunction newWeightFunction
    );
    event TrustedSignerUpdated(address oldSigner, address newSigner, address indexed changedBy);
    event WeightFunctionSet(address indexed vaultAddress, address indexed collectionAddress, WeightFunction fn);
    event DebtSubsidized(
        address indexed vaultAddress, address indexed user, address indexed collectionAddress, uint256 amount
    );
    event VaultAdded(
        address indexed vaultAddress, address indexed cTokenAddress, address indexed lendingManagerAddress
    );
    event VaultRemoved(address indexed vaultAddress);

    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidSignature();
    error ClaimExpired();
    error InvalidSecondsColl();
    error InvalidYieldSlice();
    error InsufficientYield();
    error ArrayLengthMismatch();
    error InvalidNonce();
    error VaultMismatch();
    error InvalidYieldSharePercentage(uint256 totalSharePercentage);
    error CollectionNotWhitelistedInVault(address vaultAddress, address collectionAddress);
    error CannotSetSignerToZeroAddress();
    error VaultNotRegistered(address vaultAddress);
    error CollectionAlreadyWhitelistedInVault(address vaultAddress, address collectionAddress);
    error VaultAlreadyRegistered(address vaultAddress);
    error InvalidCollectionInterface(address collectionAddress, bytes4 interfaceId);
    error LendingManagerNotSetForVault(address vaultAddress);
    error LendingManagerAssetMismatch(address vaultAsset, address lmAsset);

    // --- Vault Management ---
    function addVault(address vaultAddress_, address lendingManagerAddress_) external;
    function removeVault(address vaultAddress_) external;
    function vault(address vaultAddress) external view returns (VaultInfo memory);

    // --- Collection Management ---
    function whitelistCollection(
        address vaultAddress,
        address collectionAddress,
        CollectionType collectionType,
        RewardBasis rewardBasis,
        uint16 sharePercentageBps
    ) external;
    function removeCollection(address vaultAddress, address collectionAddress) external;
    function updateCollectionPercentageShare(
        address vaultAddress,
        address collectionAddress,
        uint16 newSharePercentageBps
    ) external;
    function isCollectionWhitelisted(address vaultAddress, address collectionAddress) external view returns (bool);
    function collectionRewardBasis(address vaultAddress, address collectionAddress)
        external
        view
        returns (RewardBasis);
    function setWeightFunction(address vaultAddress, address collectionAddress, WeightFunction calldata weightFunction)
        external;

    // --- User Information & Claims ---
    function userNonce(address vaultAddress, address userAddress) external view returns (uint64 nonce);
    function subsidize(address vaultAddress, Subsidy[] calldata subsidizes, bytes calldata signature) external;

    // --- Administrative Actions ---
    function updateTrustedSigner(address newSigner) external;
    function subsidySigner() external view returns (address);
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}
