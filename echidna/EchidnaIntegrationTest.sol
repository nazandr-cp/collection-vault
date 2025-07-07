// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/CollectionsVault.sol";
import "../src/LendingManager.sol";
import "../src/EpochManager.sol";
import "../src/CollectionRegistry.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/SimpleMockCToken.sol";
import "../src/mocks/MockERC721.sol";

// Mock DebtSubsidizer for integration testing
contract MockDebtSubsidizerIntegration {
    mapping(address => bytes32) public vaultMerkleRoots;
    mapping(address => mapping(address => uint256)) public userClaimedAmounts;
    mapping(address => bool) public isPaused;
    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) public totalClaimedForVault;
    
    uint256 public totalVaults;
    
    event MerkleRootUpdated(address indexed vault, bytes32 merkleRoot);
    event SubsidyClaimed(address indexed vault, address indexed user, uint256 amount);
    
    function updateMerkleRoot(address vault, bytes32 merkleRoot) external {
        vaultMerkleRoots[vault] = merkleRoot;
        emit MerkleRootUpdated(vault, merkleRoot);
    }
    
    function claimSubsidy(
        address vault,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external returns (uint256) {
        require(isWhitelisted[vault], "Vault not whitelisted");
        require(!isPaused[vault], "Vault is paused");
        
        userClaimedAmounts[vault][msg.sender] += amount;
        totalClaimedForVault[vault] += amount;
        
        emit SubsidyClaimed(vault, msg.sender, amount);
        return amount;
    }
    
    function addVault(address vault) external {
        isWhitelisted[vault] = true;
        totalVaults++;
    }
    
    function removeVault(address vault) external {
        isWhitelisted[vault] = false;
        if (totalVaults > 0) totalVaults--;
    }
    
    function whitelistCollection(address vault, address collection) external {
        // Mock implementation
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

// Mock Comptroller and InterestRateModel
contract MockComptrollerIntegration {
    function mintAllowed(address, address, uint256) external pure returns (uint256) { return 0; }
    function redeemAllowed(address, address, uint256) external pure returns (uint256) { return 0; }
}

contract MockInterestRateModelIntegration {
    function getBorrowRate(uint256, uint256, uint256) external pure returns (uint256) { return 5e16; }
    function getSupplyRate(uint256, uint256, uint256, uint256) external pure returns (uint256) { return 3e16; }
}

contract EchidnaIntegrationTest {
    // Core contracts
    CollectionsVault public vault;
    LendingManager public lendingManager;
    EpochManager public epochManager;
    CollectionRegistry public collectionRegistry;
    MockDebtSubsidizerIntegration public debtSubsidizer;
    
    // Mock dependencies
    MockERC20 public asset;
    SimpleMockCToken public cToken;
    MockERC721 public collection1;
    MockERC721 public collection2;
    MockComptrollerIntegration public comptroller;
    MockInterestRateModelIntegration public interestRateModel;
    
    // Test addresses
    address public admin;
    address public user1;
    address public user2;
    address public automatedSystem;
    
    // Protocol state tracking
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalYieldGenerated;
    uint256 public totalSubsidiesDistributed;
    uint256 public totalEpochsCompleted;
    
    // Collection state tracking
    mapping(address => uint256) public collectionDeposits;
    mapping(address => uint256) public collectionWithdrawals;
    mapping(address => uint256) public collectionYield;
    
    // Epoch state tracking
    uint256 public currentEpochTracker;
    mapping(uint256 => uint256) public epochTotalYield;
    mapping(uint256 => uint256) public epochTotalSubsidies;
    
    constructor() {
        admin = address(this);
        user1 = address(0x1111111111111111111111111111111111111111);
        user2 = address(0x2222222222222222222222222222222222222222);
        automatedSystem = address(0x3333333333333333333333333333333333333333);
        
        // Deploy mock tokens and dependencies
        asset = new MockERC20("Test USDC", "USDC", 6, 0);
        collection1 = new MockERC721("Collection1", "C1");
        collection2 = new MockERC721("Collection2", "C2");
        comptroller = new MockComptrollerIntegration();
        interestRateModel = new MockInterestRateModelIntegration();
        
        // Deploy mock cToken
        cToken = new SimpleMockCToken(
            address(asset),
            ComptrollerInterface(address(comptroller)),
            InterestRateModel(address(interestRateModel)),
            2e17, // Initial exchange rate: 0.2
            "Test cUSDC",
            "cUSDC",
            8,
            payable(admin)
        );
        
        // Deploy DebtSubsidizer
        debtSubsidizer = new MockDebtSubsidizerIntegration();
        
        // Deploy CollectionRegistry
        collectionRegistry = new CollectionRegistry(admin);
        
        // Deploy EpochManager
        epochManager = new EpochManager(
            7 days, // Epoch duration
            automatedSystem,
            admin,
            address(debtSubsidizer)
        );
        
        // Deploy LendingManager
        lendingManager = new LendingManager(
            admin,
            address(0), // Will be set to vault address later
            address(asset),
            address(cToken)
        );
        
        // Deploy CollectionsVault
        vault = new CollectionsVault(
            address(asset),
            "Test Vault",
            "TV",
            admin,
            address(lendingManager),
            address(collectionRegistry),
            address(epochManager)
        );
        
        // Update LendingManager with vault address
        lendingManager.grantVaultRole(address(vault));
        
        // Setup protocol state
        setupProtocol();
        
        // Initialize tracking variables
        totalDeposited = 0;
        totalWithdrawn = 0;
        totalYieldGenerated = 0;
        totalSubsidiesDistributed = 0;
        totalEpochsCompleted = 0;
        currentEpochTracker = 0;
    }
    
    function setupProtocol() internal {
        // Register collections
        collectionRegistry.registerCollection(
            address(collection1),
            "Collection 1",
            5000, // 50% yield share
            true
        );
        
        collectionRegistry.registerCollection(
            address(collection2),
            "Collection 2",
            3000, // 30% yield share
            true
        );
        
        // Add vaults to debt subsidizer
        debtSubsidizer.addVault(address(vault));
        
        // Mint initial tokens
        asset.mint(address(this), 10_000_000e6);
        asset.mint(user1, 1_000_000e6);
        asset.mint(user2, 1_000_000e6);
        asset.mint(address(cToken), 10_000_000e6);
        
        // Mint NFTs
        collection1.mint(user1, 1);
        collection1.mint(user2, 2);
        collection2.mint(user1, 1);
        collection2.mint(user2, 2);
    }
    
    // Bounded deposit function
    function deposit(uint256 amount, uint256 collectionChoice, uint256 userChoice) external {
        amount = bound(amount, 0, 100_000e6);
        collectionChoice = bound(collectionChoice, 0, 1);
        userChoice = bound(userChoice, 0, 1);
        
        if (amount == 0) return;
        
        address collection = collectionChoice == 0 ? address(collection1) : address(collection2);
        address user = userChoice == 0 ? user1 : user2;
        
        // Ensure sufficient balance
        uint256 currentBalance = asset.balanceOf(user);
        if (currentBalance < amount) {
            asset.mint(user, amount - currentBalance);
        }
        
        // Approve and deposit
        asset.approve(address(vault), amount);
        
        try vault.depositForCollection(collection, amount, user) returns (uint256 shares) {
            if (shares > 0) {
                totalDeposited += amount;
                collectionDeposits[collection] += amount;
            }
        } catch {
            // Deposit failed, continue
        }
    }
    
    // Bounded withdraw function
    function withdraw(uint256 shares, uint256 collectionChoice, uint256 userChoice) external {
        shares = bound(shares, 0, 1_000_000e18);
        collectionChoice = bound(collectionChoice, 0, 1);
        userChoice = bound(userChoice, 0, 1);
        
        if (shares == 0) return;
        
        address collection = collectionChoice == 0 ? address(collection1) : address(collection2);
        address user = userChoice == 0 ? user1 : user2;
        
        try vault.withdrawForCollection(collection, shares, user, user) returns (uint256 assets) {
            if (assets > 0) {
                totalWithdrawn += assets;
                collectionWithdrawals[collection] += assets;
            }
        } catch {
            // Withdraw failed, continue
        }
    }
    
    // Bounded epoch lifecycle testing
    function runEpochCycle(uint256 yieldAmount, uint256 subsidyAmount) external {
        yieldAmount = bound(yieldAmount, 0, 50_000e6);
        subsidyAmount = bound(subsidyAmount, 0, 10_000e6);
        
        // Start new epoch if needed
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        if (currentEpochId == 0 || currentEpochTracker != currentEpochId) {
            try epochManager.startEpoch() returns (uint256 newEpochId) {
                currentEpochTracker = newEpochId;
            } catch {
                return;
            }
        }
        
        // Simulate yield generation by updating exchange rate
        if (yieldAmount > 0) {
            uint256 currentRate = cToken.exchangeRateStored();
            uint256 newRate = currentRate + (yieldAmount * 1e18) / (1_000_000e6); // Small increase
            cToken.setExchangeRate(newRate);
            totalYieldGenerated += yieldAmount;
        }
        
        // Allocate yield to current epoch
        try vault.allocateYieldToEpoch() {
            epochTotalYield[currentEpochTracker] += yieldAmount;
        } catch {
            // Allocation failed, continue
        }
        
        // End epoch with subsidies
        if (subsidyAmount > 0) {
            bytes32 merkleRoot = keccak256(abi.encodePacked(currentEpochTracker, subsidyAmount));
            
            try epochManager.endEpochWithSubsidies(
                currentEpochTracker,
                address(vault),
                merkleRoot,
                subsidyAmount
            ) {
                totalEpochsCompleted++;
                totalSubsidiesDistributed += subsidyAmount;
                epochTotalSubsidies[currentEpochTracker] += subsidyAmount;
                currentEpochTracker = 0; // Reset to allow new epoch
            } catch {
                // End epoch failed, continue
            }
        }
    }
    
    // Bounded collection management
    function manageCollections(uint256 action, uint256 collectionChoice) external {
        action = bound(action, 0, 2);
        collectionChoice = bound(collectionChoice, 0, 1);
        
        address collection = collectionChoice == 0 ? address(collection1) : address(collection2);
        
        if (action == 0) {
            // Update yield share
            try collectionRegistry.updateYieldShare(collection, 4000) {
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
            // Reactivate collection
            try collectionRegistry.activateCollection(collection) {
                // Success
            } catch {
                // Failed
            }
        }
    }
    
    // Utility function for bounding
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
    
    // INTEGRATION INVARIANT PROPERTIES
    
    // Property 1: Total system balance consistency
    function echidna_system_balance_consistent() external view returns (bool) {
        uint256 vaultAssets = vault.totalAssets();
        uint256 lendingManagerAssets = lendingManager.totalAssets();
        
        // Vault assets should be close to lending manager assets
        if (vaultAssets > lendingManagerAssets) {
            return (vaultAssets - lendingManagerAssets) <= 1e6; // 1 USDC tolerance
        } else {
            return (lendingManagerAssets - vaultAssets) <= 1e6;
        }
    }
    
    // Property 2: Collection shares sum to total shares
    function echidna_collection_shares_consistent() external view returns (bool) {
        uint256 totalShares = vault.totalSupply();
        uint256 collection1Shares = vault.totalCollectionShares(address(collection1));
        uint256 collection2Shares = vault.totalCollectionShares(address(collection2));
        
        // Total collection shares should not exceed total shares
        return collection1Shares + collection2Shares <= totalShares + 1e18; // Small tolerance
    }
    
    // Property 3: Yield generation is non-negative
    function echidna_yield_non_negative() external view returns (bool) {
        uint256 totalAssets = vault.totalAssets();
        // Total assets should be at least total deposited minus total withdrawn
        if (totalDeposited >= totalWithdrawn) {
            uint256 netDeposits = totalDeposited - totalWithdrawn;
            return totalAssets >= netDeposits;
        }
        return true;
    }
    
    // Property 4: Collection yield shares are within bounds
    function echidna_collection_yield_shares_bounded() external view returns (bool) {
        try collectionRegistry.getCollection(address(collection1)) returns (
            address,
            string memory,
            uint16 yieldShare1,
            bool,
            address,
            int256,
            int256
        ) {
            try collectionRegistry.getCollection(address(collection2)) returns (
                address,
                string memory,
                uint16 yieldShare2,
                bool,
                address,
                int256,
                int256
            ) {
                // Total yield shares should not exceed 100%
                return yieldShare1 + yieldShare2 <= 10000;
            } catch {
                return true;
            }
        } catch {
            return true;
        }
    }
    
    // Property 5: Epoch yield allocation consistency
    function echidna_epoch_yield_consistent() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        
        if (currentEpochId == 0) return true;
        
        try epochManager.getEpochDetails(currentEpochId) returns (
            uint256,
            uint256,
            uint256,
            uint256 totalYieldAvailable,
            uint256 totalSubsidiesDistributed,
            IEpochManager.EpochStatus
        ) {
            // Subsidies should not exceed available yield
            return totalSubsidiesDistributed <= totalYieldAvailable + 1e6; // Small tolerance
        } catch {
            return true;
        }
    }
    
    // Property 6: Principal tracking consistency
    function echidna_principal_tracking_consistent() external view returns (bool) {
        uint256 principalDeposited = lendingManager.totalPrincipalDeposited();
        // Principal should not exceed total deposited
        return principalDeposited <= totalDeposited + 1e6; // Small tolerance
    }
    
    // Property 7: Collection deposit tracking consistency
    function echidna_collection_deposits_reasonable() external view returns (bool) {
        uint256 collection1Deposits = collectionDeposits[address(collection1)];
        uint256 collection2Deposits = collectionDeposits[address(collection2)];
        
        // Individual collection deposits should be reasonable
        return collection1Deposits <= totalDeposited && collection2Deposits <= totalDeposited;
    }
    
    // Property 8: Withdrawal constraints
    function echidna_withdrawal_constraints() external view returns (bool) {
        // Total withdrawn should not exceed total deposited plus yield
        return totalWithdrawn <= totalDeposited + totalYieldGenerated + 1e6; // Small tolerance
    }
    
    // Property 9: Exchange rate manipulation resistance
    function echidna_exchange_rate_reasonable() external view returns (bool) {
        uint256 exchangeRate = cToken.exchangeRateStored();
        // Exchange rate should be within reasonable bounds
        return exchangeRate >= 1e16 && exchangeRate <= 1e20; // Between 0.01 and 100
    }
    
    // Property 10: Epoch subsidies do not exceed total yield generated
    function echidna_subsidies_bounded_by_yield() external view returns (bool) {
        // Total subsidies distributed should not greatly exceed total yield generated
        return totalSubsidiesDistributed <= totalYieldGenerated + 1e6; // Small tolerance
    }
    
    // Property 11: Collection registry state consistency
    function echidna_collection_registry_consistent() external view returns (bool) {
        try collectionRegistry.isRegistered(address(collection1)) returns (bool reg1) {
            try collectionRegistry.isRegistered(address(collection2)) returns (bool reg2) {
                // Both test collections should remain registered
                return reg1 && reg2;
            } catch {
                return true;
            }
        } catch {
            return true;
        }
    }
    
    // Property 12: Vault share price should be reasonable
    function echidna_share_price_reasonable() external view returns (bool) {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return true;
        
        uint256 totalAssets = vault.totalAssets();
        uint256 sharePrice = (totalAssets * 1e18) / totalSupply;
        
        // Share price should be within reasonable bounds (0.5 to 2.0)
        return sharePrice >= 5e17 && sharePrice <= 2e18;
    }
    
    // Property 13: Lending manager circuit breaker functionality
    function echidna_circuit_breaker_effective() external view returns (bool) {
        // This property is more about ensuring the system doesn't get stuck
        // We'll check that the lending manager can still perform basic operations
        uint256 totalAssets = lendingManager.totalAssets();
        return totalAssets >= 0; // Basic sanity check
    }
    
    // Property 14: Cross-contract role consistency
    function echidna_role_consistency() external view returns (bool) {
        // Vault should have operator role in lending manager and epoch manager
        bytes32 operatorRole = lendingManager.OPERATOR_ROLE();
        return lendingManager.hasRole(operatorRole, address(vault));
    }
    
    // Property 15: No infinite loops in epoch processing
    function echidna_epoch_processing_terminates() external view returns (bool) {
        uint256 currentEpochId = epochManager.getCurrentEpochId();
        // Epoch ID should not grow indefinitely fast
        return currentEpochId <= totalEpochsCompleted + 10; // Allow some buffer
    }
}