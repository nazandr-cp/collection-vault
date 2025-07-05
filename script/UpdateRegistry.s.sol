// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CollectionRegistry} from "../src/CollectionRegistry.sol";
import {ICollectionRegistry} from "../src/interfaces/ICollectionRegistry.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {DebtSubsidizer} from "../src/DebtSubsidizer.sol";
import {Roles} from "../src/Roles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UpdateRegistry is Script {
    // Environment addresses
    address constant ASSET_ADDRESS = 0x4dd42d4559f7F5026364550FABE7824AECF5a1d1;
    address constant NFT_COLLECTION = 0xc7CfdB8290571cAA6DF7d4693059aB9E853e22EB;
    address constant CTOKEN_ADDRESS = 0x642d97319cd50D2E5FC7F0FE022Ed87407045e90;
    address constant COMPTROLLER_ADDRESS = 0x7E81fAaF1132A17DCc0C76b1280E0C0e598D5635;

    // Existing deployed contract addresses
    address constant EXISTING_VAULT = 0x5383d03855f9b29DE4BAdBD1649ccEB61c19D99E;
    address constant EXISTING_SUBSIDIZER = 0x6ebe8F36AA3865BBA247A6b1A055Fce3E65Db183;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        // Deploy new CollectionRegistry
        CollectionRegistry newRegistry = new CollectionRegistry(deployer);
        console.log("New CollectionRegistry deployed at:", address(newRegistry));

        // Check if deployer has admin role on existing contracts
        CollectionsVault existingVault = CollectionsVault(EXISTING_VAULT);
        bytes32 adminRole = existingVault.ADMIN_ROLE();

        if (!existingVault.hasRole(adminRole, deployer)) {
            console.log("Deployer does not have ADMIN_ROLE on CollectionsVault");
            console.log("Current deployer:", deployer);
            console.log("Required role:", vm.toString(adminRole));
            revert("Deployer lacks ADMIN_ROLE on existing contracts");
        }

        // Update existing CollectionsVault to use new registry
        existingVault.setCollectionRegistry(address(newRegistry));
        console.log("Updated CollectionsVault registry to:", address(newRegistry));

        // Update existing DebtSubsidizer to use new registry
        DebtSubsidizer existingSubsidizer = DebtSubsidizer(EXISTING_SUBSIDIZER);
        existingSubsidizer.setCollectionRegistry(address(newRegistry));
        console.log("Updated DebtSubsidizer registry to:", address(newRegistry));

        // Register collection data in new registry
        setupCollectionData(newRegistry, EXISTING_VAULT);

        vm.stopBroadcast();

        console.log("=== Update Summary ===");
        console.log("New CollectionRegistry:", address(newRegistry));
        console.log("Updated CollectionsVault:", EXISTING_VAULT);
        console.log("Updated DebtSubsidizer:", EXISTING_SUBSIDIZER);
        console.log("All contracts updated successfully with new registry");
    }

    function setupCollectionData(CollectionRegistry registry, address vaultAddress) internal {
        // Grant COLLECTION_MANAGER_ROLE to the deployer
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        registry.grantRole(Roles.COLLECTION_MANAGER_ROLE, deployer);

        // Register the collection with the same parameters
        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: NFT_COLLECTION,
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 100,
                p2: 0
            }),
            yieldSharePercentage: 5000,
            vaults: new address[](0)
        });

        registry.registerCollection(collectionData);
        registry.addVaultToCollection(NFT_COLLECTION, vaultAddress);

        console.log("Collection registered and vault added to collection");
    }
}
