// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICollectionsVault} from "./ICollectionsVault.sol";
import {ICollectionRegistry} from "./ICollectionRegistry.sol";

interface IDebtSubsidizer {
    struct ClaimData {
        address recipient; // recipient of the subsidy
        uint256 totalEarned; // cumulative amount earned as encoded in the leaf
        bytes32[] merkleProof; // Merkle proof for the claim
    }

    struct VaultInfo {
        address lendingManager; // lending manager address
        address cToken; // cToken address
    }

    event NewCollectionWhitelisted(address indexed vaultAddress, address indexed collectionAddress);
    event WhitelistCollectionRemoved(address indexed vaultAddress, address indexed collectionAddress);
    event TrustedSignerUpdated(address oldSigner, address newSigner, address indexed changedBy);
    event SubsidyClaimed(address indexed vaultAddress, address indexed recipient, uint256 amount);
    event MerkleRootUpdated(address indexed vaultAddress, bytes32 merkleRoot, address indexed updatedBy);
    event VaultAdded(
        address indexed vaultAddress, address indexed cTokenAddress, address indexed lendingManagerAddress
    );
    event VaultRemoved(address indexed vaultAddress);
    event CollectionYieldShareUpdated(
        address indexed vaultAddress,
        address indexed collectionAddress,
        uint16 oldSharePercentageBps,
        uint16 newSharePercentageBps
    );
    event WeightFunctionConfigUpdated(
        address indexed vaultAddress,
        address indexed collectionAddress,
        ICollectionRegistry.WeightFunction oldWeightFunction,
        ICollectionRegistry.WeightFunction newWeightFunction
    );

    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidSignature();
    error InvalidSecondsColl();
    error InvalidYieldSlice();
    error InsufficientYield();
    error ArrayLengthMismatch();
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
    error InvalidMerkleProof();
    error MerkleRootNotSet();
    error AlreadyClaimed();

    // --- Vault Management ---
    function addVault(address vaultAddress_, address lendingManagerAddress_) external;
    function removeVault(address vaultAddress_) external;
    function vault(address vaultAddress) external view returns (VaultInfo memory);

    // --- Collection Management ---
    function whitelistCollection(address vaultAddress, address collectionAddress) external;
    function removeCollection(address vaultAddress, address collectionAddress) external;
    function isCollectionWhitelisted(address vaultAddress, address collectionAddress) external view returns (bool);

    // --- User Information & Claims ---
    function claimSubsidy(address vaultAddress, ClaimData calldata claim) external;
    function updateMerkleRoot(address vaultAddress, bytes32 merkleRoot) external;

    // --- Administrative Actions ---
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}
