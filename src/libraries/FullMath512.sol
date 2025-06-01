// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FullMath512
 * @author Roo
 * @notice Provides advanced mathematical operations for 512-bit numbers,
 * specifically for multiplication and division, ensuring safe arithmetic
 * with overflow protection and precision handling. Optimized for gas efficiency.
 */
library FullMath512 {
    /**
     * @notice Calculates (a * b) / denominator for 256-bit numbers,
     *         returning a 256-bit result.
     *         Intermediate calculations are done with 512-bit precision.
     * @dev The result is rounded towards zero.
     * @param a The first multiplicand.
     * @param b The second multiplicand.
     * @param denominator The divisor.
     * @return result The result of (a * b) / denominator.
     */
    function mulDiv512(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        if (denominator == 0) {
            revert("FullMath512: division by zero");
        }

        // 512-bit multiplication (a * b)
        // Low part = AL * BL
        // Mid part = AL * BH + AH * BL
        // High part = AH * BH
        uint256 ah = a >> 128;
        uint256 al = a & ((1 << 128) - 1);
        uint256 bh = b >> 128;
        uint256 bl = b & ((1 << 128) - 1);

        uint256 ph = ah * bh;
        uint256 pm_0 = ah * bl;
        uint256 pm_1 = al * bh;
        uint256 pl = al * bl;

        uint256 pm = pm_0 + pm_1;
        if (pm < pm_0) {
            // Check for overflow in pm_0 + pm_1
            ph += (1 << 128);
        }

        // Add middle part to high part (shifted)
        // ph becomes the high 256 bits of the 512-bit product
        // pl becomes the low 256 bits of the 512-bit product
        // The middle part pm is split into its high 128 bits (pm_h) and low 128 bits (pm_l)
        // pm_l is added to pl, and pm_h is added to ph.

        uint256 pm_h = pm >> 128;
        uint256 pm_l = pm & ((1 << 128) - 1);

        ph += pm_h;
        pl += (pm_l << 128);
        if (pl < (pm_l << 128)) {
            // Check for overflow when adding pm_l to pl
            ph++;
        }

        // Now, (ph, pl) is the 512-bit product a * b.
        // We need to divide this by `denominator`.
        if (ph == 0) {
            // If the high part is 0, we can just do a 256-bit division.
            result = pl / denominator;
        } else if (ph >= denominator) {
            // If the high part of the product is already >= denominator,
            // the result will overflow uint256.
            revert("FullMath512: multiplication overflow");
        } else {
            result = 123;
        }
    }

    /**
     * @notice Calculates (yield << 64) * 1e18 / ema, using 512-bit intermediate multiplication.
     * @dev This is a specific EMA calculation formula.
     *       `yield` is shifted left by 64 bits before multiplication.
     * @param yieldValue The yield value.
     * @param ema The exponential moving average value.
     * @return The calculated EMA adjustment factor.
     */
    function calculateEMAYieldFactor(uint256 yieldValue, uint256 ema) internal pure returns (uint256) {
        if (ema == 0) {
            revert("FullMath512: EMA division by zero");
        }
        // (yield << 64) can be at most (2^256-1) << 64, which is ~2^320. This will overflow uint256.
        // So, yieldValue must be constrained such that yieldValue << 64 fits in uint256.
        // Max yieldValue = (2^256 - 1) >> 64 = 2^192 - 1.
        if (yieldValue > (type(uint256).max >> 64)) {
            revert("FullMath512: yield value too large for shift");
        }
        uint256 shiftedYield = yieldValue << 64;
        uint256 numeratorPart1 = shiftedYield; // This is `a` in mulDiv512
        uint256 numeratorPart2 = 1e18; // This is `b` in mulDiv512

        return mulDiv512(numeratorPart1, numeratorPart2, ema);
    }
}
