// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICollectionsVault} from "./ICollectionsVault.sol";
import {ICollectionRegistry} from "./ICollectionRegistry.sol";

interface IDebtSubsidizer {
    struct ClaimData {
        address recipient;
        uint256 totalEarned;
        bytes32[] merkleProof;
    }

    struct VaultInfo {
        address lendingManager;
        address cToken;
    }

    event NewCollectionWhitelisted(address indexed vaultAddress, address indexed collectionAddress);
    event WhitelistCollectionRemoved(address indexed vaultAddress, address indexed collectionAddress);
    event SubsidyClaimed(address indexed vaultAddress, address indexed recipient, uint256 amount);
    event MerkleRootUpdated(
        address indexed vaultAddress, bytes32 merkleRoot, address indexed updatedBy, uint256 totalSubsidiesForEpoch
    );
    event VaultAdded(
        address indexed vaultAddress, address indexed cTokenAddress, address indexed lendingManagerAddress
    );
    event VaultRemoved(address indexed vaultAddress);

    event DebtSubsidizerRoleGranted(bytes32 indexed role, address indexed account, address sender, uint256 timestamp);
    event DebtSubsidizerRoleRevoked(bytes32 indexed role, address indexed account, address sender, uint256 timestamp);

    event CollectionRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

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

    function addVault(address vaultAddress_, address lendingManagerAddress_) external;
    function removeVault(address vaultAddress_) external;
    function vault(address vaultAddress) external view returns (VaultInfo memory);

    function whitelistCollection(address vaultAddress, address collectionAddress) external;
    function removeCollection(address vaultAddress, address collectionAddress) external;
    function isCollectionWhitelisted(address vaultAddress, address collectionAddress) external view returns (bool);

    function claimSubsidy(address vaultAddress, ClaimData calldata claim) external;
    function claimAllSubsidies(address[] calldata vaultAddresses, ClaimData[] calldata claims) external;
    function updateMerkleRoot(address vaultAddress, bytes32 merkleRoot, uint256 totalSubsidiesForEpoch) external;
    function getMerkleRoot(address vaultAddress) external view returns (bytes32);

    function paused() external view returns (bool);

    function getTotalSubsidies(address vaultAddress) external view returns (uint256);
    function getTotalSubsidiesClaimed(address vaultAddress) external view returns (uint256);
    function getRemainingSubsidies(address vaultAddress) external view returns (uint256);
    function getTotalClaimedForVault(address vaultAddress) external view returns (uint256);
    function getUserClaimedTotal(address vaultAddress, address user) external view returns (uint256);
    function isVaultRemoved(address vaultAddress) external view returns (bool);
    function isCollectionRemoved(address vaultAddress, address collection) external view returns (bool);
    function userSecondsClaimed(address user) external view returns (uint256);
    function emergencyValidateAndPause(address vaultAddress) external;
    function validateVaultClaimsIntegrity(address vaultAddress) external view returns (bool, uint256, uint256);
}
