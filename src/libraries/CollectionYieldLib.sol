// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {ICollectionRegistry} from "../interfaces/ICollectionRegistry.sol";
import {ICollectionsVault} from "../interfaces/ICollectionsVault.sol";

/**
 * @title CollectionYieldLib
 * @dev Library for yield calculation and accrual logic
 * @dev Extracted from CollectionsVault to reduce contract size
 */
library CollectionYieldLib {
    uint256 public constant GLOBAL_DEPOSIT_INDEX_PRECISION = 1e18;

    event CollectionYieldAccrued(
        address indexed collectionAddress,
        uint256 yieldAccrued,
        uint256 newTotalDeposits,
        uint256 globalIndex,
        uint256 previousCollectionIndex
    );

    event CollectionYieldGenerated(
        address indexed collectionAddress, uint256 indexed yieldAmount, uint256 indexed timestamp
    );

    /**
     * @dev Updates the global deposit index based on lending manager yields
     * @param lendingManager The lending manager contract
     * @param totalYieldReserved The total yield currently reserved
     * @param currentGlobalDepositIndex The current global deposit index
     * @return newGlobalDepositIndex The updated global deposit index
     */
    function updateGlobalDepositIndex(
        ILendingManager lendingManager,
        uint256 totalYieldReserved,
        uint256 currentGlobalDepositIndex
    ) external view returns (uint256 newGlobalDepositIndex) {
        if (address(lendingManager) == address(0)) return currentGlobalDepositIndex;

        uint256 totalPrincipal = lendingManager.totalPrincipalDeposited();
        if (totalPrincipal == 0) {
            return currentGlobalDepositIndex;
        }

        uint256 lmAssets = lendingManager.totalAssets();
        uint256 currentTotalAssets = lmAssets > totalYieldReserved ? lmAssets - totalYieldReserved : 0;
        uint256 newIndex = (currentTotalAssets * GLOBAL_DEPOSIT_INDEX_PRECISION) / totalPrincipal;

        return newIndex > currentGlobalDepositIndex ? newIndex : currentGlobalDepositIndex;
    }

    /**
     * @dev Accrues yield for a specific collection
     * @param collectionAddress The collection to accrue yield for
     * @param vaultData The collection's vault data (will be modified)
     * @param collectionRegistry The collection registry contract
     * @param globalDepositIndex The current global deposit index
     * @param totalAssetsDepositedAllCollections Current total assets (will be modified)
     * @param collectionTotalYieldGenerated Collection yield tracking (will be modified)
     * @return yieldAccrued The amount of yield accrued
     */
    function accrueCollectionYield(
        address collectionAddress,
        ICollectionsVault.CollectionVaultData storage vaultData,
        ICollectionRegistry collectionRegistry,
        uint256 globalDepositIndex,
        uint256 totalAssetsDepositedAllCollections,
        mapping(address => uint256) storage collectionTotalYieldGenerated
    ) external returns (uint256 yieldAccrued, uint256 newTotalAssetsDepositedAllCollections) {
        ICollectionRegistry.Collection memory registryCollection = collectionRegistry.getCollection(collectionAddress);

        if (registryCollection.yieldSharePercentage == 0) {
            vaultData.lastGlobalDepositIndex = globalDepositIndex;
            return (0, totalAssetsDepositedAllCollections);
        }

        uint256 lastIndex = vaultData.lastGlobalDepositIndex;
        newTotalAssetsDepositedAllCollections = totalAssetsDepositedAllCollections;

        if (globalDepositIndex > lastIndex) {
            uint256 accruedRatio = globalDepositIndex - lastIndex;
            yieldAccrued = (vaultData.totalAssetsDeposited * accruedRatio * registryCollection.yieldSharePercentage)
                / (GLOBAL_DEPOSIT_INDEX_PRECISION * 10000);

            if (yieldAccrued > 0) {
                vaultData.totalAssetsDeposited += yieldAccrued;
                newTotalAssetsDepositedAllCollections += yieldAccrued;

                // Track collection-specific yield generation
                collectionTotalYieldGenerated[collectionAddress] += yieldAccrued;

                emit CollectionYieldGenerated(collectionAddress, yieldAccrued, block.timestamp);
                emit CollectionYieldAccrued(
                    collectionAddress, yieldAccrued, vaultData.totalAssetsDeposited, globalDepositIndex, lastIndex
                );
            }
        }
        vaultData.lastGlobalDepositIndex = globalDepositIndex;
    }

    /**
     * @dev Calculates potential yield for a collection without accruing it
     * @param collectionAddress The collection to calculate yield for
     * @param vaultData The collection's vault data
     * @param collectionRegistry The collection registry contract
     * @param globalDepositIndex The current global deposit index
     * @return potentialYieldAccrued The amount of yield that would be accrued
     */
    function calculatePotentialYield(
        address collectionAddress,
        ICollectionsVault.CollectionVaultData memory vaultData,
        ICollectionRegistry collectionRegistry,
        uint256 globalDepositIndex
    ) external view returns (uint256 potentialYieldAccrued) {
        ICollectionRegistry.Collection memory registryCollection = collectionRegistry.getCollection(collectionAddress);

        if (
            registryCollection.collectionAddress == address(0) || registryCollection.yieldSharePercentage == 0
                || globalDepositIndex <= vaultData.lastGlobalDepositIndex
        ) {
            return 0;
        }

        uint256 accruedRatio = globalDepositIndex - vaultData.lastGlobalDepositIndex;
        potentialYieldAccrued = (
            vaultData.totalAssetsDeposited * accruedRatio * registryCollection.yieldSharePercentage
        ) / (GLOBAL_DEPOSIT_INDEX_PRECISION * 10000);
    }

    /**
     * @dev Calculates current epoch yield available
     * @param lendingManager The lending manager contract
     * @param epochYieldAllocated Amount already allocated for current epoch
     * @param includeNonShared Whether to include non-shared yield
     * @return availableYield The available yield amount
     */
    function getCurrentEpochYield(ILendingManager lendingManager, uint256 epochYieldAllocated, bool includeNonShared)
        external
        view
        returns (uint256 availableYield)
    {
        if (address(lendingManager) == address(0)) {
            return 0;
        }

        uint256 totalLMYield = lendingManager.totalAssets() > lendingManager.totalPrincipalDeposited()
            ? lendingManager.totalAssets() - lendingManager.totalPrincipalDeposited()
            : 0;

        if (includeNonShared) {
            return totalLMYield;
        }

        return totalLMYield > epochYieldAllocated ? totalLMYield - epochYieldAllocated : 0;
    }
}
