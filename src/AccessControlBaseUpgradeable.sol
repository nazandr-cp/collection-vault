// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Roles} from "./Roles.sol";

/**
 * @title AccessControlBaseUpgradeable
 * @dev Upgradeable base contract providing standardized access control, pausability, and reentrancy protection
 * @dev Establishes role hierarchy and common security patterns for the Collection Vault system
 */
abstract contract AccessControlBaseUpgradeable is 
    Initializable, 
    AccessControlEnumerableUpgradeable, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable 
{
    
    // Events for role management
    event RoleGrantedWithDetails(bytes32 indexed role, address indexed account, address indexed sender, uint256 timestamp);
    event RoleRevokedWithDetails(bytes32 indexed role, address indexed account, address indexed sender, uint256 timestamp);
    event EmergencyActionTaken(address indexed actor, string action, uint256 timestamp);
    
    // Errors
    error AccessControlBase__InvalidAddress();
    error AccessControlBase__CannotRemoveLastAdmin();
    error AccessControlBase__UnauthorizedEmergencyAction();
    
    function __AccessControlBase_init(address initialAdmin) internal onlyInitializing {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControlBase_init_unchained(initialAdmin);
    }
    
    function __AccessControlBase_init_unchained(address initialAdmin) internal onlyInitializing {
        if (initialAdmin == address(0)) revert AccessControlBase__InvalidAddress();
        
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
     * @dev Enhanced role granting with event emission
     */
    function grantRoleWithDetails(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (account == address(0)) revert AccessControlBase__InvalidAddress();
        _grantRole(role, account);
        emit RoleGrantedWithDetails(role, account, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Enhanced role revoking with safety checks
     */
    function revokeRoleWithDetails(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (account == address(0)) revert AccessControlBase__InvalidAddress();
        
        // Prevent removing the last admin
        if ((role == Roles.ADMIN_ROLE || role == Roles.OWNER_ROLE || role == DEFAULT_ADMIN_ROLE) && 
            getRoleMemberCount(role) <= 1) {
            revert AccessControlBase__CannotRemoveLastAdmin();
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
     * @dev Check if caller has any of the specified roles
     */
    modifier onlyRoles(bytes32[] memory roles) {
        bool roleFound = false;
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(roles[i], msg.sender)) {
                roleFound = true;
                break;
            }
        }
        require(roleFound, "AccessControlBase: missing required role");
        _;
    }
    
    /**
     * @dev Modifier that combines role check with pause check
     */
    modifier onlyRoleWhenNotPaused(bytes32 role) {
        _checkRole(role);
        _requireNotPaused();
        _;
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
     * @dev Check if an address has admin privileges (any admin role)
     */
    function isAdmin(address account) external view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account) || 
               hasRole(Roles.OWNER_ROLE, account) || 
               hasRole(Roles.ADMIN_ROLE, account);
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}