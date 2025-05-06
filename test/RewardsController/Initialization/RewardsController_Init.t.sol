// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {LendingManager} from "../../../src/LendingManager.sol";
import {RewardsController} from "../../../src/RewardsController.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {ERC4626Vault} from "../../../src/ERC4626Vault.sol";
import {MockCToken} from "../../../src/mocks/MockCToken.sol"; // Add import

contract RewardsController_Init is RewardsController_Test_Base {
    function test_Initialize_CorrectState() public view {
        assertEq(rewardsController.owner(), OWNER);
        assertEq(address(rewardsController.lendingManager()), address(lendingManager));
        assertEq(address(rewardsController.vault()), address(tokenVault));
        assertEq(rewardsController.authorizedUpdater(), AUTHORIZED_UPDATER);
        assertEq(address(rewardsController.rewardToken()), DAI_ADDRESS);
        // Use the mock cToken address from the base setup
        assertEq(address(rewardsController.lendingManager().cToken()), address(mockCToken), "cToken address mismatch");
        assertTrue(rewardsController.globalRewardIndex() > 0, "Initial global index should be > 0");
        assertEq(rewardsController.epochDuration(), 0, "Initial epoch duration should be 0");
    }

    function test_Revert_Initialize_ZeroAddresses() public {
        RewardsController newImpl = new RewardsController();
        bytes memory initData;

        initData = abi.encodeWithSelector(
            RewardsController.initialize.selector, OWNER, address(0), address(tokenVault), AUTHORIZED_UPDATER
        );
        vm.expectRevert(IRewardsController.AddressZero.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);

        initData = abi.encodeWithSelector(
            RewardsController.initialize.selector, OWNER, address(lendingManager), address(0), AUTHORIZED_UPDATER
        );
        vm.expectRevert(IRewardsController.AddressZero.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);

        initData = abi.encodeWithSelector(
            RewardsController.initialize.selector, OWNER, address(lendingManager), address(tokenVault), address(0)
        );
        vm.expectRevert(IRewardsController.AddressZero.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);

        // Test for zero initialOwner
        initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            address(0),
            address(lendingManager),
            address(tokenVault),
            AUTHORIZED_UPDATER
        );
        vm.expectRevert(
            abi.encodeWithSelector(RewardsController.RewardsControllerInvalidInitialOwner.selector, address(0))
        );
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);
    }

    function test_Revert_Initialize_VaultAssetMismatch() public {
        MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 18);
        // Create a mock cToken for the mock asset
        MockCToken mockCT = new MockCToken(address(mockAsset));

        // Create a real LendingManager with the mock asset
        LendingManager mockLM = new LendingManager(
            OWNER, // initialAdmin
            address(1), // temporary vault address
            address(2), // temporary rewards controller address
            address(mockAsset), // asset address
            address(mockCT) // cToken address
        );

        // Create the vault using the lending manager
        ERC4626Vault mockVault = new ERC4626Vault(mockAsset, "Mock Vault", "mV", OWNER, address(mockLM));

        // Update the vault role in the lending manager
        vm.prank(OWNER);
        mockLM.revokeVaultRole(address(1));
        vm.prank(OWNER);
        mockLM.grantVaultRole(address(mockVault));

        RewardsController newImpl = new RewardsController();
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            OWNER,
            address(lendingManager),
            address(mockVault),
            AUTHORIZED_UPDATER
        );
        vm.expectRevert(RewardsController.VaultMismatch.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(proxyAdmin), initData);
    }

    function test_Revert_Initialize_AlreadyInitialized() public {
        vm.startPrank(OWNER);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        rewardsController.initialize(OWNER, address(lendingManager), address(tokenVault), AUTHORIZED_UPDATER);
        vm.stopPrank();
    }
}
