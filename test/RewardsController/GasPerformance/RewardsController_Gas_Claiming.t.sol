// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
// MockERC20 is not directly used here, rewardToken from base is used.
// MockERC721 and MockCToken are not directly instantiated here, but types might be needed if casting.
// We rely on mockERC721, mockERC721_2, and mockCToken from the base contract.
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {MockERC721} from "../../../src/mocks/MockERC721.sol"; // For casting

contract RewardsController_Gas_Claiming_Test is RewardsController_Test_Base {
    uint256 constant NUM_COLLECTIONS_1 = 1;
    uint256 constant NUM_COLLECTIONS_2 = 2; // Adjusted from 5 and 20 as we have 2 mocks in base

    function setUp() public virtual override {
        RewardsController_Test_Base.setUp();
        // Removed: vm.prank(admin); rewardToken.mint(address(rewardsController), 1_000_000 ether);
        // Yield should be generated via LendingManager.
        // For claiming tests to pass, ensure yield is present.
        // The base setup already funds the lending manager. We might need to simulate yield accrual.
        _generateYieldInLendingManager(100 ether); // Generate some initial yield
    }

    // --- Claiming ---

    function test_Gas_ClaimRewardsForCollection_Simple() public {
        // mockERC721 is already whitelisted in base setUp
        address collectionAddress = address(mockERC721);

        // Mint NFT and update balance for USER_A in that collection
        mockERC721.mintSpecific(USER_A, 1); // Use mintSpecific
        _processSingleUserUpdate(USER_A, collectionAddress, block.number, 1, 1 ether);

        // Simulate time passing to accrue rewards
        vm.warp(block.timestamp + 1 days);
        _generateYieldInLendingManager(10 ether); // Ensure some yield is available to claim

        // Execute and measure gas
        vm.prank(USER_A);
        rewardsController.claimRewardsForCollection(collectionAddress, new IRewardsController.BalanceUpdateData[](0));
    }

    function test_Gas_ClaimRewardsForAll_1_Collection() public {
        // mockERC721 is already whitelisted
        address collectionAddress = address(mockERC721);

        // Mint NFT and update balance for USER_A
        mockERC721.mintSpecific(USER_A, 1); // Use mintSpecific
        _processSingleUserUpdate(USER_A, collectionAddress, block.number, 1, 1 ether);

        // Simulate time passing
        vm.warp(block.timestamp + 1 days);
        _generateYieldInLendingManager(10 ether);

        // Execute and measure gas
        vm.prank(USER_A);
        rewardsController.claimRewardsForAll(new IRewardsController.BalanceUpdateData[](0));
    }

    function test_Gas_ClaimRewardsForAll_2_Collections() public {
        // mockERC721 and mockERC721_2 are whitelisted in base
        address collection1Address = address(mockERC721);
        address collection2Address = address(mockERC721_2);

        // Mint NFTs and update balances for USER_A in both collections
        mockERC721.mintSpecific(USER_A, 1); // Use mintSpecific // Token ID 1 for collection 1
        _processSingleUserUpdate(USER_A, collection1Address, block.number, 1, 1 ether);

        mockERC721_2.mintSpecific(USER_A, 1); // Use mintSpecific // Token ID 1 for collection 2
        _processSingleUserUpdate(USER_A, collection2Address, block.number, 1, 1 ether);

        // Simulate time passing
        vm.warp(block.timestamp + 1 days);
        _generateYieldInLendingManager(20 ether); // Yield for 2 collections

        // Execute and measure gas
        vm.prank(USER_A);
        rewardsController.claimRewardsForAll(new IRewardsController.BalanceUpdateData[](0));
    }

    // Removed _whitelistAndSetupCollections and _updateUserBalance helpers
    // as their functionality is replaced by base setup and _processSingleUserUpdate from base.
}
