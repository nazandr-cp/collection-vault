// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Roles} from "./Roles.sol";

/**
 * @title AccessControlModifiers
 * @dev Library providing standardized access control modifiers and utility functions
 * @dev Reduces code duplication and gas costs across the Collection Vault system
 */
library AccessControlModifiers {
    // Custom errors for better gas efficiency
    error AccessControlModifiers__UnauthorizedRole(bytes32 role, address account);
    error AccessControlModifiers__UnauthorizedVaultAccess(address vault, address caller);
    error AccessControlModifiers__UnauthorizedCollectionAccess(address collection, address caller);
    error AccessControlModifiers__ContractPaused();
    error AccessControlModifiers__InvalidAddress();
    error AccessControlModifiers__InsufficientPermissions(address caller);

    /**
     * @dev Checks if account has any of the specified roles
     * @param accessControl The AccessControl contract instance
     * @param roles Array of roles to check
     * @param account Address to check roles for
     * @return hasAnyRole True if account has at least one of the roles
     */
    function checkAnyRole(AccessControl accessControl, bytes32[] memory roles, address account)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < roles.length; i++) {
            if (accessControl.hasRole(roles[i], account)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Checks if account has all of the specified roles
     * @param accessControl The AccessControl contract instance
     * @param roles Array of roles to check
     * @param account Address to check roles for
     * @return hasAllRoles True if account has all the roles
     */
    function checkAllRoles(AccessControl accessControl, bytes32[] memory roles, address account)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < roles.length; i++) {
            if (!accessControl.hasRole(roles[i], account)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Checks if address is a valid vault (has VAULT_ROLE)
     * @param accessControl The AccessControl contract instance
     * @param vault Address to check
     * @return isValidVault True if address has VAULT_ROLE
     */
    function isValidVault(AccessControl accessControl, address vault) internal view returns (bool) {
        return accessControl.hasRole(Roles.OPERATOR_ROLE, vault);
    }

    /**
     * @dev Checks if address has admin privileges (any admin role)
     * @param accessControl The AccessControl contract instance
     * @param account Address to check
     * @return isAdmin True if account has admin privileges
     */
    function isAdmin(AccessControl accessControl, address account) internal view returns (bool) {
        return accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), account)
            || accessControl.hasRole(Roles.OWNER_ROLE, account) || accessControl.hasRole(Roles.ADMIN_ROLE, account);
    }

    /**
     * @dev Checks if address can perform emergency actions
     * @param accessControl The AccessControl contract instance
     * @param account Address to check
     * @return canEmergency True if account can perform emergency actions
     */
    function canPerformEmergencyActions(AccessControl accessControl, address account) internal view returns (bool) {
        return accessControl.hasRole(Roles.GUARDIAN_ROLE, account) || accessControl.hasRole(Roles.OWNER_ROLE, account)
            || accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), account);
    }

    /**
     * @dev Validates role assignment constraints
     * @param accessControl The AccessControl contract instance
     * @param role Role to validate
     * @param account Account to receive role
     */
    function validateRoleAssignment(AccessControlEnumerable accessControl, bytes32 role, address account)
        internal
        view
    {
        if (account == address(0)) {
            revert AccessControlModifiers__InvalidAddress();
        }

        // Prevent granting owner role without proper authorization
        if (role == Roles.OWNER_ROLE) {
            require(
                accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), msg.sender),
                "AccessControlModifiers: Only DEFAULT_ADMIN can grant OWNER_ROLE"
            );
        }

        // Prevent last admin removal
        if (role == Roles.ADMIN_ROLE || role == Roles.OWNER_ROLE || role == accessControl.DEFAULT_ADMIN_ROLE()) {
            require(accessControl.getRoleMemberCount(role) > 0, "AccessControlModifiers: Cannot remove last admin");
        }
    }

    /**
     * @dev Gas-efficient role checking for single role
     * @param accessControl The AccessControl contract instance
     * @param role Role to check
     * @param account Account to check
     */
    function requireRole(AccessControl accessControl, bytes32 role, address account) internal view {
        if (!accessControl.hasRole(role, account)) {
            revert AccessControlModifiers__UnauthorizedRole(role, account);
        }
    }

    /**
     * @dev Gas-efficient vault access checking
     * @param accessControl The AccessControl contract instance
     * @param caller Address attempting vault access
     */
    function requireVaultAccess(AccessControl accessControl, address caller) internal view {
        if (!accessControl.hasRole(Roles.OPERATOR_ROLE, caller)) {
            revert AccessControlModifiers__UnauthorizedVaultAccess(caller, caller);
        }
    }

    /**
     * @dev Combined role and pause state checking
     * @param accessControl The AccessControl contract instance
     * @param pausable The Pausable contract instance
     * @param role Role to check
     * @param account Account to check
     */
    function requireRoleWhenNotPaused(AccessControl accessControl, Pausable pausable, bytes32 role, address account)
        internal
        view
    {
        if (pausable.paused()) {
            revert AccessControlModifiers__ContractPaused();
        }
        requireRole(accessControl, role, account);
    }

    /**
     * @dev Emergency access checking - allows certain operations even when paused
     * @param accessControl The AccessControl contract instance
     * @param account Account attempting emergency access
     */
    function requireEmergencyAccess(AccessControl accessControl, address account) internal view {
        if (!canPerformEmergencyActions(accessControl, account)) {
            revert AccessControlModifiers__InsufficientPermissions(account);
        }
    }
}

/**
 * @title AccessControlModifiersContract
 * @dev Contract version of the modifiers for inheritance-based usage
 */
abstract contract AccessControlModifiersContract is AccessControlEnumerable, Pausable {
    using AccessControlModifiers for AccessControl;

    /**
     * @dev Modifier requiring specific role
     */
    modifier onlyRoleOptimized(bytes32 role) {
        AccessControlModifiers.requireRole(this, role, msg.sender);
        _;
    }

    /**
     * @dev Modifier requiring operator role (formerly vault role)
     */
    modifier onlyOperatorOptimized() {
        AccessControlModifiers.requireVaultAccess(this, msg.sender);
        _;
    }

    /**
     * @dev Modifier requiring role when not paused
     */
    modifier onlyRoleWhenNotPausedOptimized(bytes32 role) {
        AccessControlModifiers.requireRoleWhenNotPaused(this, this, role, msg.sender);
        _;
    }

    /**
     * @dev Modifier for emergency access
     */
    modifier onlyEmergencyAccess() {
        AccessControlModifiers.requireEmergencyAccess(this, msg.sender);
        _;
    }

    /**
     * @dev Modifier requiring any of multiple roles
     */
    modifier onlyAnyRole(bytes32[] memory roles) {
        require(
            AccessControlModifiers.checkAnyRole(this, roles, msg.sender),
            "AccessControlModifiers: caller lacks required role"
        );
        _;
    }

    /**
     * @dev Modifier requiring all of multiple roles
     */
    modifier onlyAllRoles(bytes32[] memory roles) {
        require(
            AccessControlModifiers.checkAllRoles(this, roles, msg.sender),
            "AccessControlModifiers: caller lacks all required roles"
        );
        _;
    }
}
