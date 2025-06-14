// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";

contract CollectionRegistry is ICollectionRegistry, AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(address => ICollectionRegistry.Collection) private _collections;
    address[] private _allCollections;
    mapping(address => bool) private _isRegistered;
    mapping(address => mapping(address => bool)) private _collectionHasVault;
    mapping(address => uint256) private _vaultIndexInCollection;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    function registerCollection(ICollectionRegistry.Collection calldata collectionData)
        public
        override
        onlyRole(MANAGER_ROLE)
    {
        address collectionAddress = collectionData.collectionAddress;
        require(collectionAddress != address(0), "CollectionRegistry: Zero address");
        if (!_isRegistered[collectionAddress]) {
            _isRegistered[collectionAddress] = true;
            _allCollections.push(collectionAddress);
            _collections[collectionAddress] = collectionData;
        }
    }

    function setYieldShare(address collection, uint16 share) external override onlyRole(MANAGER_ROLE) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        _collections[collection].yieldSharePercentage = share;
    }

    function setWeightFunction(
        address collection,
        ICollectionRegistry.WeightFunction calldata weightFunction,
        int256 p1,
        int256 p2
    ) external override onlyRole(MANAGER_ROLE) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        _collections[collection].weightFunction = weightFunction;
        _collections[collection].p1 = p1;
        _collections[collection].p2 = p2;
    }

    function addVaultToCollection(address collection, address vault) external override onlyRole(MANAGER_ROLE) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        require(vault != address(0), "CollectionRegistry: Zero address");
        require(!_collectionHasVault[collection][vault], "CollectionRegistry: Vault already added");

        _collections[collection].vaults.push(vault);
        _collectionHasVault[collection][vault] = true;
        _vaultIndexInCollection[vault] = _collections[collection].vaults.length - 1;
    }

    function removeVaultFromCollection(address collection, address vault) external override onlyRole(MANAGER_ROLE) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        require(_collectionHasVault[collection][vault], "CollectionRegistry: Vault not found");

        uint256 vaultIndex = _vaultIndexInCollection[vault];
        address lastVault = _collections[collection].vaults[_collections[collection].vaults.length - 1];

        _collections[collection].vaults[vaultIndex] = lastVault;
        _vaultIndexInCollection[lastVault] = vaultIndex;
        _collections[collection].vaults.pop();

        delete _collectionHasVault[collection][vault];
        delete _vaultIndexInCollection[vault];
    }

    // --- View Functions ---

    function getCollection(address collection) external view override returns (ICollectionRegistry.Collection memory) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        return _collections[collection];
    }

    function isRegistered(address collection) external view override returns (bool) {
        return _isRegistered[collection];
    }

    function allCollections() external view override returns (address[] memory) {
        return _allCollections;
    }
}
