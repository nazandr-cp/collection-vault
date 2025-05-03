// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockLendingManager} from "../../src/mocks/MockLendingManager.sol";
import {RewardsController} from "../../src/RewardsController.sol"; // Needed for selector and error
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol"; // Needed for error
import {RewardsController_Test_Base} from "./RewardsController_Test_Base.sol"; // Import the base contract
import {ERC4626Vault} from "../../src/ERC4626Vault.sol"; // Needed for mock vault deployment

contract RewardsController_Init is RewardsController_Test_Base {
    // --- Initialization Tests ---

    function test_Initialize_CorrectState() public view {
        assertEq(rewardsController.owner(), OWNER);
        assertEq(address(rewardsController.lendingManager()), address(lendingManager));
        assertEq(address(rewardsController.vault()), address(tokenVault));
        assertEq(rewardsController.authorizedUpdater(), AUTHORIZED_UPDATER);
        assertEq(address(rewardsController.rewardToken()), DAI_ADDRESS);
        // cToken is held by LendingManager, check via the LM reference
        assertEq(address(rewardsController.lendingManager().cToken()), CDAI_ADDRESS);
        assertTrue(rewardsController.globalRewardIndex() > 0, "Initial global index should be > 0");
        assertEq(rewardsController.epochDuration(), 0, "Initial epoch duration should be 0"); // Assuming default is 0
    }

    function test_Revert_Initialize_ZeroAddresses() public {
        // Deploy a new implementation to test initialization reverts
        RewardsController newImpl = new RewardsController();
        bytes memory initData;

        // Zero Owner (handled by Ownable) - Cannot test directly with initializer modifier

        // Zero Lending Manager
        initData = abi.encodeWithSelector(
            RewardsController.initialize.selector, OWNER, address(0), address(tokenVault), AUTHORIZED_UPDATER
        );
        vm.expectRevert(IRewardsController.AddressZero.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);

        // Zero Vault
        initData = abi.encodeWithSelector(
            RewardsController.initialize.selector, OWNER, address(lendingManager), address(0), AUTHORIZED_UPDATER
        );
        vm.expectRevert(IRewardsController.AddressZero.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);

        // Zero Updater
        initData = abi.encodeWithSelector(
            RewardsController.initialize.selector, OWNER, address(lendingManager), address(tokenVault), address(0)
        );
        vm.expectRevert(IRewardsController.AddressZero.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);
    }

    function test_Revert_Initialize_VaultAssetMismatch() public {
        // Deploy a mock vault with a different asset
        MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 18);
        // Deploy a mock LM configured with the mock asset
        MockLendingManager mockLM = new MockLendingManager(address(mockAsset)); // Pass address
        // Deploy mock vault using the mock LM
        ERC4626Vault mockVault = new ERC4626Vault(mockAsset, "Mock Vault", "mV", OWNER, address(mockLM));

        RewardsController newImpl = new RewardsController();
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            OWNER,
            address(lendingManager), // Use the *real* LM (with DAI) for the RewardsController init
            address(mockVault), // Vault uses MOCK asset
            AUTHORIZED_UPDATER
        );
        // Now expect the revert during RewardsController initialization
        vm.expectRevert(RewardsController.VaultMismatch.selector); // Use implementation selector
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);
    }

    function test_Revert_Initialize_AlreadyInitialized() public {
        vm.startPrank(OWNER);
        // Use the correct selector for InvalidInitialization
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        rewardsController.initialize(OWNER, address(lendingManager), address(tokenVault), AUTHORIZED_UPDATER);
        vm.stopPrank();
    }
}
