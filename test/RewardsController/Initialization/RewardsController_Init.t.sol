// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockLendingManager} from "../../../src/mocks/MockLendingManager.sol";
import {RewardsController} from "../../../src/RewardsController.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {ERC4626Vault} from "../../../src/ERC4626Vault.sol";

contract RewardsController_Init is RewardsController_Test_Base {
    function test_Initialize_CorrectState() public view {
        assertEq(rewardsController.owner(), OWNER);
        assertEq(address(rewardsController.lendingManager()), address(lendingManager));
        assertEq(address(rewardsController.vault()), address(tokenVault));
        assertEq(rewardsController.authorizedUpdater(), AUTHORIZED_UPDATER);
        assertEq(address(rewardsController.rewardToken()), DAI_ADDRESS);
        assertEq(address(rewardsController.lendingManager().cToken()), CDAI_ADDRESS);
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
    }

    function test_Revert_Initialize_VaultAssetMismatch() public {
        MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 18);
        MockLendingManager mockLM = new MockLendingManager(address(mockAsset));
        ERC4626Vault mockVault = new ERC4626Vault(mockAsset, "Mock Vault", "mV", OWNER, address(mockLM));

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
