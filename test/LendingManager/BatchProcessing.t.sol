// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LendingManager} from "../../src/LendingManager.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockCToken} from "../../src/mocks/MockCToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendingManager_BatchProcessing_Fuzz_Test is Test {
    LendingManager internal lendingManager;
    MockERC20 internal asset;
    MockCToken internal cToken;

    address internal admin;
    address internal vaultAddress;
    address internal rewardsControllerAddress;
    address payable internal recipient;

    uint256 internal constant LENDING_MANAGER_MAX_BATCH_SIZE = 50;
    uint256 internal constant MAX_BATCH_SIZE_PLUS_5 = LENDING_MANAGER_MAX_BATCH_SIZE + 5;

    function setUp() public {
        admin = address(this);
        vaultAddress = vm.addr(0x101);
        rewardsControllerAddress = vm.addr(0x102);
        recipient = payable(vm.addr(0x103));

        asset = new MockERC20("Test Asset", "TST", 18, 0); // Added initialSupply argument
        cToken = new MockCToken(address(asset));

        lendingManager =
            new LendingManager(admin, vaultAddress, rewardsControllerAddress, address(asset), address(cToken));

        vm.deal(recipient, 1 ether);
    }

    function testFuzz_transferYieldBatch_SizeConstraint(uint8 numCollections) public {
        vm.assume(numCollections <= MAX_BATCH_SIZE_PLUS_5);

        address[] memory collections = new address[](numCollections);
        uint256[] memory amounts = new uint256[](numCollections); // Ensure lengths match for this test focus

        for (uint8 i = 0; i < numCollections; ++i) {
            collections[i] = address(uint160(uint256(keccak256(abi.encodePacked("collection", i)))));
            amounts[i] = (i + 1) * 1e18;
        }

        uint256 totalAmountToTransfer = 0; // Simplifies test to focus on size constraint

        vm.startPrank(rewardsControllerAddress);

        if (numCollections > LENDING_MANAGER_MAX_BATCH_SIZE) {
            vm.expectRevert(bytes("Batch size exceeds maximum"));
            lendingManager.transferYieldBatch(collections, amounts, totalAmountToTransfer, recipient);
        } else {
            // Should not revert due to batch size.
            // If totalAmountToTransfer is 0, it will return 0 early.
            lendingManager.transferYieldBatch(collections, amounts, totalAmountToTransfer, recipient);
        }
        vm.stopPrank();
    }

    function test_transferYieldBatch_revertsIfArrayLengthMismatch() public {
        uint8 numCollectionsValidSize = 10; // A batch size that is valid
        address[] memory collections = new address[](numCollectionsValidSize);
        uint256[] memory amounts = new uint256[](numCollectionsValidSize - 1); // Mismatched length

        for (uint8 i = 0; i < numCollectionsValidSize; ++i) {
            collections[i] = address(uint160(uint256(keccak256(abi.encodePacked("collection", i)))));
        }
        // `amounts` array is shorter, no need to populate its values for this length check.

        vm.startPrank(rewardsControllerAddress);
        vm.expectRevert(bytes("Array length mismatch"));
        lendingManager.transferYieldBatch(collections, amounts, 1, recipient); // totalAmount changed to 1
        vm.stopPrank();
    }
}
