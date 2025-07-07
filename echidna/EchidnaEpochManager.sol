// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/EpochManager.sol";
import "../src/interfaces/IEpochManager.sol";
import "../src/interfaces/IDebtSubsidizer.sol";

// Mock DebtSubsidizer for testing
contract MockDebtSubsidizer {
    mapping(address => bytes32) public vaultMerkleRoots;
    mapping(address => mapping(address => uint256)) public userClaimedAmounts;
    mapping(address => bool) public isPaused;
    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) public totalClaimedForVault;
    
    uint256 public totalVaults;
    
    event MerkleRootUpdated(address indexed vault, bytes32 merkleRoot);
    
    function updateMerkleRoot(address vault, bytes32 merkleRoot) external {
        vaultMerkleRoots[vault] = merkleRoot;
        emit MerkleRootUpdated(vault, merkleRoot);
    }
    
    function addVault(address vault) external {
        isWhitelisted[vault] = true;
        totalVaults++;
    }
    
    function removeVault(address vault) external {
        isWhitelisted[vault] = false;
        if (totalVaults > 0) totalVaults--;
    }
    
    function pauseContract(address vault) external {
        isPaused[vault] = true;
    }
    
    function getTotalClaimedAmount(address vault) external view returns (uint256) {
        return totalClaimedForVault[vault];
    }
    
    function getUserClaimedAmount(address vault, address user) external view returns (uint256) {
        return userClaimedAmounts[vault][user];
    }
    
    function getVaultCount() external view returns (uint256) {
        return totalVaults;
    }
}

contract EchidnaEpochManager {
    EpochManager public epochManager;
    MockDebtSubsidizer public debtSubsidizer;
    
    address public admin;
    address public automatedSystem;
    address public vault1;
    address public vault2;
    
    uint256 public constant EPOCH_DURATION = 7 days;
    
    // State tracking for invariants
    uint256 public totalEpochsStarted;
    uint256 public totalEpochsCompleted;
    uint256 public totalEpochsFailed;
    uint256 public totalYieldAllocated;
    uint256 public totalSubsidiesDistributedGlobal;
    
    // Epoch state tracking
    mapping(uint256 => uint256) public epochYieldAllocated;
    mapping(uint256 => uint256) public epochSubsidiesDistributed;
    mapping(uint256 => IEpochManager.EpochStatus) public epochStatusHistory;
    
    // Error tracking
    uint256 public consecutiveFailures;
    bool public lastOperationFailed;
    
    constructor() {
        admin = address(this);
        automatedSystem = address(0x1111111111111111111111111111111111111111);
        vault1 = address(0x2222222222222222222222222222222222222222);
        vault2 = address(0x3333333333333333333333333333333333333333);
        
        // Deploy mock DebtSubsidizer
        debtSubsidizer = new MockDebtSubsidizer();
        
        // Deploy EpochManager
        epochManager = new EpochManager(
            EPOCH_DURATION,
            automatedSystem,
            admin,
            address(debtSubsidizer)
        );
        
        // Setup initial state
        debtSubsidizer.addVault(vault1);
        debtSubsidizer.addVault(vault2);
        
        // Grant roles
        epochManager.grantVaultRole(vault1);
        epochManager.grantVaultRole(vault2);
        
        totalEpochsStarted = 0;
        totalEpochsCompleted = 0;
        totalEpochsFailed = 0;
        totalYieldAllocated = 0;
        totalSubsidiesDistributedGlobal = 0;
        consecutiveFailures = 0;
        lastOperationFailed = false;
    }
    
    // Bounded epoch start function
    function startEpoch() external {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        try epochManager.startEpoch() returns (uint256 newEpochId) {
            totalEpochsStarted++;
            epochStatusHistory[newEpochId] = IEpochManager.EpochStatus.Active;
            lastOperationFailed = false;
            consecutiveFailures = 0;
        } catch {
            lastOperationFailed = true;
            consecutiveFailures++;
        }
    }
    
    // Bounded yield allocation function
    function allocateYield(uint256 vaultChoice, uint256 amount) external {
        vaultChoice = bound(vaultChoice, 0, 1);
        amount = bound(amount, 0, 1_000_000e18);
        
        address vault = vaultChoice == 0 ? vault1 : vault2;
        
        if (amount == 0) return;
        
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        if (currentEpochId == 0) return;
        
        try epochManager.allocateVaultYield(vault, amount) {
            totalYieldAllocated += amount;
            epochYieldAllocated[currentEpochId] += amount;
            lastOperationFailed = false;
            consecutiveFailures = 0;
        } catch {
            lastOperationFailed = true;
            consecutiveFailures++;
        }
    }
    
    // Bounded epoch end function
    function endEpoch(uint256 epochId, uint256 vaultChoice, uint256 subsidies) external {
        epochId = bound(epochId, 1, totalEpochsStarted);
        vaultChoice = bound(vaultChoice, 0, 1);
        subsidies = bound(subsidies, 0, 100_000e18);
        
        address vault = vaultChoice == 0 ? vault1 : vault2;
        bytes32 merkleRoot = keccak256(abi.encodePacked(epochId, vault, subsidies));
        
        if (epochId == 0) return;
        
        try epochManager.endEpochWithSubsidies(epochId, vault, merkleRoot, subsidies) {
            totalEpochsCompleted++;
            totalSubsidiesDistributedGlobal += subsidies;
            epochSubsidiesDistributed[epochId] += subsidies;
            epochStatusHistory[epochId] = IEpochManager.EpochStatus.Completed;
            lastOperationFailed = false;
            consecutiveFailures = 0;
        } catch {
            lastOperationFailed = true;
            consecutiveFailures++;
        }
    }
    
    // Bounded epoch failure function
    function markEpochFailed(uint256 epochId, string calldata reason) external {
        epochId = bound(epochId, 1, totalEpochsStarted);
        
        if (epochId == 0) return;
        
        try epochManager.markEpochFailed(epochId, reason) {
            totalEpochsFailed++;
            epochStatusHistory[epochId] = IEpochManager.EpochStatus.Failed;
            lastOperationFailed = false;
            consecutiveFailures = 0;
        } catch {
            lastOperationFailed = true;
            consecutiveFailures++;
        }
    }
    
    // Admin functions testing
    function testAdminFunctions(uint256 choice) external {
        choice = bound(choice, 0, 3);
        
        if (choice == 0) {
            try epochManager.setAutomatedSystem(automatedSystem) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        } else if (choice == 1) {
            try epochManager.setDebtSubsidizer(address(debtSubsidizer)) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        } else if (choice == 2) {
            try epochManager.grantVaultRole(vault1) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        } else if (choice == 3) {
            try epochManager.revokeVaultRole(vault2) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        }
    }
    
    // Utility function for bounding
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
    
    // INVARIANT PROPERTIES
    
    // Property 1: Only one active epoch at a time
    function echidna_only_one_active_epoch() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        if (currentEpochId == 0) return true;
        
        // Check if current epoch is active
        try epochManager.getEpochDetails(currentEpochId) returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            IEpochManager.EpochStatus status
        ) {
            // If current epoch is active, no other epoch should be active
            if (status == IEpochManager.EpochStatus.Active) {
                // Check all previous epochs are not active
                for (uint256 i = 1; i < currentEpochId; i++) {
                    try epochManager.getEpochDetails(i) returns (
                        uint256,
                        uint256,
                        uint256,
                        uint256,
                        uint256,
                        IEpochManager.EpochStatus prevStatus
                    ) {
                        if (prevStatus == IEpochManager.EpochStatus.Active) {
                            return false;
                        }
                    } catch {
                        // Ignore errors for non-existent epochs
                    }
                }
            }
            return true;
        } catch {
            return true;
        }
    }
    
    // Property 2: Epoch state transitions follow valid progression
    function echidna_valid_epoch_transitions() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        for (uint256 i = 1; i <= currentEpochId; i++) {
            try epochManager.getEpochDetails(i) returns (
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                IEpochManager.EpochStatus status
            ) {
                // Valid transitions: Active -> Completed/Failed
                // Invalid: Completed/Failed -> Active
                if (epochStatusHistory[i] == IEpochManager.EpochStatus.Completed || 
                    epochStatusHistory[i] == IEpochManager.EpochStatus.Failed) {
                    if (status == IEpochManager.EpochStatus.Active) {
                        return false; // Invalid transition back to Active
                    }
                }
            } catch {
                // Ignore errors for non-existent epochs
            }
        }
        return true;
    }
    
    // Property 3: Epoch yield never exceeds allocated amount
    function echidna_epoch_yield_consistent() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        for (uint256 i = 1; i <= currentEpochId; i++) {
            try epochManager.getEpochDetails(i) returns (
                uint256,
                uint256,
                uint256,
                uint256 totalYieldAvailable,
                uint256 totalSubsidiesDistributed,
                IEpochManager.EpochStatus
            ) {
                // Subsidies distributed should not exceed yield available
                if (totalSubsidiesDistributed > totalYieldAvailable) {
                    return false;
                }
            } catch {
                // Ignore errors for non-existent epochs
            }
        }
        return true;
    }
    
    // Property 4: Epoch IDs are monotonic
    function echidna_epoch_ids_monotonic() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        return currentEpochId <= totalEpochsStarted;
    }
    
    // Property 5: Total epochs accounting is consistent
    function echidna_epochs_accounting_consistent() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        // Total epochs started should be at least current epoch ID
        if (totalEpochsStarted < currentEpochId) {
            return false;
        }
        
        // Completed + Failed epochs should not exceed started epochs
        if (totalEpochsCompleted + totalEpochsFailed > totalEpochsStarted) {
            return false;
        }
        
        return true;
    }
    
    // Property 6: Vault yield allocation is reasonable
    function echidna_vault_yield_reasonable() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        if (currentEpochId == 0) return true;
        
        try epochManager.getVaultYieldForEpoch(currentEpochId, vault1) returns (uint256 yield1) {
            try epochManager.getVaultYieldForEpoch(currentEpochId, vault2) returns (uint256 yield2) {
                // Individual vault yields should be reasonable
                return yield1 <= 1_000_000e18 && yield2 <= 1_000_000e18;
            } catch {
                return true;
            }
        } catch {
            return true;
        }
    }
    
    // Property 7: Consecutive failures should be limited
    function echidna_consecutive_failures_limited() external view returns (bool) {
        // EpochManager should have better failure handling to prevent too many consecutive failures
        return consecutiveFailures <= 5;
    }
    
    // Property 8: Epoch duration consistency
    function echidna_epoch_duration_consistent() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        for (uint256 i = 1; i <= currentEpochId; i++) {
            try epochManager.getEpochDetails(i) returns (
                uint256,
                uint256 startTime,
                uint256 endTime,
                uint256,
                uint256,
                IEpochManager.EpochStatus
            ) {
                // End time should be start time + epoch duration
                if (endTime != startTime + EPOCH_DURATION) {
                    return false;
                }
            } catch {
                // Ignore errors for non-existent epochs
            }
        }
        return true;
    }
    
    // Property 9: Active epoch should have reasonable timestamps
    function echidna_active_epoch_timestamps_reasonable() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        if (currentEpochId == 0) return true;
        
        try epochManager.getEpochDetails(currentEpochId) returns (
            uint256,
            uint256 startTime,
            uint256 endTime,
            uint256,
            uint256,
            IEpochManager.EpochStatus status
        ) {
            if (status == IEpochManager.EpochStatus.Active) {
                // Start time should be reasonable (not too far in past/future)
                if (startTime > block.timestamp + 1 days) {
                    return false; // Too far in future
                }
                if (startTime < block.timestamp - 30 days) {
                    return false; // Too far in past
                }
                // End time should be after start time
                if (endTime <= startTime) {
                    return false;
                }
            }
            return true;
        } catch {
            return true;
        }
    }
    
    // Property 10: DebtSubsidizer integration consistency
    function echidna_debt_subsidizer_integration_consistent() external view returns (bool) {
        // Check that vault count in debt subsidizer is reasonable
        uint256 vaultCount = debtSubsidizer.getVaultCount();
        return vaultCount <= 100; // Should not exceed reasonable limit
    }
    
    // Property 11: Yield allocation monotonicity
    function echidna_yield_allocation_monotonic() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        if (currentEpochId == 0) return true;
        
        try epochManager.getEpochDetails(currentEpochId) returns (
            uint256,
            uint256,
            uint256,
            uint256 totalYieldAvailable,
            uint256,
            IEpochManager.EpochStatus
        ) {
            // Total yield available should match our tracking
            return totalYieldAvailable <= epochYieldAllocated[currentEpochId] + 1e18; // Allow small tolerance
        } catch {
            return true;
        }
    }
    
    // Property 12: No double-spending of subsidies
    function echidna_no_double_spending_subsidies() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        for (uint256 i = 1; i <= currentEpochId; i++) {
            try epochManager.getEpochDetails(i) returns (
                uint256,
                uint256,
                uint256,
                uint256 totalYieldAvailable,
                uint256 totalSubsidiesDistributed,
                IEpochManager.EpochStatus status
            ) {
                // For completed epochs, subsidies should not exceed yield
                if (status == IEpochManager.EpochStatus.Completed) {
                    if (totalSubsidiesDistributed > totalYieldAvailable + 1e18) { // Allow small tolerance
                        return false;
                    }
                }
            } catch {
                // Ignore errors for non-existent epochs
            }
        }
        return true;
    }
}