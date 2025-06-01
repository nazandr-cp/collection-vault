// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRootGuardian} from "./interfaces/IRootGuardian.sol";
import {ISubsidyDistributor} from "./interfaces/ISubsidyDistributor.sol"; // Assuming this will be needed for integration

/**
 * @title RootGuardian
 * @author Your Name/Company
 * @notice Manages BLS epochs, Merkle root verification with TTL, and threshold signature verification.
 * This contract is responsible for maintaining the integrity of Merkle roots used for various
 * operations, such as reward distribution in the SubsidyDistributor.
 * @dev Implements IRootGuardian. Uses OpenZeppelin's Ownable for access control.
 *      BLS signature verification is initially stubbed and marked with TODO for full integration.
 */
contract RootGuardian is IRootGuardian, Ownable {
    /**
     * @notice The duration for which an emergency root remains valid (24 hours).
     */
    uint256 public constant EMERGENCY_ROOT_TTL = 24 hours;

    /**
     * @notice Represents an epoch with its BLS public key and registration timestamp.
     */
    struct Epoch {
        uint256 id;
        bytes blsPublicKey;
        uint256 registrationTimestamp;
    }

    /**
     * @notice Represents a Merkle root, its verification timestamp, and the epoch it was verified against.
     */
    struct RootInfo {
        bytes32 root;
        uint256 verifiedTimestamp;
        uint256 epochId;
        bool isEmergency;
        uint256 emergencyExpiryTimestamp; // Only relevant if isEmergency is true
    }

    // State Variables

    /**
     * @notice Mapping from epoch ID to Epoch data.
     */
    mapping(uint256 => Epoch) private epochs;

    /**
     * @notice The ID of the current active epoch.
     */
    uint256 public currentEpochId;

    /**
     * @notice The total number of registered epochs. Also serves as a counter for new epoch IDs.
     */
    uint256 public epochCounter;

    /**
     * @notice Mapping from Merkle root to its RootInfo.
     * This stores details about verified roots, including emergency roots and their TTLs.
     */
    mapping(bytes32 => RootInfo) private rootInfos;

    /**
     * @notice Address of the SubsidyDistributor contract for integrated functionality.
     * @dev This can be set by the owner to link with the SubsidyDistributor.
     */
    ISubsidyDistributor public subsidyDistributor;

    // Modifiers

    /**
     * @dev Ensures that the caller is the owner of the contract.
     *      This is used for administrative functions like registering epochs or setting emergency roots.
     */
    modifier onlyAdmin() {
        // In a real scenario, this might be a more sophisticated role-based access control
        // or a multisig. For now, Ownable.onlyOwner is used.
        require(owner() == msg.sender, "RootGuardian: Caller is not the owner");
        _;
    }

    /**
     * @notice Constructor to initialize the contract.
     * @param _initialOwner The address that will own the contract and have administrative privileges.
     * @param _initialEpochBlsPublicKey The BLS public key for the very first epoch (epoch 0 or 1).
     */
    constructor(address _initialOwner, bytes memory _initialEpochBlsPublicKey) Ownable(_initialOwner) {
        // Register the initial epoch
        epochCounter = 0; // Start with epoch 0 or 1, let's use 0 for simplicity in registration
        _registerNewEpoch(epochCounter, _initialEpochBlsPublicKey);
        currentEpochId = epochCounter;
        epochCounter++; // Increment for the next epoch
    }

    // External Functions - Epoch Management

    /**
     * @inheritdoc IRootGuardian
     * @dev Registers a new BLS epoch. Can only be called by the contract owner (admin).
     *      The epochId provided must be the next sequential epoch ID.
     */
    function registerEpoch(uint256 epochId, bytes calldata blsPublicKey) external override onlyAdmin {
        require(epochId == epochCounter, "RootGuardian: Epoch ID out of sequence");
        _registerNewEpoch(epochId, blsPublicKey);
        // Note: currentEpochId is not automatically updated here. Rotation is a separate step.
        epochCounter++;
    }

    /**
     * @inheritdoc IRootGuardian
     * @dev Rotates to the next available epoch. Can only be called by the contract owner (admin).
     *      The target epoch must already be registered.
     */
    function rotateEpoch() external override onlyAdmin {
        uint256 nextEpochId = currentEpochId + 1;
        require(epochs[nextEpochId].registrationTimestamp != 0, "RootGuardian: Next epoch not registered");

        uint256 oldEpochId = currentEpochId;
        currentEpochId = nextEpochId;

        emit EpochRotated(oldEpochId, currentEpochId, block.timestamp);
    }

    // External Functions - Root Verification

    /**
     * @inheritdoc IRootGuardian
     * @dev Verifies a Merkle root using the BLS signature of the current epoch.
     *      If successful, the root is stored as verified.
     *      TODO: Implement actual BLS signature verification logic.
     * @dev Verifies a Merkle root using the BLS signature of the current epoch.
     *      If successful, the root is stored as verified.
     *      TODO: Implement actual BLS signature verification logic.
     * @param signature The BLS signature.
     */
    function isValidRoot(bytes32, /*_root*/ bytes calldata signature) external pure override returns (bool) {
        // TODO: Implement actual BLS signature verification logic using epochs[currentEpochId].blsPublicKey and signature.
        // For now, this is a stub. In a real implementation, this would involve cryptographic operations.
        // bytes memory currentBlsPublicKey = epochs[currentEpochId].blsPublicKey;
        // bool signatureValid = _verifyBlsSignature(root, signature, currentBlsPublicKey);
        // require(signatureValid, "RootGuardian: Invalid BLS signature");

        // This is a placeholder. Assume signature is valid for now if it's not empty.
        bool signatureValid = signature.length > 0;
        if (!signatureValid) {
            revert InvalidSignature();
        }

        // If signature is deemed valid (stubbed), then the root is considered valid for this check.
        // Note: This function's name `isValidRoot` might be confusing. It checks if a *new* root can be validated
        // with a signature. `isRootValid` checks if an *already recorded* root is still valid (e.g. not expired).
        // For the purpose of this function as per interface, it implies verification.
        // If we were to store it, it would be:
        // if (signatureValid && rootInfos[root].verifiedTimestamp == 0) {
        //     rootInfos[root] = RootInfo({
        //         root: root,
        //         verifiedTimestamp: block.timestamp,
        //         epochId: currentEpochId,
        //         isEmergency: false,
        //         emergencyExpiryTimestamp: 0
        //     });
        //     emit RootVerified(root, currentEpochId, block.timestamp);
        // }
        return signatureValid; // Placeholder
    }

    /**
     * @inheritdoc IRootGuardian
     * @dev Sets an emergency Merkle root. This root is valid for EMERGENCY_ROOT_TTL.
     *      Can only be called by the contract owner (admin).
     */
    function setEmergencyRoot(bytes32 root) external override onlyAdmin {
        uint256 expiryTimestamp = block.timestamp + EMERGENCY_ROOT_TTL;
        rootInfos[root] = RootInfo({
            root: root,
            verifiedTimestamp: block.timestamp, // Timestamp of setting the emergency root
            epochId: 0, // Emergency roots are not tied to a specific BLS epoch
            isEmergency: true,
            emergencyExpiryTimestamp: expiryTimestamp
        });

        emit EmergencyRootSet(root, expiryTimestamp, block.timestamp);
    }

    /**
     * @inheritdoc IRootGuardian
     * @dev Checks if a Merkle root is currently valid.
     *      A root is valid if it was verified (either normally or as an emergency root)
     *      and, if it's an emergency root, its TTL has not expired.
     *      Regularly verified roots (non-emergency) do not expire via this TTL mechanism by default,
     *      but their validity is tied to the epoch they were verified with.
     *      This function primarily checks the TTL for emergency roots.
     */
    function isRootValid(bytes32 root) external view override returns (bool) {
        RootInfo storage info = rootInfos[root];

        if (info.verifiedTimestamp == 0) {
            // Root has not been verified or set as emergency
            return false;
        }

        if (info.isEmergency) {
            if (block.timestamp >= info.emergencyExpiryTimestamp) {
                // Emergency root has expired
                // Consider emitting an event or logging, though view functions can't emit.
                // For now, just return false. An error could be used if called internally by a state-changing function.
                return false; // Explicitly returning false, could revert with RootExpired(root, info.emergencyExpiryTimestamp);
            }
            return true; // Emergency root is still within its TTL
        }

        // For non-emergency roots, their validity is based on being recorded.
        // Further checks (e.g., if the epoch it was verified with is still considered valid)
        // could be added here if needed, but the spec focuses on emergency TTL.
        // For now, if it's recorded and not an expired emergency root, it's "valid".
        return true;
    }

    // External Functions - Getters

    /**
     * @inheritdoc IRootGuardian
     */
    function getCurrentEpochId() external view override returns (uint256) {
        return currentEpochId;
    }

    /**
     * @inheritdoc IRootGuardian
     */
    function getBlsPublicKey(uint256 epochId) external view override returns (bytes memory) {
        if (epochs[epochId].registrationTimestamp == 0) {
            revert EpochNotFound(epochId);
        }
        return epochs[epochId].blsPublicKey;
    }

    /**
     * @inheritdoc IRootGuardian
     */
    function getEmergencyRootExpiry(bytes32 root) external view override returns (uint256) {
        RootInfo storage info = rootInfos[root];
        if (info.isEmergency) {
            return info.emergencyExpiryTimestamp;
        }
        return 0; // Not an emergency root or not found
    }

    // Internal Functions

    /**
     * @dev Internal function to register a new epoch.
     * @param epochId The ID for the new epoch.
     * @param blsPublicKey The BLS public key for the new epoch.
     */
    function _registerNewEpoch(uint256 epochId, bytes memory blsPublicKey) internal {
        require(epochs[epochId].registrationTimestamp == 0, "RootGuardian: Epoch already exists");
        require(blsPublicKey.length > 0, "RootGuardian: BLS public key cannot be empty");

        epochs[epochId] = Epoch({id: epochId, blsPublicKey: blsPublicKey, registrationTimestamp: block.timestamp});

        emit EpochRegistered(epochId, blsPublicKey, block.timestamp);
    }

    /**
     * @dev Placeholder for actual BLS signature verification.
     *      In a real implementation, this would call a precompiled contract or a library.
     * @param _root The Merkle root.
     * @param _signature The BLS signature.
     * @param _publicKey The BLS public key of the current epoch.
     * @return True if the signature is valid, false otherwise.
     */
    function _verifyBlsSignature(bytes32 _root, bytes calldata _signature, bytes memory _publicKey)
        internal
        pure
        returns (bool)
    {
        // Silence compiler warnings for unused parameters in this stub
        bytes32 r = _root;
        bytes memory s = _signature;
        bytes memory pk = _publicKey;
        r = keccak256(abi.encodePacked(s, pk)); // Dummy operation

        // TODO: Integrate with a BLS signature verification library or precompile.
        // Example: return BLSLibrary.verify(pk, abi.encodePacked(_root), _signature);
        return true; // Stub: always returns true
    }

    // Administrative functions

    /**
     * @notice Sets the address of the SubsidyDistributor contract.
     * @dev Can only be called by the contract owner.
     * @param _subsidyDistributor The address of the SubsidyDistributor.
     */
    function setSubsidyDistributor(ISubsidyDistributor _subsidyDistributor) external onlyAdmin {
        require(address(_subsidyDistributor) != address(0), "RootGuardian: Invalid address");
        subsidyDistributor = _subsidyDistributor;
    }

    // Natspec Documentation for Structs (already included above definitions)
    // Natspec for Events and Errors are in IRootGuardian.sol
}
