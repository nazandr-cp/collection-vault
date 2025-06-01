// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IRootGuardian
 * @notice Interface for the RootGuardian contract, which manages BLS epochs,
 * Merkle root verification with TTL, and threshold signature verification.
 */
interface IRootGuardian {
    /**
     * @notice Emitted when a new BLS epoch is registered.
     * @param epochId The ID of the new epoch.
     * @param blsPublicKey The BLS public key for the new epoch.
     * @param timestamp The timestamp when the epoch was registered.
     */
    event EpochRegistered(uint256 indexed epochId, bytes blsPublicKey, uint256 timestamp);

    /**
     * @notice Emitted when a Merkle root is successfully verified.
     * @param root The verified Merkle root.
     * @param epochId The epoch ID used for verification.
     * @param timestamp The timestamp of verification.
     */
    event RootVerified(bytes32 indexed root, uint256 indexed epochId, uint256 timestamp);

    /**
     * @notice Emitted when an emergency Merkle root is set.
     * @param root The emergency Merkle root.
     * @param emergencyTTL The timestamp until which the emergency root is valid.
     * @param timestamp The timestamp when the emergency root was set.
     */
    event EmergencyRootSet(bytes32 indexed root, uint256 emergencyTTL, uint256 timestamp);

    /**
     * @notice Emitted when an epoch is rotated.
     * @param oldEpochId The ID of the old epoch.
     * @param newEpochId The ID of the new epoch.
     * @param timestamp The timestamp of the epoch rotation.
     */
    event EpochRotated(uint256 indexed oldEpochId, uint256 indexed newEpochId, uint256 timestamp);

    /**
     * @notice Error for invalid BLS signatures.
     */
    error InvalidSignature();

    /**
     * @notice Error for expired Merkle roots.
     * @param root The expired root.
     * @param expiryTimestamp The timestamp when the root expired.
     */
    error RootExpired(bytes32 root, uint256 expiryTimestamp);

    /**
     * @notice Error for unauthorized access attempts.
     * @param caller The address that attempted the unauthorized action.
     */
    error Unauthorized(address caller);

    /**
     * @notice Error for when an epoch is not found.
     * @param epochId The ID of the epoch that was not found.
     */
    error EpochNotFound(uint256 epochId);

    /**
     * @notice Error for when an epoch already exists.
     * @param epochId The ID of the epoch that already exists.
     */
    error EpochAlreadyExists(uint256 epochId);

    /**
     * @notice Registers a new BLS epoch with its public key.
     * @dev Requires appropriate access control.
     * @param epochId The unique identifier for the epoch.
     * @param blsPublicKey The BLS public key for the epoch.
     */
    function registerEpoch(uint256 epochId, bytes calldata blsPublicKey) external;

    /**
     * @notice Verifies a Merkle root against a BLS signature for the current epoch.
     * @dev This function will integrate with BLS signature verification logic.
     * @param root The Merkle root to verify.
     * @param signature The BLS signature corresponding to the root.
     * @return True if the root is valid and signature is correct, false otherwise.
     */
    function isValidRoot(bytes32 root, bytes calldata signature) external view returns (bool);

    /**
     * @notice Sets an emergency Merkle root with a predefined Time-To-Live (TTL).
     * @dev This function is for emergency situations and has a strict TTL.
     *      Requires appropriate access control.
     * @param root The emergency Merkle root to set.
     */
    function setEmergencyRoot(bytes32 root) external;

    /**
     * @notice Checks if a given Merkle root is currently valid (i.e., not expired).
     * @dev Considers both regularly verified roots and emergency roots within their TTL.
     * @param root The Merkle root to check.
     * @return True if the root is valid, false otherwise.
     */
    function isRootValid(bytes32 root) external view returns (bool);

    /**
     * @notice Triggers the rotation of the current BLS epoch.
     * @dev This is part of the key security and DKG support framework.
     *      Requires appropriate access control.
     *      The new epoch details (ID and public key) should be provided through a secure mechanism
     *      or generated via DKG process before calling this. For this interface, we assume
     *      the new epoch details are managed internally or set via another function.
     */
    function rotateEpoch() external;

    /**
     * @notice Gets the current active epoch ID.
     * @return The ID of the current epoch.
     */
    function getCurrentEpochId() external view returns (uint256);

    /**
     * @notice Gets the BLS public key for a given epoch.
     * @param epochId The ID of the epoch.
     * @return The BLS public key.
     */
    function getBlsPublicKey(uint256 epochId) external view returns (bytes memory);

    /**
     * @notice Gets the expiry timestamp for an emergency root.
     * @param root The emergency root.
     * @return The UNIX timestamp when the emergency root expires. Returns 0 if not an emergency root or not found.
     */
    function getEmergencyRootExpiry(bytes32 root) external view returns (uint256);
}
