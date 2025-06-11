// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {SimpleMockCToken} from "../src/mocks/SimpleMockCToken.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

contract EpochManagerIntegrationTest is Test {
    MockERC20 internal asset;
    MockERC721 internal nft;
    SimpleMockCToken internal cToken;
    LendingManager internal lendingManager;
    CollectionsVault internal vault;
    EpochManager internal epochManager;

    address internal OWNER = address(0x1);
    address internal ADMIN = address(0x2);
    address internal AUTOMATION = address(0x3);

    uint256 internal constant INITIAL_EXCHANGE_RATE = 2e28;

    function setUp() public {
        asset = new MockERC20("Mock Token", "MOCK", 18, 0);
        nft = new MockERC721("MockNFT", "MNFT");

        cToken = new SimpleMockCToken(
            address(asset),
            ComptrollerInterface(payable(address(this))),
            InterestRateModel(payable(address(this))),
            INITIAL_EXCHANGE_RATE,
            "Mock cToken",
            "mcTOKEN",
            18,
            payable(OWNER)
        );

        lendingManager = new LendingManager(OWNER, address(1), address(asset), address(cToken));
        vault = new CollectionsVault(asset, "Vault", "vMOCK", ADMIN, address(lendingManager));

        vm.prank(OWNER);
        lendingManager.revokeVaultRole(address(1));
        vm.prank(OWNER);
        lendingManager.grantVaultRole(address(vault));

        epochManager = new EpochManager(1 days, AUTOMATION, OWNER);

        vm.prank(ADMIN);
        vault.setEpochManager(address(epochManager));

        asset.mint(address(this), 1000 ether);
        asset.approve(address(vault), 1000 ether);
        vault.depositForCollection(1000 ether, address(this), address(nft));
    }

    function _generateYield(uint256 amount) internal {
        asset.mint(address(cToken), amount);
    }

    function testEpochLifecycleAndAllocation() public {
        _generateYield(100 ether);

        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        uint256 id = epochManager.currentEpochId();
        assertEq(id, 1, "epoch should start with id 1");

        uint256 availableYield = vault.getCurrentEpochYield(true);
        assertGt(availableYield, 0, "yield should be available");

        // Simulate vault allocating yield directly in EpochManager
        vm.prank(address(vault));
        epochManager.allocateVaultYield(address(vault), 50 ether);

        uint256 allocated = epochManager.getVaultYieldForEpoch(1, address(vault));
        assertEq(allocated, 50 ether, "allocation recorded in epoch manager");

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(AUTOMATION);
        epochManager.beginEpochProcessing(1);
        (,,,,, EpochManager.EpochStatus statusProcessing) = epochManager.getEpochDetails(1);
        assertEq(uint256(statusProcessing), uint256(EpochManager.EpochStatus.Processing));

        vm.prank(AUTOMATION);
        epochManager.finalizeEpoch(1, 0);
        (,,,,, EpochManager.EpochStatus statusFinal) = epochManager.getEpochDetails(1);
        assertEq(uint256(statusFinal), uint256(EpochManager.EpochStatus.Completed));
    }

    function testCannotStartNewEpochWhileActive() public {
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();

        vm.prank(AUTOMATION);
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__InvalidEpochStatus.selector,
                1,
                EpochManager.EpochStatus.Active,
                EpochManager.EpochStatus.Completed
            )
        );
        epochManager.startNewEpoch();
    }

    function testAllocateVaultYieldFailsWithoutEpoch() public {
        vm.prank(ADMIN);
        vm.expectRevert("CollectionsVault: Allocation amount exceeds available yield");
        vault.allocateEpochYield(1 ether);
    }

    function testAllocateVaultYieldExceedsAvailable() public {
        _generateYield(10 ether);
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();

        vm.prank(ADMIN);
        vm.expectRevert("CollectionsVault: Allocation amount exceeds available yield");
        vault.allocateEpochYield(20 ether);
    }

    function testBeginProcessingTooEarly() public {
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();

        vm.prank(AUTOMATION);
        uint256 endTime = block.timestamp + 1 days;
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__EpochNotEnded.selector,
                1,
                endTime
            )
        );
        epochManager.beginEpochProcessing(1);
    }

    function testFinalizeEpochWrongStatus() public {
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(AUTOMATION);
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__InvalidEpochStatus.selector,
                1,
                EpochManager.EpochStatus.Active,
                EpochManager.EpochStatus.Processing
            )
        );
        epochManager.finalizeEpoch(1, 0);
    }
}
