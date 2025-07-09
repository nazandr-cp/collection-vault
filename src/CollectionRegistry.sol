// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RolesBase} from "./RolesBase.sol";
import {CrossContractSecurity} from "./CrossContractSecurity.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";
import {Roles} from "./Roles.sol";

contract CollectionRegistry is ICollectionRegistry, RolesBase, CrossContractSecurity {
    bytes32 public constant COLLECTION_MANAGER_ROLE = Roles.COLLECTION_MANAGER_ROLE;

    // Custom errors
    error CollectionNotRegistered(address collection);
    error VaultAlreadyAdded(address collection, address vault);
    error VaultNotFound(address collection, address vault);
    error YieldShareExceedsLimit(uint256 share, uint256 maxShare);
    error ZeroAddress();

    mapping(address => ICollectionRegistry.Collection) private _collections;
    address[] private _allCollections;
    mapping(address => bool) private _isRegistered;
    mapping(address => bool) private _isRemoved;
    mapping(address => mapping(address => bool)) private _collectionHasVault;
    mapping(address => uint256) private _vaultIndexInCollection;

    constructor(address admin) RolesBase(admin) {
        _grantRole(COLLECTION_MANAGER_ROLE, admin);
    }

    function removeCollection(address collection) external onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE) {
        if (!_isRegistered[collection]) revert CollectionNotRegistered(collection);
        if (!_isRemoved[collection]) {
            _isRemoved[collection] = true;
            emit CollectionRemoved(collection);
        }
    }

    function reactivateCollection(address collection) external onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE) {
        if (!_isRegistered[collection]) revert CollectionNotRegistered(collection);
        if (_isRemoved[collection]) {
            _isRemoved[collection] = false;
            emit CollectionReactivated(collection);
        }
    }

    function registerCollection(ICollectionRegistry.Collection calldata collectionData)
        public
        override
        onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE)
        rateLimited(address(this), this.registerCollection.selector)
    {
        address collectionAddress = collectionData.collectionAddress;
        if (collectionAddress == address(0)) revert ZeroAddress();
        if (collectionData.yieldSharePercentage > 10000) {
            revert YieldShareExceedsLimit(collectionData.yieldSharePercentage, 10000);
        }
        if (!_isRegistered[collectionAddress]) {
            _isRegistered[collectionAddress] = true;
            _allCollections.push(collectionAddress);
            _collections[collectionAddress] = collectionData;
            _isRemoved[collectionAddress] = false;

            emit CollectionRegistered(
                collectionAddress,
                collectionData.collectionType,
                collectionData.weightFunction.fnType,
                collectionData.weightFunction.p1,
                collectionData.weightFunction.p2,
                collectionData.yieldSharePercentage
            );
        }
    }

    function setYieldShare(address collection, uint16 share)
        external
        override
        onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE)
    {
        if (!_isRegistered[collection]) revert CollectionNotRegistered(collection);
        if (share > 10000) {
            revert YieldShareExceedsLimit(share, 10000);
        }
        uint16 oldShare = _collections[collection].yieldSharePercentage;
        _collections[collection].yieldSharePercentage = share;
        emit YieldShareUpdated(collection, oldShare, share);
    }

    function setWeightFunction(address collection, ICollectionRegistry.WeightFunction calldata weightFunction)
        external
        override
        onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE)
    {
        if (!_isRegistered[collection]) revert CollectionNotRegistered(collection);
        _collections[collection].weightFunction = weightFunction;
        emit WeightFunctionUpdated(collection, weightFunction.fnType, weightFunction.p1, weightFunction.p2);
    }

    function addVaultToCollection(address collection, address vault)
        external
        override
        onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE)
        rateLimited(address(this), this.addVaultToCollection.selector)
        contractValidated(vault)
    {
        if (!_isRegistered[collection]) revert CollectionNotRegistered(collection);
        if (vault == address(0)) revert ZeroAddress();
        if (_collectionHasVault[collection][vault]) revert VaultAlreadyAdded(collection, vault);

        _collections[collection].vaults.push(vault);
        _collectionHasVault[collection][vault] = true;
        _vaultIndexInCollection[vault] = _collections[collection].vaults.length - 1;
        emit VaultAddedToCollection(collection, vault);
    }

    function removeVaultFromCollection(address collection, address vault)
        external
        override
        onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE)
    {
        if (!_isRegistered[collection]) revert CollectionNotRegistered(collection);
        if (!_collectionHasVault[collection][vault]) revert VaultNotFound(collection, vault);

        uint256 vaultIndex = _vaultIndexInCollection[vault];
        address lastVault = _collections[collection].vaults[_collections[collection].vaults.length - 1];

        _collections[collection].vaults[vaultIndex] = lastVault;
        _vaultIndexInCollection[lastVault] = vaultIndex;
        _collections[collection].vaults.pop();

        delete _collectionHasVault[collection][vault];
        delete _vaultIndexInCollection[vault];
        emit VaultRemovedFromCollection(collection, vault);
    }

    // --- View Functions ---

    function getCollection(address collection) external view override returns (ICollectionRegistry.Collection memory) {
        if (!_isRegistered[collection] || _isRemoved[collection]) revert CollectionNotRegistered(collection);
        return _collections[collection];
    }

    function isRegistered(address collection) external view override returns (bool) {
        return _isRegistered[collection] && !_isRemoved[collection];
    }

    function isCollectionRemoved(address collection) external view returns (bool) {
        return _isRemoved[collection];
    }

    function allCollections() external view override returns (address[] memory) {
        uint256 length = _allCollections.length;
        uint256 count;
        for (uint256 i = 0; i < length; i++) {
            if (!_isRemoved[_allCollections[i]]) {
                count++;
            }
        }
        address[] memory active = new address[](count);
        uint256 index;
        for (uint256 i = 0; i < length; i++) {
            address col = _allCollections[i];
            if (!_isRemoved[col]) {
                active[index++] = col;
            }
        }
        return active;
    }
}
