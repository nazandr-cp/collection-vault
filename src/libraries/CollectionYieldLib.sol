// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {ICollectionRegistry} from "../interfaces/ICollectionRegistry.sol";
import {ICollectionsVault} from "../interfaces/ICollectionsVault.sol";

/**
 * @title CollectionYieldLib
 * @dev Library for yield calculation, accrual, and view functions
 */
library CollectionYieldLib {
    uint256 public constant DEPOSIT_INDEX_PRECISION = 1e18;

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
        uint256 newIndex = (currentTotalAssets * DEPOSIT_INDEX_PRECISION) / totalPrincipal;

        return newIndex > currentGlobalDepositIndex ? newIndex : currentGlobalDepositIndex;
    }

    function accrueCollectionYield(
        address collectionAddress,
        ICollectionsVault.CollectionVaultData storage vaultData,
        ICollectionRegistry collectionRegistry,
        uint256 globalDepositIndex,
        uint256 totalAssetsDepositedAllCollections,
        uint256 currentTotalYieldGenerated
    )
        external
        returns (uint256 yieldAccrued, uint256 newTotalAssetsDepositedAllCollections, uint256 newTotalYieldGenerated)
    {
        ICollectionRegistry.Collection memory registryCollection = collectionRegistry.getCollection(collectionAddress);

        if (registryCollection.yieldSharePercentage == 0) {
            vaultData.lastGlobalDepositIndex = globalDepositIndex;
            return (0, totalAssetsDepositedAllCollections, currentTotalYieldGenerated);
        }

        uint256 lastIndex = vaultData.lastGlobalDepositIndex;
        newTotalAssetsDepositedAllCollections = totalAssetsDepositedAllCollections;
        newTotalYieldGenerated = currentTotalYieldGenerated;

        if (globalDepositIndex > lastIndex) {
            uint256 accruedRatio = globalDepositIndex - lastIndex;
            yieldAccrued = (vaultData.totalAssetsDeposited * accruedRatio * registryCollection.yieldSharePercentage)
                / (DEPOSIT_INDEX_PRECISION * 10000);

            if (yieldAccrued > 0) {
                vaultData.totalAssetsDeposited += yieldAccrued;
                newTotalAssetsDepositedAllCollections += yieldAccrued;

                // Track collection-specific yield generation
                newTotalYieldGenerated += yieldAccrued;

                emit CollectionYieldGenerated(collectionAddress, yieldAccrued, block.timestamp);
                emit CollectionYieldAccrued(
                    collectionAddress, yieldAccrued, vaultData.totalAssetsDeposited, globalDepositIndex, lastIndex
                );
            }
        }
        vaultData.lastGlobalDepositIndex = globalDepositIndex;
    }

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
        ) / (DEPOSIT_INDEX_PRECISION * 10000);
    }

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

    // VIEW FUNCTIONS
    function getCollectionTotalBorrowVolume(
        mapping(address => uint256) storage collectionTotalBorrowVolume,
        address collectionAddress
    ) external view returns (uint256) {
        return collectionTotalBorrowVolume[collectionAddress];
    }

    function getCollectionTotalYieldGenerated(
        mapping(address => uint256) storage collectionTotalYieldGenerated,
        address collectionAddress
    ) external view returns (uint256) {
        return collectionTotalYieldGenerated[collectionAddress];
    }

    function getCollectionPerformanceScore(
        mapping(address => uint256) storage collectionPerformanceScore,
        address collectionAddress
    ) external view returns (uint256) {
        return collectionPerformanceScore[collectionAddress];
    }

    function getTotalAvailableYield(ILendingManager lendingManager)
        external
        view
        returns (uint256 totalAvailableYield)
    {
        if (address(lendingManager) == address(0)) {
            return 0;
        }
        return lendingManager.totalAssets() > lendingManager.totalPrincipalDeposited()
            ? lendingManager.totalAssets() - lendingManager.totalPrincipalDeposited()
            : 0;
    }

    function getRemainingCumulativeYield(ILendingManager lendingManager, uint256 totalYieldAllocatedCumulative)
        external
        view
        returns (uint256 remainingYield)
    {
        if (address(lendingManager) == address(0)) {
            return 0;
        }
        uint256 totalYield = lendingManager.totalAssets() > lendingManager.totalPrincipalDeposited()
            ? lendingManager.totalAssets() - lendingManager.totalPrincipalDeposited()
            : 0;
        return totalYield > totalYieldAllocatedCumulative ? totalYield - totalYieldAllocatedCumulative : 0;
    }

    function totalCollectionYieldShareBps(
        address[] storage allCollectionAddresses,
        ICollectionRegistry collectionRegistry
    ) external view returns (uint16 totalBps) {
        uint256 length = allCollectionAddresses.length;
        for (uint256 i = 0; i < length;) {
            totalBps += collectionRegistry.getCollection(allCollectionAddresses[i]).yieldSharePercentage;
            unchecked {
                ++i;
            }
        }
    }
}
