// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {NFTDataUpdater} from "../src/NFTDataUpdater.sol";
import {MockRewardsController} from "../src/mocks/MockRewardsController.sol";
import {IRewardsController} from "../src/interfaces/IRewardsController.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";

contract NFTDataUpdaterTest is Test {
    // --- Constants & Config ---
    address constant USER_A = address(0xAAA);
    address constant NFT_COLLECTION_1 = address(0xC1);
    address constant NFT_COLLECTION_2 = address(0xC2);
    address constant OWNER = address(0x001);
    address constant AUTHORIZED_UPDATER = address(0xBAD); // Backend/Oracle address
    address constant UNAUTHORIZED_UPDATER = address(0xABC);

    // --- Contracts ---
    NFTDataUpdater nftUpdater;
    MockRewardsController mockController;

    // --- Setup ---
    function setUp() public {
        vm.startPrank(OWNER);
        // Deploy Mock Rewards Controller
        mockController = new MockRewardsController();

        // Deploy NFTDataUpdater
        nftUpdater = new NFTDataUpdater(OWNER, address(mockController));

        // Authorize an additional updater address
        nftUpdater.setUpdaterAuthorization(AUTHORIZED_UPDATER, true);
        vm.stopPrank();
    }

    // --- Authorization Tests ---

    function test_SetUpdaterAuthorization() public {
        assertTrue(nftUpdater.authorizedUpdaters(OWNER), "Owner should be authorized initially");
        assertTrue(nftUpdater.authorizedUpdaters(AUTHORIZED_UPDATER), "Set updater should be authorized");
        assertFalse(nftUpdater.authorizedUpdaters(UNAUTHORIZED_UPDATER), "Other address shouldn't be authorized");

        // De-authorize
        vm.startPrank(OWNER);
        nftUpdater.setUpdaterAuthorization(AUTHORIZED_UPDATER, false);
        vm.stopPrank();
        assertFalse(nftUpdater.authorizedUpdaters(AUTHORIZED_UPDATER), "Updater should be de-authorized");
    }

    function test_RevertIf_SetUpdaterAuthorization_NotOwner() public {
        vm.startPrank(UNAUTHORIZED_UPDATER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED_UPDATER));
        nftUpdater.setUpdaterAuthorization(address(0x123), true);
        vm.stopPrank();
    }

    function test_RevertIf_UpdateBalance_Unauthorized() public {
        vm.startPrank(UNAUTHORIZED_UPDATER);
        vm.expectRevert(NFTDataUpdater.CallerNotAuthorized.selector);
        nftUpdater.updateNFTBalance(USER_A, NFT_COLLECTION_1, 10);
        vm.stopPrank();
    }

    function test_RevertIf_UpdateBalances_Unauthorized() public {
        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;
        uint256[] memory balances = new uint256[](1);
        balances[0] = 5;

        vm.startPrank(UNAUTHORIZED_UPDATER);
        vm.expectRevert(NFTDataUpdater.CallerNotAuthorized.selector);
        nftUpdater.updateNFTBalances(USER_A, collections, balances);
        vm.stopPrank();
    }

    // --- Forwarding Tests ---

    function test_UpdateBalance_Success() public {
        uint256 balance = 5;

        // Call from authorized updater
        vm.startPrank(AUTHORIZED_UPDATER);
        nftUpdater.updateNFTBalance(USER_A, NFT_COLLECTION_1, balance);
        vm.stopPrank();

        // Verify mock controller was called correctly
        assertEq(mockController.updateBalanceCalledCount(), 1, "Controller updateBalance call count");
        MockRewardsController.UpdateBalanceCall memory callArgs = mockController.getLastUpdateBalanceArgs();
        assertEq(callArgs.user, USER_A, "User mismatch");
        assertEq(callArgs.nftCollection, NFT_COLLECTION_1, "Collection mismatch");
        assertEq(callArgs.currentBalance, balance, "Balance mismatch");
    }

    function test_UpdateBalances_Success() public {
        address[] memory collections = new address[](2);
        collections[0] = NFT_COLLECTION_1;
        collections[1] = NFT_COLLECTION_2;
        uint256[] memory balances = new uint256[](2);
        balances[0] = 3;
        balances[1] = 7;

        // Call from owner (also authorized)
        vm.startPrank(OWNER);
        nftUpdater.updateNFTBalances(USER_A, collections, balances);
        vm.stopPrank();

        // Verify mock controller was called correctly
        assertEq(mockController.updateBalancesCalledCount(), 1, "Controller updateBalances call count");
        (address user, address[] memory colls, uint256[] memory bals) = mockController.getLastUpdateBalancesArgs();
        assertEq(user, USER_A, "Batch User mismatch");
        assertEq(colls.length, 2, "Batch Collections length mismatch");
        assertEq(bals.length, 2, "Batch Balances length mismatch");
        assertEq(colls[0], NFT_COLLECTION_1, "Batch Collection 1 mismatch");
        assertEq(bals[0], 3, "Batch Balance 1 mismatch");
        assertEq(colls[1], NFT_COLLECTION_2, "Batch Collection 2 mismatch");
        assertEq(bals[1], 7, "Batch Balance 2 mismatch");
    }

    // --- Admin Function Tests ---

    function test_SetRewardsController() public {
        MockRewardsController newMockController = new MockRewardsController();
        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true, address(nftUpdater));
        emit NFTDataUpdater.RewardsControllerSet(address(newMockController));
        nftUpdater.setRewardsController(address(newMockController));
        vm.stopPrank();

        assertEq(address(nftUpdater.rewardsController()), address(newMockController), "Controller address mismatch");
    }

    function test_RevertIf_SetRewardsController_NotOwner() public {
        MockRewardsController newMockController = new MockRewardsController();
        vm.startPrank(AUTHORIZED_UPDATER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, AUTHORIZED_UPDATER));
        nftUpdater.setRewardsController(address(newMockController));
        vm.stopPrank();
    }

    function test_RevertIf_SetRewardsController_ZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(NFTDataUpdater.AddressZero.selector);
        nftUpdater.setRewardsController(address(0));
        vm.stopPrank();
    }
}
