// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILendingManager} from "./ILendingManager.sol";

interface ICollectionsVault is IERC4626 {
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

    event YieldBatchTransferred(uint256 totalAmount, address indexed recipient);

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

    // --- Functions ---

    function ADMIN_ROLE() external view returns (bytes32);

    function REWARDS_CONTROLLER_ROLE() external view returns (bytes32);

    function lendingManager() external view returns (ILendingManager);

    function collectionTotalAssetsDeposited(address collectionAddress) external view returns (uint256);

    function setLendingManager(address _lendingManagerAddress) external;

    function setRewardsControllerRole(address newRewardsController) external;

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

    function transferYieldBatch(
        address[] calldata collections,
        uint256[] calldata amounts,
        uint256 totalAmount,
        address recipient
    ) external;

    function collectionYieldTransferred(address collectionAddress) external view returns (uint256);

    function setCollectionRewardSharePercentage(address collectionAddress, uint16 percentage) external;
}
