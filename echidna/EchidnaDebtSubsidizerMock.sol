// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/interfaces/IDebtSubsidizer.sol";
import "../src/mocks/MockERC20.sol";

// Mock DebtSubsidizer for property testing
contract MockDebtSubsidizer {
    mapping(address => uint256) public userSecondsClaimed;
    mapping(address => mapping(address => bool)) public isCollectionWhitelisted;
    mapping(address => bool) public vaultExists;
    mapping(address => bytes32) public merkleRoots;
    mapping(address => mapping(address => uint256)) public claimedTotals;
    
    bool public paused;
    address public owner;
    
    uint256 public totalSubsidiesPaid;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }
    
    function addVault(address vault, address lendingManager) external onlyOwner {
        require(vault != address(0), "Zero address");
        require(!vaultExists[vault], "Vault exists");
        vaultExists[vault] = true;
    }
    
    function removeVault(address vault) external onlyOwner {
        require(vaultExists[vault], "Vault not exists");
        vaultExists[vault] = false;
    }
    
    function whitelistCollection(address vault, address collection) external onlyOwner {
        require(vaultExists[vault], "Vault not exists");
        require(!isCollectionWhitelisted[vault][collection], "Already whitelisted");
        isCollectionWhitelisted[vault][collection] = true;
    }
    
    function removeCollection(address vault, address collection) external onlyOwner {
        require(isCollectionWhitelisted[vault][collection], "Not whitelisted");
        isCollectionWhitelisted[vault][collection] = false;
    }
    
    function updateMerkleRoot(address vault, bytes32 root) external onlyOwner {
        require(vaultExists[vault], "Vault not exists");
        merkleRoots[vault] = root;
    }
    
    function claimSubsidy(address vault, uint256 amount, address recipient) external whenNotPaused {
        require(vaultExists[vault], "Vault not exists");
        require(merkleRoots[vault] != bytes32(0), "No merkle root");
        require(amount > claimedTotals[vault][recipient], "Already claimed");
        
        uint256 subsidy = amount - claimedTotals[vault][recipient];
        claimedTotals[vault][recipient] = amount;
        userSecondsClaimed[recipient] += subsidy;
        totalSubsidiesPaid += subsidy;
    }
    
    function pause() external onlyOwner {
        paused = true;
    }
    
    function unpause() external onlyOwner {
        paused = false;
    }
}

contract EchidnaDebtSubsidizerMock {
    MockDebtSubsidizer public subsidizer;
    
    address constant OWNER = address(0x1000);
    address constant USER1 = address(0x2000);
    address constant USER2 = address(0x3000);
    address constant VAULT1 = address(0x4000);
    address constant VAULT2 = address(0x5000);
    address constant COLLECTION1 = address(0x6000);
    address constant COLLECTION2 = address(0x7000);
    
    // State tracking
    mapping(address => uint256) internal lastUserClaimed;
    uint256 internal lastTotalPaid;
    mapping(address => bool) internal vaultAdded;
    mapping(address => mapping(address => bool)) internal collectionWhitelistedLocal;
    
    constructor() {
        subsidizer = new MockDebtSubsidizer();
    }
    
    // ECHIDNA PROPERTIES
    
    /**
     * @dev User claimed amounts should be monotonic (non-decreasing)
     */
    function echidna_user_claims_monotonic() public view returns (bool) {
        uint256 user1Current = subsidizer.userSecondsClaimed(USER1);
        uint256 user2Current = subsidizer.userSecondsClaimed(USER2);
        
        return user1Current >= lastUserClaimed[USER1] && 
               user2Current >= lastUserClaimed[USER2];
    }
    
    /**
     * @dev Total subsidies paid should be monotonic
     */
    function echidna_total_subsidies_monotonic() public view returns (bool) {
        uint256 currentTotal = subsidizer.totalSubsidiesPaid();
        return currentTotal >= lastTotalPaid;
    }
    
    /**
     * @dev Vault existence should be consistent with our tracking
     */
    function echidna_vault_existence_consistent() public view returns (bool) {
        bool vault1Exists = subsidizer.vaultExists(VAULT1);
        bool vault2Exists = subsidizer.vaultExists(VAULT2);
        
        return vault1Exists == vaultAdded[VAULT1] && 
               vault2Exists == vaultAdded[VAULT2];
    }
    
    /**
     * @dev Collection whitelist should be consistent
     */
    function echidna_collection_whitelist_consistent() public view returns (bool) {
        bool vault1Collection1 = subsidizer.isCollectionWhitelisted(VAULT1, COLLECTION1);
        bool vault1Collection2 = subsidizer.isCollectionWhitelisted(VAULT1, COLLECTION2);
        
        return vault1Collection1 == collectionWhitelistedLocal[VAULT1][COLLECTION1] &&
               vault1Collection2 == collectionWhitelistedLocal[VAULT1][COLLECTION2];
    }
    
    /**
     * @dev Owner should always be the initial owner
     */
    function echidna_owner_unchanged() public view returns (bool) {
        return subsidizer.owner() == address(this);
    }
    
    // FUZZ FUNCTIONS
    
    /**
     * @dev Add vault
     */
    function addVault(bool useVault1) public {
        address vault = useVault1 ? VAULT1 : VAULT2;
        
        if (!vaultAdded[vault]) {
            try subsidizer.addVault(vault, address(0x9999)) {
                vaultAdded[vault] = true;
            } catch {
                // Failed to add vault
            }
        }
    }
    
    /**
     * @dev Remove vault
     */
    function removeVault(bool useVault1) public {
        address vault = useVault1 ? VAULT1 : VAULT2;
        
        if (vaultAdded[vault]) {
            try subsidizer.removeVault(vault) {
                vaultAdded[vault] = false;
                // Also remove collections
                collectionWhitelistedLocal[vault][COLLECTION1] = false;
                collectionWhitelistedLocal[vault][COLLECTION2] = false;
            } catch {
                // Failed to remove vault
            }
        }
    }
    
    /**
     * @dev Whitelist collection
     */
    function whitelistCollection(bool useVault1, bool useCollection1) public {
        address vault = useVault1 ? VAULT1 : VAULT2;
        address collection = useCollection1 ? COLLECTION1 : COLLECTION2;
        
        if (vaultAdded[vault] && !collectionWhitelistedLocal[vault][collection]) {
            try subsidizer.whitelistCollection(vault, collection) {
                collectionWhitelistedLocal[vault][collection] = true;
            } catch {
                // Failed to whitelist
            }
        }
    }
    
    /**
     * @dev Remove collection
     */
    function removeCollection(bool useVault1, bool useCollection1) public {
        address vault = useVault1 ? VAULT1 : VAULT2;
        address collection = useCollection1 ? COLLECTION1 : COLLECTION2;
        
        if (collectionWhitelistedLocal[vault][collection]) {
            try subsidizer.removeCollection(vault, collection) {
                collectionWhitelistedLocal[vault][collection] = false;
            } catch {
                // Failed to remove
            }
        }
    }
    
    /**
     * @dev Update merkle root
     */
    function updateMerkleRoot(bool useVault1, uint256 seed) public {
        address vault = useVault1 ? VAULT1 : VAULT2;
        
        if (vaultAdded[vault]) {
            bytes32 root = keccak256(abi.encodePacked(seed, block.timestamp));
            try subsidizer.updateMerkleRoot(vault, root) {
                // Root updated
            } catch {
                // Failed to update
            }
        }
    }
    
    /**
     * @dev Claim subsidy
     */
    function claimSubsidy(bool useVault1, bool useUser1, uint256 amount) public {
        address vault = useVault1 ? VAULT1 : VAULT2;
        address user = useUser1 ? USER1 : USER2;
        amount = bound(amount, 1, 10000e18);
        
        if (vaultAdded[vault]) {
            uint256 oldClaimed = lastUserClaimed[user];
            uint256 oldTotal = lastTotalPaid;
            
            try subsidizer.claimSubsidy(vault, amount, user) {
                // Update tracking
                uint256 newClaimed = subsidizer.userSecondsClaimed(user);
                uint256 newTotal = subsidizer.totalSubsidiesPaid();
                
                if (newClaimed >= oldClaimed) {
                    lastUserClaimed[user] = newClaimed;
                }
                if (newTotal >= oldTotal) {
                    lastTotalPaid = newTotal;
                }
            } catch {
                // Claim failed
            }
        }
    }
    
    /**
     * @dev Pause contract
     */
    function pauseContract() public {
        try subsidizer.pause() {
            // Paused
        } catch {
            // Failed to pause
        }
    }
    
    /**
     * @dev Unpause contract
     */
    function unpauseContract() public {
        try subsidizer.unpause() {
            // Unpaused
        } catch {
            // Failed to unpause
        }
    }
    
    /**
     * @dev Update tracking state manually
     */
    function updateTracking() public {
        lastUserClaimed[USER1] = subsidizer.userSecondsClaimed(USER1);
        lastUserClaimed[USER2] = subsidizer.userSecondsClaimed(USER2);
        lastTotalPaid = subsidizer.totalSubsidiesPaid();
    }
    
    // Utility function
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}
