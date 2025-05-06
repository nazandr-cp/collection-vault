// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
// MockERC721 is available from base
// MockCToken is available from base
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";

contract RewardsController_Gas_View_Test is RewardsController_Test_Base {
    uint256 constant NUM_COLLECTIONS_1 = 1;
    // Max 2 collections are set up in RewardsController_Test_Base
    uint256 constant NUM_COLLECTIONS_2 = 2;

    function setUp() public virtual override {
        RewardsController_Test_Base.setUp();
        // Yield generation for preview functions might be needed if they calculate actual rewards
        // _generateYieldInLendingManager(100 ether); // Already called in claiming tests, ensure it's appropriate here
    }

    // --- View Functions ---\n
    function test_Gas_PreviewRewards_Single_Collection() public {
        // mockERC721 is already whitelisted in base setUp
        address collectionAddress = address(mockERC721);

        // Give user a balance
        mockERC721.mintSpecific(USER_A, 1); // Use mintSpecific // Mint NFT
        _processSingleUserUpdate(USER_A, collectionAddress, block.number, 1, 1 ether);

        // Simulate time passing
        vm.warp(block.timestamp + 1 days);
        _generateYieldInLendingManager(10 ether);

        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collectionAddress;
        IRewardsController.BalanceUpdateData[] memory simulatedUpdates = new IRewardsController.BalanceUpdateData[](0);

        // Execute view function
        rewardsController.previewRewards(USER_A, collectionsToPreview, simulatedUpdates);
    }

    function test_Gas_PreviewRewards_Multiple_Collections() public {
        // mockERC721 and mockERC721_2 are whitelisted in base
        address collection1Address = address(mockERC721);
        address collection2Address = address(mockERC721_2);

        // Give user balances
        mockERC721.mintSpecific(USER_A, 1); // Use mintSpecific
        _processSingleUserUpdate(USER_A, collection1Address, block.number, 1, 1 ether);
        mockERC721_2.mintSpecific(USER_A, 2); // Use mintSpecific // Different token ID for clarity
        _processSingleUserUpdate(USER_A, collection2Address, block.number, 1, 1 ether);

        // Simulate time passing
        vm.warp(block.timestamp + 1 days);
        _generateYieldInLendingManager(20 ether);

        address[] memory collectionsToPreview = new address[](2);
        collectionsToPreview[0] = collection1Address;
        collectionsToPreview[1] = collection2Address;
        IRewardsController.BalanceUpdateData[] memory simulatedUpdates = new IRewardsController.BalanceUpdateData[](0);

        // Execute view function
        rewardsController.previewRewards(USER_A, collectionsToPreview, simulatedUpdates);
    }

    function test_Gas_PreviewRewards_WithSimulation() public {
        // mockERC721 is whitelisted
        address collectionAddress = address(mockERC721);

        // Give user an initial balance
        mockERC721.mintSpecific(USER_A, 1); // Use mintSpecific
        _processSingleUserUpdate(USER_A, collectionAddress, block.number, 1, 1 ether);

        // Simulate time passing
        vm.warp(block.timestamp + 1 days);
        _generateYieldInLendingManager(10 ether);

        // Prepare simulated updates (e.g., user's NFT balance changes)
        IRewardsController.BalanceUpdateData[] memory simulatedUpdates = new IRewardsController.BalanceUpdateData[](1);
        simulatedUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: collectionAddress,
            blockNumber: block.number + 1, // Future block for simulation
            nftDelta: 1, // e.g., acquired another NFT
            balanceDelta: 0 // No change in deposit/borrow balance for this specific update
        });

        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collectionAddress;

        // Execute view function with simulation
        rewardsController.previewRewards(USER_A, collectionsToPreview, simulatedUpdates);
    }

    function test_Gas_GetWhitelistedCollections_Max() public {
        // Collections are whitelisted in base. This test will get those.
        // No additional setup needed here as _whitelistAndSetupCollections was removed.
        // The base setup whitelists 2 collections: mockERC721 and mockERC721_2.
        rewardsController.getWhitelistedCollections();
    }

    // Removed local helper functions _whitelistAndSetupCollections and _updateUserBalance
    // Base setup handles whitelisting, and _processSingleUserUpdate from base handles balance changes.
}
