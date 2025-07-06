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
            MockERC20(asset), "Vault", "vMOCK", admin, address(lendingManager), address(collectionRegistry)
        );
        // Deploy EpochManager first without DebtSubsidizer reference
        EpochManager epochManager = new EpochManager(1 days, admin, admin, address(0));
        DebtSubsidizer debtImpl = new DebtSubsidizer();

        bytes memory initData =
            abi.encodeWithSelector(DebtSubsidizer.initialize.selector, admin, address(collectionRegistry));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(debtImpl), admin, initData);
        DebtSubsidizer debtSubsidizer = DebtSubsidizer(address(proxy));

        console.log("DebtSubsidizer Implementation:", address(debtImpl));
        console.log("DebtSubsidizer Proxy:", address(proxy));

        // Since admin is now SENDER and contracts grant roles to admin, SENDER already has all required roles
        // Grant COLLECTION_MANAGER_ROLE to SENDER (admin already has admin role to grant this)
        collectionRegistry.grantRole(Roles.COLLECTION_MANAGER_ROLE, admin);

        // Grant OPERATOR_ROLE to vault on LendingManager (needed for depositToLendingProtocol)
        lendingManager.grantRole(Roles.OPERATOR_ROLE, address(vault));

        console.log("Granted COLLECTION_MANAGER_ROLE to admin for collection operations");
        console.log("Granted OPERATOR_ROLE to vault on LendingManager");

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

        vm.stopBroadcast();
        console.log("Successfully connected collection", existingNFT, "to vault", address(vault));

        // Core deployment completed successfully!
        console.log("=== CORE DEPLOYMENT SUCCESSFUL ===");
        console.log("All contracts deployed and basic setup completed");
        console.log("Collection registered and connected to vault");

        // Note: Additional setup steps can be done manually or in separate scripts
        console.log("Note: Additional role grants and setup can be done manually:");
        console.log("1. Grant vault roles on LendingManager and EpochManager");
        console.log("2. Set contract references (EpochManager, DebtSubsidizer)");
        console.log("3. Grant collection access and whitelist collections");
        console.log("4. Set up epoch server automation roles");

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
