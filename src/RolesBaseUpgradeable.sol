// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Roles} from "./Roles.sol";

/**
 * @title RolesBaseUpgradeable
 * @dev Upgradeable unified base contract providing standardized access control, pausability, and reentrancy protection
 * @dev Combines AccessControlBaseUpgradeable and AccessControlModifiers functionality with unified onlyRoleOrGuardian pattern
 */
abstract contract RolesBaseUpgradeable is
    Initializable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    // Events for role management
    event RoleGrantedWithDetails(
        bytes32 indexed role, address indexed account, address indexed sender, uint256 timestamp
    );
    event RoleRevokedWithDetails(
        bytes32 indexed role, address indexed account, address indexed sender, uint256 timestamp
    );
    event EmergencyActionTaken(address indexed actor, string action, uint256 timestamp);

    // Custom errors for better gas efficiency
    error RolesBase__InvalidAddress();
    error RolesBase__CannotRemoveLastAdmin();
    error RolesBase__UnauthorizedRole(bytes32 role, address account);
    error RolesBase__UnauthorizedVaultAccess(address vault, address caller);
    error RolesBase__UnauthorizedCollectionAccess(address collection, address caller);
    error RolesBase__ContractPaused();
    error RolesBase__InsufficientPermissions(address caller);
    error RolesBase__UnauthorizedEmergencyAction();

    function __RolesBase_init(address initialAdmin) internal onlyInitializing {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __RolesBase_init_unchained(initialAdmin);
    }

    function __RolesBase_init_unchained(address initialAdmin) internal onlyInitializing {
        if (initialAdmin == address(0)) revert RolesBase__InvalidAddress();

        // Set up simplified role hierarchy
        // OWNER_ROLE is managed by DEFAULT_ADMIN_ROLE
        _setRoleAdmin(Roles.OWNER_ROLE, DEFAULT_ADMIN_ROLE);

        // ADMIN_ROLE is managed by OWNER_ROLE
        _setRoleAdmin(Roles.ADMIN_ROLE, Roles.OWNER_ROLE);

        // Operational roles are managed by ADMIN_ROLE
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.ADMIN_ROLE);
        _setRoleAdmin(Roles.COLLECTION_MANAGER_ROLE, Roles.ADMIN_ROLE);

        // GUARDIAN_ROLE is managed by OWNER_ROLE for security
        _setRoleAdmin(Roles.GUARDIAN_ROLE, Roles.OWNER_ROLE);

        // Grant initial roles to establish proper hierarchy
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(Roles.OWNER_ROLE, initialAdmin);
        _grantRole(Roles.ADMIN_ROLE, initialAdmin);
        _grantRole(Roles.GUARDIAN_ROLE, initialAdmin);
    }

    /**
     * @dev Core unified modifier: checks for required role OR guardian role
     * @param role The primary role required for access
     */
    modifier onlyRoleOrGuardian(bytes32 role) {
        if (!hasRole(role, msg.sender) && !hasRole(Roles.GUARDIAN_ROLE, msg.sender)) {
            revert RolesBase__UnauthorizedRole(role, msg.sender);
        }
        _;
    }

    /**
     * @dev Traditional modifier with pause check: checks for required role when not paused
     * @param role The primary role required for access
     */
    modifier onlyRoleWhenNotPaused(bytes32 role) {
        if (paused()) {
            revert RolesBase__ContractPaused();
        }
        if (!hasRole(role, msg.sender)) {
            revert RolesBase__UnauthorizedRole(role, msg.sender);
        }
        _;
    }

    /**
     * @dev Unified modifier with pause check: checks for required role OR guardian role when not paused
     * @param role The primary role required for access
     */
    modifier onlyRoleOrGuardianWhenNotPaused(bytes32 role) {
        if (paused()) {
            revert RolesBase__ContractPaused();
        }
        if (!hasRole(role, msg.sender) && !hasRole(Roles.GUARDIAN_ROLE, msg.sender)) {
            revert RolesBase__UnauthorizedRole(role, msg.sender);
        }
        _;
    }

    /**
     * @dev Emergency access modifier - allows guardian and admin roles even when paused
     */
    modifier onlyEmergencyAccess() {
        if (!canPerformEmergencyActions(msg.sender)) {
            revert RolesBase__UnauthorizedEmergencyAction();
        }
        _;
    }

    /**
     * @dev Modifier requiring any of multiple roles OR guardian role
     */
    modifier onlyAnyRoleOrGuardian(bytes32[] memory roles) {
        if (!checkAnyRole(roles, msg.sender) && !hasRole(Roles.GUARDIAN_ROLE, msg.sender)) {
            revert RolesBase__InsufficientPermissions(msg.sender);
        }
        _;
    }

    /**
     * @dev Modifier requiring all of multiple roles OR guardian role
     */
    modifier onlyAllRolesOrGuardian(bytes32[] memory roles) {
        if (!checkAllRoles(roles, msg.sender) && !hasRole(Roles.GUARDIAN_ROLE, msg.sender)) {
            revert RolesBase__InsufficientPermissions(msg.sender);
        }
        _;
    }

    /**
     * @dev Enhanced role granting with event emission
     */
    function grantRoleWithDetails(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (account == address(0)) revert RolesBase__InvalidAddress();
        _grantRole(role, account);
        emit RoleGrantedWithDetails(role, account, msg.sender, block.timestamp);
    }

    /**
     * @dev Enhanced role revoking with safety checks
     */
    function revokeRoleWithDetails(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (account == address(0)) revert RolesBase__InvalidAddress();

        // Prevent removing the last admin
        if (
            (role == Roles.ADMIN_ROLE || role == Roles.OWNER_ROLE || role == DEFAULT_ADMIN_ROLE)
                && getRoleMemberCount(role) <= 1
        ) {
            revert RolesBase__CannotRemoveLastAdmin();
        }

        _revokeRole(role, account);
        emit RoleRevokedWithDetails(role, account, msg.sender, block.timestamp);
    }

    /**
     * @dev Pause contract - restricted to GUARDIAN_ROLE
     */
    function pause() external onlyRole(Roles.GUARDIAN_ROLE) {
        _pause();
        emit EmergencyActionTaken(msg.sender, "pause", block.timestamp);
    }

    /**
     * @dev Unpause contract - restricted to GUARDIAN_ROLE
     */
    function unpause() external onlyRole(Roles.GUARDIAN_ROLE) {
        _unpause();
        emit EmergencyActionTaken(msg.sender, "unpause", block.timestamp);
    }

    /**
     * @dev Emergency pause - can be called by GUARDIAN_ROLE even when paused
     */
    function emergencyPause() external onlyRole(Roles.GUARDIAN_ROLE) {
        if (!paused()) {
            _pause();
        }
        emit EmergencyActionTaken(msg.sender, "emergency_pause", block.timestamp);
    }

    /**
     * @dev Checks if account has any of the specified roles
     * @param roles Array of roles to check
     * @param account Address to check roles for
     * @return hasAnyRole True if account has at least one of the roles
     */
    function checkAnyRole(bytes32[] memory roles, address account) public view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(roles[i], account)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Checks if account has all of the specified roles
     * @param roles Array of roles to check
     * @param account Address to check roles for
     * @return hasAllRoles True if account has all the roles
     */
    function checkAllRoles(bytes32[] memory roles, address account) public view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(roles[i], account)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Check if an address has admin privileges (any admin role)
     */
    function isAdmin(address account) public view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account) || hasRole(Roles.OWNER_ROLE, account)
            || hasRole(Roles.ADMIN_ROLE, account);
    }

    /**
     * @dev Check if address can perform emergency actions
     */
    function canPerformEmergencyActions(address account) public view returns (bool) {
        return hasRole(Roles.GUARDIAN_ROLE, account) || hasRole(Roles.OWNER_ROLE, account)
            || hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    /**
     * @dev Get all role members for a specific role (limited to first 100 for gas efficiency)
     */
    function getRoleMembers(bytes32 role) public view override returns (address[] memory) {
        uint256 count = getRoleMemberCount(role);
        uint256 returnCount = count > 100 ? 100 : count;
        address[] memory members = new address[](returnCount);

        for (uint256 i = 0; i < returnCount; i++) {
            members[i] = getRoleMember(role, i);
        }
        return members;
    }

    /**
     * @dev Internal function to require role with gas-efficient checking
     */
    function _requireRole(bytes32 role, address account) internal view {
        if (!hasRole(role, account)) {
            revert RolesBase__UnauthorizedRole(role, account);
        }
    }

    /**
     * @dev Internal function to require role or guardian with gas-efficient checking
     */
    function _requireRoleOrGuardian(bytes32 role, address account) internal view {
        if (!hasRole(role, account) && !hasRole(Roles.GUARDIAN_ROLE, account)) {
            revert RolesBase__UnauthorizedRole(role, account);
        }
    }

    /**
     * @dev Validates role assignment constraints
     */
    function _validateRoleAssignment(bytes32 role, address account) internal view {
        if (account == address(0)) {
            revert RolesBase__InvalidAddress();
        }

        // Prevent granting owner role without proper authorization
        if (role == Roles.OWNER_ROLE) {
            require(
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
                "RolesBase: Only DEFAULT_ADMIN can grant OWNER_ROLE"
            );
        }

        // Prevent last admin removal
        if (role == Roles.ADMIN_ROLE || role == Roles.OWNER_ROLE || role == DEFAULT_ADMIN_ROLE) {
            require(getRoleMemberCount(role) > 0, "RolesBase: Cannot remove last admin");
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}