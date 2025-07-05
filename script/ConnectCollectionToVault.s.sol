// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CollectionRegistry} from "../src/CollectionRegistry.sol";

contract ConnectCollectionToVault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        
        // Contract addresses from environment
        address collectionRegistryAddress = vm.envAddress("COLLECTION_REGISTRY_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address nftAddress = vm.envAddress("NFT_ADDRESS");
        
        vm.startBroadcast(deployerKey);
        
        CollectionRegistry collectionRegistry = CollectionRegistry(collectionRegistryAddress);
        
        // Add vault to collection
        collectionRegistry.addVaultToCollection(nftAddress, vaultAddress);
        
        console.log("Successfully connected collection", nftAddress, "to vault", vaultAddress);
        
        vm.stopBroadcast();
    }
}