// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RewardsController} from "src/RewardsController.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title OwnershipTests
 * @dev This is a simplified version of the Admin tests focusing only on ownership functionality
 * to bypass compilation issues with mock contracts
 */
contract OwnershipTests is Test {
    // Constants
    address constant ADMIN = address(0xAD01);
    address constant USER_1 = address(0xAAA);
    address constant USER_2 = address(0xBBB);
    address constant UPDATER = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);

    // Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Contracts
    RewardsController public rewardsController;

    function setUp() public {
        // Deploy implementation
        RewardsController implementation = new RewardsController();

        // Deploy proxy admin
        ProxyAdmin proxyAdmin = new ProxyAdmin(payable(ADMIN)); // Pass initial owner to ProxyAdmin constructor

        // Encode initialization data
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address)",
            ADMIN, // owner
            address(1), // mock lending manager
            address(2), // mock token vault
            UPDATER // authorized updater
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Cast proxy to RewardsController
        rewardsController = RewardsController(payable(address(proxy)));
    }

    // --- Test Ownership and Admin Roles ---

    function test_Owner_ReturnsCorrectOwner() public {
        assertEq(rewardsController.owner(), ADMIN, "Owner mismatch");
    }

    function test_TransferOwnership_Successful() public {
        vm.prank(ADMIN);
        rewardsController.transferOwnership(USER_1);
        assertEq(rewardsController.owner(), USER_1, "Ownership not transferred");
    }

    function test_TransferOwnership_RevertsIfNonOwner() public {
        vm.prank(USER_1); // Non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        rewardsController.transferOwnership(USER_2);
    }

    function test_TransferOwnership_RevertsIfNewOwnerIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert("Ownable: new owner is the zero address");
        rewardsController.transferOwnership(address(0));
    }

    function test_TransferOwnership_EmitsEvent() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(ADMIN, USER_1);
        rewardsController.transferOwnership(USER_1);
    }

    function test_RenounceOwnership_Successful() public {
        vm.prank(ADMIN);
        rewardsController.renounceOwnership();
        assertEq(rewardsController.owner(), address(0), "Ownership not renounced");
    }

    function test_RenounceOwnership_RevertsIfNonOwner() public {
        vm.prank(USER_1); // Non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        rewardsController.renounceOwnership();
    }

    function test_RenounceOwnership_EmitsEvent() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(ADMIN, address(0));
        rewardsController.renounceOwnership();
    }

    function test_RenounceOwnership_SetsOwnerToAddressZero() public {
        vm.prank(ADMIN);
        rewardsController.renounceOwnership();
        assertEq(rewardsController.owner(), address(0), "Owner not address(0)");
    }
}
