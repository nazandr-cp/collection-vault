// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {ICollectionsVault} from "../interfaces/ICollectionsVault.sol";

/**
 * @title CollectionOperationsLib
 * @dev Library for collection deposit/withdraw operations
 * @dev Extracted from CollectionsVault to reduce contract size
 */
library CollectionOperationsLib {
    using SafeERC20 for IERC20;

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

    error ShareBalanceUnderflow();
    error Vault_InsufficientBalancePostLMWithdraw();

    /**
     * @dev Calculates assets and shares for a collection deposit operation
     * @param assetsOrShares The input amount (assets or shares depending on operation)
     * @param operationType The type of deposit operation
     * @param previewDeposit Function to preview deposit conversion
     * @param previewMint Function to preview mint conversion
     * @return assets The amount of assets
     * @return shares The amount of shares
     */
    function calculateDepositAmounts(
        uint256 assetsOrShares,
        DepositOperationType operationType,
        function(uint256) external view returns (uint256) previewDeposit,
        function(uint256) external view returns (uint256) previewMint
    ) external view returns (uint256 assets, uint256 shares) {
        if (operationType == DepositOperationType.DEPOSIT_FOR_COLLECTION || 
            operationType == DepositOperationType.TRANSFER_FOR_COLLECTION) {
            assets = assetsOrShares;
            shares = previewDeposit(assets);
        } else {
            shares = assetsOrShares;
            assets = previewMint(shares);
        }
    }

    /**
     * @dev Updates collection data after a deposit operation
     * @param vaultData The collection's vault data storage
     * @param assets Amount of assets deposited
     * @param shares Amount of shares minted
     * @param totalAssetsDepositedAllCollections Current total (will be updated)
     * @return newTotalAssetsDepositedAllCollections Updated total
     */
    function updateCollectionDataAfterDeposit(
        ICollectionsVault.CollectionVaultData storage vaultData,
        uint256 assets,
        uint256 shares,
        uint256 totalAssetsDepositedAllCollections
    ) external returns (uint256 newTotalAssetsDepositedAllCollections) {
        vaultData.totalAssetsDeposited += assets;
        vaultData.totalSharesMinted += shares;
        vaultData.totalCTokensMinted += shares;
        return totalAssetsDepositedAllCollections + assets;
    }

    /**
     * @dev Handles full redemption logic including dust collection
     * @param assets The base assets amount
     * @param shares The shares being redeemed
     * @param totalSupply The total supply of shares
     * @param lendingManager The lending manager contract
     * @param totalYieldReserved The total yield reserved
     * @return finalAssetsToTransfer The final amount to transfer to user
     */
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
                    bool success = lendingManager.withdrawFromLendingProtocol(redeemable);
                    if (success) {
                        finalAssetsToTransfer += redeemable;
                    }
                }
            }
        }
    }

    /**
     * @dev Performs asset transfer with balance validation
     * @param asset The asset token
     * @param receiver The receiver address
     * @param amount The amount to transfer
     * @param owner The owner address for event
     * @param shares The shares amount for event
     */
    function performAssetTransfer(
        IERC20 asset,
        address receiver,
        uint256 amount,
        address owner,
        uint256 shares
    ) external {
        uint256 vaultBalance = asset.balanceOf(address(this));
        if (vaultBalance < amount) {
            revert Vault_InsufficientBalancePostLMWithdraw();
        }
        asset.safeTransfer(receiver, amount);
        emit Withdraw(msg.sender, receiver, owner, amount, shares);
    }

    /**
     * @dev Updates collection data after withdrawal
     * @param vaultData The collection's vault data storage
     * @param assets The assets withdrawn
     * @param shares The shares burned
     * @param currentCollectionTotalAssets The current collection total assets
     * @param totalAssetsDepositedAllCollections The current total (will be updated)
     * @return newTotalAssetsDepositedAllCollections Updated total
     */
    function updateCollectionDataAfterWithdraw(
        ICollectionsVault.CollectionVaultData storage vaultData,
        uint256 assets,
        uint256 shares,
        uint256 currentCollectionTotalAssets,
        uint256 totalAssetsDepositedAllCollections
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
        
        return totalAssetsDepositedAllCollections - deduction;
    }

    /**
     * @dev Updates collection data after transfer operation
     * @param vaultData The collection's vault data storage
     * @param amount The amount transferred
     * @param totalAssetsDepositedAllCollections The current total (will be updated)
     * @return newTotalAssetsDepositedAllCollections Updated total
     */
    function updateCollectionDataAfterTransfer(
        ICollectionsVault.CollectionVaultData storage vaultData,
        uint256 amount,
        uint256 totalAssetsDepositedAllCollections
    ) external returns (uint256 newTotalAssetsDepositedAllCollections) {
        if (vaultData.totalSharesMinted < amount || vaultData.totalCTokensMinted < amount) {
            revert ShareBalanceUnderflow();
        }
        
        vaultData.totalAssetsDeposited -= amount;
        vaultData.totalSharesMinted -= amount;
        vaultData.totalCTokensMinted -= amount;
        
        return totalAssetsDepositedAllCollections - amount;
    }
}