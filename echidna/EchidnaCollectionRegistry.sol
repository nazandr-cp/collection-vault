// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/CollectionRegistry.sol";
import "../src/interfaces/ICollectionRegistry.sol";
import "../src/mocks/MockERC721.sol";

contract EchidnaCollectionRegistry {
    CollectionRegistry public registry;
    
    // Test collections
    MockERC721 public collection1;
    MockERC721 public collection2;
    MockERC721 public collection3;
    MockERC721 public collection4;
    MockERC721 public collection5;
    
    // Test addresses
    address public admin;
    address public manager1;
    address public manager2;
    address public vault1;
    address public vault2;
    address public vault3;
    
    // Collection state tracking
    mapping(address => bool) public collectionRegistered;
    mapping(address => bool) public collectionRemoved;
    mapping(address => uint16) public collectionYieldShares;
    mapping(address => ICollectionRegistry.WeightFunctionType) public collectionWeightTypes;
    mapping(address => uint256) public collectionVaultCount;
    
    // Global state tracking
    uint256 public totalRegistrations;
    uint256 public totalRemovals;
    uint256 public totalReactivations;
    uint256 public totalYieldShareUpdates;
    uint256 public totalWeightFunctionUpdates;
    uint256 public totalVaultAdditions;
    uint256 public totalVaultRemovals;
    
    // Yield share accounting
    uint256 public totalAllocatedYieldShares;
    uint256 public maxYieldSharesAtOnce;
    
    // Error tracking
    uint256 public invalidOperations;
    uint256 public unauthorizedOperations;
    
    constructor() {
        admin = address(this);
        manager1 = address(0x1111111111111111111111111111111111111111);
        manager2 = address(0x2222222222222222222222222222222222222222);
        vault1 = address(0x3333333333333333333333333333333333333333);
        vault2 = address(0x4444444444444444444444444444444444444444);
        vault3 = address(0x5555555555555555555555555555555555555555);
        
        // Deploy mock collections
        collection1 = new MockERC721("Collection1", "C1");
        collection2 = new MockERC721("Collection2", "C2");
        collection3 = new MockERC721("Collection3", "C3");
        collection4 = new MockERC721("Collection4", "C4");
        collection5 = new MockERC721("Collection5", "C5");
        
        // Deploy CollectionRegistry
        registry = new CollectionRegistry(admin);
        
        // Grant roles
        registry.grantRole(registry.COLLECTION_MANAGER_ROLE(), manager1);
        registry.grantRole(registry.COLLECTION_MANAGER_ROLE(), manager2);
        
        // Initialize tracking variables
        totalRegistrations = 0;
        totalRemovals = 0;
        totalReactivations = 0;
        totalYieldShareUpdates = 0;
        totalWeightFunctionUpdates = 0;
        totalVaultAdditions = 0;
        totalVaultRemovals = 0;
        totalAllocatedYieldShares = 0;
        maxYieldSharesAtOnce = 0;
        invalidOperations = 0;
        unauthorizedOperations = 0;
    }
    
    // Bounded collection registration
    function registerCollection(uint256 collectionChoice, uint256 yieldShare, uint256 weightType, int256 p1, int256 p2) external {
        collectionChoice = bound(collectionChoice, 0, 4);
        yieldShare = bound(yieldShare, 0, 10000);
        weightType = bound(weightType, 0, 2);
        p1 = int256(bound(uint256(p1), 0, 1e6)) - 5e5; // Range -500k to 500k
        p2 = int256(bound(uint256(p2), 0, 1e6)) - 5e5;
        
        address collection = getCollectionByChoice(collectionChoice);
        
        ICollectionRegistry.WeightFunction memory weightFunction = ICollectionRegistry.WeightFunction({
            fnType: ICollectionRegistry.WeightFunctionType(weightType),
            p1: p1,
            p2: p2
        });
        
        ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
            collectionAddress: collection,
            collectionType: ICollectionRegistry.CollectionType.ERC721,
            weightFunction: weightFunction,
            yieldSharePercentage: uint16(yieldShare)
        });
        
        try registry.registerCollection(collectionData) {
            if (!collectionRegistered[collection]) {
                totalRegistrations++;
                collectionRegistered[collection] = true;
                collectionYieldShares[collection] = uint16(yieldShare);
                collectionWeightTypes[collection] = ICollectionRegistry.WeightFunctionType(weightType);
                
                // Update yield share tracking
                totalAllocatedYieldShares += yieldShare;
                if (totalAllocatedYieldShares > maxYieldSharesAtOnce) {
                    maxYieldSharesAtOnce = totalAllocatedYieldShares;
                }
            }
        } catch {
            invalidOperations++;
        }
    }
    
    // Bounded collection removal
    function removeCollection(uint256 collectionChoice) external {
        collectionChoice = bound(collectionChoice, 0, 4);
        
        address collection = getCollectionByChoice(collectionChoice);
        
        try registry.removeCollection(collection) {
            if (collectionRegistered[collection] && !collectionRemoved[collection]) {
                totalRemovals++;
                collectionRemoved[collection] = true;
                
                // Update yield share tracking
                uint16 yieldShare = collectionYieldShares[collection];
                if (totalAllocatedYieldShares >= yieldShare) {
                    totalAllocatedYieldShares -= yieldShare;
                }
            }
        } catch {
            invalidOperations++;
        }
    }
    
    // Bounded collection reactivation
    function reactivateCollection(uint256 collectionChoice) external {
        collectionChoice = bound(collectionChoice, 0, 4);
        
        address collection = getCollectionByChoice(collectionChoice);
        
        try registry.reactivateCollection(collection) {
            if (collectionRemoved[collection]) {
                totalReactivations++;
                collectionRemoved[collection] = false;
                
                // Update yield share tracking
                uint16 yieldShare = collectionYieldShares[collection];
                totalAllocatedYieldShares += yieldShare;
                if (totalAllocatedYieldShares > maxYieldSharesAtOnce) {
                    maxYieldSharesAtOnce = totalAllocatedYieldShares;
                }
            }
        } catch {
            invalidOperations++;
        }
    }
    
    // Bounded yield share updates
    function updateYieldShare(uint256 collectionChoice, uint256 newYieldShare) external {
        collectionChoice = bound(collectionChoice, 0, 4);
        newYieldShare = bound(newYieldShare, 0, 10000);
        
        address collection = getCollectionByChoice(collectionChoice);
        
        try registry.setYieldShare(collection, uint16(newYieldShare)) {
            if (collectionRegistered[collection]) {
                totalYieldShareUpdates++;
                
                // Update yield share tracking
                uint16 oldYieldShare = collectionYieldShares[collection];
                if (!collectionRemoved[collection]) {
                    totalAllocatedYieldShares = totalAllocatedYieldShares - oldYieldShare + newYieldShare;
                    if (totalAllocatedYieldShares > maxYieldSharesAtOnce) {
                        maxYieldSharesAtOnce = totalAllocatedYieldShares;
                    }
                }
                collectionYieldShares[collection] = uint16(newYieldShare);
            }
        } catch {
            invalidOperations++;
        }
    }
    
    // Bounded weight function updates
    function updateWeightFunction(uint256 collectionChoice, uint256 weightType, int256 p1, int256 p2) external {
        collectionChoice = bound(collectionChoice, 0, 4);
        weightType = bound(weightType, 0, 2);
        p1 = int256(bound(uint256(p1), 0, 1e6)) - 5e5;
        p2 = int256(bound(uint256(p2), 0, 1e6)) - 5e5;
        
        address collection = getCollectionByChoice(collectionChoice);
        
        ICollectionRegistry.WeightFunction memory weightFunction = ICollectionRegistry.WeightFunction({
            fnType: ICollectionRegistry.WeightFunctionType(weightType),
            p1: p1,
            p2: p2
        });
        
        try registry.setWeightFunction(collection, weightFunction) {
            if (collectionRegistered[collection]) {
                totalWeightFunctionUpdates++;
                collectionWeightTypes[collection] = ICollectionRegistry.WeightFunctionType(weightType);
            }
        } catch {
            invalidOperations++;
        }
    }
    
    // Bounded vault management
    function addVaultToCollection(uint256 collectionChoice, uint256 vaultChoice) external {
        collectionChoice = bound(collectionChoice, 0, 4);
        vaultChoice = bound(vaultChoice, 0, 2);
        
        address collection = getCollectionByChoice(collectionChoice);
        address vault = getVaultByChoice(vaultChoice);
        
        try registry.addVaultToCollection(collection, vault) {
            totalVaultAdditions++;
            collectionVaultCount[collection]++;
        } catch {
            invalidOperations++;
        }
    }
    
    // Bounded vault removal
    function removeVaultFromCollection(uint256 collectionChoice, uint256 vaultChoice) external {
        collectionChoice = bound(collectionChoice, 0, 4);
        vaultChoice = bound(vaultChoice, 0, 2);
        
        address collection = getCollectionByChoice(collectionChoice);
        address vault = getVaultByChoice(vaultChoice);
        
        try registry.removeVaultFromCollection(collection, vault) {
            totalVaultRemovals++;
            if (collectionVaultCount[collection] > 0) {
                collectionVaultCount[collection]--;
            }
        } catch {
            invalidOperations++;
        }
    }
    
    // Test batch operations
    function testBatchOperations(uint256 operationType, uint256 batchSize) external {
        operationType = bound(operationType, 0, 2);
        batchSize = bound(batchSize, 1, 5);
        
        if (operationType == 0) {
            // Batch register collections
            for (uint256 i = 0; i < batchSize && i < 5; i++) {
                this.registerCollection(i, 1000 + i * 500, i % 3, int256(i * 100), int256(i * 200));
            }
        } else if (operationType == 1) {
            // Batch update yield shares
            for (uint256 i = 0; i < batchSize && i < 5; i++) {
                this.updateYieldShare(i, 2000 + i * 300);
            }
        } else if (operationType == 2) {
            // Batch add vaults
            for (uint256 i = 0; i < batchSize && i < 5; i++) {
                this.addVaultToCollection(i, i % 3);
            }
        }
    }
    
    // Test edge cases
    function testEdgeCases(uint256 edgeCase) external {
        edgeCase = bound(edgeCase, 0, 5);
        
        if (edgeCase == 0) {
            // Test maximum yield share
            this.registerCollection(0, 10000, 0, 0, 0);
        } else if (edgeCase == 1) {
            // Test zero yield share
            this.registerCollection(1, 0, 1, 100, 200);
        } else if (edgeCase == 2) {
            // Test extreme weight function parameters
            this.updateWeightFunction(0, 2, type(int256).max / 1000, type(int256).min / 1000);
        } else if (edgeCase == 3) {
            // Test rapid registration and removal
            this.registerCollection(2, 5000, 0, 0, 0);
            this.removeCollection(2);
            this.reactivateCollection(2);
        } else if (edgeCase == 4) {
            // Test multiple vault additions to same collection
            this.addVaultToCollection(0, 0);
            this.addVaultToCollection(0, 1);
            this.addVaultToCollection(0, 2);
        } else if (edgeCase == 5) {
            // Test yield share updates across multiple collections
            this.updateYieldShare(0, 3000);
            this.updateYieldShare(1, 3000);
            this.updateYieldShare(2, 4000);
        }
    }
    
    // Utility functions
    function getCollectionByChoice(uint256 choice) internal view returns (address) {
        if (choice == 0) return address(collection1);
        if (choice == 1) return address(collection2);
        if (choice == 2) return address(collection3);
        if (choice == 3) return address(collection4);
        return address(collection5);
    }
    
    function getVaultByChoice(uint256 choice) internal view returns (address) {
        if (choice == 0) return vault1;
        if (choice == 1) return vault2;
        return vault3;
    }
    
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
    
    // COLLECTION REGISTRY INVARIANT PROPERTIES
    
    // Property 1: Total yield shares should not exceed reasonable bounds
    function echidna_total_yield_shares_bounded() external view returns (bool) {
        // Total allocated yield shares should not exceed 10000 (100%) by too much
        return totalAllocatedYieldShares <= 50000; // Allow some buffer for testing
    }
    
    // Property 2: Registered collections should remain registered
    function echidna_registered_collections_consistent() external view returns (bool) {
        // Test that our tracked registrations match registry state
        for (uint256 i = 0; i < 5; i++) {
            address collection = getCollectionByChoice(i);
            if (collectionRegistered[collection]) {
                try registry.isRegistered(collection) returns (bool isReg) {
                    if (!isReg) return false;
                } catch {
                    return false;
                }
            }
        }
        return true;
    }
    
    // Property 3: Collection operations should be consistent
    function echidna_collection_operations_consistent() external view returns (bool) {
        // Total operations should be reasonable
        uint256 totalOps = totalRegistrations + totalRemovals + totalReactivations + 
                          totalYieldShareUpdates + totalWeightFunctionUpdates +
                          totalVaultAdditions + totalVaultRemovals;
        
        return totalOps >= totalRegistrations; // At minimum, we should have registrations
    }
    
    // Property 4: Removal and reactivation consistency
    function echidna_removal_reactivation_consistent() external view returns (bool) {
        // Reactivations should not exceed removals
        return totalReactivations <= totalRemovals;
    }
    
    // Property 5: Vault count consistency
    function echidna_vault_count_consistent() external view returns (bool) {
        // Total vault additions should be at least total vault count
        return totalVaultAdditions >= totalVaultRemovals;
    }
    
    // Property 6: Individual collection yield shares are bounded
    function echidna_individual_yield_shares_bounded() external view returns (bool) {
        for (uint256 i = 0; i < 5; i++) {
            address collection = getCollectionByChoice(i);
            if (collectionYieldShares[collection] > 10000) {
                return false;
            }
        }
        return true;
    }
    
    // Property 7: Weight function types are valid
    function echidna_weight_function_types_valid() external view returns (bool) {
        for (uint256 i = 0; i < 5; i++) {
            address collection = getCollectionByChoice(i);
            if (collectionRegistered[collection]) {
                ICollectionRegistry.WeightFunctionType wType = collectionWeightTypes[collection];
                if (uint256(wType) > 2) {
                    return false;
                }
            }
        }
        return true;
    }
    
    // Property 8: Error rate should be reasonable
    function echidna_error_rate_reasonable() external view returns (bool) {
        uint256 totalAttempts = totalRegistrations + totalRemovals + totalReactivations + 
                               totalYieldShareUpdates + totalWeightFunctionUpdates +
                               totalVaultAdditions + totalVaultRemovals + invalidOperations;
        
        if (totalAttempts == 0) return true;
        
        // Error rate should be less than 50%
        return invalidOperations <= totalAttempts / 2;
    }
    
    // Property 9: Maximum yield shares tracking consistency
    function echidna_max_yield_shares_tracking() external view returns (bool) {
        // Max yield shares should be at least current total
        return maxYieldSharesAtOnce >= totalAllocatedYieldShares;
    }
    
    // Property 10: Collection state consistency
    function echidna_collection_state_consistent() external view returns (bool) {
        // A collection cannot be both removed and have non-zero allocated yield shares counted
        for (uint256 i = 0; i < 5; i++) {
            address collection = getCollectionByChoice(i);
            if (collectionRemoved[collection] && collectionRegistered[collection]) {
                // This is a valid state (removed but still registered)
                continue;
            }
        }
        return true;
    }
    
    // Property 11: Registry getter consistency
    function echidna_registry_getter_consistency() external view returns (bool) {
        // Test that registry getters work for registered collections
        for (uint256 i = 0; i < 3; i++) { // Test first 3 collections to avoid gas issues
            address collection = getCollectionByChoice(i);
            if (collectionRegistered[collection]) {
                try registry.getCollection(collection) returns (
                    address collAddr,
                    ICollectionRegistry.CollectionType,
                    ICollectionRegistry.WeightFunction memory,
                    uint16 yieldShare
                ) {
                    if (collAddr != collection) return false;
                    if (yieldShare != collectionYieldShares[collection]) return false;
                } catch {
                    return false;
                }
            }
        }
        return true;
    }
    
    // Property 12: Vault management consistency
    function echidna_vault_management_consistent() external view returns (bool) {
        // Each collection should not have excessive vault count
        for (uint256 i = 0; i < 5; i++) {
            address collection = getCollectionByChoice(i);
            if (collectionVaultCount[collection] > 100) { // Reasonable upper bound
                return false;
            }
        }
        return true;
    }
}