// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILendingManager} from "./ILendingManager.sol";

interface ICollectionsVault {
    // --- Events ---

    event CollectionDeposit(
        address indexed collectionAddress,
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );
    event CollectionWithdraw(
        address indexed collectionAddress,
        address caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event LendingManagerChanged(
        address indexed oldLendingManager, address indexed newLendingManager, address indexed changedBy
    );

    event CollectionYieldTransferred(address indexed collectionAddress, uint256 amount);

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
