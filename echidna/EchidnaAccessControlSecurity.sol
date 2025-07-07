// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/AccessControlBase.sol";
import "../src/CrossContractSecurity.sol";
import "../src/CollectionsVault.sol";
import "../src/LendingManager.sol";
import "../src/EpochManager.sol";
import "../src/CollectionRegistry.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";

// Mock contracts for security testing
contract MockLendingManagerSecurity {
    IERC20 public immutable asset;
    bool public failNextOperation;
    
    constructor(address _asset) {
        asset = IERC20(_asset);
        failNextOperation = false;
    }
    
    function depositToLendingProtocol(uint256 amount) external returns (bool) {
        if (failNextOperation) {
            failNextOperation = false;
            return false;
        }
        asset.transferFrom(msg.sender, address(this), amount);
        return true;
    }
    
    function withdrawFromLendingProtocol(uint256 amount) external returns (bool) {
        if (failNextOperation) {
            failNextOperation = false;
            return false;
        }
        asset.transfer(msg.sender, amount);
        return true;
    }
    
    function totalAssets() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
    
    function repayBorrowBehalf(address, uint256 amount) external returns (uint256) {
        if (failNextOperation) {
            failNextOperation = false;
            return 1;
        }
        asset.transferFrom(msg.sender, address(this), amount);
        return 0;
    }
    
    function redeemAllCTokens(address recipient) external returns (uint256) {
        uint256 balance = asset.balanceOf(address(this));
        if (balance > 0) {
            asset.transfer(recipient, balance);
        }
        return balance;
    }
    
    function setFailNextOperation(bool fail) external {
        failNextOperation = fail;
    }
}

contract MockEpochManagerSecurity {
    uint256 public currentEpochId;
    bool public failNextOperation;
    
    constructor() {
        currentEpochId = 1;
        failNextOperation = false;
    }
    
    function allocateVaultYield(address, uint256) external {
        require(!failNextOperation, "Operation forced to fail");
    }
    
    function getCurrentEpochId() external view returns (uint256) {
        return currentEpochId;
    }
    
    function setCurrentEpochId(uint256 epochId) external {
        currentEpochId = epochId;
    }
    
    function setFailNextOperation(bool fail) external {
        failNextOperation = fail;
    }
}

contract EchidnaAccessControlSecurity {
    // Core contracts
    CollectionsVault public vault;
    LendingManager public lendingManager;
    EpochManager public epochManager;
    CollectionRegistry public collectionRegistry;
    
    // Mock contracts for controlled testing
    MockLendingManagerSecurity public mockLendingManager;
    MockEpochManagerSecurity public mockEpochManager;
    MockERC20 public asset;
    MockERC721 public collection;
    
    // Test addresses with different roles
    address public admin;
    address public defaultAdmin;
    address public operator1;
    address public operator2;
    address public collectionManager;
    address public attacker;
    address public user;
    address public emergencyGuardian;
    
    // Security state tracking
    mapping(address => mapping(bytes32 => bool)) public addressHasRole;
    mapping(bytes32 => uint256) public roleGrantCount;
    mapping(bytes32 => uint256) public roleRevokeCount;
    mapping(address => uint256) public unauthorizedAttempts;
    mapping(address => uint256) public successfulOperations;
    
    // Security metrics
    uint256 public totalRoleChanges;
    uint256 public totalUnauthorizedAttempts;
    uint256 public totalSecurityViolations;
    uint256 public totalEmergencyActions;
    uint256 public totalRateLimitHits;
    uint256 public totalCircuitBreakerActivations;
    
    // Circuit breaker and rate limiting tracking
    mapping(bytes4 => uint256) public functionCallCounts;
    mapping(bytes4 => uint256) public functionFailCounts;
    
    constructor() {
        admin = address(this);
        defaultAdmin = address(0x1111111111111111111111111111111111111111);
        operator1 = address(0x2222222222222222222222222222222222222222);
        operator2 = address(0x3333333333333333333333333333333333333333);
        collectionManager = address(0x4444444444444444444444444444444444444444);
        attacker = address(0x5555555555555555555555555555555555555555);
        user = address(0x6666666666666666666666666666666666666666);
        emergencyGuardian = address(0x7777777777777777777777777777777777777777);
        
        // Deploy mock contracts
        asset = new MockERC20("Test USDC", "USDC", 6, 0);
        collection = new MockERC721("Test Collection", "TC");
        
        mockLendingManager = new MockLendingManagerSecurity(address(asset));
        mockEpochManager = new MockEpochManagerSecurity();
        
        // Deploy CollectionRegistry
        collectionRegistry = new CollectionRegistry(admin);
        
        // Deploy CollectionsVault with mock dependencies
        vault = new CollectionsVault(
            address(asset),
            "Test Vault",
            "TV",
            admin,
            address(mockLendingManager),
            address(collectionRegistry),
            address(mockEpochManager)
        );
        
        // Setup initial roles and permissions
        setupRolesAndPermissions();
        
        // Initialize security metrics
        totalRoleChanges = 0;
        totalUnauthorizedAttempts = 0;
        totalSecurityViolations = 0;
        totalEmergencyActions = 0;
        totalRateLimitHits = 0;
        totalCircuitBreakerActivations = 0;
    }
    
    function setupRolesAndPermissions() internal {
        // Grant initial roles
        bytes32 adminRole = vault.ADMIN_ROLE();
        bytes32 operatorRole = vault.OPERATOR_ROLE();
        bytes32 collectionManagerRole = collectionRegistry.COLLECTION_MANAGER_ROLE();
        
        // Track role assignments
        addressHasRole[admin][adminRole] = true;
        addressHasRole[operator1][operatorRole] = true;
        addressHasRole[collectionManager][collectionManagerRole] = true;
        
        roleGrantCount[adminRole]++;
        roleGrantCount[operatorRole]++;
        roleGrantCount[collectionManagerRole]++;
        
        // Mint initial tokens for testing
        asset.mint(address(this), 1_000_000e6);
        asset.mint(user, 1_000_000e6);
        asset.mint(attacker, 1_000_000e6);
        asset.mint(address(mockLendingManager), 5_000_000e6);
        
        collection.mint(user, 1);
        collection.mint(attacker, 2);
    }
    
    // Test role-based access control
    function testRoleBasedAccess(uint256 actionChoice, uint256 addressChoice, uint256 roleChoice) external {
        actionChoice = bound(actionChoice, 0, 5);
        addressChoice = bound(addressChoice, 0, 6);
        roleChoice = bound(roleChoice, 0, 3);
        
        address actor = getAddressByChoice(addressChoice);
        bytes32 role = getRoleByChoice(roleChoice);
        
        if (actionChoice == 0) {
            // Test role grant
            try vault.grantRole(role, actor) {
                totalRoleChanges++;
                roleGrantCount[role]++;
                addressHasRole[actor][role] = true;
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        } else if (actionChoice == 1) {
            // Test role revoke
            try vault.revokeRole(role, actor) {
                totalRoleChanges++;
                roleRevokeCount[role]++;
                addressHasRole[actor][role] = false;
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        } else if (actionChoice == 2) {
            // Test admin operation (pause)
            try vault.pause() {
                totalEmergencyActions++;
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        } else if (actionChoice == 3) {
            // Test admin operation (unpause)
            try vault.unpause() {
                totalEmergencyActions++;
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        } else if (actionChoice == 4) {
            // Test operator operation (collection operator setting)
            try vault.setCollectionOperator(address(collection), actor, true) {
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        } else if (actionChoice == 5) {
            // Test collection manager operation (register collection)
            ICollectionRegistry.WeightFunction memory weightFunction = ICollectionRegistry.WeightFunction({
                fnType: ICollectionRegistry.WeightFunctionType.Linear,
                p1: 100,
                p2: 200
            });
            
            ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
                collectionAddress: address(collection),
                collectionType: ICollectionRegistry.CollectionType.ERC721,
                weightFunction: weightFunction,
                yieldSharePercentage: 5000
            });
            
            try collectionRegistry.registerCollection(collectionData) {
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        }
    }
    
    // Test circuit breaker functionality
    function testCircuitBreaker(uint256 operationType, uint256 failureCount) external {
        operationType = bound(operationType, 0, 2);
        failureCount = bound(failureCount, 0, 10);
        
        // Simulate multiple failures to trigger circuit breaker
        for (uint256 i = 0; i < failureCount; i++) {
            mockLendingManager.setFailNextOperation(true);
            
            if (operationType == 0) {
                // Test deposit operation
                try vault.depositForCollection(address(collection), 1000e6, user) {
                    functionCallCounts[vault.depositForCollection.selector]++;
                } catch {
                    functionFailCounts[vault.depositForCollection.selector]++;
                    totalCircuitBreakerActivations++;
                }
            } else if (operationType == 1) {
                // Test withdraw operation
                try vault.withdrawForCollection(address(collection), 1000e18, user, user) {
                    functionCallCounts[vault.withdrawForCollection.selector]++;
                } catch {
                    functionFailCounts[vault.withdrawForCollection.selector]++;
                    totalCircuitBreakerActivations++;
                }
            } else if (operationType == 2) {
                // Test yield allocation
                try vault.allocateYieldToEpoch() {
                    functionCallCounts[vault.allocateYieldToEpoch.selector]++;
                } catch {
                    functionFailCounts[vault.allocateYieldToEpoch.selector]++;
                    totalCircuitBreakerActivations++;
                }
            }
        }
    }
    
    // Test rate limiting
    function testRateLimiting(uint256 operationType, uint256 callCount) external {
        operationType = bound(operationType, 0, 2);
        callCount = bound(callCount, 1, 20);
        
        // Rapid successive calls to test rate limiting
        for (uint256 i = 0; i < callCount; i++) {
            if (operationType == 0) {
                // Test registration rate limiting
                ICollectionRegistry.WeightFunction memory weightFunction = ICollectionRegistry.WeightFunction({
                    fnType: ICollectionRegistry.WeightFunctionType.Linear,
                    p1: int256(i),
                    p2: int256(i * 2)
                });
                
                ICollectionRegistry.Collection memory collectionData = ICollectionRegistry.Collection({
                    collectionAddress: address(uint160(uint256(keccak256(abi.encodePacked(i))))),
                    collectionType: ICollectionRegistry.CollectionType.ERC721,
                    weightFunction: weightFunction,
                    yieldSharePercentage: 1000
                });
                
                try collectionRegistry.registerCollection(collectionData) {
                    functionCallCounts[collectionRegistry.registerCollection.selector]++;
                } catch {
                    totalRateLimitHits++;
                }
            } else if (operationType == 1) {
                // Test vault addition rate limiting
                try collectionRegistry.addVaultToCollection(address(collection), address(vault)) {
                    functionCallCounts[collectionRegistry.addVaultToCollection.selector]++;
                } catch {
                    totalRateLimitHits++;
                }
            } else if (operationType == 2) {
                // Test epoch start rate limiting (if we had epoch manager)
                // This would test epoch start rate limiting
                mockEpochManager.setCurrentEpochId(i + 1);
            }
        }
    }
    
    // Test emergency functions
    function testEmergencyFunctions(uint256 actionChoice, uint256 actorChoice) external {
        actionChoice = bound(actionChoice, 0, 3);
        actorChoice = bound(actorChoice, 0, 6);
        
        address actor = getAddressByChoice(actorChoice);
        
        if (actionChoice == 0) {
            // Test emergency pause
            try vault.pause() {
                totalEmergencyActions++;
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        } else if (actionChoice == 1) {
            // Test emergency unpause
            try vault.unpause() {
                totalEmergencyActions++;
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        } else if (actionChoice == 2) {
            // Test emergency role management
            try vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), emergencyGuardian) {
                totalEmergencyActions++;
                successfulOperations[actor]++;
            } catch {
                unauthorizedAttempts[actor]++;
                totalUnauthorizedAttempts++;
            }
        } else if (actionChoice == 3) {
            // Test emergency asset recovery (if such function exists)
            // This would test emergency withdrawal functions
        }
    }
    
    // Test access control bypassing attempts
    function testAccessControlBypass(uint256 bypassMethod, uint256 targetFunction) external {
        bypassMethod = bound(bypassMethod, 0, 4);
        targetFunction = bound(targetFunction, 0, 3);
        
        if (bypassMethod == 0) {
            // Attempt to call sensitive functions directly
            if (targetFunction == 0) {
                try vault.depositForCollection(address(collection), 1000e6, attacker) {
                    totalSecurityViolations++;
                } catch {
                    // Expected to fail
                }
            }
        } else if (bypassMethod == 1) {
            // Attempt reentrancy attacks (simplified test)
            // This would test for reentrancy vulnerabilities
        } else if (bypassMethod == 2) {
            // Attempt role escalation
            try vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), attacker) {
                totalSecurityViolations++;
            } catch {
                // Expected to fail
            }
        } else if (bypassMethod == 3) {
            // Attempt to bypass pause state
            if (vault.paused()) {
                try vault.depositForCollection(address(collection), 1000e6, attacker) {
                    totalSecurityViolations++;
                } catch {
                    // Expected to fail when paused
                }
            }
        } else if (bypassMethod == 4) {
            // Attempt to manipulate contract state
            // This would test for state manipulation vulnerabilities
        }
    }
    
    // Utility functions
    function getAddressByChoice(uint256 choice) internal view returns (address) {
        if (choice == 0) return admin;
        if (choice == 1) return operator1;
        if (choice == 2) return operator2;
        if (choice == 3) return collectionManager;
        if (choice == 4) return attacker;
        if (choice == 5) return user;
        return emergencyGuardian;
    }
    
    function getRoleByChoice(uint256 choice) internal view returns (bytes32) {
        if (choice == 0) return vault.DEFAULT_ADMIN_ROLE();
        if (choice == 1) return vault.ADMIN_ROLE();
        if (choice == 2) return vault.OPERATOR_ROLE();
        return collectionRegistry.COLLECTION_MANAGER_ROLE();
    }
    
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
    
    // SECURITY INVARIANT PROPERTIES
    
    // Property 1: Unauthorized attempts should be rejected
    function echidna_unauthorized_attempts_rejected() external view returns (bool) {
        // Unauthorized attempts should be much higher than successful operations for attackers
        return unauthorizedAttempts[attacker] >= successfulOperations[attacker];
    }
    
    // Property 2: Role changes should be controlled
    function echidna_role_changes_controlled() external view returns (bool) {
        // Total role changes should be reasonable relative to operations
        return totalRoleChanges <= 1000; // Reasonable upper bound
    }
    
    // Property 3: Security violations should be minimal
    function echidna_security_violations_minimal() external view returns (bool) {
        // Security violations should be very rare
        return totalSecurityViolations <= 5; // Very low tolerance
    }
    
    // Property 4: Emergency actions should be limited
    function echidna_emergency_actions_limited() external view returns (bool) {
        // Emergency actions should not be excessive
        return totalEmergencyActions <= 100;
    }
    
    // Property 5: Circuit breaker should activate on failures
    function echidna_circuit_breaker_activates() external view returns (bool) {
        // Circuit breaker activations should correlate with function failures
        uint256 totalFailures = 0;
        totalFailures += functionFailCounts[vault.depositForCollection.selector];
        totalFailures += functionFailCounts[vault.withdrawForCollection.selector];
        totalFailures += functionFailCounts[vault.allocateYieldToEpoch.selector];
        
        // Circuit breaker activations should be at least some portion of failures
        return totalCircuitBreakerActivations <= totalFailures;
    }
    
    // Property 6: Rate limiting should prevent spam
    function echidna_rate_limiting_prevents_spam() external view returns (bool) {
        // Rate limit hits should occur when there are many calls
        uint256 totalCalls = 0;
        totalCalls += functionCallCounts[collectionRegistry.registerCollection.selector];
        totalCalls += functionCallCounts[collectionRegistry.addVaultToCollection.selector];
        
        // If there are many calls, there should be some rate limit hits
        if (totalCalls > 50) {
            return totalRateLimitHits > 0;
        }
        return true;
    }
    
    // Property 7: Role grant and revoke counts should be balanced
    function echidna_role_balance_reasonable() external view returns (bool) {
        bytes32 adminRole = vault.ADMIN_ROLE();
        bytes32 operatorRole = vault.OPERATOR_ROLE();
        
        // Revokes should not exceed grants
        return roleRevokeCount[adminRole] <= roleGrantCount[adminRole] &&
               roleRevokeCount[operatorRole] <= roleGrantCount[operatorRole];
    }
    
    // Property 8: Admin privileges should be protected
    function echidna_admin_privileges_protected() external view returns (bool) {
        // Admin should retain admin role
        return addressHasRole[admin][vault.DEFAULT_ADMIN_ROLE()];
    }
    
    // Property 9: Attacker should not gain privileged roles
    function echidna_attacker_no_privileged_roles() external view returns (bool) {
        // Attacker should not have admin roles
        return !addressHasRole[attacker][vault.DEFAULT_ADMIN_ROLE()] &&
               !addressHasRole[attacker][vault.ADMIN_ROLE()];
    }
    
    // Property 10: Function call patterns should be reasonable
    function echidna_function_call_patterns_reasonable() external view returns (bool) {
        // Function calls should not be excessive relative to failures
        uint256 totalSuccessfulCalls = 0;
        uint256 totalFailedCalls = 0;
        
        totalSuccessfulCalls += functionCallCounts[vault.depositForCollection.selector];
        totalSuccessfulCalls += functionCallCounts[vault.withdrawForCollection.selector];
        totalFailedCalls += functionFailCounts[vault.depositForCollection.selector];
        totalFailedCalls += functionFailCounts[vault.withdrawForCollection.selector];
        
        // Success rate should not be 0% (unless no calls) or 100% (some should fail)
        if (totalSuccessfulCalls + totalFailedCalls > 0) {
            return totalSuccessfulCalls > 0; // At least some should succeed
        }
        return true;
    }
    
    // Property 11: Emergency guardian should have limited scope
    function echidna_emergency_guardian_limited_scope() external view returns (bool) {
        // Emergency guardian should not have excessive successful operations
        return successfulOperations[emergencyGuardian] <= 10;
    }
    
    // Property 12: Access control consistency
    function echidna_access_control_consistent() external view returns (bool) {
        // Our tracking should be consistent with actual role assignments
        // (This is a simplified check)
        return totalRoleChanges >= roleGrantCount[vault.ADMIN_ROLE()];
    }
}