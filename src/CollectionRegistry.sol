// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlBase} from "./AccessControlBase.sol";
import {CrossContractSecurity} from "./CrossContractSecurity.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";
import {Roles} from "./Roles.sol";

contract CollectionRegistry is ICollectionRegistry, AccessControlBase, CrossContractSecurity {
    bytes32 public constant COLLECTION_MANAGER_ROLE = Roles.COLLECTION_MANAGER_ROLE;

    mapping(address => ICollectionRegistry.Collection) private _collections;
    address[] private _allCollections;
    mapping(address => bool) private _isRegistered;
    mapping(address => bool) private _isRemoved;
    mapping(address => mapping(address => bool)) private _collectionHasVault;
    mapping(address => uint256) private _vaultIndexInCollection;
    uint16 public totalYieldBps;

    constructor(address admin) AccessControlBase(admin) {
        _grantRole(COLLECTION_MANAGER_ROLE, admin);
    }

    function removeCollection(address collection) external onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        if (!_isRemoved[collection]) {
            _isRemoved[collection] = true;
            totalYieldBps -= _collections[collection].yieldSharePercentage;
            emit CollectionRemoved(collection);
        }
    }

    function reactivateCollection(address collection) external onlyRoleWhenNotPaused(COLLECTION_MANAGER_ROLE) {
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        if (_isRemoved[collection]) {
            uint16 newTotal = totalYieldBps + _collections[collection].yieldSharePercentage;
            require(newTotal <= 10000, "CollectionRegistry: Total yield share exceeds 10000 bps");
            _isRemoved[collection] = false;
            totalYieldBps = newTotal;
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
            uint16 newTotal = totalYieldBps + collectionData.yieldSharePercentage;
            require(newTotal <= 10000, "CollectionRegistry: Total yield share exceeds 10000 bps");
            _isRegistered[collectionAddress] = true;
            _allCollections.push(collectionAddress);
            _collections[collectionAddress] = collectionData;
            _isRemoved[collectionAddress] = false;
            totalYieldBps = newTotal;

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
        if (!_isRemoved[collection]) {
            uint16 newTotal = totalYieldBps - oldShare + share;
            require(newTotal <= 10000, "CollectionRegistry: Total yield share exceeds 10000 bps");
            totalYieldBps = newTotal;
        }
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
        require(!_collectionHasVault[collection][vault], "CollectionRegistry: Vault already added");

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
        require(_isRegistered[collection], "CollectionRegistry: Not registered");
        require(_collectionHasVault[collection][vault], "CollectionRegistry: Vault not found");

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
        require(_isRegistered[collection] && !_isRemoved[collection], "CollectionRegistry: Not registered");
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
