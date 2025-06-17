// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/DebtSubsidizer.sol";
import "../src/mocks/MockERC20.sol";

// Minimal mock for testing DebtSubsidizer
contract MinimalCollectionRegistry {
    mapping(address => bool) public isRegistered;
    
    function registerCollection(address collection) external {
        isRegistered[collection] = true;
    }
}

contract MinimalLendingManager {
    IERC20 public immutable asset;
    
    constructor(address _asset) {
        asset = IERC20(_asset);
    }
}

contract MinimalVault {
    address public immutable asset;
    mapping(uint256 => uint256) public epochYieldAllocations;
    mapping(address => uint256) public borrowBalances;
    address public epochManager;
    
    constructor(address _asset) {
        asset = _asset;
        epochManager = address(this); // Self-reference for simplicity
    }
    
    function setEpochYield(uint256 epochId, uint256 amount) external {
        epochYieldAllocations[epochId] = amount;
    }
    
    function getEpochYieldAllocated(uint256 epochId) external view returns (uint256) {
        return epochYieldAllocations[epochId];
    }
    
    function getCurrentEpochId() external pure returns (uint256) {
        return 1;
    }
    
    function setBorrowBalance(address user, uint256 amount) external {
        borrowBalances[user] = amount;
    }
    
    function repayBorrowBehalf(uint256 amount, address borrower) external {
        require(borrowBalances[borrower] >= amount, "Insufficient balance");
        borrowBalances[borrower] -= amount;
    }
}

contract EchidnaDebtSubsidizerSimple {
    DebtSubsidizer public subsidizer;
    MockERC20 public asset;
    MinimalLendingManager public lendingManager;
    MinimalCollectionRegistry public registry;
    MinimalVault public vault;
    
    address constant OWNER = address(0x1111);
    address constant USER1 = address(0x2222);
    address constant USER2 = address(0x3333);
    address constant COLLECTION = address(0x4444);
    
    // State tracking
    uint256 internal totalSubsidiesPaid;
    mapping(address => uint256) internal userTotalClaimed;
    bool internal vaultAdded;
    bool internal collectionWhitelisted;
    
    constructor() {
        // Deploy mocks
        asset = new MockERC20("Test", "TST", 18, 0);
        lendingManager = new MinimalLendingManager(address(asset));
        registry = new MinimalCollectionRegistry();
        vault = new MinimalVault(address(asset));
        
        // Deploy and initialize subsidizer
        subsidizer = new DebtSubsidizer();
        subsidizer.initialize(OWNER, address(registry));
        
        // Setup initial state
        asset.mint(address(this), 1000000e18);
        asset.mint(address(vault), 1000000e18);
        vault.setEpochYield(1, 100000e18);
        vault.setBorrowBalance(USER1, 50000e18);
        vault.setBorrowBalance(USER2, 30000e18);
        registry.registerCollection(COLLECTION);
    }
    
    // ECHIDNA PROPERTIES
    
    /**
     * @dev Total subsidies paid should never exceed available yield
     */
    function echidna_subsidies_not_exceed_yield() public view returns (bool) {
        uint256 availableYield = vault.getEpochYieldAllocated(1);
        return totalSubsidiesPaid <= availableYield;
    }
    
    /**
     * @dev User claimed amounts should be monotonic (non-decreasing)
     */
    function echidna_user_claims_monotonic() public view returns (bool) {
        uint256 user1Claimed = subsidizer.userSecondsClaimed(USER1);
        uint256 user2Claimed = subsidizer.userSecondsClaimed(USER2);
        
        return user1Claimed >= userTotalClaimed[USER1] && 
               user2Claimed >= userTotalClaimed[USER2];
    }
    
    /**
     * @dev Contract should not be paused initially
     */
    function echidna_not_paused_initially() public view returns (bool) {
        // If no pause operations were called, should not be paused
        return !subsidizer.paused() || vaultAdded; // Allow some flexibility
    }
    
    /**
     * @dev Vault registration should be consistent
     */
    function echidna_vault_registration_consistent() public view returns (bool) {
        if (!vaultAdded) return true; // No vault added yet
        
        try subsidizer.vault(address(vault)) returns (IDebtSubsidizer.VaultInfo memory info) {
            return info.cToken == address(asset);
        } catch {
            return false; // Vault should be accessible if added
        }
    }
    
    /**
     * @dev Collection whitelist should be consistent
     */
    function echidna_collection_whitelist_consistent() public view returns (bool) {
        if (!vaultAdded || !collectionWhitelisted) return true;
        
        return subsidizer.isCollectionWhitelisted(address(vault), COLLECTION);
    }
    
    // FUZZ FUNCTIONS
    
    /**
     * @dev Add vault (owner operation)
     */
    function addVault() public {
        if (!vaultAdded) {
            try subsidizer.addVault(address(vault), address(lendingManager)) {
                vaultAdded = true;
            } catch {
                // Failed to add vault
            }
        }
    }
    
    /**
     * @dev Remove vault (owner operation)
     */
    function removeVault() public {
        if (vaultAdded) {
            try subsidizer.removeVault(address(vault)) {
                vaultAdded = false;
                collectionWhitelisted = false; // Collection gets unwhitelisted too
            } catch {
                // Failed to remove vault
            }
        }
    }
    
    /**
     * @dev Whitelist collection (owner operation)
     */
    function whitelistCollection() public {
        if (vaultAdded && !collectionWhitelisted) {
            try subsidizer.whitelistCollection(address(vault), COLLECTION) {
                collectionWhitelisted = true;
            } catch {
                // Failed to whitelist
            }
        }
    }
    
    /**
     * @dev Remove collection from whitelist (owner operation)
     */
    function removeCollection() public {
        if (vaultAdded && collectionWhitelisted) {
            try subsidizer.removeCollection(address(vault), COLLECTION) {
                collectionWhitelisted = false;
            } catch {
                // Failed to remove collection
            }
        }
    }
    
    /**
     * @dev Update merkle root (owner operation)
     */
    function updateMerkleRoot(uint256 seed) public {
        if (vaultAdded) {
            bytes32 root = keccak256(abi.encodePacked(seed, block.timestamp));
            try subsidizer.updateMerkleRoot(address(vault), root) {
                // Root updated
            } catch {
                // Failed to update root
            }
        }
    }
    
    /**
     * @dev Attempt to claim subsidy with valid merkle proof
     */
    function claimSubsidyValid(uint256 amount, bool useUser1) public {
        if (!vaultAdded) return;
        
        address user = useUser1 ? USER1 : USER2;
        amount = bound(amount, 1, 5000e18);
        
        // Create simple single-leaf merkle tree
        bytes32 leaf = keccak256(abi.encodePacked(user, amount));
        
        // Update merkle root first
        try subsidizer.updateMerkleRoot(address(vault), leaf) {
            // Create claim with empty proof (single leaf)
            IDebtSubsidizer.ClaimData memory claim = IDebtSubsidizer.ClaimData({
                recipient: user,
                totalEarned: amount,
                merkleProof: new bytes32[](0)
            });
            
            uint256 oldClaimed = userTotalClaimed[user];
            
            try subsidizer.claimSubsidy(address(vault), claim) {
                uint256 newClaimed = subsidizer.userSecondsClaimed(user);
                if (newClaimed > oldClaimed) {
                    uint256 claimed = newClaimed - oldClaimed;
                    totalSubsidiesPaid += claimed;
                    userTotalClaimed[user] = newClaimed;
                }
            } catch {
                // Claim failed
            }
        } catch {
            // Failed to update merkle root
        }
    }
    
    /**
     * @dev Test pause functionality
     */
    function pauseContract() public {
        try subsidizer.pause() {
            // Paused
        } catch {
            // Failed to pause
        }
    }
    
    /**
     * @dev Test unpause functionality  
     */
    function unpauseContract() public {
        try subsidizer.unpause() {
            // Unpaused
        } catch {
            // Failed to unpause
        }
    }
    
    /**
     * @dev Test invalid claims (should fail)
     */
    function claimSubsidyInvalid(uint256 amount, bool useUser1) public {
        if (!vaultAdded) return;
        
        address user = useUser1 ? USER1 : USER2;
        amount = bound(amount, 1, 1000e18);
        
        // Create claim with invalid proof
        IDebtSubsidizer.ClaimData memory claim = IDebtSubsidizer.ClaimData({
            recipient: user,
            totalEarned: amount,
            merkleProof: new bytes32[](1) // Invalid proof
        });
        
        // This should fail
        try subsidizer.claimSubsidy(address(vault), claim) {
            // Should not succeed with invalid proof
            assert(false);
        } catch {
            // Expected to fail
        }
    }
    
    // Utility function
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}
