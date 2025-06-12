// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title EpochManager
 * @author Roo
 * @notice Manages the lifecycle of epochs for distributing rewards.
 * It handles epoch creation, state transitions, and yield allocation tracking.
 */
contract EpochManager is Ownable, AccessControl, ReentrancyGuard {
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

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

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

    uint256 public epochDuration; // Duration of each epoch in seconds (e.g., 7 days)
    uint256 public currentEpochId;
    mapping(uint256 => Epoch) public epochs;

    address public automatedSystem; // Address authorized to call certain functions (e.g., Go server)

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

    modifier onlyAutomatedSystem() {
        if (msg.sender != automatedSystem && msg.sender != owner()) {
            revert EpochManager__Unauthorized();
        }
        _;
    }

    /**
     * @notice Initializes the EpochManager contract.
     * @param _initialEpochDuration The initial duration for epochs (e.g., 7 days in seconds).
     * @param _initialAutomatedSystem The address of the automated system that will interact with this contract.
     * @param _initialOwner The initial owner of the contract.
     */
    constructor(uint256 _initialEpochDuration, address _initialAutomatedSystem, address _initialOwner)
        Ownable(_initialOwner)
    {
        if (_initialEpochDuration == 0) {
            revert EpochManager__InvalidEpochDuration();
        }
        epochDuration = _initialEpochDuration;
        automatedSystem = _initialAutomatedSystem;
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        _grantRole(VAULT_ROLE, _initialOwner);
        // currentEpochId is 0 initially, startNewEpoch will create epoch 1.
    }

    /**
     * @notice Starts a new epoch.
     * @dev Can only be called by the automated system or owner.
     * The previous epoch (if any) must be 'Completed' or this is the first epoch.
     */
    function startNewEpoch() external nonReentrant onlyAutomatedSystem {
        if (currentEpochId > 0) {
            Epoch storage currentEpoch = epochs[currentEpochId];
            if (currentEpoch.status != EpochStatus.Completed) {
                revert EpochManager__InvalidEpochStatus(currentEpochId, currentEpoch.status, EpochStatus.Completed);
            }
        }

        currentEpochId++;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + epochDuration;

        Epoch storage newEpoch = epochs[currentEpochId];
        newEpoch.id = currentEpochId;
        newEpoch.startTime = startTime;
        newEpoch.endTime = endTime;
        newEpoch.totalYieldAvailable = 0;
        newEpoch.totalSubsidiesDistributed = 0;
        newEpoch.status = EpochStatus.Active;
        // The mapping 'vaultYieldAllocated' is implicitly initialized as empty

        emit EpochStarted(currentEpochId, startTime, endTime);
    }

    /**
     * @notice Allocates yield from a specific vault to the current active epoch.
     * @dev This function is expected to be called by a CollectionsVault contract
     * when it allocates its yield for the epoch.
     * @param vault The address of the CollectionsVault.
     * @param amount The amount of yield being allocated.
     */
    function allocateVaultYield(address vault, uint256 amount) external nonReentrant onlyRole(VAULT_ROLE) {
        if (currentEpochId == 0) {
            revert EpochManager__InvalidEpochId(0);
        }
        Epoch storage currentActiveEpoch = epochs[currentEpochId];
        if (currentActiveEpoch.status != EpochStatus.Active) {
            revert EpochManager__InvalidEpochStatus(currentEpochId, currentActiveEpoch.status, EpochStatus.Active);
        }

        currentActiveEpoch.vaultYieldAllocated[vault] += amount;
        currentActiveEpoch.totalYieldAvailable += amount;

        emit VaultYieldAllocated(currentEpochId, vault, amount);
    }

    /**
     * @notice Transitions an active epoch to the Processing state.
     * @dev This indicates that the epoch has ended and subsidy calculations/distributions are underway.
     * Can only be called by the automated system or owner.
     * @param epochId The ID of the epoch to begin processing.
     */
    function beginEpochProcessing(uint256 epochId) external nonReentrant onlyAutomatedSystem {
        if (epochId == 0 || epochId > currentEpochId) {
            revert EpochManager__InvalidEpochId(epochId);
        }
        Epoch storage epoch = epochs[epochId];

        if (epoch.status != EpochStatus.Active) {
            revert EpochManager__InvalidEpochStatus(epochId, epoch.status, EpochStatus.Active);
        }
        if (block.timestamp < epoch.endTime) {
            revert EpochManager__EpochNotEnded(epochId, epoch.endTime);
        }

        epoch.status = EpochStatus.Processing;
        emit EpochProcessingStarted(epochId);
        emit ProcessingStarted(epochId);
    }

    /**
     * @notice Finalizes a processing epoch, marking it as Completed.
     * @dev Records the total subsidies distributed during the epoch.
     * Can only be called by the automated system or owner.
     * @param epochId The ID of the epoch to finalize.
     * @param subsidiesDistributed The total amount of subsidies distributed for this epoch.
     */
    function finalizeEpoch(uint256 epochId, uint256 subsidiesDistributed) external nonReentrant onlyAutomatedSystem {
        if (epochId == 0 || epochId > currentEpochId) {
            revert EpochManager__InvalidEpochId(epochId);
        }
        Epoch storage epoch = epochs[epochId];

        if (epoch.status != EpochStatus.Processing) {
            revert EpochManager__InvalidEpochStatus(epochId, epoch.status, EpochStatus.Processing);
        }

        epoch.totalSubsidiesDistributed = subsidiesDistributed;
        epoch.status = EpochStatus.Completed;

        emit EpochFinalized(epochId, epoch.totalYieldAvailable, epoch.totalSubsidiesDistributed);
    }

    /**
     * @notice Updates the duration for epochs.
     * @param newDuration The new duration in seconds.
     */
    function setEpochDuration(uint256 newDuration) external onlyOwner {
        if (newDuration == 0) {
            revert EpochManager__InvalidEpochDuration();
        }
        epochDuration = newDuration;
        emit EpochDurationUpdated(newDuration);
    }

    /**
     * @notice Updates the address of the automated system.
     * @param newAutomatedSystem The new address for the automated system.
     */
    function setAutomatedSystem(address newAutomatedSystem) external onlyOwner {
        if (newAutomatedSystem == address(0)) {
            revert("EpochManager: Automated system address cannot be zero.");
        }
        automatedSystem = newAutomatedSystem;
        emit AutomatedSystemUpdated(newAutomatedSystem);
    }

    /**
     * @notice Gets the details of a specific epoch.
     * @param epochId The ID of the epoch.
     * @return id The epoch ID.
     * @return startTime The start timestamp.
     * @return endTime The end timestamp.
     * @return totalYieldAvailable Total yield available for the epoch.
     * @return totalSubsidiesDistributed Total subsidies distributed.
     * @return status The current status of the epoch.
     */
    function getEpochDetails(uint256 epochId)
        external
        view
        returns (
            uint256 id,
            uint256 startTime,
            uint256 endTime,
            uint256 totalYieldAvailable,
            uint256 totalSubsidiesDistributed,
            EpochStatus status
        )
    {
        if (epochId == 0 || epochId > currentEpochId) {
            revert EpochManager__InvalidEpochId(epochId);
        }
        Epoch storage e = epochs[epochId];
        return (e.id, e.startTime, e.endTime, e.totalYieldAvailable, e.totalSubsidiesDistributed, e.status);
    }

    /**
     * @notice Gets the details of a specific epoch (alternative signature for interface compatibility).
     * @param epochId The ID of the epoch.
     * @return id The epoch ID.
     * @return startTime The start timestamp.
     * @return endTime The end timestamp.
     * @return totalYieldAvailableInEpoch Total yield available for the epoch.
     * @return totalSubsidiesDistributed Total subsidies distributed.
     * @return status The current status of the epoch.
     */
    function getEpoch(uint256 epochId)
        external
        view
        returns (
            uint256 id,
            uint256 startTime,
            uint256 endTime,
            uint256 totalYieldAvailableInEpoch,
            uint256 totalSubsidiesDistributed,
            EpochStatus status
        )
    {
        if (epochId == 0 || epochId > currentEpochId) {
            revert EpochManager__InvalidEpochId(epochId);
        }
        Epoch storage e = epochs[epochId];
        return (e.id, e.startTime, e.endTime, e.totalYieldAvailable, e.totalSubsidiesDistributed, e.status);
    }

    /**
     * @notice Gets the yield allocated by a specific vault for a given epoch.
     * @param epochId The ID of the epoch.
     * @param vault The address of the vault.
     * @return The amount of yield allocated by the vault for the epoch.
     */
    function getVaultYieldForEpoch(uint256 epochId, address vault) external view returns (uint256) {
        if (epochId == 0 || epochId > currentEpochId) {
            revert EpochManager__InvalidEpochId(epochId);
        }
        return epochs[epochId].vaultYieldAllocated[vault];
    }

    /**
     * @notice Returns the ID of the current epoch. If no epoch has started, returns 0.
     * @return The current epoch ID.
     */
    function getCurrentEpochId() external view returns (uint256) {
        return currentEpochId;
    }

    /**
     * @notice Returns the details of the current epoch.
     * @dev Reverts if no epoch is active or has been started.
     * @return id The epoch ID.
     * @return startTime The start timestamp.
     * @return endTime The end timestamp.
     * @return totalYieldAvailable Total yield available for the epoch.
     * @return totalSubsidiesDistributed Total subsidies distributed.
     * @return status The current status of the epoch.
     */
    function getCurrentEpochDetails()
        external
        view
        returns (
            uint256 id,
            uint256 startTime,
            uint256 endTime,
            uint256 totalYieldAvailable,
            uint256 totalSubsidiesDistributed,
            EpochStatus status
        )
    {
        if (currentEpochId == 0) {
            revert EpochManager__InvalidEpochId(0); // Or a more specific "NoActiveEpoch" error
        }
        Epoch storage e = epochs[currentEpochId];
        return (e.id, e.startTime, e.endTime, e.totalYieldAvailable, e.totalSubsidiesDistributed, e.status);
    }

    /**
     * @notice Marks an epoch as Failed.
     * @dev Can only be called by the automated system or owner.
     * This is used to explicitly abort an epoch if issues arise.
     * @param epochId The ID of the epoch to mark as failed.
     * @param reason A string describing the reason for failure.
     */
    function markEpochFailed(uint256 epochId, string calldata reason) external nonReentrant onlyAutomatedSystem {
        if (epochId == 0 || epochId > currentEpochId) {
            revert EpochManager__InvalidEpochId(epochId);
        }
        Epoch storage epoch = epochs[epochId];

        // An epoch can be marked as failed if it's Pending, Active, or Processing.
        // Cannot mark a Completed or already Failed epoch as Failed.
        if (epoch.status == EpochStatus.Completed || epoch.status == EpochStatus.Failed) {
            revert EpochManager__InvalidEpochStatus(epochId, epoch.status, EpochStatus.Active); // Or a more specific error
        }

        epoch.status = EpochStatus.Failed;
        emit EpochFailed(epochId, reason);
        emit ProcessingFailed(epochId, reason);
    }

    function grantVaultRole(address vault) external onlyOwner {
        _grantRole(VAULT_ROLE, vault);
    }

    function revokeVaultRole(address vault) external onlyOwner {
        _revokeRole(VAULT_ROLE, vault);
    }
}
