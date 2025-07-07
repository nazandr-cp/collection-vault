// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICollectionRegistry} from "../interfaces/ICollectionRegistry.sol";
import {ICollectionsVault} from "../interfaces/ICollectionsVault.sol";

/**
 * @title CollectionValidationLib
 * @dev Library for collection validation and access control logic
 * @dev Extracted from CollectionsVault to reduce contract size
 */
library CollectionValidationLib {
    uint256 public constant GLOBAL_DEPOSIT_INDEX_PRECISION = 1e18;

    error CollectionNotRegistered(address collectionAddress);
    error CollectionInsufficientBalance(address collectionAddress, uint256 requested, uint256 available);
    error UnauthorizedCollectionAccess(address collectionAddress, address operator);
    error AddressZero();

    /**
     * @dev Ensures a collection is known and registered in the vault
     * @param collectionAddress The collection address to check
     * @param collectionRegistry The collection registry contract
     * @param isCollectionRegistered Mapping to track registered collections
     * @param allCollectionAddresses Array of all collection addresses
     * @param vaultData The collection's vault data storage
     * @param globalDepositIndex The current global deposit index
     */
    function ensureCollectionKnownAndRegistered(
        address collectionAddress,
        ICollectionRegistry collectionRegistry,
        mapping(address => bool) storage isCollectionRegistered,
        address[] storage allCollectionAddresses,
        ICollectionsVault.CollectionVaultData storage vaultData,
        uint256 globalDepositIndex
    ) external {
        if (!collectionRegistry.isRegistered(collectionAddress)) {
            revert CollectionNotRegistered(collectionAddress);
        }
        
        if (!isCollectionRegistered[collectionAddress]) {
            isCollectionRegistered[collectionAddress] = true;
            allCollectionAddresses.push(collectionAddress);
            vaultData.lastGlobalDepositIndex = globalDepositIndex;
        }
    }

    /**
     * @dev Validates collection operator access
     * @param collectionAddress The collection address
     * @param operator The operator address to check
     * @param collectionOperators Mapping of collection operators
     */
    function validateCollectionOperator(
        address collectionAddress,
        address operator,
        mapping(address => mapping(address => bool)) storage collectionOperators
    ) external view {
        if (!collectionOperators[collectionAddress][operator]) {
            revert UnauthorizedCollectionAccess(collectionAddress, operator);
        }
    }

    /**
     * @dev Validates collection balance for operations
     * @param collectionAddress The collection address
     * @param requestedAmount The amount requested
     * @param availableAmount The amount available
     */
    function validateCollectionBalance(
        address collectionAddress,
        uint256 requestedAmount,
        uint256 availableAmount
    ) external pure {
        if (requestedAmount > availableAmount) {
            revert CollectionInsufficientBalance(collectionAddress, requestedAmount, availableAmount);
        }
    }

    /**
     * @dev Validates address is not zero
     * @param addr The address to validate
     */
    function validateAddress(address addr) external pure {
        if (addr == address(0)) {
            revert AddressZero();
        }
    }

    /**
     * @dev Validates collection exists in registry
     * @param collectionAddress The collection address
     * @param collectionRegistry The collection registry contract
     */
    function validateCollectionExists(
        address collectionAddress,
        ICollectionRegistry collectionRegistry
    ) external view {
        if (!collectionRegistry.isRegistered(collectionAddress)) {
            revert CollectionNotRegistered(collectionAddress);
        }
    }

    /**
     * @dev Calculates collection total assets with potential yield
     * @param collectionAddress The collection address
     * @param vaultData The collection's vault data
     * @param collectionRegistry The collection registry contract
     * @param globalDepositIndex The current global deposit index
     * @param isCollectionRegistered Mapping to check registration
     * @return totalAssets The total assets including potential yield
     */
    function calculateCollectionTotalAssets(
        address collectionAddress,
        ICollectionsVault.CollectionVaultData memory vaultData,
        ICollectionRegistry collectionRegistry,
        uint256 globalDepositIndex,
        mapping(address => bool) storage isCollectionRegistered
    ) external view returns (uint256 totalAssets) {
        if (!isCollectionRegistered[collectionAddress]) {
            ICollectionRegistry.Collection memory registryCollectionTest =
                collectionRegistry.getCollection(collectionAddress);
            if (registryCollectionTest.collectionAddress == address(0)) return 0;
        }

        ICollectionRegistry.Collection memory registryCollection = collectionRegistry.getCollection(collectionAddress);

        if (
            registryCollection.collectionAddress == address(0) || 
            registryCollection.yieldSharePercentage == 0 ||
            globalDepositIndex <= vaultData.lastGlobalDepositIndex
        ) {
            return vaultData.totalAssetsDeposited;
        }

        uint256 accruedRatio = globalDepositIndex - vaultData.lastGlobalDepositIndex;
        uint256 potentialYieldAccrued = (
            vaultData.totalAssetsDeposited * accruedRatio * registryCollection.yieldSharePercentage
        ) / (GLOBAL_DEPOSIT_INDEX_PRECISION * 10000);

        return vaultData.totalAssetsDeposited + potentialYieldAccrued;
    }

    /**
     * @dev Validates batch operation parameters
     * @param arraysLength1 Length of first array
     * @param arraysLength2 Length of second array
     * @param maxBatchSize Maximum allowed batch size
     */
    function validateBatchOperation(
        uint256 arraysLength1,
        uint256 arraysLength2,
        uint256 maxBatchSize
    ) external pure {
        require(arraysLength1 == arraysLength2, "Array lengths mismatch");
        require(arraysLength1 <= maxBatchSize, "Batch size exceeds maximum limit");
    }

    /**
     * @dev Validates performance score
     * @param score The performance score to validate
     */
    function validatePerformanceScore(uint256 score) external pure {
        require(score <= 10000, "Performance score cannot exceed 10000 (100%)");
    }

    /**
     * @dev Validates epoch and collection for yield application
     * @param collectionAddress The collection address
     * @param epochId The epoch ID
     * @param isCollectionRegistered Mapping to check registration
     * @param epochCollectionYieldApplied Mapping to check if yield already applied
     */
    function validateEpochYieldApplication(
        address collectionAddress,
        uint256 epochId,
        mapping(address => bool) storage isCollectionRegistered,
        mapping(uint256 => mapping(address => bool)) storage epochCollectionYieldApplied
    ) external view {
        if (collectionAddress == address(0)) {
            revert AddressZero();
        }
        if (!isCollectionRegistered[collectionAddress]) {
            revert CollectionNotRegistered(collectionAddress);
        }
        require(!epochCollectionYieldApplied[epochId][collectionAddress], "Yield already applied for this collection and epoch");
    }
}