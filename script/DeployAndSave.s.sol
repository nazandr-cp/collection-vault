// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {SimpleMockCToken} from "../src/mocks/SimpleMockCToken.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {CollectionRegistry} from "../src/CollectionRegistry.sol";
import {ICollectionRegistry} from "../src/interfaces/ICollectionRegistry.sol";
import {DebtSubsidizer} from "../src/DebtSubsidizer.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {Comptroller} from "compound-protocol-2.8.1/contracts/Comptroller.sol";
import {WhitePaperInterestRateModel} from "compound-protocol-2.8.1/contracts/WhitePaperInterestRateModel.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployAndSave is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // Deployments
        MockERC20 asset = new MockERC20("Mock Token", "MOCK", 18, 0);
        MockERC721 nft = new MockERC721("MockNFT", "MNFT");
        Comptroller comp = new Comptroller();
        WhitePaperInterestRateModel irm = new WhitePaperInterestRateModel(0, 0);
        SimpleMockCToken cToken = new SimpleMockCToken(
            address(asset),
            ComptrollerInterface(address(comp)),
            InterestRateModel(address(irm)),
            2e28,
            "Mock cToken",
            "mcTOKEN",
            18,
            payable(msg.sender)
        );
        LendingManager lendingManager = new LendingManager(msg.sender, msg.sender, address(asset), address(cToken));
        CollectionRegistry collectionRegistry = new CollectionRegistry(msg.sender);
        CollectionsVault vault = new CollectionsVault(
            asset, "Vault", "vMOCK", msg.sender, address(lendingManager), address(collectionRegistry)
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

        vm.stopBroadcast();

        // Save addresses to a file
        string memory filePath = "deployed-contracts.json";
        string memory json = string.concat(
            '{"asset": "',
            vm.toString(address(asset)),
            '", "nft": "',
            vm.toString(address(nft)),
            '", "cToken": "',
            vm.toString(address(cToken)),
            '", "lendingManager": "',
            vm.toString(address(lendingManager)),
            '", "collectionRegistry": "',
            vm.toString(address(collectionRegistry)),
            '", "collectionsVault": "',
            vm.toString(address(vault)),
            '", "epochManager": "',
            vm.toString(address(epochManager)),
            '", "debtSubsidizer": "',
            vm.toString(address(debtSubsidizer)),
            '"}'
        );
        vm.writeFile(filePath, json);
    }
}
