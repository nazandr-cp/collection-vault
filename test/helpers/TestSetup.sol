// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {CollectionsVault} from "../../src/CollectionsVault.sol";
import {LendingManager} from "../../src/LendingManager.sol";
import {DebtSubsidizer} from "../../src/DebtSubsidizer.sol";
import {EpochManager} from "../../src/EpochManager.sol";
import {CollectionRegistry} from "../../src/CollectionRegistry.sol";

import {ICollectionsVault} from "../../src/interfaces/ICollectionsVault.sol";
import {ILendingManager} from "../../src/interfaces/ILendingManager.sol";
import {IDebtSubsidizer} from "../../src/interfaces/IDebtSubsidizer.sol";
import {IEpochManager} from "../../src/interfaces/IEpochManager.sol";
import {ICollectionRegistry} from "../../src/interfaces/ICollectionRegistry.sol";
import {Roles} from "../../src/Roles.sol";

import {MockTokenFactory} from "../mocks/MockTokenFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {MockCToken} from "../mocks/MockCToken.sol";
import {MockComptroller} from "../mocks/MockComptroller.sol";

contract TestSetup is Test {
    address public constant ADMIN = address(0x1001);
    address public constant VAULT_OPERATOR = address(0x1002);
    address public constant COLLECTION_OPERATOR = address(0x1003);
    address public constant USER_1 = address(0x2001);
    address public constant USER_2 = address(0x2002);
    address public constant USER_3 = address(0x2003);
    address public constant BORROWER_1 = address(0x3001);
    address public constant BORROWER_2 = address(0x3002);
    address public constant AUTOMATED_SYSTEM = address(0x4001);

    CollectionsVault public collectionsVault;
    LendingManager public lendingManager;
    DebtSubsidizer public debtSubsidizer;
    EpochManager public epochManager;
    CollectionRegistry public collectionRegistry;

    MockTokenFactory public tokenFactory;
    MockERC20 public usdc;
    MockERC721 public nftCollection1;
    MockERC721 public nftCollection2;
    MockCToken public cUsdc;
    MockComptroller public comptroller;

    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public constant INITIAL_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 public constant INITIAL_EXCHANGE_RATE = 2e17; // 0.2 (1 cToken = 0.2 underlying)

    event ContractDeployed(string contractName, address contractAddress);
    event TestDataExported(string fileName, string data);

    function setUp() public virtual {
        _setupAccounts();
        _deployMockInfrastructure();
        _deployProtocolContracts();
        _configureProtocol();
        _exportContractAddresses();
    }

    function _setupAccounts() internal {
        vm.deal(ADMIN, 100 ether);
        vm.deal(VAULT_OPERATOR, 100 ether);
        vm.deal(COLLECTION_OPERATOR, 100 ether);
        vm.deal(USER_1, 100 ether);
        vm.deal(USER_2, 100 ether);
        vm.deal(USER_3, 100 ether);
        vm.deal(BORROWER_1, 100 ether);
        vm.deal(BORROWER_2, 100 ether);
        vm.deal(AUTOMATED_SYSTEM, 100 ether);

        vm.label(ADMIN, "Admin");
        vm.label(VAULT_OPERATOR, "VaultOperator");
        vm.label(COLLECTION_OPERATOR, "CollectionOperator");
        vm.label(USER_1, "User1");
        vm.label(USER_2, "User2");
        vm.label(USER_3, "User3");
        vm.label(BORROWER_1, "Borrower1");
        vm.label(BORROWER_2, "Borrower2");
        vm.label(AUTOMATED_SYSTEM, "AutomatedSystem");
    }

    function _deployMockInfrastructure() internal {
        tokenFactory = new MockTokenFactory();
        emit ContractDeployed("MockTokenFactory", address(tokenFactory));

        usdc = tokenFactory.createERC20("USD Coin", "USDC", 6, INITIAL_SUPPLY);
        emit ContractDeployed("MockUSDC", address(usdc));

        nftCollection1 = tokenFactory.createERC721("Test Collection 1", "TC1");
        nftCollection2 = tokenFactory.createERC721("Test Collection 2", "TC2");
        emit ContractDeployed("NFTCollection1", address(nftCollection1));
        emit ContractDeployed("NFTCollection2", address(nftCollection2));

        comptroller = new MockComptroller();
        emit ContractDeployed("MockComptroller", address(comptroller));

        cUsdc = tokenFactory.createCToken(
            address(usdc), address(comptroller), INITIAL_EXCHANGE_RATE, "Compound USDC", "cUSDC", 8
        );
        emit ContractDeployed("MockCUSDC", address(cUsdc));

        _distributeTokens();
    }

    function _deployProtocolContracts() internal {
        collectionRegistry = new CollectionRegistry(ADMIN);
        emit ContractDeployed("CollectionRegistry", address(collectionRegistry));

        epochManager = new EpochManager(EPOCH_DURATION, AUTOMATED_SYSTEM, ADMIN, address(debtSubsidizer));
        emit ContractDeployed("EpochManager", address(epochManager));

        lendingManager = new LendingManager(ADMIN, address(0), address(usdc), address(cUsdc));
        emit ContractDeployed("LendingManager", address(lendingManager));

        collectionsVault = new CollectionsVault(
            usdc, "Collections Vault USDC", "cvUSDC", ADMIN, address(lendingManager), address(collectionRegistry)
        );
        emit ContractDeployed("CollectionsVault", address(collectionsVault));

        address debtSubsidizerImpl = address(new DebtSubsidizer());
        emit ContractDeployed("DebtSubsidizerImpl", debtSubsidizerImpl);

        debtSubsidizer = DebtSubsidizer(debtSubsidizerImpl);
        debtSubsidizer.initialize(ADMIN, address(collectionRegistry));
        emit ContractDeployed("DebtSubsidizer", address(debtSubsidizer));
    }

    function _configureProtocol() internal {
        vm.startPrank(ADMIN);

        lendingManager.grantVaultRole(address(collectionsVault));

        collectionsVault.setEpochManager(address(epochManager));
        collectionsVault.setDebtSubsidizer(address(debtSubsidizer));

        collectionsVault.grantRole(Roles.COLLECTION_MANAGER_ROLE, COLLECTION_OPERATOR);

        epochManager.grantVaultRole(address(collectionsVault));

        _registerCollections();

        collectionRegistry.addVaultToCollection(address(nftCollection1), address(collectionsVault));
        collectionRegistry.addVaultToCollection(address(nftCollection2), address(collectionsVault));

        debtSubsidizer.addVault(address(collectionsVault), address(lendingManager));
        debtSubsidizer.whitelistCollection(address(collectionsVault), address(nftCollection1));
        debtSubsidizer.whitelistCollection(address(collectionsVault), address(nftCollection2));

        vm.stopPrank();
    }

    function _registerCollections() internal {
        _registerCollection1();
        _registerCollection2();
    }

    function _registerCollection1() internal {
        ICollectionRegistry.WeightFunction memory weightFunc =
            ICollectionRegistry.WeightFunction({fnType: ICollectionRegistry.WeightFunctionType.LINEAR, p1: 1000, p2: 0});

        collectionRegistry.registerCollection(
            ICollectionRegistry.Collection({
                collectionAddress: address(nftCollection1),
                collectionType: ICollectionRegistry.CollectionType.ERC721,
                weightFunction: weightFunc,
                yieldSharePercentage: 5000, // 50%
                vaults: new address[](0)
            })
        );
    }

    function _registerCollection2() internal {
        ICollectionRegistry.WeightFunction memory weightFunc =
            ICollectionRegistry.WeightFunction({fnType: ICollectionRegistry.WeightFunctionType.LINEAR, p1: 1000, p2: 0});

        collectionRegistry.registerCollection(
            ICollectionRegistry.Collection({
                collectionAddress: address(nftCollection2),
                collectionType: ICollectionRegistry.CollectionType.ERC721,
                weightFunction: weightFunc,
                yieldSharePercentage: 3000, // 30%
                vaults: new address[](0)
            })
        );
    }

    function _distributeTokens() internal {
        usdc.mint(ADMIN, 100_000e6);
        usdc.mint(VAULT_OPERATOR, 50_000e6);
        usdc.mint(USER_1, 25_000e6);
        usdc.mint(USER_2, 25_000e6);
        usdc.mint(USER_3, 25_000e6);
        usdc.mint(BORROWER_1, 10_000e6);
        usdc.mint(BORROWER_2, 10_000e6);

        nftCollection1.mint(USER_1, 1);
        nftCollection1.mint(USER_1, 2);
        nftCollection1.mint(USER_2, 3);
        nftCollection2.mint(USER_2, 1);
        nftCollection2.mint(USER_3, 2);
        nftCollection2.mint(USER_3, 3);

        vm.startPrank(ADMIN);
        usdc.approve(address(cUsdc), type(uint256).max);
        cUsdc.mint(100_000e6);
        vm.stopPrank();
    }

    function _exportContractAddresses() internal {
        string memory part1 = _buildAddressesPart1();
        string memory part2 = _buildAddressesPart2();
        string memory contractAddresses = string(abi.encodePacked("{\n", part1, part2, "}"));

        emit TestDataExported("contract-addresses.json", contractAddresses);

        vm.writeFile("test-exports/contract-addresses.json", contractAddresses);
    }

    function _buildAddressesPart1() internal view returns (string memory) {
        return string(
            abi.encodePacked(
                '  "collectionsVault": "',
                vm.toString(address(collectionsVault)),
                '",\n',
                '  "lendingManager": "',
                vm.toString(address(lendingManager)),
                '",\n',
                '  "debtSubsidizer": "',
                vm.toString(address(debtSubsidizer)),
                '",\n',
                '  "epochManager": "',
                vm.toString(address(epochManager)),
                '",\n',
                '  "collectionRegistry": "',
                vm.toString(address(collectionRegistry)),
                '",\n'
            )
        );
    }

    function _buildAddressesPart2() internal view returns (string memory) {
        return string(
            abi.encodePacked(
                '  "usdc": "',
                vm.toString(address(usdc)),
                '",\n',
                '  "cUsdc": "',
                vm.toString(address(cUsdc)),
                '",\n',
                '  "nftCollection1": "',
                vm.toString(address(nftCollection1)),
                '",\n',
                '  "nftCollection2": "',
                vm.toString(address(nftCollection2)),
                '",\n',
                '  "comptroller": "',
                vm.toString(address(comptroller)),
                '"\n'
            )
        );
    }

    function createEpochAndAdvanceTime() public {
        vm.prank(AUTOMATED_SYSTEM);
        epochManager.startEpoch();
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
    }

    function depositForCollection(address collection, uint256 amount, address user) public {
        vm.startPrank(user);
        usdc.approve(address(collectionsVault), amount);
        vm.stopPrank();

        vm.prank(COLLECTION_OPERATOR);
        collectionsVault.depositForCollection(amount, user, collection);
    }

    function simulateBorrowing(address borrower, uint256 amount) public {
        vm.startPrank(borrower);
        usdc.approve(address(cUsdc), amount);
        cUsdc.borrow(amount);
        vm.stopPrank();
    }

    function getCurrentEpochYield() public view returns (uint256) {
        return collectionsVault.getCurrentEpochYield(false);
    }

    function getCollectionTotalAssets(address collection) public view returns (uint256) {
        return collectionsVault.collectionTotalAssetsDeposited(collection);
    }

    function verifyContractDeployment() public view returns (bool) {
        return address(collectionsVault) != address(0) && address(lendingManager) != address(0)
            && address(debtSubsidizer) != address(0) && address(epochManager) != address(0)
            && address(collectionRegistry) != address(0);
    }

    function verifyInitialBalances() public view returns (bool) {
        return usdc.balanceOf(USER_1) == 25_000e6 && usdc.balanceOf(USER_2) == 25_000e6
            && nftCollection1.ownerOf(1) == USER_1 && nftCollection2.ownerOf(1) == USER_2;
    }

    function logTestState(string memory phase) public view {
        console.log("=== Test State: %s ===", phase);
        console.log("Block timestamp: %s", block.timestamp);
        console.log("Current epoch ID: %s", epochManager.getCurrentEpochId());
        console.log("Total vault assets: %s", collectionsVault.totalAssets());
        console.log("Available epoch yield: %s", getCurrentEpochYield());
        console.log("Collection1 assets: %s", getCollectionTotalAssets(address(nftCollection1)));
        console.log("Collection2 assets: %s", getCollectionTotalAssets(address(nftCollection2)));
    }
}
