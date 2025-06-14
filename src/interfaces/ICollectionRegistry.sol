// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICollectionRegistry {
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
        int256 p1; // Parameter 1 for the weight function
        int256 p2; // Parameter 2 for the weight function
        uint16 yieldSharePercentage;
        address[] vaults;
    }

    // --- Functions ---
    function registerCollection(Collection calldata collection) external;
    function setYieldShare(address collection, uint16 share) external;
    function setWeightFunction(address collection, WeightFunction calldata weightFunction, int256 p1, int256 p2)
        external;
    function addVaultToCollection(address collection, address vault) external;
    function removeVaultFromCollection(address collection, address vault) external;
    function isRegistered(address collection) external view returns (bool);
    function getCollection(address collection) external view returns (Collection memory);
    function allCollections() external view returns (address[] memory);
}
