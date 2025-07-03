// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {IEpochManager} from "../src/interfaces/IEpochManager.sol";

contract RedeployEpochManager is Script {
    // Current deployed contract addresses from config
    address constant EXISTING_EPOCH_MANAGER = 0x5B6dD10DD0fa3454a2749dec1dcBc9e0983620DA;
    address constant DEBT_SUBSIDIZER = 0xf45CfbC6553BA36328Aba23A4473D4b4a3F569aF;
    address constant COLLECTIONS_VAULT = 0x5383d03855f9b29DE4BAdBD1649ccEB61c19D99E;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        console.log("=== Redeploying EpochManager ===");
        console.log("Deployer:", deployer);
        console.log("Current EpochManager:", EXISTING_EPOCH_MANAGER);

        // Get existing configuration from current EpochManager
        EpochManager existingEpochManager = EpochManager(EXISTING_EPOCH_MANAGER);
        uint256 currentEpochDuration = existingEpochManager.epochDuration();
        address currentAutomatedSystem = existingEpochManager.automatedSystem();
        address currentOwner = existingEpochManager.owner();

        console.log("Current epoch duration:", currentEpochDuration);
        console.log("Current automated system:", currentAutomatedSystem);
        console.log("Current owner:", currentOwner);

        // Deploy new EpochManager with same configuration
        EpochManager newEpochManager = new EpochManager(
            currentEpochDuration,
            currentAutomatedSystem,
            currentOwner,
            DEBT_SUBSIDIZER
        );

        console.log("New EpochManager deployed at:", address(newEpochManager));

        // Check if deployer has admin role on CollectionsVault
        CollectionsVault vault = CollectionsVault(COLLECTIONS_VAULT);
        bytes32 adminRole = vault.ADMIN_ROLE();

        if (!vault.hasRole(adminRole, deployer)) {
            console.log("Deployer does not have ADMIN_ROLE on CollectionsVault");
            console.log("Current deployer:", deployer);
            console.log("Required role:", vm.toString(adminRole));
            revert("Deployer lacks ADMIN_ROLE on existing contracts");
        }

        // Update CollectionsVault to use new EpochManager
        vault.setEpochManager(address(newEpochManager));
        console.log("Updated CollectionsVault epochManager to:", address(newEpochManager));

        // Grant VAULT_ROLE to CollectionsVault on new EpochManager
        newEpochManager.grantVaultRole(COLLECTIONS_VAULT);
        console.log("Granted VAULT_ROLE to CollectionsVault on new EpochManager");

        // Verify the update was successful
        address updatedEpochManager = address(vault.epochManager());
        require(updatedEpochManager == address(newEpochManager), "EpochManager update failed");

        // Verify VAULT_ROLE was granted
        bytes32 vaultRole = newEpochManager.VAULT_ROLE();
        require(newEpochManager.hasRole(vaultRole, COLLECTIONS_VAULT), "VAULT_ROLE grant failed");

        vm.stopBroadcast();

        console.log("=== Redeployment Summary ===");
        console.log("Old EpochManager:", EXISTING_EPOCH_MANAGER);
        console.log("New EpochManager:", address(newEpochManager));
        console.log("CollectionsVault updated:", COLLECTIONS_VAULT);
        console.log("All operations completed successfully!");
        console.log("");
        console.log("=== MANUAL UPDATES REQUIRED ===");
        console.log("Update the following configuration files:");
        console.log("1. epoch-server/configs/config.yaml");
        console.log("   epoch_manager: \"%s\"", vm.toString(address(newEpochManager)));
        console.log("2. Any other environment-specific configs with EpochManager address");
        console.log("3. Update contract bindings if needed:");
        console.log("   ../scripts/generate_bindings.sh");
    }
}