// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RateLimiter
 * @author Roo
 * @notice Provides rate limiting and bounds checking functionality.
 *         Designed for use with SubsidyDistributor for deltaIdx protection
 *         and EMA bounds checking.
 */
library RateLimiter {
    struct RateLimitConfig {
        uint256 deltaIdxMax; // Maximum allowed change in index per period
        uint256 emaMin; // Minimum allowed EMA value
        uint256 emaMax; // Maximum allowed EMA value
        uint256 timePeriod; // Time period for rate limiting deltaIdx (e.g., 1 hour)
        uint256 lastUpdateTime; // Timestamp of the last index update
        uint256 accumulatedDeltaSinceLastPeriod; // Accumulated deltaIdx within the current period
    }

    event RateLimitViolation(string reason, uint256 currentValue, uint256 limit);
    event DeltaIdxAccumulationReset(uint256 timestamp);

    /**
     * @notice Checks if a new EMA value is within the configured bounds.
     * @param config The rate limit configuration.
     * @param newEma The new EMA value to check.
     * @return True if the new EMA is within bounds, false otherwise.
     */
    function checkEmaBounds(RateLimitConfig storage config, uint256 newEma) internal returns (bool) {
        if (newEma < config.emaMin) {
            emit RateLimitViolation("EMA below minimum", newEma, config.emaMin);
            return false;
        }
        if (newEma > config.emaMax) {
            emit RateLimitViolation("EMA above maximum", newEma, config.emaMax);
            return false;
        }
        return true;
    }

    /**
     * @notice Checks if a proposed change in index (deltaIdx) is within the rate limit.
     * @dev This function also updates the accumulated delta for the current period.
     *      It should be called before applying the actual index change.
     * @param config The rate limit configuration storage.
     * @param proposedDeltaIdx The proposed change in the index.
     * @return True if the proposed deltaIdx is within limits, false otherwise.
     */
    function checkAndUpdateDeltaIdxRateLimit(RateLimitConfig storage config, uint256 proposedDeltaIdx)
        internal
        returns (bool)
    {
        uint256 currentTime = block.timestamp;

        // If the current time period has passed, reset the accumulated delta.
        if (currentTime >= config.lastUpdateTime + config.timePeriod) {
            config.accumulatedDeltaSinceLastPeriod = 0;
            config.lastUpdateTime = currentTime; // Start new period from current time
            emit DeltaIdxAccumulationReset(currentTime);
        }

        // Check if the proposed delta, added to what's already accumulated in this period, exceeds the max.
        if (config.accumulatedDeltaSinceLastPeriod + proposedDeltaIdx > config.deltaIdxMax) {
            emit RateLimitViolation(
                "deltaIdx exceeds rate limit for current period",
                config.accumulatedDeltaSinceLastPeriod + proposedDeltaIdx,
                config.deltaIdxMax
            );
            return false;
        }

        config.accumulatedDeltaSinceLastPeriod += proposedDeltaIdx;
        return true;
    }

    /**
     * @notice Initializes or updates the rate limit configuration.
     * @param config The rate limit configuration storage.
     * @param _deltaIdxMax Maximum allowed change in index per period.
     * @param _emaMin Minimum allowed EMA value.
     * @param _emaMax Maximum allowed EMA value.
     * @param _timePeriod Time period for rate limiting deltaIdx.
     */
    function setRateLimitConfig(
        RateLimitConfig storage config,
        uint256 _deltaIdxMax,
        uint256 _emaMin,
        uint256 _emaMax,
        uint256 _timePeriod
    ) internal {
        require(_emaMin <= _emaMax, "RateLimiter: EMA min cannot exceed EMA max");
        require(_timePeriod > 0, "RateLimiter: Time period must be positive");

        config.deltaIdxMax = _deltaIdxMax;
        config.emaMin = _emaMin;
        config.emaMax = _emaMax;
        config.timePeriod = _timePeriod;

        // If it's the very first initialization, set lastUpdateTime to current time.
        if (config.lastUpdateTime == 0) {
            config.lastUpdateTime = block.timestamp;
        }
    }

    /**
     * @notice Records an index update, ensuring period logic is correctly handled.
     * @param config The rate limit configuration storage.
     */
    function recordIndexUpdate(RateLimitConfig storage config) internal {
        uint256 currentTime = block.timestamp;
        // Ensure period logic is re-evaluated if a long time passed since last check/update.
        if (currentTime >= config.lastUpdateTime + config.timePeriod) {
            config.accumulatedDeltaSinceLastPeriod = 0; // Reset for the new period
            config.lastUpdateTime = currentTime;
            emit DeltaIdxAccumulationReset(currentTime);
        }
        // If no new period, accumulatedDeltaSinceLastPeriod and lastUpdateTime
        // are assumed to be correctly set by a preceding checkAndUpdateDeltaIdxRateLimit call.
    }
}
