// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm, console} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {RewardsController} from "../src/RewardsController.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {ERC4626Vault} from "../src/ERC4626Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {ILendingManager} from "../src/interfaces/ILendingManager.sol";
import {IRewardsController} from "../src/interfaces/IRewardsController.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

//     // --- Reward Calculation Tests ---

//     function test_CalculateBoost() public {
//         // Zero NFTs
//         assertEq(rewardsController.calculateBoost(0, BETA_1), 0, "Boost with 0 NFTs");

//         // Normal boost
//         uint256 expectedBoost = 5 * BETA_1; // 5 NFTs * 0.1 ether = 0.5 ether
//         assertEq(rewardsController.calculateBoost(5, BETA_1), expectedBoost, "Boost calculation normal");

//         // Max boost cap (PRECISION * 9 = 9e18)
//         uint256 highNFTCount = 100; // 100 * 0.1 ether = 10 ether > 9 ether
//         uint256 maxBoost = PRECISION * 9;
//         assertEq(rewardsController.calculateBoost(highNFTCount, BETA_1), maxBoost, "Boost calculation capped");
//     }

//     // --- _calculateRewardsWithDelta (Tested via preview/claim) ---

//     function test_PreviewRewards_ZeroNFTs() public {
//         uint256 updateBlock = block.number + 1;
//         vm.roll(updateBlock);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, 0, 1000 ether); // 0 NFTs, some balance

//         vm.roll(block.number + 100); // Accrue time
//         cToken.accrueInterest(); // Accrue interest

//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);

//         assertEq(preview, 0, "Preview should be 0 with 0 NFTs");
//     }

//     function test_PreviewRewards_ZeroBalance() public {
//         uint256 updateBlock = block.number + 1;
//         vm.roll(updateBlock);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, 5, 0); // 5 NFTs, 0 balance

//         vm.roll(block.number + 100); // Accrue time
//         cToken.accrueInterest(); // Accrue interest

//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);

//         assertEq(preview, 0, "Preview should be 0 with 0 balance");
//     }

//     function test_PreviewRewards_NoTimePassed() public {
//         uint256 updateBlock = block.number + 1;
//         vm.roll(updateBlock);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, 5, 1000 ether);

//         // No time passes, no interest accrual

//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);

//         assertEq(preview, 0, "Preview should be 0 with no time passed");
//     }

//     function test_PreviewRewards_BasicAccrual() public {
//         uint256 updateBlock = block.number + 1;
//         vm.roll(updateBlock);
//         uint256 nftCount = 3;
//         uint256 balance = 1000 ether;
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, int256(nftCount), int256(balance));
//         (uint256 startIndex,,,,) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

//         vm.roll(block.number + 100); // Accrue time
//         cToken.accrueInterest(); // Accrue interest
//         uint256 endIndex = cToken.exchangeRateStored(); // Get index after accrual

//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);

//         assertTrue(preview > 0, "Preview should be > 0 after accrual");

//         // Manual calculation for rough verification
//         uint256 indexDelta = endIndex - startIndex;
//         uint256 yieldReward = (balance * indexDelta) / startIndex;
//         uint256 share = rewardsController.collectionRewardSharePercentages(NFT_COLLECTION_1);
//         uint256 allocatedYield = (yieldReward * share) / MAX_REWARD_SHARE_PERCENTAGE;
//         uint256 beta = rewardsController.getCollectionBeta(NFT_COLLECTION_1);
//         uint256 boost = rewardsController.calculateBoost(nftCount, beta);
//         uint256 bonus = (allocatedYield * boost) / PRECISION;
//         uint256 expected = allocatedYield + bonus;

//         // Use approx eq due to potential minor differences in index fetching timing
//         assertApproxEqAbs(preview, expected, preview / 1000, "Preview mismatch vs manual calculation"); // 0.1% tolerance
//     }

//     function test_PreviewRewards_WithSimulatedUpdates_Increase() public {
//         uint256 block1 = block.number + 1;
//         vm.roll(block1);
//         uint256 nftCount1 = 2;
//         uint256 balance1 = 500 ether;
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, int256(nftCount1), int256(balance1));

//         uint256 block2 = block.number + 50; // Simulate update happening later
//         uint256 block3 = block.number + 100; // Preview time
//         vm.roll(block3);
//         cToken.accrueInterest();

//         IRewardsController.BalanceUpdateData[] memory simUpdates = new IRewardsController.BalanceUpdateData[](1);
//         simUpdates[0] = IRewardsController.BalanceUpdateData({
//             collection: NFT_COLLECTION_1,
//             blockNumber: block2, // Update happens between block1 and block3
//             nftDelta: 1, // +1 NFT
//             balanceDelta: 100 ether // +100 balance
//         });

//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;
//         uint256 preview = rewardsController.previewRewards(USER_A, collections, simUpdates);

//         assertTrue(preview > 0, "Preview with simulation should be > 0");

//         // Manual calculation is complex here, relying on contract logic correctness for now.
//         // We expect the reward to be higher than if the simulation wasn't included.
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 previewWithoutSim = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
//         assertTrue(preview > previewWithoutSim, "Preview with simulation should be higher");
//     }

//     function test_PreviewRewards_WithSimulatedUpdates_Decrease() public {
//         uint256 block1 = block.number + 1;
//         vm.roll(block1);
//         uint256 nftCount1 = 3;
//         uint256 balance1 = 600 ether;
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, int256(nftCount1), int256(balance1));

//         uint256 block2 = block.number + 50; // Simulate update happening later
//         uint256 block3 = block.number + 100; // Preview time
//         vm.roll(block3);
//         cToken.accrueInterest();

//         IRewardsController.BalanceUpdateData[] memory simUpdates = new IRewardsController.BalanceUpdateData[](1);
//         simUpdates[0] = IRewardsController.BalanceUpdateData({
//             collection: NFT_COLLECTION_1,
//             blockNumber: block2, // Update happens between block1 and block3
//             nftDelta: -1, // -1 NFT
//             balanceDelta: -100 ether // -100 balance
//         });

//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;
//         uint256 preview = rewardsController.previewRewards(USER_A, collections, simUpdates);

//         assertTrue(preview > 0, "Preview with simulation should be > 0");

//         // We expect the reward to be lower than if the simulation wasn't included.
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 previewWithoutSim = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
//         assertTrue(preview < previewWithoutSim, "Preview with simulation should be lower");
//     }

//     function test_Revert_PreviewRewards_SimulatedUpdateOutOfOrder() public {
//         uint256 block1 = block.number + 10;
//         vm.roll(block1);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 1, 100 ether);

//         uint256 block2 = block.number + 5; // Simulate update before last processed block
//         uint256 block3 = block.number + 20;
//         vm.roll(block3);

//         IRewardsController.BalanceUpdateData[] memory simUpdates = new IRewardsController.BalanceUpdateData[](1);
//         simUpdates[0] = IRewardsController.BalanceUpdateData({
//             collection: NFT_COLLECTION_1,
//             blockNumber: block2,
//             nftDelta: 1,
//             balanceDelta: 10 ether
//         });

//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;

//         uint256 expectedAttemptedBlock = block2;
//         uint256 expectedLastProcessedBlock = block1;
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 IRewardsController.SimulationUpdateOutOfOrder.selector,
//                 expectedAttemptedBlock,
//                 expectedLastProcessedBlock
//             )
//         );
//         rewardsController.previewRewards(USER_A, collections, simUpdates);
//     }

//     function test_Revert_PreviewRewards_SimulatedBalanceUnderflow() public {
//         uint256 block1 = block.number + 1;
//         vm.roll(block1);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 1, 100 ether); // Start with 100 balance

//         uint256 block2 = block.number + 10;
//         uint256 block3 = block.number + 20;
//         vm.roll(block3);

//         IRewardsController.BalanceUpdateData[] memory simUpdates = new IRewardsController.BalanceUpdateData[](1);
//         // Simulate decreasing balance by more than available
//         simUpdates[0] = IRewardsController.BalanceUpdateData({
//             collection: NFT_COLLECTION_1,
//             blockNumber: block2,
//             nftDelta: 0,
//             balanceDelta: -150 ether
//         });

//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;

//         uint256 expectedCurrentBalance = 100 ether;
//         uint256 expectedUnderflowAmountSim = 150 ether;
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 IRewardsController.SimulationBalanceUpdateUnderflow.selector,
//                 expectedCurrentBalance,
//                 expectedUnderflowAmountSim
//             )
//         );
//         rewardsController.previewRewards(USER_A, collections, simUpdates);
//     }

//     function test_Revert_PreviewRewards_CollectionNotWhitelisted() public {
//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_3; // Use non-whitelisted
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
//         rewardsController.previewRewards(USER_A, collections, noSimUpdates);
//     }

//     function test_PreviewRewards_EmptyCollectionsArray() public {
//         address[] memory collections; // Empty
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 preview = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
//         assertEq(preview, 0, "Preview with empty collections array should be 0");
//     }

//     // --- Claiming Tests ---

//     // --- claimRewardsForCollection ---
//     function test_ClaimRewardsForCollection_Basic() public {
//         // 1. Setup initial state
//         uint256 updateBlock = block.number + 1;
//         vm.roll(updateBlock);
//         uint256 nftCount = 3;
//         uint256 balance = 1000 ether;
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, int256(nftCount), int256(balance));

//         // 2. Accrue rewards
//         uint256 claimBlock = block.number + 100;
//         vm.roll(claimBlock);
//         cToken.accrueInterest();

//         // 3. Preview rewards just before claim
//         address[] memory collectionsToPreview = new address[](1);
//         collectionsToPreview[0] = NFT_COLLECTION_1;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 expectedReward = rewardsController.previewRewards(USER_A, collectionsToPreview, noSimUpdates);
//         assertTrue(expectedReward > 0, "Expected reward should be positive before claim");

//         // 4. Simulate available yield in LendingManager (ensure enough for full claim)
//         vm.startPrank(DAI_WHALE);
//         rewardToken.transfer(address(lendingManager), expectedReward * 2); // Provide ample yield
//         vm.stopPrank();
//         uint256 lmBalanceBefore = rewardToken.balanceOf(address(lendingManager));

//         // 5. Claim and Record Logs
//         vm.recordLogs(); // Start recording events
//         vm.startPrank(USER_A);
//         rewardsController.claimRewardsForCollection(NFT_COLLECTION_1, noSimUpdates);
//         vm.stopPrank();

//         // Instead of parsing logs in detail, we'll just check balances
//         // to verify the claim functionality

//         // Verify balance changes
//         uint256 lmBalanceAfter = rewardToken.balanceOf(address(lendingManager));
//         // Check internal state reset

//         // Check internal state reset
//         (uint256 lastIdx, uint256 accrued, uint256 nftBal, uint256 depAmt, uint256 lastUpdate) =
//             rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
//         assertEq(accrued, 0, "Accrued should be 0 after claim");
//         assertTrue(lastIdx >= rewardsController.globalRewardIndex(), "Last index should be updated"); // Use >=
//         assertEq(lastUpdate, block.number, "Last update block should be claim block");
//         assertEq(nftBal, nftCount, "NFT balance should persist");
//         assertEq(depAmt, balance, "Deposit amount should persist");
//     }

//     function test_ClaimRewardsForCollection_YieldCapped() public {
//         // 1. Setup initial state
//         uint256 updateBlock = block.number + 1;
//         vm.roll(updateBlock);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, 3, 1000 ether);

//         // 2. Accrue rewards
//         uint256 claimBlock = block.number + 100;
//         vm.roll(claimBlock);
//         cToken.accrueInterest();

//         // 3. Preview rewards
//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 expectedReward = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
//         assertTrue(expectedReward > 0);

//         // 4. Simulate INSUFFICIENT available yield in LendingManager
//         uint256 availableYield = expectedReward / 2; // Only half the required yield
//         vm.startPrank(DAI_WHALE);
//         rewardToken.transfer(address(lendingManager), availableYield);
//         vm.stopPrank();
//         // Ensure LM principal is 0 for easy yield calculation (or mock LM)
//         // For this test, assume principal is low enough that availableYield is the cap.

//         // 5. Claim and Record Logs
//         vm.recordLogs(); // Start recording events
//         vm.startPrank(USER_A);
//         rewardsController.claimRewardsForCollection(NFT_COLLECTION_1, noSimUpdates);
//         vm.stopPrank();
//         Vm.Log[] memory entries = vm.getRecordedLogs(); // Get recorded events

//         // 6. Verify Event
//         assertEq(entries.length, 1, "Expected 1 event log");
//         Vm.Log memory entry = entries[0];

//         // Decode RewardsClaimedForCollection(address indexed user, address indexed collection, uint256 amount)
//         address loggedUser = address(uint160(bytes20(entry.topics[1]))); // Decode indexed address
//         address loggedCollection = address(uint160(bytes20(entry.topics[2]))); // Decode indexed address
//         uint256 loggedAmount = abi.decode(entry.data, (uint256)); // Decode non-indexed amount

//         assertEq(loggedUser, USER_A, "Event user mismatch");
//         assertEq(loggedCollection, NFT_COLLECTION_1, "Event collection mismatch");
//         // Check the amount emitted equals the available yield (cap)
//         assertEq(loggedAmount, availableYield, "Emitted claimed amount should equal available yield when capped");

//         // Check internal state - accrued should store the deficit
//         (uint256 lastIdx, uint256 accrued,,, uint256 lastUpdate) =
//             rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
//         // Deficit might be slightly off expectedReward - availableYield due to index changes.
//         // Check that accrued is positive and roughly correct.
//         assertTrue(accrued > 0, "Accrued deficit should be > 0 after capped claim");
//         assertApproxEqAbs(accrued, expectedReward - availableYield, expectedReward / 1000, "Accrued deficit mismatch");
//         assertTrue(lastIdx >= rewardsController.globalRewardIndex(), "Last index should be updated");
//         assertEq(lastUpdate, block.number, "Last update block should be claim block");
//     }

//     function test_ClaimRewardsForCollection_ZeroRewards() public {
//         // 1. Setup initial state (but don't accrue rewards)
//         uint256 updateBlock = block.number + 1;
//         vm.roll(updateBlock);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, 3, 1000 ether);

//         // 2. Preview rewards (should be 0)
//         address[] memory collections = new address[](1);
//         collections[0] = NFT_COLLECTION_1;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 expectedReward = rewardsController.previewRewards(USER_A, collections, noSimUpdates);
//         assertEq(expectedReward, 0, "Expected reward should be 0 before claim");

//         // 3. Claim
//         vm.startPrank(USER_A);
//         uint256 userBalanceBefore = rewardToken.balanceOf(USER_A);
//         // Expect claim event with 0 amount
//         vm.expectEmit(true, true, true, true, address(rewardsController));
//         emit IRewardsController.RewardsClaimedForCollection(USER_A, NFT_COLLECTION_1, 0);
//         rewardsController.claimRewardsForCollection(NFT_COLLECTION_1, noSimUpdates);
//         uint256 userBalanceAfter = rewardToken.balanceOf(USER_A);
//         vm.stopPrank();

//         // 4. Verify
//         uint256 actualClaimed = userBalanceAfter - userBalanceBefore;
//         assertEq(actualClaimed, 0, "Claimed amount should be 0 when no rewards");

//         // Check internal state reset (index and block updated, accrued remains 0)
//         (uint256 lastIdx, uint256 accrued,,, uint256 lastUpdate) =
//             rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
//         assertEq(accrued, 0, "Accrued should be 0 after claim");
//         assertTrue(lastIdx >= rewardsController.globalRewardIndex(), "Last index should be updated");
//         assertEq(lastUpdate, block.number, "Last update block should be claim block");
//     }

//     function test_Revert_ClaimRewardsForCollection_NotWhitelisted() public {
//         vm.startPrank(USER_A);
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
//         rewardsController.claimRewardsForCollection(NFT_COLLECTION_3, noSimUpdates);
//         vm.stopPrank();
//     }
//     // --- Simple Claim Test (from todo_initialization_admin_view.md line 44) ---

//     function test_ClaimRewardsForCollection_Simple_Success() public {
//         // 1. Setup: Use USER_A and NFT_COLLECTION_1 (whitelisted in setUp)
//         address user = USER_A;
//         address collection = NFT_COLLECTION_1;
//         uint256 updateBlock = block.number + 1;
//         vm.roll(updateBlock);
//         uint256 nftCount = 5;
//         uint256 balance = 2000 ether;
//         _processSingleUserUpdate(user, collection, updateBlock, int256(nftCount), int256(balance));

//         // 2. Advance time and accrue interest
//         uint256 timePassed = 1 days; // Advance 1 day
//         vm.warp(block.timestamp + timePassed); // Use warp for predictable time passage
//         vm.roll(block.number + (timePassed / 12)); // Roll blocks roughly corresponding to time (assuming ~12s block time)
//         cToken.accrueInterest(); // Trigger interest accrual on cToken

//         // 3. Preview rewards (optional but good practice)
//         address[] memory collectionsToPreview = new address[](1);
//         collectionsToPreview[0] = collection;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 expectedReward = rewardsController.previewRewards(user, collectionsToPreview, noSimUpdates);
//         assertTrue(expectedReward > 0, "Previewed reward should be greater than 0 after time passage");

//         // 4. Ensure Lending Manager has sufficient yield
//         uint256 yieldAmount = expectedReward * 2; // Provide more than needed
//         vm.startPrank(DAI_WHALE);
//         rewardToken.transfer(address(lendingManager), yieldAmount);
//         vm.stopPrank();
//         uint256 userBalanceBefore = rewardToken.balanceOf(user);
//         uint256 lmBalanceBefore = rewardToken.balanceOf(address(lendingManager));

//         // 5. Call claimRewardsForCollection
//         vm.startPrank(user);
//         // Expect the event with correct parameters
//         vm.expectEmit(true, true, true, true, address(rewardsController));
//         emit IRewardsController.RewardsClaimedForCollection(user, collection, expectedReward);
//         rewardsController.claimRewardsForCollection(collection, noSimUpdates);
//         vm.stopPrank();

//         // 6. Verify reward transfer
//         uint256 userBalanceAfter = rewardToken.balanceOf(user);
//         uint256 actualClaimed = userBalanceAfter - userBalanceBefore;
//         // Use approx check due to potential minor rounding differences in preview vs claim
//         assertApproxEqAbs(
//             actualClaimed, expectedReward, expectedReward / 10000, "User did not receive the correct reward amount"
//         ); // 0.01% tolerance

//         // Verify LM balance decreased (optional, confirms transfer occurred)
//         uint256 lmBalanceAfter = rewardToken.balanceOf(address(lendingManager));
//         assertApproxEqAbs(
//             lmBalanceBefore - lmBalanceAfter,
//             expectedReward,
//             expectedReward / 10000,
//             "LM balance did not decrease correctly"
//         );

//         // 7. Verify userNFTData state reset
//         (uint256 lastIdx, uint256 accrued, uint256 nftBal, uint256 depAmt, uint256 lastUpdate) =
//             rewardsController.userNFTData(user, collection);
//         assertEq(accrued, 0, "Accrued reward should be reset to 0 after claim");
//         assertTrue(lastIdx >= rewardsController.globalRewardIndex(), "User's lastRewardIndex should be updated"); // Use >= due to potential index updates
//         assertEq(lastUpdate, block.number, "User's lastUpdateBlock should be the claim block number");
//         // Ensure other state remains
//         assertEq(nftBal, nftCount, "NFT balance should remain unchanged");
//         assertEq(depAmt, balance, "Balance should remain unchanged");
//     }

//     // --- claimRewardsForAll ---
//     function test_ClaimRewardsForAll_MultipleCollections() public {
//         // 1. Setup state for two collections
//         uint256 block1 = block.number + 1;
//         vm.roll(block1);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 2, 500 ether);
//         uint256 block2 = block.number + 1;
//         vm.roll(block2);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_2, block2, 1, 300 ether);

//         // 2. Accrue rewards
//         uint256 claimBlock = block.number + 100;
//         vm.roll(claimBlock);
//         cToken.accrueInterest();

//         // 3. Preview rewards for both
//         address[] memory cols1 = new address[](1);
//         cols1[0] = NFT_COLLECTION_1;
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 expectedReward1 = rewardsController.previewRewards(USER_A, cols1, noSimUpdates);

//         address[] memory cols2 = new address[](1);
//         cols2[0] = NFT_COLLECTION_2;
//         uint256 expectedReward2 = rewardsController.previewRewards(USER_A, cols2, noSimUpdates);

//         uint256 totalExpectedReward = expectedReward1 + expectedReward2;
//         assertTrue(totalExpectedReward > 0, "Total expected reward should be positive");

//         // 4. Simulate available yield
//         vm.startPrank(DAI_WHALE);
//         rewardToken.transfer(address(lendingManager), totalExpectedReward * 2);
//         vm.stopPrank();

//         // 5. Claim All and Record Logs
//         vm.recordLogs(); // Start recording events
//         vm.startPrank(USER_A);
//         rewardsController.claimRewardsForAll(noSimUpdates);
//         vm.stopPrank();
//         Vm.Log[] memory entries = vm.getRecordedLogs(); // Get recorded events

//         // 6. Verify Event
//         assertEq(entries.length, 1, "Expected 1 event log"); // RewardsClaimedForAll event
//         Vm.Log memory entry = entries[0];

//         // Decode RewardsClaimedForAll(address indexed user, uint256 amount)
//         // Topic 0: Event Signature keccak256("RewardsClaimedForAll(address,uint256)")
//         // Topic 1: user (indexed)
//         // Data: amount (not indexed)
//         address loggedUser = address(uint160(bytes20(entry.topics[1]))); // Decode indexed address
//         uint256 loggedAmount = abi.decode(entry.data, (uint256)); // Decode non-indexed amount

//         assertEq(loggedUser, USER_A, "Event user mismatch");
//         // Check the total amount emitted by the RewardsController
//         assertApproxEqAbs(
//             loggedAmount, totalExpectedReward, totalExpectedReward / 1000, "Emitted total claimed amount mismatch"
//         );

//         // Check state reset for both collections
//         (uint256 lastIdx1, uint256 accrued1,,, uint256 lastUpdate1) =
//             rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
//         assertEq(accrued1, 0, "Accrued 1 should be 0");
//         assertTrue(lastIdx1 >= rewardsController.globalRewardIndex(), "Last index 1 updated");
//         assertEq(lastUpdate1, block.number, "Last update block 1");

//         (uint256 lastIdx2, uint256 accrued2,,, uint256 lastUpdate2) =
//             rewardsController.userNFTData(USER_A, NFT_COLLECTION_2);
//         assertEq(accrued2, 0, "Accrued 2 should be 0");
//         assertTrue(lastIdx2 >= rewardsController.globalRewardIndex(), "Last index 2 updated");
//         assertEq(lastUpdate2, block.number, "Last update block 2");
//     }

//     function test_ClaimRewardsForAll_YieldCapped() public {
//         // 1. Setup state for two collections
//         uint256 block1 = block.number + 1;
//         vm.roll(block1);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 2, 500 ether);
//         uint256 block2 = block.number + 1;
//         vm.roll(block2);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_2, block2, 1, 300 ether);

//         // 2. Accrue rewards
//         uint256 claimBlock = block.number + 100;
//         vm.roll(claimBlock);
//         cToken.accrueInterest();

//         // 3. Preview total rewards
//         address[] memory allCols = rewardsController.getUserNFTCollections(USER_A);
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         uint256 totalExpectedReward = rewardsController.previewRewards(USER_A, allCols, noSimUpdates);
//         assertTrue(totalExpectedReward > 0);

//         // 4. Simulate INSUFFICIENT available yield
//         uint256 availableYield = totalExpectedReward / 3;
//         vm.startPrank(DAI_WHALE);
//         rewardToken.transfer(address(lendingManager), availableYield);
//         vm.stopPrank();

//         // 5. Claim All and Record Logs
//         vm.recordLogs(); // Start recording events
//         vm.startPrank(USER_A);
//         rewardsController.claimRewardsForAll(noSimUpdates);
//         vm.stopPrank();
//         Vm.Log[] memory entries = vm.getRecordedLogs(); // Get recorded events

//         // 6. Verify Event
//         assertEq(entries.length, 1, "Expected 1 event log"); // RewardsClaimedForAll event
//         Vm.Log memory entry = entries[0];

//         // Decode RewardsClaimedForAll(address indexed user, uint256 amount)
//         address loggedUser = address(uint160(bytes20(entry.topics[1]))); // Decode indexed address
//         uint256 loggedAmount = abi.decode(entry.data, (uint256)); // Decode non-indexed amount

//         assertEq(loggedUser, USER_A, "Event user mismatch");
//         // Check the total amount emitted equals the available yield (cap)
//         assertEq(loggedAmount, availableYield, "Emitted total claimed amount should equal available yield when capped");

//         // Check state reset - accrued should be 0 for all claimed collections even if capped
//         (uint256 lastIdx1, uint256 accrued1,,, uint256 lastUpdate1) =
//             rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
//         assertEq(accrued1, 0, "Accrued 1 should be 0 even if capped");
//         assertTrue(lastIdx1 >= rewardsController.globalRewardIndex(), "Last index 1 updated");
//         assertEq(lastUpdate1, block.number, "Last update block 1");

//         (uint256 lastIdx2, uint256 accrued2,,, uint256 lastUpdate2) =
//             rewardsController.userNFTData(USER_A, NFT_COLLECTION_2);
//         assertEq(accrued2, 0, "Accrued 2 should be 0 even if capped");
//         assertTrue(lastIdx2 >= rewardsController.globalRewardIndex(), "Last index 2 updated");
//         assertEq(lastUpdate2, block.number, "Last update block 2");
//     }

//     function test_Revert_ClaimRewardsForAll_NoActiveCollections() public {
//         // User A has no active collections initially
//         vm.startPrank(USER_A);
//         IRewardsController.BalanceUpdateData[] memory noSimUpdates;
//         vm.expectRevert(IRewardsController.NoRewardsToClaim.selector);
//         rewardsController.claimRewardsForAll(noSimUpdates);
//         vm.stopPrank();
//     }

//     // --- View Function Tests ---

//     function test_GetUserCollectionTracking() public {
//         uint256 block1 = block.number + 1;
//         vm.roll(block1);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 2, 100 ether);
//         uint256 block2 = block.number + 1;
//         vm.roll(block2);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_2, block2, 1, 50 ether);

//         address[] memory collections = new address[](2);
//         collections[0] = NFT_COLLECTION_1;
//         collections[1] = NFT_COLLECTION_2;

//         IRewardsController.UserCollectionTracking[] memory tracking =
//             rewardsController.getUserCollectionTracking(USER_A, collections);

//         assertEq(tracking.length, 2);
//         // Collection 1
//         assertEq(tracking[0].lastUpdateBlock, block1);
//         assertEq(tracking[0].lastNFTBalance, 2);
//         assertEq(tracking[0].lastBalance, 100 ether);
//         assertTrue(tracking[0].lastUserRewardIndex > 0);
//         // Collection 2
//         assertEq(tracking[1].lastUpdateBlock, block2);
//         assertEq(tracking[1].lastNFTBalance, 1);
//         assertEq(tracking[1].lastBalance, 50 ether);
//         assertTrue(tracking[1].lastUserRewardIndex > 0);
//     }

//     function test_Revert_GetUserCollectionTracking_EmptyArray() public {
//         address[] memory collections; // Empty
//         vm.expectRevert(IRewardsController.CollectionsArrayEmpty.selector);
//         rewardsController.getUserCollectionTracking(USER_A, collections);
//     }

//     function test_GetCollectionBeta() public {
//         assertEq(rewardsController.getCollectionBeta(NFT_COLLECTION_1), BETA_1);
//     }

//     function test_Revert_GetCollectionBeta() public {
//         vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
//         rewardsController.getCollectionBeta(NFT_COLLECTION_3);
//     }

//     function test_GetCollectionRewardBasis() public {
//         assertEq(
//             uint256(rewardsController.getCollectionRewardBasis(NFT_COLLECTION_1)),
//             uint256(IRewardsController.RewardBasis.BORROW)
//         );
//         assertEq(
//             uint256(rewardsController.getCollectionRewardBasis(NFT_COLLECTION_2)),
//             uint256(IRewardsController.RewardBasis.DEPOSIT)
//         );
//     }

//     function test_Revert_GetCollectionRewardBasis_NotWhitelisted() public {
//         vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
//         rewardsController.getCollectionRewardBasis(NFT_COLLECTION_3);
//     }

//     function test_GetUserNFTCollections() public {
//         // No collections initially
//         address[] memory active0 = rewardsController.getUserNFTCollections(USER_A);
//         assertEq(active0.length, 0);

//         // Add one collection
//         uint256 block1 = block.number + 1;
//         vm.roll(block1);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 1, 10 ether);
//         address[] memory active1 = rewardsController.getUserNFTCollections(USER_A);
//         assertEq(active1.length, 1);
//         assertEq(active1[0], NFT_COLLECTION_1);

//         // Add another collection
//         uint256 block2 = block.number + 1;
//         vm.roll(block2);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_2, block2, 1, 10 ether);
//         address[] memory active2 = rewardsController.getUserNFTCollections(USER_A);
//         assertEq(active2.length, 2);
//         // Order might not be guaranteed, check for presence
//         assertTrue(active2[0] == NFT_COLLECTION_1 || active2[1] == NFT_COLLECTION_1);
//         assertTrue(active2[0] == NFT_COLLECTION_2 || active2[1] == NFT_COLLECTION_2);

//         // Remove one collection by zeroing balance/nft
//         uint256 block3 = block.number + 1;
//         vm.roll(block3);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block3, -1, -10 ether);
//         address[] memory active3 = rewardsController.getUserNFTCollections(USER_A);
//         assertEq(active3.length, 1);
//         assertEq(active3[0], NFT_COLLECTION_2);
//     }

//     function test_IsCollectionWhitelisted() public {
//         assertTrue(rewardsController.isCollectionWhitelisted(NFT_COLLECTION_1));
//         assertFalse(rewardsController.isCollectionWhitelisted(NFT_COLLECTION_3));
//     }

//     function test_GetWhitelistedCollections() public {
//         address[] memory whitelisted = rewardsController.getWhitelistedCollections();
//         assertEq(whitelisted.length, 2); // Initially added 2
//         // Order might not be guaranteed
//         assertTrue(whitelisted[0] == NFT_COLLECTION_1 || whitelisted[1] == NFT_COLLECTION_1);
//         assertTrue(whitelisted[0] == NFT_COLLECTION_2 || whitelisted[1] == NFT_COLLECTION_2);

//         // Add another
//         vm.startPrank(OWNER);
//         rewardsController.addNFTCollection(
//             NFT_COLLECTION_3, BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
//         );
//         vm.stopPrank();
//         whitelisted = rewardsController.getWhitelistedCollections();
//         assertEq(whitelisted.length, 3);
//     }

//     function test_UserNFTData() public {
//         uint256 block1 = block.number + 1;
//         vm.roll(block1);
//         _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 2, 100 ether);

//         (
//             uint256 lastRewardIndex,
//             uint256 accruedReward,
//             uint256 lastNFTBalance,
//             uint256 lastBalance,
//             uint256 lastUpdateBlock
//         ) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

//         assertTrue(lastRewardIndex > 0);
//         assertEq(accruedReward, 0);
//         assertEq(lastNFTBalance, 2);
//         assertEq(lastBalance, 100 ether);
//         assertEq(lastUpdateBlock, block1);
//     }

//     function test_CollectionRewardSharePercentages_Success() public {
//         // Collection 1 added in setUp with VALID_REWARD_SHARE_PERCENTAGE
//         assertEq(
//             rewardsController.collectionRewardSharePercentages(NFT_COLLECTION_1),
//             VALID_REWARD_SHARE_PERCENTAGE,
//             "Share percentage mismatch for collection 1"
//         );
//         // Collection 2 added in setUp with VALID_REWARD_SHARE_PERCENTAGE
//         assertEq(
//             rewardsController.collectionRewardSharePercentages(NFT_COLLECTION_2),
//             VALID_REWARD_SHARE_PERCENTAGE,
//             "Share percentage mismatch for collection 2"
//         );
//         // Non-whitelisted collection should have 0 share
//         assertEq(
//             rewardsController.collectionRewardSharePercentages(NFT_COLLECTION_3),
//             0,
//             "Share percentage should be 0 for non-whitelisted"
//         );
//     }

//     function test_UserNFTData_Initial() public {
//         // Check data for a user and collection that have had no interactions
//         (
//             uint256 lastRewardIndex,
//             uint256 accruedReward,
//             uint256 lastNFTBalance,
//             uint256 lastBalance,
//             uint256 lastUpdateBlock
//         ) = rewardsController.userNFTData(USER_C, NFT_COLLECTION_1); // USER_C has no activity

//         assertEq(lastRewardIndex, 0, "Initial lastRewardIndex should be 0");
//         assertEq(accruedReward, 0, "Initial accruedReward should be 0");
//         assertEq(lastNFTBalance, 0, "Initial lastNFTBalance should be 0");
//         assertEq(lastBalance, 0, "Initial lastBalance should be 0");
//         assertEq(lastUpdateBlock, 0, "Initial lastUpdateBlock should be 0");

//         // Also check for a whitelisted collection the user hasn't interacted with
//         (lastRewardIndex, accruedReward, lastNFTBalance, lastBalance, lastUpdateBlock) =
//             rewardsController.userNFTData(USER_A, NFT_COLLECTION_2); // Assume USER_A hasn't interacted with C2 yet

//         assertEq(lastRewardIndex, 0, "Initial lastRewardIndex for C2 should be 0");
//         assertEq(accruedReward, 0, "Initial accruedReward for C2 should be 0");
//         assertEq(lastNFTBalance, 0, "Initial lastNFTBalance for C2 should be 0");
//         assertEq(lastBalance, 0, "Initial lastBalance for C2 should be 0");
//         assertEq(lastUpdateBlock, 0, "Initial lastUpdateBlock for C2 should be 0");
//     }
// }

// // Minimal Mock ERC20 for testing Vault mismatch
// contract MockERC20 is IERC20 {
//     string public name;
//     string public symbol;
//     uint8 public decimals;
//     mapping(address => uint256) public balanceOf;
//     mapping(address => mapping(address => uint256)) public allowance;
//     uint256 public totalSupply;

//     constructor(string memory _name, string memory _symbol, uint8 _decimals) {
//         name = _name;
//         symbol = _symbol;
//         decimals = _decimals;
//     }

//     function transfer(address to, uint256 amount) external returns (bool) {
//         balanceOf[msg.sender] -= amount;
//         balanceOf[to] += amount;
//         emit Transfer(msg.sender, to, amount);
//         return true;
//     }

//     function approve(address spender, uint256 amount) external returns (bool) {
//         allowance[msg.sender][spender] = amount;
//         emit Approval(msg.sender, spender, amount);
//         return true;
//     }

//     function transferFrom(address from, address to, uint256 amount) external returns (bool) {
//         allowance[from][msg.sender] -= amount;
//         balanceOf[from] -= amount;
//         balanceOf[to] += amount;
//         emit Transfer(from, to, amount);
//         return true;
//     }
//     // Implement other IERC20 functions as needed (can be empty for this test)

//     function mint(address to, uint256 amount) external {
//         balanceOf[to] += amount;
//         totalSupply += amount;
//         emit Transfer(address(0), to, amount);
//     }
// }

// // --- V2 Mock Contract ---
// // Simple V2 mock that adds a getVersion function
// contract RewardsControllerV2Mock is RewardsController {
//     function getVersion() public pure returns (string memory) {
//         return "V2";
//     }
// }

// // --- Upgrade Tests ---

// contract RewardsControllerUpgradeTest is RewardsControllerTest {
//     // Use the specific V2 mock for functionality change tests
//     RewardsControllerV2Mock internal rewardsControllerV2Mock;

//     // Override setUp to prevent redeployment in inherited tests if needed,
//     // or keep it to ensure a fresh V1 state for each upgrade test.
//     // For simplicity, we'll let each test run the full setUp.

//     // Helper to deploy the standard V2 (same as V1 for state tests)
//     function _deployAndUpgradeToV2() internal returns (RewardsController) {
//         vm.startPrank(OWNER);
//         RewardsController v2Impl = new RewardsController();
//         vm.stopPrank();
//         vm.label(address(v2Impl), "RewardsController (Impl V2 - State Test)");

//         vm.startPrank(ADMIN);
//         address proxyAddr = address(rewardsController);
//         address implAddr = address(v2Impl);
//         proxyAdmin.upgrade(proxyAddr, implAddr);
//         vm.stopPrank();
//         return v2Impl; // Return the deployed V2 instance if needed
//     }

//     // Helper specifically for deploying and upgrading to the V2 Mock
//     function _deployAndUpgradeToV2Mock() internal {
//         vm.startPrank(OWNER);
//         rewardsControllerV2Mock = new RewardsControllerV2Mock();
//         vm.stopPrank();
//         vm.label(address(rewardsControllerV2Mock), "RewardsController (Impl V2 Mock)");

//         vm.startPrank(ADMIN);
//         address proxyAddr = address(rewardsController);
//         address implAddr = address(rewardsControllerV2Mock);
//         proxyAdmin.upgrade(proxyAddr, implAddr);
//         vm.stopPrank();
//     }

//     /// forge-test-fail
//     function test_Revert_Upgrade_NonAdmin() public {
//         // Deploy V2 Implementation
//         vm.startPrank(OWNER);
//         RewardsController v2Impl = new RewardsController();
//         vm.stopPrank();

//         // Attempt upgrade from non-admin (OWNER)
//         vm.startPrank(OWNER);
//         // ProxyAdmin reverts with custom error OwnableUnauthorizedAccount(address account)
//         vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OWNER));
//         proxyAdmin.upgrade(address(rewardsController), address(v2Impl));
//         vm.stopPrank();
//     }

//     /// forge-test-fail
//     function test_Revert_Upgrade_ZeroImplementation() public {
//         vm.startPrank(ADMIN);
//         // ProxyAdmin reverts with "ERC1967: new implementation is not a contract"
//         vm.expectRevert("ERC1967: new implementation is not a contract");
//         proxyAdmin.upgrade(address(rewardsController), address(0));
//         vm.stopPrank();
//     }

//     /// forge-test-fail
//     function test_Revert_Upgrade_NonContractImplementation() public {
//         vm.startPrank(ADMIN);
//         // ProxyAdmin reverts with "ERC1967: new implementation is not a contract"
//         vm.expectRevert("ERC1967: new implementation is not a contract");
//         proxyAdmin.upgrade(address(rewardsController), USER_C); // Use an EOA
//         vm.stopPrank();
//     }
// }
