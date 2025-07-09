// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEpochManager {
    enum EpochStatus {
        Active, // Epoch is currently active and accumulating yield
        Completed, // Epoch processing is finished, subsidies distributed
        Failed // Epoch was aborted due to an issue

    }

    /**
     * @dev Thrown when an action is attempted by an unauthorized address.
     */
    error EpochManager__Unauthorized();

    /**
     * @dev Thrown when trying to start a new epoch while the current one is still active.
     */
    error EpochManager__EpochStillActive();

    /**
     * @dev Thrown when trying to operate on an epoch that is not in the expected state.
     * @param epochId The ID of the epoch.
     * @param currentStatus The current status of the epoch.
     * @param expectedStatus The expected status for the operation.
     */
    error EpochManager__InvalidEpochStatus(uint256 epochId, EpochStatus currentStatus, EpochStatus expectedStatus);

    /**
     * @dev Thrown when trying to finalize an epoch that has not ended yet.
     * @param epochId The ID of the epoch.
     * @param endTime The end time of the epoch.
     */
    error EpochManager__EpochNotEnded(uint256 epochId, uint256 endTime);

    /**
     * @dev Thrown when an invalid epoch ID is provided.
     * @param epochId The invalid epoch ID.
     */
    error EpochManager__InvalidEpochId(uint256 epochId);

    /**
     * @dev Thrown when the epoch duration is set to zero.
     */
    error EpochManager__InvalidEpochDuration();

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
     * @dev Emitted when the automated system address is updated.
     * @param newAutomatedSystem The new address authorized for automated system interactions.
     */
    event AutomatedSystemUpdated(address indexed newAutomatedSystem);

    /**
     * @dev Emitted when the DebtSubsidizer address is updated.
     * @param newDebtSubsidizer The new address for the DebtSubsidizer contract.
     */
    event DebtSubsidizerUpdated(address indexed newDebtSubsidizer);

    // Role management events with context
    event EpochManagerRoleGranted(bytes32 indexed role, address indexed account, address sender, uint256 timestamp);
    event EpochManagerRoleRevoked(bytes32 indexed role, address indexed account, address sender, uint256 timestamp);

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
    function getVaultYieldForEpoch(uint256 epochId, address vault) external view returns (uint256);
    function setAutomatedSystem(address newAutomatedSystem) external;
    function setDebtSubsidizer(address newDebtSubsidizer) external;
    function grantVaultRole(address vault) external;
    function revokeVaultRole(address vault) external;

    // Simplified workflow functions - only 2 calls needed per epoch
    function startEpoch() external returns (uint256 epochId);
    function endEpochWithSubsidies(
        uint256 epochId,
        address vaultAddress,
        bytes32 merkleRoot,
        uint256 subsidiesDistributed
    ) external;

    function forceEndEpochWithZeroYield(uint256 epochId, address vaultAddress) external;
}
