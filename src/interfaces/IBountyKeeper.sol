// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IBountyKeeper Interface
 * @notice Interface for the BountyKeeper contract, which manages automated yield pulling,
 * distribution, and bounty rewards.
 */
interface IBountyKeeper {
    /**
     * @notice Emitted when the poke function is successfully executed.
     * @param caller The address that triggered the poke.
     * @param yieldPulled The amount of yield pulled from the MarketVault.
     * @param bountyPaid The amount of bounty paid to the caller.
     * @param nextTriggerTimestamp The timestamp for the next earliest possible time-based trigger.
     */
    event PokeExecuted(address indexed caller, uint256 yieldPulled, uint256 bountyPaid, uint256 nextTriggerTimestamp);

    /**
     * @notice Emitted when trigger conditions are met.
     * @param yieldThresholdMet True if yield threshold was met.
     * @param timeThresholdMet True if time threshold was met.
     * @param emergencyTrigger True if an emergency trigger was activated.
     * @param bufferThresholdMet True if the subsidy distributor buffer threshold was met.
     */
    event TriggerConditionsMet(
        bool yieldThresholdMet, bool timeThresholdMet, bool emergencyTrigger, bool bufferThresholdMet
    );

    /**
     * @notice Emitted when a bounty is paid.
     * @param recipient The address that received the bounty.
     * @param amount The amount of bounty paid.
     */
    event BountyPaid(address indexed recipient, uint256 amount);

    /**
     * @notice Error for when poke is called too soon.
     * @param nextAvailableTime The timestamp when poke can be called next.
     */
    error PokeRateLimited(uint256 nextAvailableTime);

    /**
     * @notice Error for when no trigger conditions are met for poke.
     */
    error NoTriggerConditionMet();

    /**
     * @notice Error for when an invalid contract address is provided.
     * @param contractAddress The invalid address.
     */
    error InvalidContractAddress(address contractAddress);

    /**
     * @notice Error for when bounty calculation results in zero.
     */
    error BountyCalculationZero();

    /**
     * @notice Error for when bounty exceeds the maximum allowed limit.
     * @param calculatedBounty The bounty amount that exceeded the limit.
     * @param maxBounty The maximum allowed bounty.
     */
    error BountyExceedsLimit(uint256 calculatedBounty, uint256 maxBounty);

    /**
     * @notice Error for when bounty distribution fails.
     * @param recipient The intended recipient of the bounty.
     * @param amount The amount of bounty that failed to transfer.
     */
    error BountyDistributionFailed(address recipient, uint256 amount);

    /**
     * @notice Error for when MarketVault.pullYield() fails.
     */
    error PullYieldFailed();

    /**
     * @notice Error for when SubsidyDistributor.takeBuffer() fails.
     */
    error TakeBufferFailed();

    /**
     * @notice Main trigger function that executes pull + push operations if conditions are met.
     * @dev This function can be called by anyone. A bounty is paid to the caller if successful.
     * It checks various trigger conditions (yield, time, emergency, buffer) before proceeding.
     * Reentrancy protection is applied.
     */
    function poke() external returns (uint256 yieldPulled, uint256 bountyAwarded);

    /**
     * @notice Sets the configuration for bounty parameters.
     * @dev Only callable by the owner.
     * @param minYieldThreshold Minimum yield accumulated to trigger poke.
     * @param maxTimeDelay Maximum time delay since last execution to trigger poke.
     * @param bountyPercentagePPM Bounty percentage in parts per million (PPM).
     * @param maxBountyAmount Maximum absolute bounty amount.
     * @param pokeCooldown Minimum time between poke calls.
     */
    function setBountyConfig(
        uint256 minYieldThreshold,
        uint256 maxTimeDelay,
        uint32 bountyPercentagePPM,
        uint256 maxBountyAmount,
        uint256 pokeCooldown
    ) external;

    /**
     * @notice Sets the integration contract addresses.
     * @dev Only callable by the owner.
     * @param marketVaultAddr Address of the MarketVault contract.
     * @param subsidyDistributorAddr Address of the SubsidyDistributor contract.
     * @param rootGuardianAddr Address of the RootGuardian contract.
     */
    function setIntegrationContracts(address marketVaultAddr, address subsidyDistributorAddr, address rootGuardianAddr)
        external;

    /**
     * @notice Allows an authorized address (e.g., RootGuardian) to trigger an emergency poke.
     * @dev This bypasses normal time and yield thresholds but still respects cooldown.
     */
    function emergencyPoke() external returns (uint256 yieldPulled, uint256 bountyAwarded);

    /**
     * @notice Retrieves the current bounty configuration.
     * @return minYieldThreshold_ Current minimum yield threshold.
     * @return maxTimeDelay_ Current maximum time delay.
     * @return bountyPercentagePPM_ Current bounty percentage in PPM.
     * @return maxBountyAmount_ Current maximum bounty amount.
     * @return pokeCooldown_ Current poke cooldown period.
     */
    function getBountyConfig()
        external
        view
        returns (
            uint256 minYieldThreshold_,
            uint256 maxTimeDelay_,
            uint32 bountyPercentagePPM_,
            uint256 maxBountyAmount_,
            uint256 pokeCooldown_
        );

    /**
     * @notice Retrieves the addresses of the integrated contracts.
     * @return marketVault_ Address of the MarketVault.
     * @return subsidyDistributor_ Address of the SubsidyDistributor.
     * @return rootGuardian_ Address of the RootGuardian.
     */
    function getIntegrationContracts()
        external
        view
        returns (address marketVault_, address subsidyDistributor_, address rootGuardian_);

    /**
     * @notice Retrieves the timestamp of the last successful poke execution.
     * @return lastExecutionTimestamp_ The timestamp of the last execution.
     */
    function getLastExecutionTimestamp() external view returns (uint256 lastExecutionTimestamp_);

    /**
     * @notice Retrieves the timestamp of the last poke attempt (successful or not).
     * @return lastPokeAttemptTimestamp_ The timestamp of the last poke attempt.
     */
    function getLastPokeAttemptTimestamp() external view returns (uint256 lastPokeAttemptTimestamp_);
}
