// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";

contract ConfigureVault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address epochManagerAddress = vm.envAddress("EPOCH_MANAGER_ADDRESS");
        
        vm.startBroadcast(deployerKey);

        // Get the vault instance
        CollectionsVault vault = CollectionsVault(vaultAddress);
        
        // Check if EpochManager is already set
        address currentEpochManager = address(vault.epochManager());
        if (currentEpochManager == address(0)) {
            console.log("Setting EpochManager on vault...");
            vault.setEpochManager(epochManagerAddress);
            console.log("EpochManager configured successfully");
        } else {
            console.log("EpochManager already set to:", currentEpochManager);
            if (currentEpochManager != epochManagerAddress) {
                console.log("WARNING: Current EpochManager differs from expected:");
                console.log("Current:", currentEpochManager);
                console.log("Expected:", epochManagerAddress);
                
                // Update to the correct EpochManager
                vault.setEpochManager(epochManagerAddress);
                console.log("EpochManager updated to:", epochManagerAddress);
            }
        }

        vm.stopBroadcast();
        
        // Log final configuration
        console.log("=== VAULT CONFIGURATION COMPLETE ===");
        console.log("Vault Address:", vaultAddress);
        console.log("EpochManager Address:", epochManagerAddress);
        console.log("Configuration verified successfully");
    }
}