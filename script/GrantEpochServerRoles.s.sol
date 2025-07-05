// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {Roles} from "../src/Roles.sol";

contract GrantEpochServerRoles is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address epochServerAddress = vm.envAddress("EPOCH_SERVER_ADDRESS");
        
        // Contract addresses from environment
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address epochManagerAddress = vm.envAddress("EPOCH_MANAGER_ADDRESS");
        
        vm.startBroadcast(deployerKey);
        
        CollectionsVault vault = CollectionsVault(vaultAddress);
        EpochManager epochManager = EpochManager(epochManagerAddress);
        
        console.log("Granting roles to epoch server:", epochServerAddress);
        console.log("Vault address:", vaultAddress);
        console.log("EpochManager address:", epochManagerAddress);
        
        // Grant ADMIN_ROLE on vault (for allocateYieldToEpoch)
        vault.grantRole(Roles.ADMIN_ROLE, epochServerAddress);
        console.log("Granted vault ADMIN_ROLE to epoch server");
        
        // Grant OPERATOR_ROLE on epoch manager (for startEpoch and endEpochWithSubsidies)
        epochManager.grantRole(Roles.OPERATOR_ROLE, epochServerAddress);
        console.log("Granted epoch manager OPERATOR_ROLE to epoch server");
        
        vm.stopBroadcast();
        
        console.log("Role granting completed successfully");
    }
}