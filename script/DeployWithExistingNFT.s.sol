// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {CollectionRegistry} from "../src/CollectionRegistry.sol";
import {ICollectionRegistry} from "../src/interfaces/ICollectionRegistry.sol";
import {DebtSubsidizer} from "../src/DebtSubsidizer.sol";
import {Roles} from "../src/Roles.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {CErc20Immutable} from "compound-protocol-2.8.1/contracts/CErc20Immutable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployWithExistingNFT is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address existingNFT = vm.envAddress("NFT_ADDRESS");
        vm.startBroadcast(deployerKey);

        // Use already deployed Compound addresses from environment
        address asset = vm.envAddress("ASSET_ADDRESS"); // underlyingAddr
        address cToken = vm.envAddress("CTOKEN_ADDRESS"); // cTokenAddr
        // address comptroller = vm.envAddress("COMPTROLLER_ADDRESS");

        // Deploy new contracts that depend on Compound
        // Use the actual SENDER address as admin for all contracts
        address admin = vm.envAddress("SENDER");

        LendingManager lendingManager = new LendingManager(admin, admin, asset, cToken);
        CollectionRegistry collectionRegistry = new CollectionRegistry(admin);
        CollectionsVault vault = new CollectionsVault(
            MockERC20(asset), "Vault mUSDC", "vMOCK", admin, address(lendingManager), address(collectionRegistry)
        );
        // Deploy EpochManager first without DebtSubsidizer reference
        EpochManager epochManager = new EpochManager(1 days, admin, admin, address(0));
        DebtSubsidizer debtImpl = new DebtSubsidizer();

        bytes memory initData =
            abi.encodeWithSelector(DebtSubsidizer.initialize.selector, admin, address(collectionRegistry));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(debtImpl), admin, initData);
        DebtSubsidizer debtSubsidizer = DebtSubsidizer(address(proxy));

        // Register the existing NFT collection
        collectionRegistry.registerCollection(
            ICollectionRegistry.Collection({
                collectionAddress: existingNFT,
                collectionType: ICollectionRegistry.CollectionType.ERC721,
                weightFunction: ICollectionRegistry.WeightFunction({
                    fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                    p1: 1.0e18,
                    p2: 0
                }),
                yieldSharePercentage: 5000,
                vaults: new address[](0)
            })
        );

        // Connect collection to vault
        collectionRegistry.addVaultToCollection(existingNFT, address(vault));

        // Grant OPERATOR_ROLE to vault on LendingManager (needed for lending protocol interactions)
        lendingManager.grantRoleWithDetails(Roles.OPERATOR_ROLE, address(vault));

        // Configure vault with EpochManager and proper roles

        // 1. Set EpochManager on vault
        address currentEpochManager = address(vault.epochManager());
        if (currentEpochManager == address(0)) {
            vault.setEpochManager(address(epochManager));
        } else if (currentEpochManager != address(epochManager)) {
            console.log("WARNING: Current EpochManager differs from expected:");
            console.log("Current:", currentEpochManager);
            console.log("Expected:", address(epochManager));
            vault.setEpochManager(address(epochManager));
            console.log("EpochManager updated to:", address(epochManager));
        } else {
            console.log("EpochManager already set correctly:", currentEpochManager);
        }

        // 2. Grant OPERATOR_ROLE to admin (epoch server caller) on vault using enhanced role system
        bool hasOperatorRole = vault.hasRole(Roles.OPERATOR_ROLE, admin);
        if (!hasOperatorRole) {
            vault.grantRoleWithDetails(Roles.OPERATOR_ROLE, admin);
        }

        // 3. Grant OPERATOR_ROLE to vault on EpochManager (needed for allocateVaultYield)
        bool vaultHasRoleOnEpochManager = epochManager.hasRole(Roles.OPERATOR_ROLE, address(vault));
        if (!vaultHasRoleOnEpochManager) {
            epochManager.grantRoleWithDetails(Roles.OPERATOR_ROLE, address(vault));
        } else {
            console.log("Vault already has OPERATOR_ROLE on EpochManager");
        }

        // 4. Configure Cross-Contract Security Features

        // Validate critical contract addresses for CrossContractSecurity
        vault.validateContract(address(lendingManager));
        epochManager.validateContract(address(vault));
        epochManager.validateContract(address(debtSubsidizer));

        // 5. Add vault to DebtSubsidizer to enable subgraph CollectionVault template
        debtSubsidizer.addVault(address(vault), address(lendingManager));

        // 6. Make initial deposit to create CollectionParticipation for subgraph
        uint256 initialDepositAmount = 1000 * (10 ** MockERC20(asset).decimals()); // 1000 tokens

        // Grant collection operator access to the deployer
        vault.grantCollectionAccess(existingNFT, admin);

        // Approve the vault to spend tokens
        MockERC20(asset).approve(address(vault), initialDepositAmount);

        // Deposit to the vault for the NFT collection
        vault.depositForCollection(initialDepositAmount, admin, existingNFT);

        vm.stopBroadcast();

        // === ROLE VERIFICATION ===

        // Verify admin has all required roles
        require(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "Admin missing DEFAULT_ADMIN_ROLE on vault");
        require(vault.hasRole(Roles.OWNER_ROLE, admin), "Admin missing OWNER_ROLE on vault");
        require(vault.hasRole(Roles.ADMIN_ROLE, admin), "Admin missing ADMIN_ROLE on vault");
        require(vault.hasRole(Roles.GUARDIAN_ROLE, admin), "Admin missing GUARDIAN_ROLE on vault");
        require(vault.hasRole(Roles.OPERATOR_ROLE, admin), "Admin missing OPERATOR_ROLE on vault");
        console.log("Admin has all required roles on vault");

        // Verify cross-contract permissions
        require(
            lendingManager.hasRole(Roles.OPERATOR_ROLE, address(vault)), "Vault missing OPERATOR_ROLE on LendingManager"
        );
        require(
            epochManager.hasRole(Roles.OPERATOR_ROLE, address(vault)), "Vault missing OPERATOR_ROLE on EpochManager"
        );
        require(
            collectionRegistry.hasRole(Roles.COLLECTION_MANAGER_ROLE, admin), "Admin missing COLLECTION_MANAGER_ROLE"
        );
        console.log("All cross-contract permissions verified");

        // Verify collection operator access
        require(vault.isCollectionOperator(existingNFT, admin), "Admin missing collection operator access");
        console.log("Collection operator access verified");

        // Log deployed contract addresses
        console.log("Asset:", asset);
        console.log("cToken:", cToken);
        console.log("Existing NFT:", existingNFT);
        console.log("LendingManager:", address(lendingManager));
        console.log("CollectionRegistry:", address(collectionRegistry));
        console.log("CollectionsVault:", address(vault));
        console.log("EpochManager:", address(epochManager));
        console.log("DebtSubsidizer Implementation:", address(debtImpl));
        console.log("DebtSubsidizer Proxy:", address(debtSubsidizer));
    }
}
