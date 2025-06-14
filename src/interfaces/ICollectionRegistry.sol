// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICollectionsVault} from "./ICollectionsVault.sol";

interface ICollectionRegistry {
    function registerCollection(address collection) external;
    function updateCollection(address collection, ICollectionsVault.Collection calldata data) external;
    function setYieldShare(address collection, uint16 share) external;
    function getCollection(address collection) external view returns (ICollectionsVault.Collection memory);
    function isRegistered(address collection) external view returns (bool);
    function allCollections() external view returns (address[] memory);
}
