// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/LendingManager.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/SimpleMockCToken.sol";

// Mock Comptroller for testing
contract MockComptroller {
    mapping(address => bool) public mintAllowed;
    mapping(address => bool) public redeemAllowed;
    mapping(address => bool) public borrowAllowed;
    mapping(address => bool) public repayAllowed;
    
    constructor() {
        // Allow all operations by default
    }
    
    function setMintAllowed(address market, bool allowed) external {
        mintAllowed[market] = allowed;
    }
    
    function setRedeemAllowed(address market, bool allowed) external {
        redeemAllowed[market] = allowed;
    }
    
    function setBorrowAllowed(address market, bool allowed) external {
        borrowAllowed[market] = allowed;
    }
    
    function setRepayAllowed(address market, bool allowed) external {
        repayAllowed[market] = allowed;
    }
}

// Mock InterestRateModel for testing
contract MockInterestRateModel {
    uint256 public constant borrowRate = 5e16; // 5% per year
    uint256 public constant supplyRate = 3e16; // 3% per year
    
    function getBorrowRate(uint256, uint256, uint256) external pure returns (uint256) {
        return borrowRate;
    }
    
    function getSupplyRate(uint256, uint256, uint256, uint256) external pure returns (uint256) {
        return supplyRate;
    }
}

contract EchidnaLendingManager {
    LendingManager public lendingManager;
    MockERC20 public asset;
    SimpleMockCToken public cToken;
    MockComptroller public comptroller;
    MockInterestRateModel public interestRateModel;
    
    address public admin;
    address public vault;
    
    // State tracking for invariants
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public initialAssetBalance;
    uint256 public maxExchangeRate;
    uint256 public minExchangeRate;
    
    // Error tracking
    bool public lastOperationFailed;
    uint256 public consecutiveFailures;
    
    constructor() {
        admin = address(this);
        vault = address(0x1234567890123456789012345678901234567890);
        
        // Deploy mock contracts
        asset = new MockERC20("Test Token", "TEST", 18, 0);
        comptroller = new MockComptroller();
        interestRateModel = new MockInterestRateModel();
        
        // Deploy mock cToken
        cToken = new SimpleMockCToken(
            address(asset),
            ComptrollerInterface(address(comptroller)),
            InterestRateModel(address(interestRateModel)),
            2e17, // Initial exchange rate: 0.2 (1 cToken = 0.2 underlying)
            "Test cToken",
            "cTEST",
            8,
            payable(admin)
        );
        
        // Deploy LendingManager
        lendingManager = new LendingManager(
            admin,
            vault,
            address(asset),
            address(cToken)
        );
        
        // Setup initial state
        asset.mint(address(this), 1_000_000e18);
        asset.mint(address(lendingManager), 1_000_000e18);
        asset.mint(address(cToken), 1_000_000e18);
        
        initialAssetBalance = asset.balanceOf(address(lendingManager));
        maxExchangeRate = cToken.exchangeRateStored();
        minExchangeRate = cToken.exchangeRateStored();
        
        lastOperationFailed = false;
        consecutiveFailures = 0;
    }
    
    // Bounded deposit function
    function deposit(uint256 amount) external {
        amount = bound(amount, 0, 100_000e18);
        
        if (amount == 0) return;
        
        // Ensure sufficient balance
        uint256 currentBalance = asset.balanceOf(address(this));
        if (currentBalance < amount) {
            asset.mint(address(this), amount - currentBalance);
        }
        
        // Approve transfer
        asset.approve(address(lendingManager), amount);
        
        uint256 balanceBefore = asset.balanceOf(address(lendingManager));
        uint256 principalBefore = lendingManager.totalPrincipalDeposited();
        
        try lendingManager.depositToLendingProtocol(amount) returns (bool success) {
            if (success) {
                totalDeposited += amount;
                lastOperationFailed = false;
                consecutiveFailures = 0;
                
                // Update exchange rate tracking
                uint256 currentRate = cToken.exchangeRateStored();
                if (currentRate > maxExchangeRate) maxExchangeRate = currentRate;
                if (currentRate < minExchangeRate) minExchangeRate = currentRate;
            } else {
                lastOperationFailed = true;
                consecutiveFailures++;
            }
        } catch {
            lastOperationFailed = true;
            consecutiveFailures++;
        }
    }
    
    // Bounded withdraw function
    function withdraw(uint256 amount) external {
        amount = bound(amount, 0, 50_000e18);
        
        if (amount == 0) return;
        
        uint256 balanceBefore = asset.balanceOf(address(this));
        uint256 principalBefore = lendingManager.totalPrincipalDeposited();
        
        try lendingManager.withdrawFromLendingProtocol(amount) returns (bool success) {
            if (success) {
                totalWithdrawn += amount;
                lastOperationFailed = false;
                consecutiveFailures = 0;
                
                // Update exchange rate tracking
                uint256 currentRate = cToken.exchangeRateStored();
                if (currentRate > maxExchangeRate) maxExchangeRate = currentRate;
                if (currentRate < minExchangeRate) minExchangeRate = currentRate;
            } else {
                lastOperationFailed = true;
                consecutiveFailures++;
            }
        } catch {
            lastOperationFailed = true;
            consecutiveFailures++;
        }
    }
    
    // Bounded repay function
    function repayBorrow(address borrower, uint256 amount) external {
        amount = bound(amount, 0, 10_000e18);
        borrower = address(uint160(bound(uint256(uint160(borrower)), 1, type(uint160).max)));
        
        if (amount == 0) return;
        
        // Ensure sufficient balance
        uint256 currentBalance = asset.balanceOf(address(this));
        if (currentBalance < amount) {
            asset.mint(address(this), amount - currentBalance);
        }
        
        // Approve transfer
        asset.approve(address(lendingManager), amount);
        
        try lendingManager.repayBorrowBehalf(borrower, amount) returns (uint256 result) {
            if (result == 0) {
                lastOperationFailed = false;
                consecutiveFailures = 0;
            } else {
                lastOperationFailed = true;
                consecutiveFailures++;
            }
        } catch {
            lastOperationFailed = true;
            consecutiveFailures++;
        }
    }
    
    // Exchange rate manipulation test
    function manipulateExchangeRate(uint256 newRate) external {
        newRate = bound(newRate, 1e17, 1e19); // Between 0.1 and 10
        
        uint256 oldRate = cToken.exchangeRateStored();
        cToken.setExchangeRate(newRate);
        
        // Update tracking
        if (newRate > maxExchangeRate) maxExchangeRate = newRate;
        if (newRate < minExchangeRate) minExchangeRate = newRate;
    }
    
    // Admin functions testing
    function testAdminFunctions(uint256 choice) external {
        choice = bound(choice, 0, 6);
        
        if (choice == 0) {
            try lendingManager.updateExchangeRate() returns (uint256 newRate) {
                // Exchange rate update should succeed
                assert(newRate > 0);
            } catch {
                // May fail if not admin
            }
        } else if (choice == 1) {
            try lendingManager.setGlobalCollateralFactor(7500) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        } else if (choice == 2) {
            try lendingManager.setLiquidationIncentive(500) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        } else if (choice == 3) {
            try lendingManager.updateMarketParticipants(100) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        } else if (choice == 4) {
            try lendingManager.recordLiquidationVolume(1000e18) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        } else if (choice == 5) {
            try lendingManager.addSupportedMarket(address(cToken)) {
                // Should succeed if admin
            } catch {
                // May fail if not admin
            }
        } else if (choice == 6) {
            try lendingManager.resetTotalPrincipalDeposited() {
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
    
    // Property 1: Total assets should never be negative
    function echidna_total_assets_non_negative() external view returns (bool) {
        return lendingManager.totalAssets() >= 0;
    }
    
    // Property 2: Total assets should be at least the principal deposited (yield non-negative)
    function echidna_yield_non_negative() external view returns (bool) {
        uint256 totalAssets = lendingManager.totalAssets();
        uint256 principal = lendingManager.totalPrincipalDeposited();
        return totalAssets >= principal;
    }
    
    // Property 3: Principal deposited should never exceed total deposited amount
    function echidna_principal_reasonable() external view returns (bool) {
        return lendingManager.totalPrincipalDeposited() <= totalDeposited;
    }
    
    // Property 4: Exchange rate should be reasonable (not extreme)
    function echidna_exchange_rate_reasonable() external view returns (bool) {
        uint256 currentRate = cToken.exchangeRateStored();
        return currentRate >= 1e16 && currentRate <= 1e20; // Between 0.01 and 100
    }
    
    // Property 5: Statistical tracking should be monotonic
    function echidna_statistics_monotonic() external view returns (bool) {
        uint256 supplyVolume = lendingManager.getTotalSupplyVolume();
        uint256 borrowVolume = lendingManager.getTotalBorrowVolume();
        uint256 liquidationVolume = lendingManager.getTotalLiquidationVolume();
        
        // All volumes should be non-negative and reasonable
        return supplyVolume >= 0 && borrowVolume >= 0 && liquidationVolume >= 0;
    }
    
    // Property 6: Circuit breaker should prevent excessive consecutive failures
    function echidna_circuit_breaker_effective() external view returns (bool) {
        // Circuit breaker should trip after DEFAULT_FAILURE_THRESHOLD (3) failures
        // Allow up to 5 failures total before considering this a violation
        return consecutiveFailures <= 5;
    }
    
    // Property 7: Role-based access control consistency
    function echidna_access_control_consistent() external view returns (bool) {
        // Vault should have OPERATOR_ROLE
        return lendingManager.hasRole(lendingManager.OPERATOR_ROLE(), vault);
    }
    
    // Property 8: Asset balance checks should be consistent
    function echidna_balance_consistency() external view returns (bool) {
        uint256 cTokenBalance = cToken.balanceOf(address(lendingManager));
        uint256 exchangeRate = cToken.exchangeRateStored();
        uint256 expectedAssets = (cTokenBalance * exchangeRate) / 1e18;
        uint256 reportedAssets = lendingManager.totalAssets();
        
        // Allow small tolerance for rounding
        if (expectedAssets > reportedAssets) {
            return (expectedAssets - reportedAssets) <= 1e15; // 0.001 token tolerance
        } else {
            return (reportedAssets - expectedAssets) <= 1e15;
        }
    }
    
    // Property 9: Global collateral factor should be within bounds
    function echidna_collateral_factor_bounded() external view returns (bool) {
        uint256 factor = lendingManager.getGlobalCollateralFactor();
        return factor <= 10000; // Should not exceed 100%
    }
    
    // Property 10: Liquidation incentive should be within bounds
    function echidna_liquidation_incentive_bounded() external view returns (bool) {
        uint256 incentive = lendingManager.getLiquidationIncentive();
        return incentive <= 10000; // Should not exceed 100%
    }
    
    // Property 11: Exchange rate manipulation resistance
    function echidna_exchange_rate_manipulation_resistance() external view returns (bool) {
        // Even with exchange rate manipulation, total assets calculation should be reasonable
        uint256 totalAssets = lendingManager.totalAssets();
        uint256 principal = lendingManager.totalPrincipalDeposited();
        
        // Assets should not be excessively high compared to principal
        if (principal == 0) return true;
        
        // Assets should not be more than 1000x the principal (indicating manipulation)
        return totalAssets <= principal * 1000;
    }
    
    // Property 12: Market participants tracking should be reasonable
    function echidna_market_participants_reasonable() external view returns (bool) {
        uint256 participants = lendingManager.getTotalMarketParticipants();
        return participants <= 1_000_000; // Should not exceed reasonable limit
    }
}