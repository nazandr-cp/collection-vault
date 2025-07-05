// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlBase} from "./AccessControlBase.sol";
import {Roles} from "./Roles.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {IDebtSubsidizer} from "./interfaces/IDebtSubsidizer.sol";

/**
 * @title EpochManager
 * @author Roo
 * @notice Manages the lifecycle of epochs for distributing rewards.
 * It handles epoch creation, state transitions, and yield allocation tracking.
 */
contract EpochManager is IEpochManager, AccessControlBase {
    bytes32 public constant OPERATOR_ROLE = Roles.OPERATOR_ROLE;

    uint256 public epochDuration; // Duration of each epoch in seconds (e.g., 7 days)
    uint256 public currentEpochId;
    mapping(uint256 => Epoch) public epochs;

    IDebtSubsidizer public debtSubsidizer; // DebtSubsidizer contract for Merkle root updates

    /**
     * @notice Initializes the EpochManager contract.
     * @param _initialEpochDuration The initial duration for epochs (e.g., 7 days in seconds).
     * @param _initialAutomatedSystem The address of the automated system that will interact with this contract.
     * @param _initialAdmin The initial admin of the contract.
     * @param _debtSubsidizer The address of the DebtSubsidizer contract.
     */
    constructor(
        uint256 _initialEpochDuration,
        address _initialAutomatedSystem,
        address _initialAdmin,
        address _debtSubsidizer
    ) AccessControlBase(_initialAdmin) {
        if (_initialEpochDuration == 0) {
            revert EpochManager__InvalidEpochDuration();
        }
        epochDuration = _initialEpochDuration;
        if (_initialAutomatedSystem != address(0)) {
            _grantRole(Roles.OPERATOR_ROLE, _initialAutomatedSystem);
        }
        debtSubsidizer = IDebtSubsidizer(_debtSubsidizer);
        // currentEpochId is 0 initially, startEpoch will create epoch 1.
    }

    /**
     * @notice Allocates yield from a specific vault to the current active epoch.
     * @dev This function is expected to be called by a CollectionsVault contract
     * when it allocates its yield for the epoch.
     * @param vault The address of the CollectionsVault.
     * @param amount The amount of yield being allocated.
     */
    function allocateVaultYield(address vault, uint256 amount) external nonReentrant onlyRoleWhenNotPaused(OPERATOR_ROLE) {
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
     * @notice Updates the address of the automated system.
     * @param newAutomatedSystem The new address for the automated system.
     */
    function setAutomatedSystem(address newAutomatedSystem) external onlyRole(Roles.ADMIN_ROLE) {
        if (newAutomatedSystem == address(0)) {
            revert("EpochManager: Automated system address cannot be zero.");
        }
        // Revoke old automation system role if any
        uint256 memberCount = getRoleMemberCount(Roles.OPERATOR_ROLE);
        for (uint256 i = 0; i < memberCount; i++) {
            address oldAutomation = getRoleMember(Roles.OPERATOR_ROLE, 0);
            _revokeRole(Roles.OPERATOR_ROLE, oldAutomation);
        }
        // Grant role to new automation system
        if (newAutomatedSystem != address(0)) {
            _grantRole(Roles.OPERATOR_ROLE, newAutomatedSystem);
        }
        emit AutomatedSystemUpdated(newAutomatedSystem);
    }

    /**
     * @notice Updates the address of the DebtSubsidizer contract.
     * @param newDebtSubsidizer The new address for the DebtSubsidizer contract.
     */
    function setDebtSubsidizer(address newDebtSubsidizer) external onlyRole(Roles.ADMIN_ROLE) {
        debtSubsidizer = IDebtSubsidizer(newDebtSubsidizer);
        emit DebtSubsidizerUpdated(newDebtSubsidizer);
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
    function markEpochFailed(uint256 epochId, string calldata reason) external nonReentrant onlyRoleWhenNotPaused(Roles.OPERATOR_ROLE) {
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

    /**
     * @notice Starts a new epoch with simplified interface.
     * @dev Streamlined version that just starts the epoch and returns the ID.
     * @return epochId The ID of the newly started epoch.
     */
    function startEpoch() external nonReentrant onlyRoleWhenNotPaused(Roles.OPERATOR_ROLE) returns (uint256) {
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

        emit EpochStarted(currentEpochId, startTime, endTime);
        return currentEpochId;
    }

    /**
     * @notice Ends an epoch with subsidies in a single atomic operation.
     * @dev Combines Merkle root update and epoch finalization for simplified workflow.
     * @param epochId The ID of the epoch to end.
     * @param vaultAddress The address of the vault for which to update the Merkle root.
     * @param merkleRoot The Merkle root for subsidy claims.
     * @param subsidiesDistributed The total amount of subsidies distributed.
     */
    function endEpochWithSubsidies(
        uint256 epochId,
        address vaultAddress,
        bytes32 merkleRoot,
        uint256 subsidiesDistributed
    ) external nonReentrant onlyRoleWhenNotPaused(Roles.OPERATOR_ROLE) {
        if (epochId == 0 || epochId > currentEpochId) {
            revert EpochManager__InvalidEpochId(epochId);
        }
        Epoch storage epoch = epochs[epochId];

        if (epoch.status != EpochStatus.Active) {
            revert EpochManager__InvalidEpochStatus(epochId, epoch.status, EpochStatus.Active);
        }

        // Update subsidies and complete epoch
        epoch.totalSubsidiesDistributed = subsidiesDistributed;
        epoch.status = EpochStatus.Completed;

        // Update Merkle root in DebtSubsidizer for subsidy claims
        if (address(debtSubsidizer) != address(0) && merkleRoot != bytes32(0)) {
            debtSubsidizer.updateMerkleRoot(vaultAddress, merkleRoot);
        }

        emit EpochFinalized(epochId, epoch.totalYieldAvailable, epoch.totalSubsidiesDistributed);
    }

    function grantVaultRole(address vault) external onlyRoleWhenNotPaused(Roles.ADMIN_ROLE) {
        _grantRole(OPERATOR_ROLE, vault);
        emit EpochManagerRoleGranted(OPERATOR_ROLE, vault, msg.sender, block.timestamp);
    }

    function revokeVaultRole(address vault) external onlyRoleWhenNotPaused(Roles.ADMIN_ROLE) {
        _revokeRole(OPERATOR_ROLE, vault);
        emit EpochManagerRoleRevoked(OPERATOR_ROLE, vault, msg.sender, block.timestamp);
    }
}
