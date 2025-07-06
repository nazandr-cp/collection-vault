// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {Roles} from "../src/Roles.sol";

contract CheckRoles is Script {
    function run() external {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        CollectionsVault vault = CollectionsVault(vaultAddress);

        address sender = vm.envAddress("SENDER");
        address defaultSender = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

        console.log("Vault address:", vaultAddress);
        console.log("Sender:", sender);
        console.log("DefaultSender:", defaultSender);

        // Check DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = vault.DEFAULT_ADMIN_ROLE();
        console.log("DEFAULT_ADMIN_ROLE:", vm.toString(defaultAdminRole));

        console.log("Sender has DEFAULT_ADMIN_ROLE:", vault.hasRole(defaultAdminRole, sender));
        console.log("DefaultSender has DEFAULT_ADMIN_ROLE:", vault.hasRole(defaultAdminRole, defaultSender));

        // Check ADMIN_ROLE
        bytes32 adminRole = Roles.ADMIN_ROLE;
        console.log("ADMIN_ROLE:", vm.toString(adminRole));

        console.log("Sender has ADMIN_ROLE:", vault.hasRole(adminRole, sender));
        console.log("DefaultSender has ADMIN_ROLE:", vault.hasRole(adminRole, defaultSender));
    }
}
