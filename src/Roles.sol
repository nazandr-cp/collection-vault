// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Simplified role definitions used across the Collection Vault system
/// @dev Defines a clear 5-role hierarchy with intuitive naming and distinct purposes
library Roles {
    /// @notice Ultimate system control and governance
    /// @dev Can grant/revoke all other roles, perform critical system changes
    /// @dev Replaces: DEFAULT_ADMIN_ROLE, SUPER_ADMIN_ROLE
    bytes32 internal constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @notice Day-to-day administrative operations
    /// @dev Contract configuration, non-critical updates, standard admin functions
    /// @dev Replaces: Previous ADMIN_ROLE (with reduced scope)
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Cross-contract operational calls and automation
    /// @dev Automated system calls, cross-contract interactions, operational functions
    /// @dev Replaces: VAULT_ROLE, AUTOMATION_ROLE, DEBT_SUBSIDIZER_ROLE
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Collection-specific operations and management
    /// @dev Collection registration, operations, yield share management
    /// @dev Replaces: MANAGER_ROLE, COLLECTION_ADMIN_ROLE, COLLECTION_OPERATOR_ROLE
    bytes32 internal constant COLLECTION_MANAGER_ROLE = keccak256("COLLECTION_MANAGER_ROLE");

    /// @notice Emergency controls and security functions
    /// @dev Pause/unpause, emergency actions, security responses
    /// @dev Replaces: PAUSE_ROLE, EMERGENCY_ROLE
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // Legacy role constants for backward compatibility during migration
    // TODO: Remove these after migration is complete
    bytes32 internal constant VAULT_ROLE = OPERATOR_ROLE;
    bytes32 internal constant AUTOMATION_ROLE = OPERATOR_ROLE;
    bytes32 internal constant DEBT_SUBSIDIZER_ROLE = OPERATOR_ROLE;
    bytes32 internal constant MANAGER_ROLE = COLLECTION_MANAGER_ROLE;
    bytes32 internal constant COLLECTION_ADMIN_ROLE = COLLECTION_MANAGER_ROLE;
    bytes32 internal constant COLLECTION_OPERATOR_ROLE = COLLECTION_MANAGER_ROLE;
    bytes32 internal constant PAUSE_ROLE = GUARDIAN_ROLE;
    bytes32 internal constant EMERGENCY_ROLE = GUARDIAN_ROLE;
}
