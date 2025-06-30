// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEpochManager {
    /**
     * @dev Emitted when a new epoch is started.
     * @param epochId The ID of the new epoch.
     * @param startTime The start timestamp of the epoch.
     * @param endTime The end timestamp of the epoch.
     */
    event EpochStarted(uint256 indexed epochId, uint256 startTime, uint256 endTime);

    /**
     * @dev Emitted when an epoch is finalized.
     * @param epochId The ID of the epoch being finalized.
     * @param totalYieldAvailable The total yield available for the epoch.
     * @param totalSubsidiesDistributed The total subsidies distributed during the epoch.
     */
    event EpochFinalized(uint256 indexed epochId, uint256 totalYieldAvailable, uint256 totalSubsidiesDistributed);

    /**
     * @dev Emitted when an epoch's processing has started.
     * @param epochId The ID of the epoch.
     */
    event EpochProcessingStarted(uint256 indexed epochId);

    /**
     * @dev Emitted when processing of an epoch has started. Alias of
     * `EpochProcessingStarted` for easier integrations.
     */
    event ProcessingStarted(uint256 indexed epochId);

    /**
     * @dev Emitted when an epoch is marked as failed.
     * @param epochId The ID of the epoch.
     * @param reason The reason for the failure.
     */
    event EpochFailed(uint256 indexed epochId, string reason);

    /**
     * @dev Emitted when processing of an epoch fails and it is forcefully
     * aborted. Mirrors `EpochFailed` but uses a distinct event name.
     */
    event ProcessingFailed(uint256 indexed epochId, string reason);

    /**
     * @dev Emitted when yield is allocated to a vault for a specific epoch.
     * @param epochId The ID of the epoch.
     * @param vault The address of the vault.
     * @param amount The amount of yield allocated.
     */
    event VaultYieldAllocated(uint256 indexed epochId, address indexed vault, uint256 amount);

    /**
     * @dev Emitted when the epoch duration is updated.
     * @param newDuration The new duration for epochs in seconds.
     */
    event EpochDurationUpdated(uint256 newDuration);

    /**
     * @dev Emitted when the automated system address is updated.
     * @param newAutomatedSystem The new address authorized for automated system interactions.
     */
    event AutomatedSystemUpdated(address indexed newAutomatedSystem);

    // Enhanced events with participant counts and processing metrics
    event EpochStartedWithParticipants(
        uint256 indexed epochId, uint256 startTime, uint256 endTime, uint256 participantCount
    );
    event EpochFinalizedWithMetrics(
        uint256 indexed epochId,
        uint256 totalYieldAvailable,
        uint256 totalSubsidiesDistributed,
        uint256 processingTimeMs
    );
    event EpochProcessingStartedWithMetrics(
        uint256 indexed epochId, uint256 participantCount, uint256 estimatedProcessingTime
    );

    // Role management events with context
    event EpochManagerRoleGranted(bytes32 indexed role, address indexed account, address sender, uint256 timestamp);
    event EpochManagerRoleRevoked(bytes32 indexed role, address indexed account, address sender, uint256 timestamp);

    enum EpochStatus {
        Pending, // Epoch has not started yet
        Active, // Epoch is currently active and accumulating yield
        Processing, // Epoch has ended, subsidies are being calculated and processed
        Completed, // Epoch processing is finished, subsidies distributed
        Failed // Epoch was aborted due to an issue

    }

    struct Epoch {
        uint256 id;
        uint256 startTime;
        uint256 endTime;
        uint256 totalYieldAvailable; // Total yield accumulated across all vaults for this epoch
        uint256 totalSubsidiesDistributed; // Total subsidies paid out from this epoch's yield
        EpochStatus status;
        mapping(address => uint256) vaultYieldAllocated; // Yield allocated from a specific vault for this epoch
    }

    function getCurrentEpochId() external view returns (uint256);
    function allocateVaultYield(address vault, uint256 amount) external;

    function startNewEpochWithParticipants(uint256 participantCount) external;
    function finalizeEpochWithMetrics(uint256 epochId, uint256 subsidiesDistributed, uint256 processingTimeMs)
        external;
    function beginEpochProcessingWithMetrics(uint256 epochId, uint256 participantCount, uint256 estimatedProcessingTime)
        external;
}
