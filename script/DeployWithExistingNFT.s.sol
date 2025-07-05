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
        address existingNFT = vm.envAddress("EXISTING_NFT_ADDRESS");
        vm.startBroadcast(deployerKey);

        // Use already deployed Compound addresses from environment
        address asset = vm.envAddress("COMPOUND_ASSET_ADDRESS"); // underlyingAddr
        address cToken = vm.envAddress("COMPOUND_CTOKEN_ADDRESS"); // cTokenAddr
        address comptroller = vm.envAddress("COMPOUND_COMPTROLLER_ADDRESS");

        // Deploy new contracts that depend on Compound
        LendingManager lendingManager = new LendingManager(msg.sender, msg.sender, asset, cToken);
        CollectionRegistry collectionRegistry = new CollectionRegistry(msg.sender);
        CollectionsVault vault = new CollectionsVault(
            MockERC20(asset), "Vault", "vMOCK", msg.sender, address(lendingManager), address(collectionRegistry)
        );
        EpochManager epochManager = new EpochManager(1 days, msg.sender, msg.sender, address(0));
        DebtSubsidizer debtImpl = new DebtSubsidizer();

        bytes memory initData =
            abi.encodeWithSelector(DebtSubsidizer.initialize.selector, msg.sender, address(collectionRegistry));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(debtImpl), msg.sender, initData);
        DebtSubsidizer debtSubsidizer = DebtSubsidizer(address(proxy));

        // The deployer (msg.sender) should already have all roles via the constructor
        
        // Register the existing NFT collection
        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: existingNFT,
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1.0e18, // 1.0 in 18 decimals
                p2: 0
            }),
            yieldSharePercentage: 5000,
            vaults: new address[](0)
        });
        collectionRegistry.registerCollection(collectionData);

        // Post-deployment setup
        lendingManager.grantVaultRole(address(vault));
        epochManager.grantVaultRole(address(vault));
        vault.setEpochManager(address(epochManager));
        debtSubsidizer.addVault(address(vault), address(lendingManager));
        vault.setDebtSubsidizer(address(debtSubsidizer));
        debtSubsidizer.whitelistCollection(address(vault), existingNFT);
        collectionRegistry.setYieldShare(existingNFT, 5000);

        // Support the new cToken market
        address[] memory markets = new address[](1);
        markets[0] = cToken;
        ComptrollerInterface(comptroller).enterMarkets(markets);

        // Grant epoch server roles for automated epoch processing
        address epochServerAddress = vm.envAddress("EPOCH_SERVER_ADDRESS");
        console.log("Granting roles to epoch server:", epochServerAddress);
        
        // Grant ADMIN_ROLE on vault (for allocateYieldToEpoch)
        vault.grantRole(Roles.ADMIN_ROLE, epochServerAddress);
        console.log("Granted vault ADMIN_ROLE to epoch server");
        
        // Grant OPERATOR_ROLE on epoch manager (for endEpochWithSubsidies)
        epochManager.grantRole(Roles.OPERATOR_ROLE, epochServerAddress);
        console.log("Granted epoch manager OPERATOR_ROLE to epoch server");

        vm.stopBroadcast();

        // Log deployed contract addresses
        console.log("Asset:", asset);
        console.log("cToken:", cToken);
        console.log("Existing NFT:", existingNFT);
        console.log("LendingManager:", address(lendingManager));
        console.log("CollectionRegistry:", address(collectionRegistry));
        console.log("CollectionsVault:", address(vault));
        console.log("EpochManager:", address(epochManager));
        console.log("DebtSubsidizer:", address(debtSubsidizer));
    }
}
