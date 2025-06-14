// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICollectionsVault} from "./ICollectionsVault.sol";

interface ICollectionRegistry {
    // --- Structs ---
    struct Collection {
        address collectionAddress;
        uint256 totalAssetsDeposited;
        uint256 totalSharesMinted;
        uint256 totalCTokensMinted;
        uint16 yieldSharePercentage;
        uint256 totalYieldTransferred;
        uint256 lastGlobalDepositIndex;
    }

    // --- Functions ---
    function registerCollection(address collection) external;
    function updateCollection(address collection, Collection calldata data) external;
    function setYieldShare(address collection, uint16 share) external;
    function getCollection(address collection) external view returns (Collection memory);
    function isRegistered(address collection) external view returns (bool);
    function allCollections() external view returns (address[] memory);
}
