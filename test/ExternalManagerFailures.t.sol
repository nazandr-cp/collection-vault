// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CollectionsVault} from "../src/CollectionsVault.sol";
import {CollectionRegistry} from "../src/CollectionRegistry.sol";
import {ICollectionsVault} from "../src/interfaces/ICollectionsVault.sol";
import {ICollectionRegistry} from "../src/interfaces/ICollectionRegistry.sol";
import {Roles} from "../src/Roles.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockFailingEpochManager} from "./mocks/MockFailingEpochManager.sol";
import {MockFailingLendingManager} from "./mocks/MockFailingLendingManager.sol";

contract ExternalManagerFailuresTest is Test {
    // Test accounts
    address public constant ADMIN = address(0x1001);
    address public constant COLLECTION_OPERATOR = address(0x1002);
    address public constant USER_1 = address(0x2001);
    address public constant NFT_COLLECTION_1 = address(0x3001);

    // Protocol contracts
    CollectionsVault public collectionsVault;
    CollectionRegistry public collectionRegistry;
    MockFailingEpochManager public epochManager;
    MockFailingLendingManager public lendingManager;

    // Mock tokens
    MockERC20 public usdc;
    MockERC721 public nftCollection;

    // Test constants
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant DEPOSIT_AMOUNT = 100e18;
    uint256 public constant EPOCH_ID = 1;

    function setUp() public {
        vm.deal(ADMIN, 10 ether);
        vm.deal(COLLECTION_OPERATOR, 10 ether);
        vm.deal(USER_1, 10 ether);

        usdc = new MockERC20("USD Coin", "USDC", 6, 0);
        nftCollection = new MockERC721("Test Collection", "TEST");

        vm.startPrank(ADMIN);

        collectionRegistry = new CollectionRegistry(ADMIN);
        epochManager = new MockFailingEpochManager(EPOCH_ID);
        lendingManager = new MockFailingLendingManager(address(usdc), 0);

        collectionsVault = new CollectionsVault(
            usdc, "Collections Vault Token", "CVT", ADMIN, address(lendingManager), address(collectionRegistry)
        );

        collectionsVault.setEpochManager(address(epochManager));
        collectionsVault.grantRole(Roles.COLLECTION_MANAGER_ROLE, COLLECTION_OPERATOR);

        ICollectionRegistry.Collection memory collection = ICollectionRegistry.Collection({
            collectionAddress: NFT_COLLECTION_1,
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1,
                p2: 0
            }),
            yieldSharePercentage: 1000,
            vaults: new address[](0)
        });
        collectionRegistry.registerCollection(collection);

        vm.stopPrank();

        usdc.mint(USER_1, INITIAL_BALANCE);
        vm.prank(USER_1);
        usdc.approve(address(collectionsVault), type(uint256).max);

        usdc.mint(COLLECTION_OPERATOR, INITIAL_BALANCE);
        vm.prank(COLLECTION_OPERATOR);
        usdc.approve(address(collectionsVault), type(uint256).max);
    }

    function testEpochManagerAllocationFailure() public {
        vm.prank(COLLECTION_OPERATOR);
        collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);

        lendingManager.setTotalAssets(DEPOSIT_AMOUNT + 50e18);

        uint256 availableYield = collectionsVault.getCurrentEpochYield(false);

        if (availableYield == 0) {
            epochManager.setShouldFailAllocateVaultYield(true);
            vm.prank(ADMIN);
            vm.expectRevert("CollectionsVault: Allocation amount exceeds available yield");
            collectionsVault.allocateEpochYield(1);
            return;
        }

        epochManager.setShouldFailAllocateVaultYield(true);
        vm.prank(ADMIN);
        vm.expectRevert(ICollectionsVault.EpochManagerAllocationFailed.selector);
        collectionsVault.allocateEpochYield(availableYield);
    }

    function testEpochManagerGetCurrentEpochIdFailure() public {
        epochManager.setShouldFailGetCurrentEpochId(true);
        vm.prank(ADMIN);
        vm.expectRevert(ICollectionsVault.EpochManagerUnavailable.selector);
        collectionsVault.allocateEpochYield(1);
    }

    function testEpochManagerFailureInGetCurrentEpochYield() public {
        epochManager.setShouldFailGetCurrentEpochId(true);
        uint256 yield = collectionsVault.getCurrentEpochYield(false);
        assertEq(yield, 0);
    }

    function testEpochManagerFailureInRepayBorrowBehalf() public {
        vm.prank(COLLECTION_OPERATOR);
        collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);

        epochManager.setShouldFailGetCurrentEpochId(true);

        vm.prank(ADMIN);
        collectionsVault.grantRole(Roles.OPERATOR_ROLE, ADMIN);

        vm.prank(ADMIN);
        collectionsVault.repayBorrowBehalf(50e18, USER_1);
    }

    function testAllocateYieldToEpochFailure() public {
        vm.prank(COLLECTION_OPERATOR);
        collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);

        epochManager.setShouldFailAllocateVaultYield(true);

        vm.prank(ADMIN);
        vm.expectRevert(ICollectionsVault.EpochManagerAllocationFailed.selector);
        collectionsVault.allocateYieldToEpoch(EPOCH_ID);
    }

    function testAllocateCumulativeYieldToEpochFailure() public {
        vm.prank(COLLECTION_OPERATOR);
        collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);

        epochManager.setShouldFailAllocateVaultYield(true);

        vm.prank(ADMIN);
        vm.expectRevert(ICollectionsVault.EpochManagerAllocationFailed.selector);
        collectionsVault.allocateCumulativeYieldToEpoch(EPOCH_ID, DEPOSIT_AMOUNT);
    }

    function testLendingManagerDepositFailure() public {
        lendingManager.setShouldFailDeposit(true);

        vm.prank(COLLECTION_OPERATOR);
        vm.expectRevert(ICollectionsVault.LendingManagerDepositFailed.selector);
        collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);
    }

    function testLendingManagerWithdrawFailure() public {
        vm.prank(COLLECTION_OPERATOR);
        collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);

        lendingManager.setShouldFailWithdraw(true);

        vm.prank(COLLECTION_OPERATOR);
        vm.expectRevert(ICollectionsVault.LendingManagerWithdrawFailed.selector);
        collectionsVault.withdrawForCollection(DEPOSIT_AMOUNT / 2, USER_1, USER_1, NFT_COLLECTION_1);
    }

    function testFullRedemptionWithLendingManagerFailure() public {
        vm.prank(COLLECTION_OPERATOR);
        uint256 shares = collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);

        lendingManager.setTotalAssets(DEPOSIT_AMOUNT + 1000);
        lendingManager.setShouldFailWithdraw(true);

        vm.prank(COLLECTION_OPERATOR);
        uint256 assetsReceived = collectionsVault.redeemForCollection(shares, USER_1, USER_1, NFT_COLLECTION_1);

        assertEq(assetsReceived, DEPOSIT_AMOUNT);
    }

    function testStateConsistencyAfterEpochManagerFailure() public {
        vm.prank(COLLECTION_OPERATOR);
        collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);

        uint256 initialTotalYieldReserved = collectionsVault.totalYieldReserved();
        uint256 initialEpochAllocation = collectionsVault.getEpochYieldAllocated(EPOCH_ID);

        epochManager.setShouldFailAllocateVaultYield(true);

        vm.prank(ADMIN);
        vm.expectRevert(ICollectionsVault.EpochManagerAllocationFailed.selector);
        collectionsVault.allocateEpochYield(DEPOSIT_AMOUNT);

        assertEq(collectionsVault.totalYieldReserved(), initialTotalYieldReserved);
        assertEq(collectionsVault.getEpochYieldAllocated(EPOCH_ID), initialEpochAllocation);
    }

    function testRecoveryAfterEpochManagerFailure() public {
        vm.prank(COLLECTION_OPERATOR);
        collectionsVault.depositForCollection(DEPOSIT_AMOUNT, USER_1, NFT_COLLECTION_1);

        epochManager.setShouldFailAllocateVaultYield(true);

        vm.prank(ADMIN);
        vm.expectRevert(ICollectionsVault.EpochManagerAllocationFailed.selector);
        collectionsVault.allocateEpochYield(DEPOSIT_AMOUNT);

        epochManager.setShouldFailAllocateVaultYield(false);

        vm.prank(ADMIN);
        collectionsVault.allocateEpochYield(DEPOSIT_AMOUNT);

        assertGt(collectionsVault.getEpochYieldAllocated(EPOCH_ID), 0);
    }
}
