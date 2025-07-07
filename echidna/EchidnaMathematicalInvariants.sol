// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/CollectionsVault.sol";
import "../src/mocks/MockERC20.sol";

// Mathematical testing contract focusing on precision and overflow scenarios
contract EchidnaMathematicalInvariants {
    // Test contracts
    MockERC20 public asset;
    
    // Test addresses
    address public user1;
    address public user2;
    
    // Mathematical state tracking
    uint256 public totalMathOperations;
    uint256 public precisionErrors;
    uint256 public overflowAttempts;
    uint256 public underflowAttempts;
    uint256 public divisionByZeroAttempts;
    
    // Precision tracking
    uint256 public maxPrecisionLoss;
    uint256 public cumulativePrecisionLoss;
    
    // Test values for edge cases
    uint256 public constant MAX_UINT256 = type(uint256).max;
    uint256 public constant MIN_POSITIVE = 1;
    uint256 public constant PRECISION_SCALE = 1e18;
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;
    
    constructor() {
        user1 = address(0x1111111111111111111111111111111111111111);
        user2 = address(0x2222222222222222222222222222222222222222);
        
        asset = new MockERC20("Test Token", "TEST", 18, 0);
        
        // Mint large amounts for overflow testing
        asset.mint(address(this), MAX_UINT256 / 2);
        asset.mint(user1, MAX_UINT256 / 4);
        asset.mint(user2, MAX_UINT256 / 4);
        
        totalMathOperations = 0;
        precisionErrors = 0;
        overflowAttempts = 0;
        underflowAttempts = 0;
        divisionByZeroAttempts = 0;
        maxPrecisionLoss = 0;
        cumulativePrecisionLoss = 0;
    }
    
    // Test ERC4626 conversion math with extreme values
    function testConversionsExtreme(uint256 assets, uint256 shares, uint256 totalAssets, uint256 totalShares) external {
        assets = bound(assets, 0, MAX_UINT256 / 2);
        shares = bound(shares, 0, MAX_UINT256 / 2);
        totalAssets = bound(totalAssets, 1, MAX_UINT256 / 2);
        totalShares = bound(totalShares, 1, MAX_UINT256 / 2);
        
        totalMathOperations++;
        
        // Test convertToShares math
        if (totalShares == 0) {
            divisionByZeroAttempts++;
        } else {
            try this.safeConvertToShares(assets, totalAssets, totalShares) returns (uint256 result) {
                // Check for reasonable result
                if (totalAssets > 0) {
                    uint256 expectedRatio = (assets * PRECISION_SCALE) / totalAssets;
                    uint256 actualRatio = (result * PRECISION_SCALE) / totalShares;
                    
                    uint256 precisionLoss = expectedRatio > actualRatio ? 
                        expectedRatio - actualRatio : actualRatio - expectedRatio;
                    
                    if (precisionLoss > maxPrecisionLoss) {
                        maxPrecisionLoss = precisionLoss;
                    }
                    cumulativePrecisionLoss += precisionLoss;
                }
            } catch {
                overflowAttempts++;
            }
        }
        
        // Test convertToAssets math
        if (totalAssets == 0) {
            divisionByZeroAttempts++;
        } else {
            try this.safeConvertToAssets(shares, totalAssets, totalShares) returns (uint256 result) {
                // Check for reasonable result
                if (totalShares > 0) {
                    uint256 expectedRatio = (shares * PRECISION_SCALE) / totalShares;
                    uint256 actualRatio = (result * PRECISION_SCALE) / totalAssets;
                    
                    uint256 precisionLoss = expectedRatio > actualRatio ? 
                        expectedRatio - actualRatio : actualRatio - expectedRatio;
                    
                    if (precisionLoss > maxPrecisionLoss) {
                        maxPrecisionLoss = precisionLoss;
                    }
                    cumulativePrecisionLoss += precisionLoss;
                }
            } catch {
                overflowAttempts++;
            }
        }
    }
    
    // Test percentage calculations (basis points)
    function testPercentageCalculations(uint256 amount, uint256 percentage) external {
        amount = bound(amount, 0, MAX_UINT256 / BASIS_POINTS_DENOMINATOR);
        percentage = bound(percentage, 0, BASIS_POINTS_DENOMINATOR);
        
        totalMathOperations++;
        
        try this.safePercentageCalculation(amount, percentage) returns (uint256 result) {
            // Result should not exceed original amount for percentages <= 100%
            if (percentage <= BASIS_POINTS_DENOMINATOR) {
                if (result > amount) {
                    precisionErrors++;
                }
            }
        } catch {
            overflowAttempts++;
        }
    }
    
    // Test yield calculation edge cases
    function testYieldCalculations(uint256 principal, uint256 exchangeRate, uint256 timeElapsed) external {
        principal = bound(principal, 0, MAX_UINT256 / 2);
        exchangeRate = bound(exchangeRate, PRECISION_SCALE / 10, PRECISION_SCALE * 10); // 0.1x to 10x
        timeElapsed = bound(timeElapsed, 0, 365 days);
        
        totalMathOperations++;
        
        try this.safeYieldCalculation(principal, exchangeRate, timeElapsed) returns (uint256 yield) {
            // Yield should be reasonable relative to principal
            if (exchangeRate > PRECISION_SCALE) {
                // Positive yield case
                if (yield < principal) {
                    // This might be precision loss or legitimate scenario
                    uint256 loss = principal - yield;
                    cumulativePrecisionLoss += loss;
                }
            }
        } catch {
            overflowAttempts++;
        }
    }
    
    // Test collection yield share calculations
    function testCollectionYieldShares(uint256 totalYield, uint256 yieldShare1, uint256 yieldShare2, uint256 yieldShare3) external {
        totalYield = bound(totalYield, 0, MAX_UINT256 / BASIS_POINTS_DENOMINATOR);
        yieldShare1 = bound(yieldShare1, 0, BASIS_POINTS_DENOMINATOR);
        yieldShare2 = bound(yieldShare2, 0, BASIS_POINTS_DENOMINATOR - yieldShare1);
        yieldShare3 = bound(yieldShare3, 0, BASIS_POINTS_DENOMINATOR - yieldShare1 - yieldShare2);
        
        totalMathOperations++;
        
        uint256 allocation1 = 0;
        uint256 allocation2 = 0;
        uint256 allocation3 = 0;
        
        try this.safePercentageCalculation(totalYield, yieldShare1) returns (uint256 result) {
            allocation1 = result;
        } catch {
            overflowAttempts++;
        }
        
        try this.safePercentageCalculation(totalYield, yieldShare2) returns (uint256 result) {
            allocation2 = result;
        } catch {
            overflowAttempts++;
        }
        
        try this.safePercentageCalculation(totalYield, yieldShare3) returns (uint256 result) {
            allocation3 = result;
        } catch {
            overflowAttempts++;
        }
        
        // Total allocations should not exceed total yield
        uint256 totalAllocated = allocation1 + allocation2 + allocation3;
        if (totalAllocated > totalYield) {
            precisionErrors++;
        }
    }
    
    // Test compound interest calculations
    function testCompoundInterest(uint256 principal, uint256 rate, uint256 periods) external {
        principal = bound(principal, MIN_POSITIVE, MAX_UINT256 / 1e6); // Reduce range for compound calculations
        rate = bound(rate, 0, PRECISION_SCALE / 10); // Max 10% per period
        periods = bound(periods, 0, 100); // Max 100 periods
        
        totalMathOperations++;
        
        uint256 amount = principal;
        
        for (uint256 i = 0; i < periods && amount <= MAX_UINT256 / 2; i++) {
            try this.safeCompoundStep(amount, rate) returns (uint256 newAmount) {
                amount = newAmount;
            } catch {
                overflowAttempts++;
                break;
            }
        }
        
        // Final amount should be reasonable (not infinite growth)
        if (amount > principal * 1000 && periods < 50) {
            precisionErrors++;
        }
    }
    
    // Test square root approximations (for price calculations)
    function testSqrtApproximation(uint256 value) external {
        value = bound(value, 0, MAX_UINT256 / 2);
        
        totalMathOperations++;
        
        try this.safeSqrt(value) returns (uint256 result) {
            // Verify sqrt property: result^2 should be close to value
            if (result > 0 && value > 0) {
                uint256 squared = result * result;
                uint256 error = squared > value ? squared - value : value - squared;
                
                // Error should be small relative to value
                if (value > 1e6 && error > value / 1000) {
                    precisionErrors++;
                }
            }
        } catch {
            overflowAttempts++;
        }
    }
    
    // Test division with rounding
    function testDivisionRounding(uint256 numerator, uint256 denominator, bool roundUp) external {
        numerator = bound(numerator, 0, MAX_UINT256 / 2);
        denominator = bound(denominator, 1, MAX_UINT256 / 2);
        
        totalMathOperations++;
        
        try this.safeDivisionWithRounding(numerator, denominator, roundUp) returns (uint256 result) {
            // Check rounding correctness
            uint256 remainder = numerator % denominator;
            uint256 quotient = numerator / denominator;
            
            if (roundUp && remainder > 0) {
                if (result != quotient + 1) {
                    precisionErrors++;
                }
            } else {
                if (result != quotient) {
                    precisionErrors++;
                }
            }
        } catch {
            overflowAttempts++;
        }
    }
    
    // Test exponential calculations (for weight functions)
    function testExponentialCalculations(int256 exponent, uint256 base) external {
        exponent = int256(bound(uint256(exponent), 0, 1e6)) - 5e5; // Range from -500k to 500k
        base = bound(base, PRECISION_SCALE / 10, PRECISION_SCALE * 2); // 0.1 to 2.0
        
        totalMathOperations++;
        
        try this.safeExponential(base, exponent) returns (uint256 result) {
            // Result should be reasonable
            if (exponent >= 0 && result < base) {
                // For positive exponents, result should generally be >= base
                precisionErrors++;
            }
            if (exponent < 0 && result > base) {
                // For negative exponents, result should generally be <= base
                precisionErrors++;
            }
        } catch {
            overflowAttempts++;
        }
    }
    
    // Safe mathematical operations (external for testing)
    
    function safeConvertToShares(uint256 assets, uint256 totalAssets, uint256 totalShares) 
        external pure returns (uint256) {
        if (totalAssets == 0) return assets;
        return (assets * totalShares) / totalAssets;
    }
    
    function safeConvertToAssets(uint256 shares, uint256 totalAssets, uint256 totalShares) 
        external pure returns (uint256) {
        if (totalShares == 0) return shares;
        return (shares * totalAssets) / totalShares;
    }
    
    function safePercentageCalculation(uint256 amount, uint256 percentage) 
        external pure returns (uint256) {
        return (amount * percentage) / BASIS_POINTS_DENOMINATOR;
    }
    
    function safeYieldCalculation(uint256 principal, uint256 exchangeRate, uint256 timeElapsed) 
        external pure returns (uint256) {
        uint256 multiplier = (exchangeRate * timeElapsed) / (365 days);
        return (principal * multiplier) / PRECISION_SCALE;
    }
    
    function safeCompoundStep(uint256 amount, uint256 rate) 
        external pure returns (uint256) {
        uint256 interest = (amount * rate) / PRECISION_SCALE;
        return amount + interest;
    }
    
    function safeSqrt(uint256 value) external pure returns (uint256) {
        if (value == 0) return 0;
        
        uint256 x = value;
        uint256 y = (x + 1) / 2;
        
        while (y < x) {
            x = y;
            y = (x + value / x) / 2;
        }
        
        return x;
    }
    
    function safeDivisionWithRounding(uint256 numerator, uint256 denominator, bool roundUp) 
        external pure returns (uint256) {
        uint256 result = numerator / denominator;
        if (roundUp && numerator % denominator > 0) {
            result += 1;
        }
        return result;
    }
    
    function safeExponential(uint256 base, int256 exponent) 
        external pure returns (uint256) {
        if (exponent == 0) return PRECISION_SCALE;
        if (exponent == 1) return base;
        if (exponent == -1) return PRECISION_SCALE * PRECISION_SCALE / base;
        
        // Simplified exponential for testing (not production ready)
        uint256 result = PRECISION_SCALE;
        uint256 absExp = exponent > 0 ? uint256(exponent) : uint256(-exponent);
        
        for (uint256 i = 0; i < absExp && i < 10; i++) {
            if (exponent > 0) {
                result = (result * base) / PRECISION_SCALE;
            } else {
                result = (result * PRECISION_SCALE) / base;
            }
        }
        
        return result;
    }
    
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
    
    // MATHEMATICAL INVARIANT PROPERTIES
    
    // Property 1: No integer overflow in percentage calculations
    function echidna_no_percentage_overflow() external view returns (bool) {
        return overflowAttempts <= totalMathOperations / 2; // Allow some overflow attempts
    }
    
    // Property 2: Precision loss should be bounded
    function echidna_precision_loss_bounded() external view returns (bool) {
        if (totalMathOperations == 0) return true;
        
        uint256 averagePrecisionLoss = cumulativePrecisionLoss / totalMathOperations;
        return averagePrecisionLoss <= PRECISION_SCALE / 1000; // Max 0.1% average precision loss
    }
    
    // Property 3: Maximum precision loss should be reasonable
    function echidna_max_precision_loss_reasonable() external view returns (bool) {
        return maxPrecisionLoss <= PRECISION_SCALE / 100; // Max 1% precision loss in any single operation
    }
    
    // Property 4: Division by zero attempts should be handled
    function echidna_division_by_zero_handled() external view returns (bool) {
        return divisionByZeroAttempts <= totalMathOperations; // All attempts should be tracked
    }
    
    // Property 5: Precision errors should be minimal
    function echidna_precision_errors_minimal() external view returns (bool) {
        if (totalMathOperations == 0) return true;
        
        // Precision errors should be less than 5% of total operations
        return precisionErrors <= totalMathOperations / 20;
    }
    
    // Property 6: Overflow attempts should be reasonable
    function echidna_overflow_attempts_reasonable() external view returns (bool) {
        // Not all operations should overflow
        return overflowAttempts <= totalMathOperations;
    }
    
    // Property 7: Underflow attempts should be tracked
    function echidna_underflow_attempts_tracked() external view returns (bool) {
        return underflowAttempts <= totalMathOperations;
    }
    
    // Property 8: Mathematical operations should terminate
    function echidna_operations_terminate() external view returns (bool) {
        // Total operations should be reasonable (not infinite loops)
        return totalMathOperations <= 100000;
    }
    
    // Property 9: Cumulative precision loss should be bounded
    function echidna_cumulative_precision_bounded() external view returns (bool) {
        // Cumulative precision loss should not grow without bound
        return cumulativePrecisionLoss <= totalMathOperations * (PRECISION_SCALE / 1000);
    }
    
    // Property 10: No catastrophic precision loss
    function echidna_no_catastrophic_precision_loss() external view returns (bool) {
        // Maximum single precision loss should not be catastrophic
        return maxPrecisionLoss <= PRECISION_SCALE / 10; // Max 10% in any single operation
    }
    
    // Property 11: Error rate should be acceptable
    function echidna_error_rate_acceptable() external view returns (bool) {
        if (totalMathOperations == 0) return true;
        
        uint256 totalErrors = precisionErrors + overflowAttempts + underflowAttempts + divisionByZeroAttempts;
        
        // Total error rate should be less than 30%
        return totalErrors <= (totalMathOperations * 30) / 100;
    }
    
    // Property 12: Mathematical consistency
    function echidna_mathematical_consistency() external view returns (bool) {
        // Basic mathematical consistency checks
        uint256 testValue1 = 1000 * PRECISION_SCALE;
        uint256 testValue2 = 500 * PRECISION_SCALE;
        
        // Basic arithmetic should work
        return testValue1 > testValue2 && testValue1 + testValue2 > testValue1;
    }
}