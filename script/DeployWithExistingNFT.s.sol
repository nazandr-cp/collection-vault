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
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {CErc20Immutable} from "compound-protocol-2.8.1/contracts/CErc20Immutable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployWithExistingNFT is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address existingNFT = vm.envAddress("EXISTING_NFT_ADDRESS");
        vm.startBroadcast(deployerKey);

        // Use already deployed Compound addresses
        address asset = 0x4dd42d4559f7F5026364550FABE7824AECF5a1d1; // underlyingAddr
        address cToken = 0x642d97319cd50D2E5FC7F0FE022Ed87407045e90; // cTokenAddr
        address comptroller = 0x7E81fAaF1132A17DCc0C76b1280E0C0e598D5635;
        // address interestRateModel = 0x13431E4D4a4281Be1A405681ECADb9F445Cd8Eb6;

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
        address epochServerAddress = 0xD620932690E1ae01126CDf541CBAdd0C7C1B918F;
        console.log("Granting roles to epoch server:", epochServerAddress);
        
        // Grant admin role on vault (for allocateYieldToEpoch)
        vault.grantRole(0x0000000000000000000000000000000000000000000000000000000000000000, epochServerAddress);
        console.log("Granted vault admin role to epoch server");
        
        // Grant automated system role on epoch manager (for endEpochWithSubsidies)
        epochManager.grantRole(keccak256("AUTOMATED_SYSTEM_ROLE"), epochServerAddress);
        console.log("Granted automated system role to epoch server");

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
