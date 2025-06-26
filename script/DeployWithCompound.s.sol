// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {CollectionRegistry} from "../src/CollectionRegistry.sol";
import {ICollectionRegistry} from "../src/interfaces/ICollectionRegistry.sol";
import {DebtSubsidizer} from "../src/DebtSubsidizer.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {CErc20Immutable} from "compound-protocol-2.8.1/contracts/CErc20Immutable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployWithCompound is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // Use already deployed Compound addresses
        address asset = 0x4dd42d4559f7F5026364550FABE7824AECF5a1d1; // underlyingAddr
        address cToken = 0x642d97319cd50D2E5FC7F0FE022Ed87407045e90; // cTokenAddr
        address comptroller = 0x7E81fAaF1132A17DCc0C76b1280E0C0e598D5635;
        address interestRateModel = 0x13431E4D4a4281Be1A405681ECADb9F445Cd8Eb6;

        // Deploy new contracts that depend on Compound
        MockERC721 nft = new MockERC721("MockNFT", "MNFT");
        LendingManager lendingManager = new LendingManager(msg.sender, msg.sender, asset, cToken);
        CollectionRegistry collectionRegistry = new CollectionRegistry(msg.sender);
        CollectionsVault vault = new CollectionsVault(
            MockERC20(asset), "Vault", "vMOCK", msg.sender, address(lendingManager), address(collectionRegistry)
        );
        EpochManager epochManager = new EpochManager(1 days, msg.sender, msg.sender);
        DebtSubsidizer debtImpl = new DebtSubsidizer();
        bytes memory initData =
            abi.encodeWithSelector(DebtSubsidizer.initialize.selector, msg.sender, address(collectionRegistry));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(debtImpl), msg.sender, initData);
        DebtSubsidizer debtSubsidizer = DebtSubsidizer(address(proxy));

        // Register the NFT collection
        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: address(nft),
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 0,
                p2: 0
            }),
            p1: 0,
            p2: 0,
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
        debtSubsidizer.whitelistCollection(address(vault), address(nft));
        collectionRegistry.setYieldShare(address(nft), 5000);

        // Support the new cToken market
        ComptrollerInterface(comptroller)._supportMarket(cToken);

        vm.stopBroadcast();

        // Log deployed contract addresses
        console.log("Asset:", asset);
        console.log("cToken:", cToken);
        console.log("NFT:", address(nft));
        console.log("LendingManager:", address(lendingManager));
        console.log("CollectionRegistry:", address(collectionRegistry));
        console.log("CollectionsVault:", address(vault));
        console.log("EpochManager:", address(epochManager));
        console.log("DebtSubsidizer:", address(debtSubsidizer));
    }
}
