// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";

contract CollectionRegistry is ICollectionRegistry, AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(address => ICollectionsVault.Collection) private _collections;
    address[] private _allCollections;
    mapping(address => bool) private _isRegistered;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    function registerCollection(address collection) public override onlyRole(MANAGER_ROLE) {
        if (!_isRegistered[collection]) {
            _isRegistered[collection] = true;
            _allCollections.push(collection);
            _collections[collection].collectionAddress = collection;
        }
    }

    function updateCollection(address collection, ICollectionsVault.Collection calldata data)
        external
        override
        onlyRole(MANAGER_ROLE)
    {
        if (!_isRegistered[collection]) {
            registerCollection(collection);
        }
        _collections[collection] = data;
    }

    function setYieldShare(address collection, uint16 share) external override onlyRole(MANAGER_ROLE) {
        if (!_isRegistered[collection]) {
            registerCollection(collection);
        }
        _collections[collection].yieldSharePercentage = share;
    }

    function getCollection(address collection)
        external
        view
        override
        returns (ICollectionsVault.Collection memory)
    {
        return _collections[collection];
    }

    function isRegistered(address collection) external view override returns (bool) {
        return _isRegistered[collection];
    }

    function allCollections() external view override returns (address[] memory) {
        return _allCollections;
    }
}
