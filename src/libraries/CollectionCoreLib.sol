// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {ICollectionsVault} from "../interfaces/ICollectionsVault.sol";
import {ICollectionRegistry} from "../interfaces/ICollectionRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../Roles.sol";

/**
 * @title CollectionCoreLib
 * @dev Library for collection operations and validation
 */
library CollectionCoreLib {
    using SafeERC20 for IERC20;

    uint256 public constant DEPOSIT_INDEX_PRECISION = 1e18;
    uint256 public constant MAX_PERFORMANCE_SCORE = 10000;

    enum DepositOperationType {
        DEPOSIT_FOR_COLLECTION,
        TRANSFER_FOR_COLLECTION,
        MINT_FOR_COLLECTION
    }

    event CollectionDeposit(
        address indexed collectionAddress,
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 cTokenAmount
    );

    event CollectionWithdraw(
        address indexed collectionAddress,
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 cTokenAmount
    );

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Withdraw(address indexed from, address indexed to, address indexed owner, uint256 assets, uint256 shares);
    event LendingManagerCallFailed(address indexed vault, string operation, uint256 amount, string reason);

    error CollectionNotRegistered(address collectionAddress);
    error CollectionInsufficientBalance(address collectionAddress, uint256 requested, uint256 available);
    error UnauthorizedCollectionAccess(address collectionAddress, address operator);
    error AddressZero();
    error ShareBalanceUnderflow();
    error Vault_InsufficientBalancePostLMWithdraw();
    error LendingManagerWithdrawFailed();
    error PerformanceScoreExceedsLimit(uint256 score, uint256 maxScore);

    function validateAddress(address addr) external pure {
        if (addr == address(0)) revert AddressZero();
    }

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

    function validateCollectionOperator(address collectionAddress, address operator, IAccessControl accessControl)
        external
        view
    {
        if (
            !accessControl.hasRole(Roles.COLLECTION_MANAGER_ROLE, operator)
                && !accessControl.hasRole(Roles.GUARDIAN_ROLE, operator)
        ) {
            revert UnauthorizedCollectionAccess(collectionAddress, operator);
        }
    }

    function validateCollectionBalance(address collectionAddress, uint256 requestedAmount, uint256 availableAmount)
        external
        pure
    {
        if (requestedAmount > availableAmount) {
            revert CollectionInsufficientBalance(collectionAddress, requestedAmount, availableAmount);
        }
    }

    function validatePerformanceScore(uint256 score) external pure {
        if (score > MAX_PERFORMANCE_SCORE) revert PerformanceScoreExceedsLimit(score, MAX_PERFORMANCE_SCORE);
    }

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
            registryCollection.collectionAddress == address(0) || registryCollection.yieldSharePercentage == 0
                || globalDepositIndex <= vaultData.lastGlobalDepositIndex
        ) {
            return vaultData.totalAssetsDeposited;
        }

        uint256 accruedRatio = globalDepositIndex - vaultData.lastGlobalDepositIndex;
        uint256 potentialYieldAccrued = (
            vaultData.totalAssetsDeposited * accruedRatio * registryCollection.yieldSharePercentage
        ) / (DEPOSIT_INDEX_PRECISION * 10000);

        return vaultData.totalAssetsDeposited + potentialYieldAccrued;
    }

    function calculateDepositAmounts(
        uint256 assetsOrShares,
        DepositOperationType operationType,
        function(uint256) external view returns (uint256) previewDeposit,
        function(uint256) external view returns (uint256) previewMint
    ) external view returns (uint256 assets, uint256 shares) {
        if (
            operationType == DepositOperationType.DEPOSIT_FOR_COLLECTION
                || operationType == DepositOperationType.TRANSFER_FOR_COLLECTION
        ) {
            assets = assetsOrShares;
            shares = previewDeposit(assets);
        } else {
            shares = assetsOrShares;
            assets = previewMint(shares);
        }
    }

    function updateCollectionDataAfterDeposit(
        ICollectionsVault.CollectionVaultData storage vaultData,
        uint256 assets,
        uint256 shares,
        uint256 totalAssetsDeposited
    ) external returns (uint256 newTotalAssetsDepositedAllCollections) {
        vaultData.totalAssetsDeposited += assets;
        vaultData.totalSharesMinted += shares;
        vaultData.totalCTokensMinted += shares;
        return totalAssetsDeposited + assets;
    }

    function handleWithdrawOperation(
        uint256 assets,
        IERC20 asset,
        ILendingManager lendingManager,
        uint256 totalYieldReserved,
        address msgSender,
        function(bytes32, address) external view returns (bool) hasRole
    ) external {
        if (assets == 0) return;
        uint256 directBalance = asset.balanceOf(address(this));
        if (directBalance < assets) {
            uint256 neededFromLM = assets - directBalance;
            uint256 availableInLM = lendingManager.totalAssets();
            uint256 reserve = totalYieldReserved;
            uint256 usableInLM = hasRole(Roles.OPERATOR_ROLE, msgSender)
                ? availableInLM
                : (availableInLM > reserve ? availableInLM - reserve : 0);
            if (neededFromLM <= usableInLM && neededFromLM > 0) {
                try lendingManager.withdrawFromLendingProtocol(neededFromLM) returns (bool success) {
                    if (!success) {
                        emit LendingManagerCallFailed(address(this), "withdraw", neededFromLM, "Withdraw false");
                        revert LendingManagerWithdrawFailed();
                    }
                    uint256 balanceAfterLMWithdraw = asset.balanceOf(address(this));
                    if (balanceAfterLMWithdraw < assets) {
                        revert Vault_InsufficientBalancePostLMWithdraw();
                    }
                } catch Error(string memory reason) {
                    emit LendingManagerCallFailed(address(this), "withdraw", neededFromLM, reason);
                    revert LendingManagerWithdrawFailed();
                } catch {
                    emit LendingManagerCallFailed(address(this), "withdraw", neededFromLM, "Unknown");
                    revert LendingManagerWithdrawFailed();
                }
            }
        }
    }

    function handleFullRedemption(
        uint256 assets,
        uint256 shares,
        uint256 totalSupply,
        ILendingManager lendingManager,
        uint256 totalYieldReserved
    ) external returns (uint256 finalAssetsToTransfer) {
        finalAssetsToTransfer = assets;
        bool isFullRedeem = (shares == totalSupply && shares != 0);

        if (isFullRedeem) {
            uint256 remainingDustInLM = lendingManager.totalAssets();
            uint256 reserve = totalYieldReserved;

            if (remainingDustInLM > reserve) {
                uint256 redeemable = remainingDustInLM - reserve;
                if (redeemable > 0) {
                    try lendingManager.withdrawFromLendingProtocol(redeemable) returns (bool success) {
                        if (success) {
                            finalAssetsToTransfer += redeemable;
                        }
                    } catch {}
                }
            }
        }
    }

    function performAssetTransfer(IERC20 asset, address receiver, uint256 amount, address owner, uint256 shares)
        external
    {
        uint256 vaultBalance = asset.balanceOf(address(this));
        if (vaultBalance < amount) {
            revert Vault_InsufficientBalancePostLMWithdraw();
        }
        asset.safeTransfer(receiver, amount);
        emit Withdraw(msg.sender, receiver, owner, amount, shares);
    }

    function updateCollectionDataAfterWithdraw(
        ICollectionsVault.CollectionVaultData storage vaultData,
        uint256 assets,
        uint256 shares,
        uint256 currentCollectionTotalAssets,
        uint256 totalAssetsDeposited
    ) external returns (uint256 newTotalAssetsDepositedAllCollections) {
        uint256 deduction;
        if (assets <= currentCollectionTotalAssets) {
            vaultData.totalAssetsDeposited = currentCollectionTotalAssets - assets;
            deduction = assets;
        } else {
            deduction = currentCollectionTotalAssets;
            vaultData.totalAssetsDeposited = 0;
        }

        if (vaultData.totalSharesMinted < shares || vaultData.totalCTokensMinted < shares) {
            revert ShareBalanceUnderflow();
        }

        vaultData.totalSharesMinted -= shares;
        vaultData.totalCTokensMinted -= shares;

        return totalAssetsDeposited - deduction;
    }
}
