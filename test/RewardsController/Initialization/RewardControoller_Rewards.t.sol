// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {RewardsController} from "../../../src/RewardsController.sol";
import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";

contract RewardsController_Rewards is RewardsController_Test_Base {
    // --- Reward Calculation Tests ---

    function test_CalculateBoost() public view {
        // Zero NFTs
        assertEq(rewardsController.calculateBoost(0, BETA_1), 0, "Boost with 0 NFTs");

        // Normal boost
        uint256 expectedBoost = 5 * BETA_1; // 5 NFTs * 0.1 ether = 0.5 ether
        assertEq(rewardsController.calculateBoost(5, BETA_1), expectedBoost, "Boost calculation normal");

        // Max boost cap (PRECISION * 9 = 9e18)
        uint256 highNFTCount = 100; // 100 * 0.1 ether = 10 ether > 9 ether
        uint256 maxBoost = PRECISION * 9;
        assertEq(rewardsController.calculateBoost(highNFTCount, BETA_1), maxBoost, "Boost calculation capped");
    }

    // --- _calculateRewardsWithDelta (Tested via preview/claim) ---

    function test_PreviewRewards_ZeroNFTs() public {
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, 0, 1000 ether); // 0 NFTs, some balance

        vm.roll(block.number + 100); // Accrue time
        mockCToken.accrueInterest(); // Accrue interest

        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);

        assertEq(preview, 0, "Preview should be 0 with 0 NFTs");
    }

    function test_PreviewRewards_ZeroBalance() public {
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, 5, 0); // 5 NFTs, 0 balance

        vm.roll(block.number + 100); // Accrue time
        mockCToken.accrueInterest(); // Accrue interest

        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);

        assertEq(preview, 0, "Preview should be 0 with 0 balance");
    }

    function test_PreviewRewards_NoTimePassed() public {
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, 5, 1000 ether);

        // No time passes, no interest accrual

        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);

        assertEq(preview, 0, "Preview should be 0 with no time passed");
    }

    function test_PreviewRewards_BasicAccrual() public {
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        uint256 nftCount = 3;
        uint256 balance = 1000 ether;
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, int256(nftCount), int256(balance));
        (uint256 startIndex,,,,) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        vm.roll(block.number + 100); // Accrue time
        mockCToken.accrueInterest(); // Accrue interest
        uint256 endIndex = mockCToken.exchangeRateStored(); // Get index after accrual

        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);

        assertTrue(preview > 0, "Preview should be > 0 after accrual");

        // Manual calculation for rough verification
        uint256 indexDelta = endIndex - startIndex;
        uint256 yieldReward = (balance * indexDelta) / startIndex;
        uint256 share = rewardsController.collectionRewardSharePercentages(NFT_COLLECTION_1);
        uint256 allocatedYield = (yieldReward * share) / MAX_REWARD_SHARE_PERCENTAGE;
        uint256 beta = rewardsController.getCollectionBeta(NFT_COLLECTION_1);
        uint256 boost = rewardsController.calculateBoost(nftCount, beta);
        uint256 bonus = (allocatedYield * boost) / PRECISION;
        uint256 expected = allocatedYield + bonus;

        // Use approx eq due to potential minor differences in index fetching timing
        assertApproxEqAbs(preview, expected, preview / 1000, "Preview mismatch vs manual calculation"); // 0.1% tolerance
    }

    function test_PreviewRewards_WithSimulatedUpdates_Increase() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        uint256 nftCount1 = 2;
        uint256 balance1 = 500 ether;
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, int256(nftCount1), int256(balance1));

        uint256 block2 = block.number + 50; // Simulate update happening later
        uint256 block3 = block.number + 100; // Preview time
        vm.roll(block3);
        mockCToken.accrueInterest();

        IRewardsController.BalanceUpdateData[] memory simUpdates = new IRewardsController.BalanceUpdateData[](1);
        simUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: block2, // Update happens between block1 and block3
            nftDelta: 1, // +1 NFT
            balanceDelta: 100 ether // +100 balance
        });

        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;
        uint256 preview = rewardsController.previewRewards(USER_A, collections, simUpdates);

        assertTrue(preview > 0, "Preview with simulation should be > 0");

        // Manual calculation is complex here, relying on contract logic correctness for now.
        // We expect the reward to be higher than if the simulation wasn't included.
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 previewWithoutSim = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
        assertTrue(preview > previewWithoutSim, "Preview with simulation should be higher");
    }

    function test_PreviewRewards_WithSimulatedUpdates_Decrease() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        uint256 nftCount1 = 3;
        uint256 balance1 = 600 ether;
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, int256(nftCount1), int256(balance1));

        uint256 block2 = block.number + 50; // Simulate update happening later
        uint256 block3 = block.number + 100; // Preview time
        vm.roll(block3);
        mockCToken.accrueInterest();

        IRewardsController.BalanceUpdateData[] memory simUpdates = new IRewardsController.BalanceUpdateData[](1);
        simUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: block2, // Update happens between block1 and block3
            nftDelta: -1, // -1 NFT
            balanceDelta: -100 ether // -100 balance
        });

        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;
        uint256 preview = rewardsController.previewRewards(USER_A, collections, simUpdates);

        assertTrue(preview > 0, "Preview with simulation should be > 0");

        // We expect the reward to be lower than if the simulation wasn't included.
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        uint256 previewWithoutSim = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
        assertTrue(preview < previewWithoutSim, "Preview with simulation should be lower");
    }

    function test_Revert_PreviewRewards_SimulatedUpdateOutOfOrder() public {
        // 1. Initial state update
        uint256 block1 = block.number + 10;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 1, 100 ether);

        // 2. Second state update at a later block
        uint256 block3 = block.number + 20; // block3 > block1
        vm.roll(block3);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block3, 1, 10 ether); // Update state at block3
        // Now, userRewardState[USER_A][NFT_COLLECTION_1].lastUpdateBlock is block3

        // 3. Roll forward again
        uint256 block4 = block.number + 10; // block4 > block3
        vm.roll(block4);

        // 4. Prepare simulation for a block *before* the last update (block3)
        uint256 block2 = block1 + 5; // block1 < block2 < block3
        IRewardsController.BalanceUpdateData[] memory simUpdates = new IRewardsController.BalanceUpdateData[](1);
        simUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: block2, // Simulate update at block2
            nftDelta: 1,
            balanceDelta: 10 ether
        });

        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;

        // 5. Expect revert because sim block (block2) < last processed block (block3)
        uint256 expectedAttemptedBlock = block2;
        uint256 expectedLastProcessedBlock = block3; // The last processed block is now block3
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardsController.SimulationUpdateOutOfOrder.selector,
                expectedAttemptedBlock,
                expectedLastProcessedBlock
            )
        );
        rewardsController.previewRewards(USER_A, collections, simUpdates);
    }

    function test_Revert_PreviewRewards_SimulatedBalanceUnderflow() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 1, 100 ether); // Start with 100 balance

        uint256 block2 = block.number + 10;
        uint256 block3 = block.number + 20;
        vm.roll(block3);

        IRewardsController.BalanceUpdateData[] memory simUpdates = new IRewardsController.BalanceUpdateData[](1);
        // Simulate decreasing balance by more than available
        simUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: block2,
            nftDelta: 0,
            balanceDelta: -150 ether
        });

        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_1;

        uint256 expectedCurrentBalance = 100 ether;
        uint256 expectedUnderflowAmountSim = 150 ether;
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardsController.SimulationBalanceUpdateUnderflow.selector,
                expectedCurrentBalance,
                expectedUnderflowAmountSim
            )
        );
        rewardsController.previewRewards(USER_A, collections, simUpdates);
    }

    function test_Revert_PreviewRewards_CollectionNotWhitelisted() public {
        address[] memory collections = new address[](1);
        collections[0] = NFT_COLLECTION_3; // Use non-whitelisted
        IRewardsController.BalanceUpdateData[] memory noSimUpdates;
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.previewRewards(USER_A, collections, noSimUpdates);
    }
}
