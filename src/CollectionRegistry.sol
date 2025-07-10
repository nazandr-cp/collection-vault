// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlBase} from "./AccessControlBase.sol";
import {CrossContractSecurity} from "./CrossContractSecurity.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";
import {Roles} from "./Roles.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract CollectionRegistry is ICollectionRegistry, AccessControlBase, CrossContractSecurity {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant COLLECTION_MANAGER_ROLE = Roles.COLLECTION_MANAGER_ROLE;

    struct CollectionInfo {
        address collectionAddress;
        ICollectionRegistry.CollectionType collectionType;
        ICollectionRegistry.WeightFunction weightFunction;
        uint16 yieldSharePercentage;
    }

    mapping(address => CollectionInfo) private _collections;
    mapping(address => EnumerableSet.AddressSet) private _collectionVaults;
    address[] private _allCollections;
    mapping(address => bool) private _isRegistered;
    mapping(address => bool) private _isRemoved;

    constructor(address admin) AccessControlBase(admin) {
        _grantRole(COLLECTION_MANAGER_ROLE, admin);
    }

    function removeCollection(address collection) external onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        if (!_isRemoved[collection]) {
            _isRemoved[collection] = true;
            emit CollectionRemoved(collection);
        }
    }

    function reactivateCollection(address collection) external onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
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
        require(collectionAddress != address(0), "CollectionRegistry: Zero address");
        if (collectionData.yieldSharePercentage > 10000) {
            revert("CollectionRegistry: Yield share percentage cannot exceed 10000 (100%)");
        }
        if (!_isRegistered[collectionAddress]) {
            _isRegistered[collectionAddress] = true;
            _allCollections.push(collectionAddress);
            _collections[collectionAddress] = CollectionInfo({
                collectionAddress: collectionAddress,
                collectionType: collectionData.collectionType,
                weightFunction: collectionData.weightFunction,
                yieldSharePercentage: collectionData.yieldSharePercentage
            });
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
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        if (share > 10000) {
            revert("CollectionRegistry: Yield share percentage cannot exceed 10000 (100%)");
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
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
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
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        require(vault != address(0), "CollectionRegistry: Zero address");
        bool added = _collectionVaults[collection].add(vault);
        require(added, "CollectionRegistry: Vault already added");
        emit VaultAddedToCollection(collection, vault);
    }

    function removeVaultFromCollection(address collection, address vault)
        external
        override
        onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE)
    {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        bool removed = _collectionVaults[collection].remove(vault);
        require(removed, "CollectionRegistry: Vault not found");
        emit VaultRemovedFromCollection(collection, vault);
    }

    // --- View Functions ---

    function getCollection(address collection) external view override returns (ICollectionRegistry.Collection memory) {
        require(_isRegistered[collection] && !_isRemoved[collection], "CollectionRegistry: Not registered");
        CollectionInfo storage info = _collections[collection];
        address[] memory vaults = _collectionVaults[collection].values();
        return ICollectionRegistry.Collection({
            collectionAddress: info.collectionAddress,
            collectionType: info.collectionType,
            weightFunction: info.weightFunction,
            yieldSharePercentage: info.yieldSharePercentage,
            vaults: vaults
        });
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
