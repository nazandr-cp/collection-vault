// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CollectionRegistry} from "../src/CollectionRegistry.sol";
import {ICollectionRegistry} from "../src/interfaces/ICollectionRegistry.sol";
import {Roles} from "../src/Roles.sol";

contract RegisterCollection is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address nftAddress = vm.envAddress("NFT_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");

        // Get deployed CollectionRegistry address (from your deployment)
        address registryAddress = 0x0bFb4027C2257C354df64Ca00E526B0c3176bcd1;

        vm.startBroadcast(deployerKey);

        CollectionRegistry registry = CollectionRegistry(registryAddress);

        // Register the collection
        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: nftAddress,
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1.0e18, // 1.0 in 18 decimals
                p2: 0
            }),
            yieldSharePercentage: 5000, // 50%
            vaults: new address[](0)
        });

        registry.registerCollection(collectionData);
        console.log("Collection registered:", nftAddress);

        // Connect collection to vault
        registry.addVaultToCollection(nftAddress, vaultAddress);
        console.log("Collection connected to vault:", vaultAddress);

        vm.stopBroadcast();
    }
}
