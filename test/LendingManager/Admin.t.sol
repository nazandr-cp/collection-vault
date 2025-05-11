// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LendingManager} from "src/LendingManager.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockCToken} from "src/mocks/MockCToken.sol";

contract LendingManagerAdminTest is Test {
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    LendingManager internal lendingManager;
    MockERC20 internal underlyingAsset;
    MockCToken internal cToken;

    address internal admin1;
    address internal admin2;
    address internal vault;
    address internal rewardsController;

    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    function setUp() public {
        admin1 = makeAddr("admin1");
        admin2 = makeAddr("admin2");
        vault = makeAddr("vault");
        rewardsController = makeAddr("rewardsController");

        underlyingAsset = new MockERC20("Underlying Token", "UT", 18, 0); // Added initialSupply
        cToken = new MockCToken(address(underlyingAsset));

        lendingManager = new LendingManager(admin1, vault, rewardsController, address(underlyingAsset), address(cToken));
    }

    function test_RevokeLastAdmin_Reverts() public {
        // admin1 is the only admin initially
        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 1, "Initial admin count should be 1");
        assertTrue(lendingManager.hasRole(ADMIN_ROLE, admin1), "admin1 should have ADMIN_ROLE");

        vm.startPrank(admin1);
        vm.expectRevert("Cannot remove last admin");
        lendingManager.revokeAdminRole(admin1);
        vm.stopPrank();
    }

    function test_RevokeLastAdminAsDefaultAdmin_Reverts() public {
        // admin1 is the only admin initially
        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 1, "Initial admin count should be 1");
        assertTrue(lendingManager.hasRole(ADMIN_ROLE, admin1), "admin1 should have ADMIN_ROLE");
        assertTrue(lendingManager.hasRole(DEFAULT_ADMIN_ROLE, admin1), "admin1 should have DEFAULT_ADMIN_ROLE");

        vm.startPrank(admin1);
        vm.expectRevert("Cannot remove last admin");
        lendingManager.revokeAdminRoleAsDefaultAdmin(admin1);
        vm.stopPrank();
    }

    function test_RevokeAdmin_WhenMultipleAdmins_Succeeds() public {
        // Grant admin2 ADMIN_ROLE
        vm.prank(admin1);
        lendingManager.grantAdminRole(admin2);
        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 2, "Admin count should be 2 after granting role");
        assertTrue(lendingManager.hasRole(ADMIN_ROLE, admin2), "admin2 should have ADMIN_ROLE");

        // Revoke admin2's role by admin1
        vm.startPrank(admin1);
        vm.expectEmit(true, true, true, true, address(lendingManager));
        emit RoleRevoked(ADMIN_ROLE, admin2, admin1);
        lendingManager.revokeAdminRole(admin2);
        vm.stopPrank();

        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 1, "Admin count should be 1 after revoking role");
        assertFalse(lendingManager.hasRole(ADMIN_ROLE, admin2), "admin2 should not have ADMIN_ROLE");
        assertTrue(lendingManager.hasRole(ADMIN_ROLE, admin1), "admin1 should still have ADMIN_ROLE");
    }

    function test_RevokeAdminAsDefaultAdmin_WhenMultipleAdmins_Succeeds() public {
        // Grant admin2 ADMIN_ROLE by default admin (admin1)
        vm.prank(admin1); // admin1 is DEFAULT_ADMIN_ROLE holder
        lendingManager.grantAdminRoleAsDefaultAdmin(admin2);

        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 2, "Admin count should be 2 after granting role");
        assertTrue(lendingManager.hasRole(ADMIN_ROLE, admin2), "admin2 should have ADMIN_ROLE");

        // Revoke admin2's role by default admin (admin1)
        vm.startPrank(admin1);
        vm.expectEmit(true, true, true, true, address(lendingManager));
        emit RoleRevoked(ADMIN_ROLE, admin2, admin1);
        lendingManager.revokeAdminRoleAsDefaultAdmin(admin2);
        vm.stopPrank();

        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 1, "Admin count should be 1 after revoking role");
        assertFalse(lendingManager.hasRole(ADMIN_ROLE, admin2), "admin2 should not have ADMIN_ROLE");
        assertTrue(lendingManager.hasRole(ADMIN_ROLE, admin1), "admin1 should still have ADMIN_ROLE");
    }

    function test_RevokeAdmin_WhenMultipleAdmins_RevokeSelf_Succeeds() public {
        // Grant admin2 ADMIN_ROLE
        vm.prank(admin1);
        lendingManager.grantAdminRole(admin2);
        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 2, "Admin count should be 2 after granting role");

        // admin1 revokes its own ADMIN_ROLE
        vm.startPrank(admin1);
        vm.expectEmit(true, true, true, true, address(lendingManager));
        emit RoleRevoked(ADMIN_ROLE, admin1, admin1);
        lendingManager.revokeAdminRole(admin1);
        vm.stopPrank();

        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 1, "Admin count should be 1 after self-revocation");
        assertFalse(
            lendingManager.hasRole(ADMIN_ROLE, admin1), "admin1 should not have ADMIN_ROLE after self-revocation"
        );
        assertTrue(lendingManager.hasRole(ADMIN_ROLE, admin2), "admin2 should still have ADMIN_ROLE");
    }

    function test_RevokeAdminAsDefaultAdmin_WhenMultipleAdmins_RevokeSelfAsAdmin_Succeeds() public {
        // Grant admin2 ADMIN_ROLE by default admin (admin1)
        vm.prank(admin1); // admin1 is DEFAULT_ADMIN_ROLE holder
        lendingManager.grantAdminRoleAsDefaultAdmin(admin2);
        assertEq(lendingManager.getRoleMemberCount(ADMIN_ROLE), 2, "Admin count should be 2 after granting role");

        // admin1 (who is also an ADMIN_ROLE holder) revokes its own ADMIN_ROLE using revokeAdminRoleAsDefaultAdmin
        // This scenario tests if a DEFAULT_ADMIN can remove an ADMIN_ROLE even if it's themselves.
        // Note: DEFAULT_ADMIN_ROLE is not affected, only ADMIN_ROLE.
        vm.startPrank(admin1);
        vm.expectEmit(true, true, true, true, address(lendingManager));
        emit RoleRevoked(ADMIN_ROLE, admin1, admin1);
        lendingManager.revokeAdminRoleAsDefaultAdmin(admin1);
        vm.stopPrank();

        assertEq(
            lendingManager.getRoleMemberCount(ADMIN_ROLE), 1, "Admin count should be 1 after self-revocation as admin"
        );
        assertFalse(
            lendingManager.hasRole(ADMIN_ROLE, admin1),
            "admin1 should not have ADMIN_ROLE after self-revocation as admin"
        );
        assertTrue(lendingManager.hasRole(ADMIN_ROLE, admin2), "admin2 should still have ADMIN_ROLE");
        assertTrue(lendingManager.hasRole(DEFAULT_ADMIN_ROLE, admin1), "admin1 should still have DEFAULT_ADMIN_ROLE");
    }
}
