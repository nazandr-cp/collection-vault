// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {RewardsController} from "../../../src/RewardsController.sol";
import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol"; // Import ERC1967Utils

// --- V2 Mock Contract ---
// Simple V2 mock that adds a getVersion function
contract RewardsControllerV2Mock is RewardsController {
    function getVersion() public pure returns (string memory) {
        return "V2";
    }
}

// --- Upgrade Tests ---

contract RewardsControllerUpgradeTest is RewardsController_Test_Base {
    // Use the specific V2 mock for functionality change tests
    RewardsControllerV2Mock internal rewardsControllerV2Mock;

    // Override setUp to prevent redeployment in inherited tests if needed,
    // or keep it to ensure a fresh V1 state for each upgrade test.
    // For simplicity, we'll let each test run the full setUp.

    // Helper to deploy the standard V2 (same as V1 for state tests)
    function _deployAndUpgradeToV2() internal returns (RewardsController) {
        vm.startPrank(OWNER);
        RewardsController v2Impl = new RewardsController();
        vm.stopPrank();
        vm.label(address(v2Impl), "RewardsController (Impl V2 - State Test)");

        vm.startPrank(ADMIN);
        address proxyAddr = address(rewardsController);
        address implAddr = address(v2Impl);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(proxyAddr), implAddr, ""); // Call with empty data
        vm.stopPrank();
        return v2Impl; // Return the deployed V2 instance if needed
    }

    // Helper specifically for deploying and upgrading to the V2 Mock
    function _deployAndUpgradeToV2Mock() internal {
        vm.startPrank(OWNER);
        rewardsControllerV2Mock = new RewardsControllerV2Mock();
        vm.stopPrank();
        vm.label(address(rewardsControllerV2Mock), "RewardsController (Impl V2 Mock)");

        vm.startPrank(ADMIN);
        address proxyAddr = address(rewardsController);
        address implAddr = address(rewardsControllerV2Mock);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(proxyAddr), implAddr, ""); // Call with empty data
        vm.stopPrank();
    }

    // Test that upgrade reverts if called by non-admin
    function test_Revert_Upgrade_NonAdmin() public {
        // Deploy V2 Implementation
        vm.startPrank(OWNER);
        RewardsController v2Impl = new RewardsController();
        vm.stopPrank();

        // Attempt upgrade from non-admin (OWNER)
        vm.startPrank(OWNER);
        // ProxyAdmin reverts with custom error OwnableUnauthorizedAccount(address account)
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OWNER));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsController)), address(v2Impl), "");
        vm.stopPrank();
    }

    // Test that upgrade reverts if implementation is address(0)
    function test_Revert_Upgrade_ZeroImplementation() public {
        vm.startPrank(ADMIN);
        // Expect any revert when implementation is address(0)
        vm.expectRevert();
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsController)), address(0), "");
        vm.stopPrank();
    }

    // Test that upgrade reverts if implementation is not a contract (EOA)
    function test_Revert_Upgrade_NonContractImplementation() public {
        vm.startPrank(ADMIN);
        // Expect any revert when implementation is not a contract
        vm.expectRevert();
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(rewardsController)), USER_C, ""); // Use an EOA
        vm.stopPrank();
    }
}
