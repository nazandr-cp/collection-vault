// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEpochManager {
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

    event EpochManagerRoleGranted(bytes32 indexed role, address indexed account, address sender, uint256 timestamp);
    event EpochManagerRoleRevoked(bytes32 indexed role, address indexed account, address sender, uint256 timestamp);

    function getCurrentEpochId() external view returns (uint256);
    function allocateVaultYield(address vault, uint256 amount) external;

    function startNewEpochWithParticipants(uint256 participantCount) external;
    function finalizeEpochWithMetrics(uint256 epochId, uint256 subsidiesDistributed, uint256 processingTimeMs)
        external;
    function beginEpochProcessingWithMetrics(uint256 epochId, uint256 participantCount, uint256 estimatedProcessingTime)
        external;
}
