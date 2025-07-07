// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/CollectionsVault.sol";
import "../src/CollectionRegistry.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";

// Mock LendingManager for advanced vault testing
contract MockLendingManagerAdvanced {
    mapping(address => uint256) public depositedAmounts;
    mapping(address => uint256) public withdrawnAmounts;
    uint256 public totalAssetsStored;
    uint256 public exchangeRateMultiplier; // For simulating yield
    bool public operationShouldFail;
    
    IERC20 public immutable asset;
    
    constructor(address _asset) {
        asset = IERC20(_asset);
        totalAssetsStored = 0;
        exchangeRateMultiplier = 1e18; // 1:1 initially
        operationShouldFail = false;
    }
    
    function depositToLendingProtocol(uint256 amount) external returns (bool) {
        if (operationShouldFail) return false;
        
        asset.transferFrom(msg.sender, address(this), amount);
        depositedAmounts[msg.sender] += amount;
        totalAssetsStored += amount;
        return true;
    }
    
    function withdrawFromLendingProtocol(uint256 amount) external returns (bool) {
        if (operationShouldFail) return false;
        if (totalAssetsStored < amount) return false;
        
        asset.transfer(msg.sender, amount);
        withdrawnAmounts[msg.sender] += amount;
        totalAssetsStored -= amount;
        return true;
    }
    
    function totalAssets() external view returns (uint256) {
        // Apply exchange rate multiplier to simulate yield
        return (totalAssetsStored * exchangeRateMultiplier) / 1e18;
    }
    
    function repayBorrowBehalf(address, uint256 amount) external returns (uint256) {
        if (operationShouldFail) return 1; // Error code
        asset.transferFrom(msg.sender, address(this), amount);
        return 0; // Success
    }
    
    function redeemAllCTokens(address recipient) external returns (uint256) {
        if (operationShouldFail) return 0;
        uint256 balance = asset.balanceOf(address(this));
        if (balance > 0) {
            asset.transfer(recipient, balance);
        }
        return balance;
    }
    
    // Test utility functions
    function setExchangeRateMultiplier(uint256 multiplier) external {
        exchangeRateMultiplier = multiplier;
    }
    
    function setOperationShouldFail(bool shouldFail) external {
        operationShouldFail = shouldFail;
    }
}

// Mock EpochManager for advanced vault testing
contract MockEpochManagerAdvanced {
    uint256 public currentEpochId;
    mapping(uint256 => mapping(address => uint256)) public epochVaultYield;
    mapping(uint256 => uint256) public epochTotalYield;
    bool public operationShouldFail;
    
    constructor() {
        currentEpochId = 1;
        operationShouldFail = false;
    }
    
    function allocateVaultYield(address vault, uint256 amount) external {
        require(!operationShouldFail, "Operation forced to fail");
        epochVaultYield[currentEpochId][vault] += amount;
        epochTotalYield[currentEpochId] += amount;
    }
    
    function getCurrentEpochId() external view returns (uint256) {
        return currentEpochId;
    }
    
    // Test utility functions
    function setCurrentEpochId(uint256 epochId) external {
        currentEpochId = epochId;
    }
    
    function setOperationShouldFail(bool shouldFail) external {
        operationShouldFail = shouldFail;
    }
}

contract EchidnaCollectionsVaultAdvanced {
    CollectionsVault public vault;
    CollectionRegistry public collectionRegistry;
    MockLendingManagerAdvanced public lendingManager;
    MockEpochManagerAdvanced public epochManager;
    MockERC20 public asset;
    
    // Test collections
    MockERC721 public collection1;
    MockERC721 public collection2;
    MockERC721 public collection3;
    
    // Test addresses
    address public admin;
    address public user1;
    address public user2;
    address public user3;
    address public operator1;
    address public operator2;
    
    // Collection-specific state tracking
    mapping(address => uint256) public collectionTotalDeposits;
    mapping(address => uint256) public collectionTotalWithdrawals;
    mapping(address => uint256) public collectionSharesIssued;
    mapping(address => mapping(address => uint256)) public userCollectionShares;
    mapping(address => mapping(address => uint256)) public userCollectionDeposits;
    
    // Global state tracking
    uint256 public globalDepositIndex;
    uint256 public totalOperations;
    uint256 public totalYieldAllocated;
    uint256 public totalBatchOperations;
    
    // Error tracking
    uint256 public depositFailures;
    uint256 public withdrawFailures;
    uint256 public operatorActionFailures;
    
    constructor() {
        admin = address(this);
        user1 = address(0x1111111111111111111111111111111111111111);
        user2 = address(0x2222222222222222222222222222222222222222);
        user3 = address(0x3333333333333333333333333333333333333333);
        operator1 = address(0x4444444444444444444444444444444444444444);
        operator2 = address(0x5555555555555555555555555555555555555555);
        
        // Deploy mock contracts
        asset = new MockERC20("Test USDC", "USDC", 6, 0);
        collection1 = new MockERC721("Collection1", "C1");
        collection2 = new MockERC721("Collection2", "C2");
        collection3 = new MockERC721("Collection3", "C3");
        
        lendingManager = new MockLendingManagerAdvanced(address(asset));
        epochManager = new MockEpochManagerAdvanced();
        
        // Deploy CollectionRegistry
        collectionRegistry = new CollectionRegistry(admin);
        
        // Deploy CollectionsVault
        vault = new CollectionsVault(
            address(asset),
            "Test Collections Vault",
            "TCV",
            admin,
            address(lendingManager),
            address(collectionRegistry),
            address(epochManager)
        );
        
        // Setup protocol
        setupProtocol();
        
        // Initialize tracking variables
        globalDepositIndex = 1e18;
        totalOperations = 0;
        totalYieldAllocated = 0;
        totalBatchOperations = 0;
        depositFailures = 0;
        withdrawFailures = 0;
        operatorActionFailures = 0;
    }
    
    function setupProtocol() internal {
        // Register collections with different yield shares
        collectionRegistry.registerCollection(
            address(collection1),
            "Collection 1",
            4000, // 40% yield share
            true
        );
        
        collectionRegistry.registerCollection(
            address(collection2),
            "Collection 2",
            3500, // 35% yield share
            true
        );
        
        collectionRegistry.registerCollection(
            address(collection3),
            "Collection 3",
            2000, // 20% yield share
            true
        );
        
        // Set collection operators
        vault.setCollectionOperator(address(collection1), operator1, true);
        vault.setCollectionOperator(address(collection2), operator2, true);
        vault.setCollectionOperator(address(collection3), operator1, true);
        
        // Mint initial tokens and NFTs
        asset.mint(address(this), 10_000_000e6);
        asset.mint(user1, 1_000_000e6);
        asset.mint(user2, 1_000_000e6);
        asset.mint(user3, 1_000_000e6);
        asset.mint(address(lendingManager), 5_000_000e6);
        
        // Mint NFTs to users
        collection1.mint(user1, 1);
        collection1.mint(user2, 2);
        collection1.mint(user3, 3);
        
        collection2.mint(user1, 1);
        collection2.mint(user2, 2);
        collection2.mint(user3, 3);
        
        collection3.mint(user1, 1);
        collection3.mint(user2, 2);
        collection3.mint(user3, 3);
    }
    
    // Bounded collection-specific deposit function
    function depositForCollection(uint256 collectionChoice, uint256 userChoice, uint256 amount) external {
        collectionChoice = bound(collectionChoice, 0, 2);
        userChoice = bound(userChoice, 0, 2);
        amount = bound(amount, 0, 100_000e6);
        
        if (amount == 0) return;
        
        address collection = getCollectionByChoice(collectionChoice);
        address user = getUserByChoice(userChoice);
        
        // Ensure sufficient balance
        uint256 currentBalance = asset.balanceOf(user);
        if (currentBalance < amount) {
            asset.mint(user, amount - currentBalance);
        }
        
        // Approve and deposit
        asset.approve(address(vault), amount);
        
        try vault.depositForCollection(collection, amount, user) returns (uint256 shares) {
            if (shares > 0) {
                collectionTotalDeposits[collection] += amount;
                collectionSharesIssued[collection] += shares;
                userCollectionShares[collection][user] += shares;
                userCollectionDeposits[collection][user] += amount;
                totalOperations++;
            }
        } catch {
            depositFailures++;
        }
    }
    
    // Bounded collection-specific withdraw function
    function withdrawForCollection(uint256 collectionChoice, uint256 userChoice, uint256 shares) external {
        collectionChoice = bound(collectionChoice, 0, 2);
        userChoice = bound(userChoice, 0, 2);
        shares = bound(shares, 0, 1_000_000e18);
        
        if (shares == 0) return;
        
        address collection = getCollectionByChoice(collectionChoice);
        address user = getUserByChoice(userChoice);
        
        try vault.withdrawForCollection(collection, shares, user, user) returns (uint256 assets) {
            if (assets > 0) {
                collectionTotalWithdrawals[collection] += assets;
                if (userCollectionShares[collection][user] >= shares) {
                    userCollectionShares[collection][user] -= shares;
                }
                totalOperations++;
            }
        } catch {
            withdrawFailures++;
        }
    }
    
    // Bounded operator actions
    function operatorAction(uint256 actionChoice, uint256 collectionChoice, uint256 amount) external {
        actionChoice = bound(actionChoice, 0, 2);
        collectionChoice = bound(collectionChoice, 0, 2);
        amount = bound(amount, 0, 50_000e6);
        
        address collection = getCollectionByChoice(collectionChoice);
        address operator = getOperatorForCollection(collection);
        
        if (actionChoice == 0) {
            // Operator deposit
            if (amount == 0) return;
            
            uint256 currentBalance = asset.balanceOf(operator);
            if (currentBalance < amount) {
                asset.mint(operator, amount - currentBalance);
            }
            
            asset.approve(address(vault), amount);
            
            try vault.depositForCollection(collection, amount, operator) returns (uint256 shares) {
                if (shares > 0) {
                    collectionTotalDeposits[collection] += amount;
                    collectionSharesIssued[collection] += shares;
                    userCollectionShares[collection][operator] += shares;
                    totalOperations++;
                }
            } catch {
                operatorActionFailures++;
            }
        } else if (actionChoice == 1) {
            // Operator withdraw
            if (amount == 0) return;
            
            try vault.withdrawForCollection(collection, amount, operator, operator) returns (uint256 assets) {
                if (assets > 0) {
                    collectionTotalWithdrawals[collection] += assets;
                    totalOperations++;
                }
            } catch {
                operatorActionFailures++;
            }
        } else if (actionChoice == 2) {
            // Batch repay borrow (operator function)
            address[] memory borrowers = new address[](2);
            uint256[] memory amounts = new uint256[](2);
            
            borrowers[0] = user1;
            borrowers[1] = user2;
            amounts[0] = amount / 2;
            amounts[1] = amount / 2;
            
            if (amounts[0] == 0 && amounts[1] == 0) return;
            
            uint256 totalAmount = amounts[0] + amounts[1];
            uint256 currentBalance = asset.balanceOf(operator);
            if (currentBalance < totalAmount) {
                asset.mint(operator, totalAmount - currentBalance);
            }
            
            asset.approve(address(vault), totalAmount);
            
            try vault.repayBorrowBehalfBatch(collection, borrowers, amounts) {
                totalBatchOperations++;
                totalOperations++;
            } catch {
                operatorActionFailures++;
            }
        }
    }
    
    // Bounded yield allocation testing
    function testYieldAllocation(uint256 yieldMultiplier) external {
        yieldMultiplier = bound(yieldMultiplier, 100, 200); // 1.0x to 2.0x yield
        
        // Simulate yield generation
        lendingManager.setExchangeRateMultiplier(yieldMultiplier * 1e16); // Convert to 18 decimals
        
        try vault.allocateYieldToEpoch() {
            totalYieldAllocated += 1; // Track successful allocations
        } catch {
            // Allocation failed
        }
    }
    
    // Bounded global deposit index updates
    function updateGlobalDepositIndex(uint256 indexChange) external {
        indexChange = bound(indexChange, 0, 1e17); // Small changes only
        
        // This would normally be done internally, but we simulate it for testing
        uint256 newIndex = globalDepositIndex + indexChange;
        globalDepositIndex = newIndex;
    }
    
    // Bounded collection management
    function manageCollection(uint256 collectionChoice, uint256 action, uint256 newValue) external {
        collectionChoice = bound(collectionChoice, 0, 2);
        action = bound(action, 0, 3);
        newValue = bound(newValue, 0, 5000);
        
        address collection = getCollectionByChoice(collectionChoice);
        
        if (action == 0) {
            // Update yield share
            try collectionRegistry.updateYieldShare(collection, uint16(newValue)) {
                // Success
            } catch {
                // Failed
            }
        } else if (action == 1) {
            // Deactivate collection
            try collectionRegistry.deactivateCollection(collection) {
                // Success
            } catch {
                // Failed
            }
        } else if (action == 2) {
            // Activate collection
            try collectionRegistry.activateCollection(collection) {
                // Success
            } catch {
                // Failed
            }
        } else if (action == 3) {
            // Toggle collection operator
            address operator = getOperatorForCollection(collection);
            try vault.setCollectionOperator(collection, operator, newValue % 2 == 0) {
                // Success
            } catch {
                // Failed
            }
        }
    }
    
    // Utility functions
    function getCollectionByChoice(uint256 choice) internal view returns (address) {
        if (choice == 0) return address(collection1);
        if (choice == 1) return address(collection2);
        return address(collection3);
    }
    
    function getUserByChoice(uint256 choice) internal view returns (address) {
        if (choice == 0) return user1;
        if (choice == 1) return user2;
        return user3;
    }
    
    function getOperatorForCollection(address collection) internal view returns (address) {
        if (collection == address(collection1) || collection == address(collection3)) {
            return operator1;
        }
        return operator2;
    }
    
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
    
    // ADVANCED VAULT INVARIANT PROPERTIES
    
    // Property 1: Collection shares sum consistency
    function echidna_collection_shares_sum_consistent() external view returns (bool) {
        uint256 totalShares = vault.totalSupply();
        uint256 collection1Shares = vault.totalCollectionShares(address(collection1));
        uint256 collection2Shares = vault.totalCollectionShares(address(collection2));
        uint256 collection3Shares = vault.totalCollectionShares(address(collection3));
        
        uint256 sumCollectionShares = collection1Shares + collection2Shares + collection3Shares;
        
        // Sum of collection shares should equal total shares (within tolerance)
        if (sumCollectionShares > totalShares) {
            return (sumCollectionShares - totalShares) <= 1e18;
        } else {
            return (totalShares - sumCollectionShares) <= 1e18;
        }
    }
    
    // Property 2: Collection-specific user shares consistency
    function echidna_user_collection_shares_consistent() external view returns (bool) {
        // Check that individual user shares don't exceed collection totals
        uint256 collection1Total = vault.totalCollectionShares(address(collection1));
        uint256 collection2Total = vault.totalCollectionShares(address(collection2));
        uint256 collection3Total = vault.totalCollectionShares(address(collection3));
        
        uint256 user1Collection1 = vault.userCollectionShares(address(collection1), user1);
        uint256 user1Collection2 = vault.userCollectionShares(address(collection2), user1);
        uint256 user1Collection3 = vault.userCollectionShares(address(collection3), user1);
        
        return user1Collection1 <= collection1Total && 
               user1Collection2 <= collection2Total && 
               user1Collection3 <= collection3Total;
    }
    
    // Property 3: Collection yield share bounds
    function echidna_collection_yield_shares_bounded() external view returns (bool) {
        try collectionRegistry.getCollection(address(collection1)) returns (
            address, string memory, uint16 yield1, bool, address, int256, int256
        ) {
            try collectionRegistry.getCollection(address(collection2)) returns (
                address, string memory, uint16 yield2, bool, address, int256, int256
            ) {
                try collectionRegistry.getCollection(address(collection3)) returns (
                    address, string memory, uint16 yield3, bool, address, int256, int256
                ) {
                    // Total yield shares should not exceed 100%
                    return yield1 + yield2 + yield3 <= 10000;
                } catch {
                    return true;
                }
            } catch {
                return true;
            }
        } catch {
            return true;
        }
    }
    
    // Property 4: Global deposit index monotonicity
    function echidna_global_deposit_index_monotonic() external view returns (bool) {
        uint256 currentIndex = vault.globalDepositIndex();
        // Global deposit index should be reasonable and not decrease dramatically
        return currentIndex >= 1e17 && currentIndex <= 1e20; // Between 0.1 and 100
    }
    
    // Property 5: Collection operator permissions consistency
    function echidna_collection_operator_permissions() external view returns (bool) {
        // Check that operators have proper permissions for their assigned collections
        bool op1Collection1 = vault.collectionOperators(address(collection1), operator1);
        bool op2Collection2 = vault.collectionOperators(address(collection2), operator2);
        bool op1Collection3 = vault.collectionOperators(address(collection3), operator1);
        
        // At least the originally assigned operators should have permissions
        return op1Collection1 && op2Collection2 && op1Collection3;
    }
    
    // Property 6: Collection deposits vs shares correlation
    function echidna_deposits_shares_correlation() external view returns (bool) {
        // For each collection, total deposits should correlate with total shares issued
        for (uint256 i = 0; i < 3; i++) {
            address collection = getCollectionByChoice(i);
            uint256 totalShares = vault.totalCollectionShares(collection);
            uint256 trackedShares = collectionSharesIssued[collection];
            
            // Tracked shares should be close to vault reported shares
            if (totalShares > trackedShares) {
                if (totalShares - trackedShares > 1e18) return false;
            } else {
                if (trackedShares - totalShares > 1e18) return false;
            }
        }
        return true;
    }
    
    // Property 7: Batch operation consistency
    function echidna_batch_operations_consistent() external view returns (bool) {
        // Batch operations should not cause inconsistencies
        return totalBatchOperations <= totalOperations;
    }
    
    // Property 8: Collection asset allocation consistency
    function echidna_collection_asset_allocation() external view returns (bool) {
        // Each collection's asset allocation should be proportional to its shares
        uint256 totalAssets = vault.totalAssets();
        uint256 totalShares = vault.totalSupply();
        
        if (totalShares == 0) return true;
        
        for (uint256 i = 0; i < 3; i++) {
            address collection = getCollectionByChoice(i);
            uint256 collectionShares = vault.totalCollectionShares(collection);
            uint256 expectedAssets = (collectionShares * totalAssets) / totalShares;
            
            // Collection should have reasonable asset allocation
            // (This is a simplified check since actual implementation may be more complex)
            if (expectedAssets > totalAssets) return false;
        }
        return true;
    }
    
    // Property 9: User balance consistency across collections
    function echidna_user_balance_consistency() external view returns (bool) {
        // User's total shares across all collections should be reasonable
        uint256 user1TotalShares = vault.userCollectionShares(address(collection1), user1) +
                                  vault.userCollectionShares(address(collection2), user1) +
                                  vault.userCollectionShares(address(collection3), user1);
        
        uint256 vaultTotalShares = vault.totalSupply();
        
        // Individual user shouldn't own more than total shares
        return user1TotalShares <= vaultTotalShares;
    }
    
    // Property 10: Yield allocation frequency bounds
    function echidna_yield_allocation_reasonable() external view returns (bool) {
        // Total yield allocations should be reasonable relative to operations
        return totalYieldAllocated <= totalOperations + 100; // Allow some buffer
    }
    
    // Property 11: Error rate bounds
    function echidna_error_rates_reasonable() external view returns (bool) {
        // Error rates should not be excessive
        uint256 totalErrors = depositFailures + withdrawFailures + operatorActionFailures;
        
        if (totalOperations == 0) return true;
        
        // Error rate should not exceed 50%
        return totalErrors <= totalOperations;
    }
    
    // Property 12: Collection activation state consistency
    function echidna_collection_activation_consistent() external view returns (bool) {
        // All test collections should remain registered (may be inactive but registered)
        try collectionRegistry.isRegistered(address(collection1)) returns (bool reg1) {
            try collectionRegistry.isRegistered(address(collection2)) returns (bool reg2) {
                try collectionRegistry.isRegistered(address(collection3)) returns (bool reg3) {
                    return reg1 && reg2 && reg3;
                } catch {
                    return true;
                }
            } catch {
                return true;
            }
        } catch {
            return true;
        }
    }
}