// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICollectionRegistry {
    // --- Events ---
    event CollectionRegistered(
        address indexed collection,
        CollectionType collectionType,
        WeightFunctionType weightFunctionType,
        int256 p1,
        int256 p2,
        uint16 yieldSharePercentage
    );
    event YieldShareUpdated(address indexed collection, uint16 oldShare, uint16 newShare);
    event WeightFunctionUpdated(
        address indexed collection, WeightFunctionType weightFunctionType, int256 p1, int256 p2
    );
    event VaultAddedToCollection(address indexed collection, address indexed vault);
    event VaultRemovedFromCollection(address indexed collection, address indexed vault);

    event CollectionRemoved(address indexed collection);
    event CollectionReactivated(address indexed collection);
    // --- Structs ---

    enum CollectionType {
        ERC721,
        ERC1155
    }

    enum WeightFunctionType {
        LINEAR,
        EXPONENTIAL
    }

    struct WeightFunction {
        WeightFunctionType fnType;
        int256 p1;
        int256 p2;
    }

    struct Collection {
        address collectionAddress;
        CollectionType collectionType;
        WeightFunction weightFunction;
        uint16 yieldSharePercentage;
        address[] vaults;
    }

    // --- Functions ---
    function registerCollection(Collection calldata collection) external;
    function setYieldShare(address collection, uint16 share) external;
    function setWeightFunction(address collection, WeightFunction calldata weightFunction) external;
    function addVaultToCollection(address collection, address vault) external;
    function removeVaultFromCollection(address collection, address vault) external;
    function isRegistered(address collection) external view returns (bool);
    function getCollection(address collection) external view returns (Collection memory);
    function allCollections() external view returns (address[] memory);
}
