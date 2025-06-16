// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILendingManager} from "./ILendingManager.sol";
import {IEpochManager} from "./IEpochManager.sol";

interface ICollectionsVault is IERC4626 {
    // --- Structs ---
    struct CollectionVaultData {
        uint256 totalAssetsDeposited;
        uint256 totalSharesMinted;
        uint256 totalCTokensMinted;
        uint256 lastGlobalDepositIndex;
    }

    // --- Events ---
    /**
     * @dev Emitted when assets are deposited into the vault on behalf of a collection.
     * @param collectionAddress The address of the collection.
     * @param caller The address that initiated the deposit.
     * @param receiver The address that receives the shares.
     * @param assets The amount of underlying assets deposited.
     * @param shares The amount of vault shares minted.
     * @param cTokenAmount The amount of cTokens (shares) minted.
     */
    event CollectionDeposit(
        address indexed collectionAddress,
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 cTokenAmount
    );

    /**
     * @dev Emitted when shares are minted for a collection.
     * @param collectionAddress The address of the collection.
     * @param caller The address that initiated the minting.
     * @param receiver The address that receives the assets.
     * @param assets The amount of underlying assets received.
     * @param shares The amount of vault shares minted.
     * @param cTokenAmount The amount of cTokens (shares) minted.
     */
    event CollectionWithdraw(
        address indexed collectionAddress,
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 cTokenAmount
    );
    event LendingManagerChanged(
        address indexed oldLendingManager, address indexed newLendingManager, address indexed changedBy
    );

    event YieldBatchRepaid(uint256 totalAmount, address indexed recipient);
    event CollectionYieldIndexed(
        address indexed collectionAddress, uint256 indexed epochId, uint256 assets, uint256 shares, uint256 cTokenAmount
    );

    event CollectionYieldAccrued(
        address indexed collectionAddress,
        uint256 yieldAccrued,
        uint256 newTotalDeposits,
        uint256 globalIndex,
        uint256 previousCollectionIndex
    );

    event VaultYieldAllocatedToEpoch(uint256 indexed epochId, uint256 amount);

    event CollectionYieldAppliedForEpoch(
        uint256 indexed epochId,
        address indexed collection,
        uint16 yieldSharePercentage,
        uint256 yieldAdded,
        uint256 newTotalDeposits
    );

    event CollectionTransfer(
        address indexed collectionAddress, address indexed from, address indexed to, uint256 assets
    );

    event CollectionAccessGranted(address indexed collection, address indexed operator);
    event CollectionAccessRevoked(address indexed collection, address indexed operator);

    // --- Errors ---

    error LendingManagerDepositFailed();
    error LendingManagerWithdrawFailed();
    error LendingManagerMismatch();
    error AddressZero();
    error Vault_InsufficientBalancePostLMWithdraw();
    error CollectionInsufficientBalance(address collectionAddress, uint256 requested, uint256 available);
    error FunctionDisabledUse(string functionName);
    error InsufficientBalanceInProtocol();
    error ExcessiveYieldAmount(address collection, uint256 requested, uint256 maxAllowed);
    error ShareBalanceUnderflow();
    error CollectionNotRegistered(address collectionAddress);
    error UnauthorizedCollectionAccess(address collectionAddress, address operator);

    // --- Functions ---

    function ADMIN_ROLE() external view returns (bytes32);

    function DEBT_SUBSIDIZER_ROLE() external view returns (bytes32);

    function lendingManager() external view returns (ILendingManager);
    function epochManager() external view returns (IEpochManager);

    function collectionTotalAssetsDeposited(address collectionAddress) external view returns (uint256);
    function totalAssetsDepositedAllCollections() external view returns (uint256);
    function totalYieldReserved() external view returns (uint256);
    function setLendingManager(address _lendingManagerAddress) external;
    function setDebtSubsidizer(address _debtSubsidizerAddress) external;

    function depositForCollection(uint256 assets, address receiver, address collectionAddress)
        external
        returns (uint256 shares);
    function mintForCollection(uint256 shares, address receiver, address collectionAddress)
        external
        returns (uint256 assets);
    function withdrawForCollection(uint256 assets, address receiver, address owner, address collectionAddress)
        external
        returns (uint256 shares);
    function redeemForCollection(uint256 shares, address receiver, address owner, address collectionAddress)
        external
        returns (uint256 assets);
    function transferForCollection(address collectionAddress, address to, uint256 assets)
        external
        returns (uint256 shares);

    function grantCollectionAccess(address collectionAddress, address operator) external;
    function revokeCollectionAccess(address collectionAddress, address operator) external;
    function isCollectionOperator(address collectionAddress, address operator) external view returns (bool);

    function repayBorrowBehalf(uint256 amount, address borrower) external;
    function repayBorrowBehalfBatch(uint256[] calldata amounts, address[] calldata borrowers, uint256 totalAmount)
        external;

    function getCurrentEpochYield(bool includeNonShared) external view returns (uint256 availableYield);
    function allocateEpochYield(uint256 amount) external;
    function allocateYieldToEpoch(uint256 epochId) external;
    function applyCollectionYieldForEpoch(address collection, uint256 epochId) external;
    function resetEpochCollectionYieldFlags(uint256 epochId, address[] calldata collections) external;
    function getEpochYieldAllocated(uint256 epochId) external view returns (uint256 amount);
}
