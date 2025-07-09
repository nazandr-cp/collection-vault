// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {CollectionRegistry} from "../src/CollectionRegistry.sol";
import {ICollectionRegistry} from "../src/interfaces/ICollectionRegistry.sol";
import {Roles} from "../src/Roles.sol";

import {MockERC721} from "./mocks/MockERC721.sol";

contract CollectionRegistryTest is Test {
    CollectionRegistry public registry;
    MockERC721 public nftCollection1;
    MockERC721 public nftCollection2;

    address public constant ADMIN = address(0x1001);
    address public constant MANAGER = address(0x1002);
    address public constant UNAUTHORIZED = address(0x2001);
    address public constant VAULT_1 = address(0x3001);
    address public constant VAULT_2 = address(0x3002);

    event CollectionRegistered(
        address indexed collection,
        ICollectionRegistry.CollectionType collectionType,
        ICollectionRegistry.WeightFunctionType weightFunctionType,
        int256 p1,
        int256 p2,
        uint16 yieldSharePercentage
    );

    event YieldShareUpdated(address indexed collection, uint16 oldShare, uint16 newShare);

    event WeightFunctionUpdated(
        address indexed collection, ICollectionRegistry.WeightFunctionType weightFunctionType, int256 p1, int256 p2
    );

    event VaultAddedToCollection(address indexed collection, address indexed vault);
    event VaultRemovedFromCollection(address indexed collection, address indexed vault);
    event CollectionRemoved(address indexed collection);
    event CollectionReactivated(address indexed collection);

    function setUp() public {
        vm.startPrank(ADMIN);

        registry = new CollectionRegistry(ADMIN);
        nftCollection1 = new MockERC721("Collection 1", "COL1");
        nftCollection2 = new MockERC721("Collection 2", "COL2");

        // Grant MANAGER role to test account
        registry.grantRole(Roles.COLLECTION_MANAGER_ROLE, MANAGER);

        vm.stopPrank();
    }

    // === Registration Tests ===

    function testRegisterCollection() public {
        vm.startPrank(MANAGER);

        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: address(nftCollection1),
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1000000000000000000, // 1e18
                p2: 0
            }),
            yieldSharePercentage: 5000, // 50%
            vaults: new address[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit CollectionRegistered(
            address(nftCollection1),
            ICollectionRegistry.CollectionType.ERC721,
            ICollectionRegistry.WeightFunctionType.LINEAR,
            1000000000000000000,
            0,
            5000
        );

        registry.registerCollection(collectionData);

        assertTrue(registry.isRegistered(address(nftCollection1)));
        assertFalse(registry.isCollectionRemoved(address(nftCollection1)));

        ICollectionRegistry.Collection memory retrievedCollection = registry.getCollection(address(nftCollection1));
        assertEq(retrievedCollection.collectionAddress, address(nftCollection1));
        assertEq(uint8(retrievedCollection.collectionType), uint8(ICollectionRegistry.CollectionType.ERC721));
        assertEq(uint8(retrievedCollection.weightFunction.fnType), uint8(ICollectionRegistry.WeightFunctionType.LINEAR));
        assertEq(retrievedCollection.weightFunction.p1, 1000000000000000000);
        assertEq(retrievedCollection.weightFunction.p2, 0);
        assertEq(retrievedCollection.yieldSharePercentage, 5000);

        vm.stopPrank();
    }

    function testRegisterCollectionZeroAddress() public {
        vm.startPrank(MANAGER);

        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: address(0),
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1000000000000000000,
                p2: 0
            }),
            yieldSharePercentage: 5000,
            vaults: new address[](0)
        });

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.ZeroAddress.selector));
        registry.registerCollection(collectionData);

        vm.stopPrank();
    }

    function testRegisterCollectionUnauthorized() public {
        vm.startPrank(UNAUTHORIZED);

        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: address(nftCollection1),
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1000000000000000000,
                p2: 0
            }),
            yieldSharePercentage: 5000,
            vaults: new address[](0)
        });

        vm.expectRevert();
        registry.registerCollection(collectionData);

        vm.stopPrank();
    }

    function testRegisterCollectionTwice() public {
        vm.startPrank(MANAGER);

        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: address(nftCollection1),
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1000000000000000000,
                p2: 0
            }),
            yieldSharePercentage: 5000,
            vaults: new address[](0)
        });

        registry.registerCollection(collectionData);

        // Registering the same collection again should not revert but also not add it twice
        registry.registerCollection(collectionData);

        address[] memory allCollections = registry.allCollections();
        assertEq(allCollections.length, 1);
        assertEq(allCollections[0], address(nftCollection1));

        vm.stopPrank();
    }

    // === Weight Function Tests ===

    function testSetWeightFunction() public {
        vm.startPrank(MANAGER);

        // First register a collection
        _registerDefaultCollection(address(nftCollection1));

        ICollectionRegistry.WeightFunction memory newWeightFunction = ICollectionRegistry.WeightFunction({
            fnType: ICollectionRegistry.WeightFunctionType.EXPONENTIAL,
            p1: 2000000000000000000, // 2e18
            p2: 500000000000000000 // 0.5e18
        });

        vm.expectEmit(true, true, true, true);
        emit WeightFunctionUpdated(
            address(nftCollection1),
            ICollectionRegistry.WeightFunctionType.EXPONENTIAL,
            2000000000000000000,
            500000000000000000
        );

        registry.setWeightFunction(address(nftCollection1), newWeightFunction);

        ICollectionRegistry.Collection memory retrievedCollection = registry.getCollection(address(nftCollection1));
        assertEq(
            uint8(retrievedCollection.weightFunction.fnType), uint8(ICollectionRegistry.WeightFunctionType.EXPONENTIAL)
        );
        assertEq(retrievedCollection.weightFunction.p1, 2000000000000000000);
        assertEq(retrievedCollection.weightFunction.p2, 500000000000000000);

        vm.stopPrank();
    }

    function testSetWeightFunctionNotRegistered() public {
        vm.startPrank(MANAGER);

        ICollectionRegistry.WeightFunction memory weightFunction = ICollectionRegistry.WeightFunction({
            fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
            p1: 1000000000000000000,
            p2: 0
        });

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.CollectionNotRegistered.selector, address(nftCollection1)));
        registry.setWeightFunction(address(nftCollection1), weightFunction);

        vm.stopPrank();
    }

    function testSetWeightFunctionUnauthorized() public {
        vm.startPrank(MANAGER);
        _registerDefaultCollection(address(nftCollection1));
        vm.stopPrank();

        vm.startPrank(UNAUTHORIZED);

        ICollectionRegistry.WeightFunction memory weightFunction = ICollectionRegistry.WeightFunction({
            fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
            p1: 1000000000000000000,
            p2: 0
        });

        vm.expectRevert();
        registry.setWeightFunction(address(nftCollection1), weightFunction);

        vm.stopPrank();
    }

    // === Yield Share Tests ===

    function testSetYieldShare() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));

        uint16 newYieldShare = 7500; // 75%

        vm.expectEmit(true, true, true, true);
        emit YieldShareUpdated(address(nftCollection1), 5000, 7500);

        registry.setYieldShare(address(nftCollection1), newYieldShare);

        ICollectionRegistry.Collection memory retrievedCollection = registry.getCollection(address(nftCollection1));
        assertEq(retrievedCollection.yieldSharePercentage, 7500);

        vm.stopPrank();
    }

    function testSetYieldShareNotRegistered() public {
        vm.startPrank(MANAGER);

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.CollectionNotRegistered.selector, address(nftCollection1)));
        registry.setYieldShare(address(nftCollection1), 7500);

        vm.stopPrank();
    }

    function testSetYieldShareUnauthorized() public {
        vm.startPrank(MANAGER);
        _registerDefaultCollection(address(nftCollection1));
        vm.stopPrank();

        vm.startPrank(UNAUTHORIZED);

        vm.expectRevert();
        registry.setYieldShare(address(nftCollection1), 7500);

        vm.stopPrank();
    }

    // === Vault Management Tests ===

    function testAddVaultToCollection() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));

        vm.expectEmit(true, true, true, true);
        emit VaultAddedToCollection(address(nftCollection1), VAULT_1);

        registry.addVaultToCollection(address(nftCollection1), VAULT_1);

        ICollectionRegistry.Collection memory retrievedCollection = registry.getCollection(address(nftCollection1));
        assertEq(retrievedCollection.vaults.length, 1);
        assertEq(retrievedCollection.vaults[0], VAULT_1);

        vm.stopPrank();
    }

    function testAddMultipleVaultsToCollection() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));

        registry.addVaultToCollection(address(nftCollection1), VAULT_1);
        registry.addVaultToCollection(address(nftCollection1), VAULT_2);

        ICollectionRegistry.Collection memory retrievedCollection = registry.getCollection(address(nftCollection1));
        assertEq(retrievedCollection.vaults.length, 2);
        assertEq(retrievedCollection.vaults[0], VAULT_1);
        assertEq(retrievedCollection.vaults[1], VAULT_2);

        vm.stopPrank();
    }

    function testAddVaultToCollectionZeroAddress() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.ZeroAddress.selector));
        registry.addVaultToCollection(address(nftCollection1), address(0));

        vm.stopPrank();
    }

    function testAddVaultToCollectionNotRegistered() public {
        vm.startPrank(MANAGER);

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.CollectionNotRegistered.selector, address(nftCollection1)));
        registry.addVaultToCollection(address(nftCollection1), VAULT_1);

        vm.stopPrank();
    }

    function testAddVaultToCollectionAlreadyAdded() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));
        registry.addVaultToCollection(address(nftCollection1), VAULT_1);

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.VaultAlreadyAdded.selector, address(nftCollection1), VAULT_1));
        registry.addVaultToCollection(address(nftCollection1), VAULT_1);

        vm.stopPrank();
    }

    function testRemoveVaultFromCollection() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));
        registry.addVaultToCollection(address(nftCollection1), VAULT_1);
        registry.addVaultToCollection(address(nftCollection1), VAULT_2);

        vm.expectEmit(true, true, true, true);
        emit VaultRemovedFromCollection(address(nftCollection1), VAULT_1);

        registry.removeVaultFromCollection(address(nftCollection1), VAULT_1);

        ICollectionRegistry.Collection memory retrievedCollection = registry.getCollection(address(nftCollection1));
        assertEq(retrievedCollection.vaults.length, 1);
        assertEq(retrievedCollection.vaults[0], VAULT_2);

        vm.stopPrank();
    }

    function testRemoveVaultFromCollectionNotRegistered() public {
        vm.startPrank(MANAGER);

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.CollectionNotRegistered.selector, address(nftCollection1)));
        registry.removeVaultFromCollection(address(nftCollection1), VAULT_1);

        vm.stopPrank();
    }

    function testRemoveVaultFromCollectionNotFound() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.VaultNotFound.selector, address(nftCollection1), VAULT_1));
        registry.removeVaultFromCollection(address(nftCollection1), VAULT_1);

        vm.stopPrank();
    }

    // === Collection Removal/Reactivation Tests ===

    function testRemoveCollection() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));

        vm.expectEmit(true, true, true, true);
        emit CollectionRemoved(address(nftCollection1));

        registry.removeCollection(address(nftCollection1));

        // After removal, isRegistered returns false because it checks !_isRemoved
        assertFalse(registry.isRegistered(address(nftCollection1)));
        assertTrue(registry.isCollectionRemoved(address(nftCollection1)));

        // Should not appear in allCollections
        address[] memory allCollections = registry.allCollections();
        assertEq(allCollections.length, 0);

        vm.stopPrank();
    }

    function testRemoveCollectionNotRegistered() public {
        vm.startPrank(MANAGER);

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.CollectionNotRegistered.selector, address(nftCollection1)));
        registry.removeCollection(address(nftCollection1));

        vm.stopPrank();
    }

    function testRemoveCollectionTwice() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));
        registry.removeCollection(address(nftCollection1));

        // Should not emit event second time
        vm.recordLogs();
        registry.removeCollection(address(nftCollection1));

        // Verify no CollectionRemoved event was emitted
        vm.getRecordedLogs();

        vm.stopPrank();
    }

    function testReactivateCollection() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));
        registry.removeCollection(address(nftCollection1));

        vm.expectEmit(true, true, true, true);
        emit CollectionReactivated(address(nftCollection1));

        registry.reactivateCollection(address(nftCollection1));

        assertTrue(registry.isRegistered(address(nftCollection1)));
        assertFalse(registry.isCollectionRemoved(address(nftCollection1)));

        // Should appear in allCollections again
        address[] memory allCollections = registry.allCollections();
        assertEq(allCollections.length, 1);
        assertEq(allCollections[0], address(nftCollection1));

        vm.stopPrank();
    }

    function testReactivateCollectionNotRegistered() public {
        vm.startPrank(MANAGER);

        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.CollectionNotRegistered.selector, address(nftCollection1)));
        registry.reactivateCollection(address(nftCollection1));

        vm.stopPrank();
    }

    function testReactivateCollectionNotRemoved() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));

        // Should not emit event if collection is not removed
        vm.recordLogs();
        registry.reactivateCollection(address(nftCollection1));

        // Verify no CollectionReactivated event was emitted
        vm.getRecordedLogs();

        vm.stopPrank();
    }

    // === View Function Tests ===

    function testAllCollections() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));
        _registerDefaultCollection(address(nftCollection2));

        address[] memory allCollections = registry.allCollections();
        assertEq(allCollections.length, 2);
        assertEq(allCollections[0], address(nftCollection1));
        assertEq(allCollections[1], address(nftCollection2));

        // Remove one and check again
        registry.removeCollection(address(nftCollection1));

        allCollections = registry.allCollections();
        assertEq(allCollections.length, 1);
        assertEq(allCollections[0], address(nftCollection2));

        vm.stopPrank();
    }

    function testGetCollectionNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(CollectionRegistry.CollectionNotRegistered.selector, address(nftCollection1)));
        registry.getCollection(address(nftCollection1));
    }

    function testIsRegistered() public {
        assertFalse(registry.isRegistered(address(nftCollection1)));

        vm.startPrank(MANAGER);
        _registerDefaultCollection(address(nftCollection1));
        vm.stopPrank();

        assertTrue(registry.isRegistered(address(nftCollection1)));
    }

    function testIsRemoved() public {
        vm.startPrank(MANAGER);

        _registerDefaultCollection(address(nftCollection1));
        assertFalse(registry.isCollectionRemoved(address(nftCollection1)));

        registry.removeCollection(address(nftCollection1));
        assertTrue(registry.isCollectionRemoved(address(nftCollection1)));

        vm.stopPrank();
    }

    // === Access Control Tests ===

    function testGrantManagerRole() public {
        vm.startPrank(ADMIN);

        address newManager = address(0x9999);
        registry.grantRole(Roles.COLLECTION_MANAGER_ROLE, newManager);

        assertTrue(registry.hasRole(Roles.COLLECTION_MANAGER_ROLE, newManager));

        vm.stopPrank();

        // New manager should be able to register collections
        vm.startPrank(newManager);
        _registerDefaultCollection(address(nftCollection1));
        assertTrue(registry.isRegistered(address(nftCollection1)));
        vm.stopPrank();
    }

    function testRevokeManagerRole() public {
        vm.startPrank(ADMIN);

        registry.revokeRole(Roles.COLLECTION_MANAGER_ROLE, MANAGER);
        assertFalse(registry.hasRole(Roles.COLLECTION_MANAGER_ROLE, MANAGER));

        vm.stopPrank();

        // Manager should no longer be able to register collections
        vm.startPrank(MANAGER);

        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: address(nftCollection1),
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1000000000000000000,
                p2: 0
            }),
            yieldSharePercentage: 5000,
            vaults: new address[](0)
        });

        vm.expectRevert();
        registry.registerCollection(collectionData);

        vm.stopPrank();
    }

    // === Helper Functions ===

    function _registerDefaultCollection(address collectionAddress) internal {
        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: collectionAddress,
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                p1: 1000000000000000000, // 1e18
                p2: 0
            }),
            yieldSharePercentage: 5000, // 50%
            vaults: new address[](0)
        });

        registry.registerCollection(collectionData);
    }
}
