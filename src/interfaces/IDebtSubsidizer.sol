// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICollectionsVault} from "./ICollectionsVault.sol";

interface IDebtSubsidizer {
    enum CollectionType {
        ERC721,
        ERC1155
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

    struct ClaimData {
        address recipient; // recipient of the subsidy
        address collection; // collection address for which subsidy is claimed
        uint256 amount; // amount to claim, as per Merkle leaf
        bytes32[] merkleProof; // Merkle proof for the claim
    }

    struct VaultInfo {
        address lendingManager; // lending manager address
        address cToken; // cToken address
    }

    event NewCollectionWhitelisted(
        address indexed vaultAddress,
        address indexed collectionAddress,
        CollectionType collectionType,
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
    event SubsidyClaimed(
        address indexed vaultAddress, address indexed recipient, address indexed collection, uint256 amount
    );
    event MerkleRootUpdated(address indexed vaultAddress, bytes32 merkleRoot, address indexed updatedBy);
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
    error LeafAlreadyClaimed();

    // --- Vault Management ---
    function addVault(address vaultAddress_, address lendingManagerAddress_) external;
    function removeVault(address vaultAddress_) external;
    function vault(address vaultAddress) external view returns (VaultInfo memory);

    // --- Collection Management ---
    function whitelistCollection(
        address vaultAddress,
        address collectionAddress,
        CollectionType collectionType,
        uint16 sharePercentageBps
    ) external;
    function removeCollection(address vaultAddress, address collectionAddress) external;
    function updateCollectionPercentageShare(
        address vaultAddress,
        address collectionAddress,
        uint16 newSharePercentageBps
    ) external;
    function isCollectionWhitelisted(address vaultAddress, address collectionAddress) external view returns (bool);
    function setWeightFunction(address vaultAddress, address collectionAddress, WeightFunction calldata weightFunction)
        external;

    // --- User Information & Claims ---
    function claimSubsidy(address vaultAddress, ClaimData calldata claim) external;
    function updateMerkleRoot(address vaultAddress, bytes32 merkleRoot) external;

    // --- Administrative Actions ---
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}
