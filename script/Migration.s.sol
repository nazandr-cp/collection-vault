// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {DeployConfig} from "./utils/DeployConfig.sol";
// TODO: Import interfaces for old and new MarketVault, and any data structures
// import {IMarketVaultOld} from "src/interfaces/IMarketVaultOld.sol"; // Hypothetical old interface
// import {IMarketVaultNew} from "src/interfaces/IMarketVault.sol"; // Current/new interface

contract Migration is Script {
    DeployConfig deployConfig;

    // --- Configuration ---
    // address public oldMarketVaultAddress; // Address of the contract to migrate from
    // address public newMarketVaultAddress; // Address of the new, deployed MarketVault

    // struct UserData { // Example data structure
    //     address user;
    //     uint256 balance;
    //     // Add other relevant fields
    // }

    constructor() {
        deployConfig = new DeployConfig();
        // oldMarketVaultAddress = vm.envAddress("OLD_MARKET_VAULT_ADDRESS");
        // newMarketVaultAddress = vm.envAddress("NEW_MARKET_VAULT_ADDRESS"); // Should be the deployed proxy address
    }

    function run() external {
        // 1. Select Network and Load Configuration
        DeployConfig.Network selectedNetwork = deployConfig.selectNetwork();
        DeployConfig.NetworkConfig memory networkConfig = deployConfig.getNetworkConfig(selectedNetwork);
        console.log("Starting migration on network:", vm.toString(abi.encodePacked(selectedNetwork)));
        console.log("Using MultiSig/Owner for migration steps:", networkConfig.multiSig);

        // Get migrator address (ensure it has necessary permissions on both contracts)
        address _migrator = vm.envOr("MIGRATOR_ADDRESS", msg.sender);
        // uint256 migratorPrivateKey = vm.envUint("MIGRATOR_PRIVATE_KEY");

        // vm.startBroadcast(migratorPrivateKey); // Or vm.startBroadcast(migrator);

        // --- Pre-Migration Steps ---
        // 1. Pause old contract (if possible and makes sense)
        // IMarketVaultOld oldVault = IMarketVaultOld(oldMarketVaultAddress);
        // if (oldVault.paused() == false) {
        //     console.log("Pausing old MarketVault at", oldMarketVaultAddress);
        //     oldVault.pause(); // Assuming a pause function exists and migrator is owner/admin
        // }

        // 2. Ensure new contract is ready and configured (e.g., set permissions for migrator)
        // IMarketVaultNew newVault = IMarketVaultNew(newMarketVaultAddress);
        // Example: newVault.grantRole(newVault.MIGRATOR_ROLE(), migrator);

        // --- Data Extraction (from old contract) ---
        // This part is highly dependent on the old contract's state and getters.
        // It might involve:
        // - Reading user lists and their balances.
        // - Reading collection data, settings, etc.
        // - This might need to be done off-chain if data is too large or complex for on-chain script.
        // For this example, let's assume a simple getter for a list of users.
        // address[] memory usersToMigrate = oldVault.getAllUsers(); // Hypothetical
        // console.log("Found", usersToMigrate.length, "users to migrate.");

        // --- Data Migration (to new contract) ---
        // Batching is crucial for large datasets to avoid gas limits.
        // uint256 batchSize = 50; // Adjust based on gas costs
        // for (uint i = 0; i < usersToMigrate.length; i += batchSize) {
        //     console.log("Migrating batch starting from user index", i);
        //     // UserData[] memory batchData = new UserData[](batchSize); // Or smaller if at end of list
        //     // uint currentBatchActualSize = 0;
        //     // for (uint j = 0; j < batchSize && (i + j) < usersToMigrate.length; ++j) {
        //         // address user = usersToMigrate[i+j];
        //         // uint256 balance = oldVault.balanceOf(user); // Hypothetical
        //         // batchData[j] = UserData(user, balance);
        //         // currentBatchActualSize++;
        //     // }
        //     // UserData[] memory finalBatch = new UserData[](currentBatchActualSize);
        //     // for(uint k=0; k < currentBatchActualSize; ++k) finalBatch[k] = batchData[k];

        //     // newVault.migrateUsers(finalBatch); // Hypothetical batch migration function
        //     console.log("Batch migrated.");
        // }

        // --- Post-Migration Steps ---
        // 1. Verify data consistency (spot checks, checksums if possible)
        // 2. Unpause new contract if it was deployed paused for migration.
        // 3. Communicate to users about the successful migration.
        // 4. Potentially, permanently disable or self-destruct the old contract (with caution!).
        //    This is a critical step and usually done after a soak period.
        //    Example: oldVault.setMigrationCompleteAndDestruct(newMarketVaultAddress); // Highly hypothetical

        // vm.stopBroadcast();

        console.log("Migration script finished for network:", vm.toString(abi.encodePacked(selectedNetwork)));
        // Note: Complex migrations might require multiple scripts or off-chain components.
    }
}
