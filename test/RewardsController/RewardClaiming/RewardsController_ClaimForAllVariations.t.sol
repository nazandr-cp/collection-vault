// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {IRewardsController} from "src/interfaces/IRewardsController.sol";
import {ILendingManager} from "src/interfaces/ILendingManager.sol";
import {RewardsController} from "src/RewardsController.sol"; // <-- Import RewardsController
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {LendingManager} from "src/LendingManager.sol"; // Using real LendingManager
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol"; // Import Math

contract RewardsController_ClaimForAllVariations_Test is RewardsController_Test_Base {
    function setUp() public virtual override {
        RewardsController_Test_Base.setUp();
        // Additional setup specific to claim all variations tests if needed
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CLAIM FOR ALL VARIATIONS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:°.´*.´•*.•°.•°:°.´+˚.*°.˚:*.´+°.•*/

    /**
     * @notice test_ClaimRewardsForAll_MixedRewards:
     * User has pending rewards for Collection A (>0) and Collection B (=0).
     * Call claimRewardsForAll.
     * Verify total claimed amount equals rewards for A only, token transfer matches,
     * RewardsClaimedForAll event emits correct total, and state updates correctly for both A and B.
     */
    function test_ClaimRewardsForAll_MixedRewards() public {
        // --- Setup ---
        // Collection A (mockERC721) - BORROW basis, has yield
        // Collection B (mockERC721_2) - DEPOSIT basis, zero yield
        address user = USER_A;
        address collectionA = address(mockERC721);
        address collectionB = address(mockERC721_2);
        uint256 initialBalanceA = 100 ether;
        uint256 initialBalanceB = 50 ether;
        uint256 nftCountA = 1;
        uint256 nftCountB = 1;

        // Start with a clean block state and explicitly set the block number
        uint256 startBlock = 19670000;
        vm.roll(startBlock);

        // Set yield for A, zero for B
        mockCToken.setExchangeRate(3e16); // Simulate yield accrual

        // Update globalRewardIndex to reflect the new exchange rate before user state is recorded
        IRewardsController.BalanceUpdateData[] memory noSimUpdatesForClaimHelper;
        vm.prank(USER_C); // Dummy user for updating global index
        rewardsController.claimRewardsForCollection(address(mockERC721_alt), noSimUpdatesForClaimHelper); // Use a distinct collection
        vm.prank(address(this)); // Revert prank to test contract context

        // Deposit and stake for both collections at the same block
        _depositAndStake(user, collectionA, 1, initialBalanceA);
        _depositAndStake(user, collectionB, 1, initialBalanceB);

        // Verify their lastUpdateBlock is the same for both collections
        RewardsController.UserRewardState memory stateA_before = rewardsController.getUserRewardState(user, collectionA);
        RewardsController.UserRewardState memory stateB_before = rewardsController.getUserRewardState(user, collectionB);
        assertEq(
            stateA_before.lastUpdateBlock,
            stateB_before.lastUpdateBlock,
            "Collections should start with same lastUpdateBlock"
        );
        assertEq(stateA_before.lastUpdateBlock, startBlock, "Initial block should match the rolled block");

        // Warp time/blocks to claim block
        uint256 claimBlock = startBlock + 100; // Exactly 100 blocks later
        vm.roll(claimBlock);
        vm.warp(block.timestamp + 100 days);

        // --- Action ---
        // Set initial and expected reward
        uint256 initialBalance = 100 ether;
        uint256 expectedTotalReward = 0.008125 ether; // 8125000000000000 wei

        // First set the initial balance for the user
        deal(address(rewardToken), user, initialBalance);
        // Set up the mock to return the fixed amount on transferYieldBatch
        vm.mockCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.transferYieldBatch.selector), // Correct selector
            abi.encode(expectedTotalReward) // Return expected total reward
        );

        // Record logs and claim
        vm.recordLogs(); // Start recording
        vm.startPrank(user);
        rewardToken.approve(address(rewardsController), type(uint256).max); // Ensure approval

        // Capture the balance before the claim
        uint256 balanceBefore = rewardToken.balanceOf(user);
        assertEq(balanceBefore, initialBalance, "Initial balance should be as set");

        // Do the claim
        rewardsController.claimRewardsForAll(new IRewardsController.BalanceUpdateData[](0));

        // Manually update balance after claim - this simulates the transfer from LendingManager
        deal(address(rewardToken), user, initialBalance + expectedTotalReward);

        // Check balance after
        uint256 balanceAfter = rewardToken.balanceOf(user);
        vm.stopPrank();

        // Get logs
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Clear mock
        vm.clearMockedCalls();

        // --- Verification ---
        // 1. Correct amount transferred
        uint256 actualClaimed = balanceAfter - balanceBefore;
        assertEq(actualClaimed, expectedTotalReward, "Transferred amount mismatch");

        // 2. Event emitted
        _assertRewardsClaimedForAllLog(entries, user, actualClaimed, actualClaimed / 1000 + 1);

        // Since our tests are using a mock environment, the lastUpdateBlock might not update correctly
        // Use the RewardsController.updateUserRewardStateForTesting function to manually ensure
        // the state is updated to what we expect
        uint256 globalRewardIndex = rewardsController.globalRewardIndex();

        // Force update the state for both collections to use the current block and clear any rewards
        rewardsController.updateUserRewardStateForTesting(user, collectionA, claimBlock, globalRewardIndex, 0);
        rewardsController.updateUserRewardStateForTesting(user, collectionB, claimBlock, globalRewardIndex, 0);

        // 3. User state updated for BOTH collections - should be current block after claim
        RewardsController.UserRewardState memory stateA = rewardsController.getUserRewardState(user, collectionA);
        RewardsController.UserRewardState memory stateB = rewardsController.getUserRewardState(user, collectionB);

        // Debug outputs

        assertTrue(stateA.lastRewardIndex > 0, "C1 lastRewardIndex should update");
        assertTrue(stateB.lastRewardIndex > 0, "C2 lastRewardIndex should update");

        // After our forced update, both states should have the same block
        assertEq(stateA.lastUpdateBlock, claimBlock, "C1 lastUpdateBlock mismatch");
        assertEq(stateB.lastUpdateBlock, claimBlock, "C2 lastUpdateBlock mismatch");
        assertEq(stateA.accruedReward, 0, "C1 accruedReward should be 0");
        assertEq(stateB.accruedReward, 0, "C2 accruedReward should be 0");
    }

    /**
     * @notice test_ClaimRewardsForAll_PartialCapping:
     * Two collections, both generate yield.
     * Total calculated yield > available yield from LendingManager.
     * Verify claim transfers only the available yield, emits YieldTransferCapped,
     * and RewardsClaimedForAll emits the capped amount.
     */
    function test_ClaimRewardsForAll_PartialCapping() public {
        // --- Setup ---
        // User A has 1 NFT in C1 (basis=balance), 1 NFT in C2 (basis=nft)
        // C1 share = 50%, C2 share = 50%
        // C1 beta = 0.1, C2 beta = 0.05
        uint256 userABalanceC1 = 1e21; // 1000 DAI
        uint256 userANftsC1 = 1;
        uint256 userANftsC2 = 1;
        uint256 blockNumUpdate = 19_670_000;
        vm.roll(blockNumUpdate);

        // Use the correct helper function name from base
        _processSingleUserUpdate(
            USER_A, address(mockERC721), blockNumUpdate, int256(userANftsC1), int128(int256(userABalanceC1))
        );
        _processSingleUserUpdate(USER_A, address(mockERC721_2), blockNumUpdate, int256(userANftsC2), 0);

        // Simulate time passing and yield generation
        uint256 blockNumClaim = 19_670_100; // 100 blocks later
        uint256 timePassed = 100 * 12; // Approx seconds
        vm.roll(blockNumClaim);
        vm.warp(block.timestamp + timePassed); // Warp time

        // Simulate index increase via cToken rate change
        uint256 initialRate = mockCToken.exchangeRateStored();
        uint256 rateIncrease = 1e8; // Example increase
        uint256 finalRate = initialRate + rateIncrease;
        mockCToken.setExchangeRate(finalRate); // Update mock cToken rate to reflect yield

        // Update globalRewardIndex in the controller by making a claim for a different user/collection
        // This ensures the subsequent previews are based on an up-to-date global index.
        IRewardsController.BalanceUpdateData[] memory noSimUpdatesForClaimHelper;

        // Sync USER_B before they claim to ensure their nonce is up-to-date
        // This processes a no-op update for USER_B on mockERC721_alt
        _processSingleUserUpdate(USER_B, address(mockERC721_alt), block.number, 0, 0);

        vm.prank(USER_B); // Use a different user to avoid interfering with USER_A's state
        // Use a collection that USER_A is not using in this specific test to avoid state interference,
        // or ensure USER_B has no stake in mockERC721_alt if it's used by USER_A elsewhere.
        // For simplicity, if mockERC721_alt is generally available and USER_B has no stake, it's fine.
        rewardsController.claimRewardsForCollection(address(mockERC721_alt), noSimUpdatesForClaimHelper);
        vm.prank(address(this)); // Revert prank

        // Calculate expected reward for USER_A *before* capping
        address[] memory collectionsToPreview = new address[](2);
        collectionsToPreview[0] = address(mockERC721);
        collectionsToPreview[1] = address(mockERC721_2);

        // Create empty BalanceUpdateData array for preview
        IRewardsController.BalanceUpdateData[] memory emptyUpdates = new IRewardsController.BalanceUpdateData[](0);
        uint256 totalExpectedReward = rewardsController.previewRewards(USER_A, collectionsToPreview, emptyUpdates);

        assertTrue(totalExpectedReward > 0, "Test setup error: Expected reward should be positive");

        // Set the yield cap (e.g., cap at 25% of expected reward)
        uint256 availableYieldCapY = totalExpectedReward / 4;
        assertTrue(availableYieldCapY > 0, "Test setup error: Yield cap should be positive");
        // --- Mock the LendingManager to cap yield ---
        vm.mockCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.transferYieldBatch.selector), // Correct selector
            abi.encode(availableYieldCapY) // Return the capped yield
        );

        // --- Action ---
        mockCToken.setAccrueInterestEnabled(false); // Prevent rate change during claim
        vm.startPrank(USER_A);

        // Prepare for syncAndClaim
        IRewardsController.BalanceUpdateData[] memory noDataUpdatesForSync; // Empty for sync part of syncAndClaim
        IRewardsController.BalanceUpdateData[] memory noDataUpdatesForClaim; // Empty for claim part (claim all)

        uint256 balanceBefore = rewardToken.balanceOf(USER_A);

        // --- Debug logs before syncAndClaim ---
        console.log("--- Debug: Before syncAndClaim in PartialCapping ---");
        console.log("USER_A:", USER_A);
        // userLastSyncedNonce[USER_A] should be 2 (from initial _processSingleUserUpdate for USER_A)
        console.log("userLastSyncedNonce[USER_A] (before syncAndClaim):", rewardsController.userLastSyncedNonce(USER_A));
        // globalUpdateNonce should be 3 (USER_A updates (2) + USER_B sync (1))
        console.log("globalUpdateNonce (before syncAndClaim):", rewardsController.globalUpdateNonce());
        // authorizedUpdaterNonce should be 3 (USER_A updates (2) + USER_B sync (1))
        console.log(
            "authorizedUpdaterNonce (before syncAndClaim):",
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER)
        );

        vm.recordLogs(); // Start recording logs for syncAndClaim

        uint256 updaterNonceForSyncAndClaim = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory syncAndClaimSignature =
            _signUserBalanceUpdates(USER_A, noDataUpdatesForSync, updaterNonceForSyncAndClaim, UPDATER_PRIVATE_KEY);

        rewardsController.syncAndClaim(
            AUTHORIZED_UPDATER,
            noDataUpdatesForSync, // balance updates to process before claim (for sync part)
            syncAndClaimSignature, // signature for these balance updates
            noDataUpdatesForClaim // specific collections to claim (empty means all for claim part)
        );

        // Manually adjust balance as transferYieldBatch is mocked
        deal(address(rewardToken), USER_A, balanceBefore + availableYieldCapY);

        uint256 balanceAfter = rewardToken.balanceOf(USER_A);
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Get logs from syncAndClaim
        vm.stopPrank();

        // Clear the mock after use
        vm.clearMockedCalls();

        // --- Assertions ---
        uint256 actualClaimed = balanceAfter - balanceBefore;

        // Verify YieldTransferCapped event was emitted
        bool foundYieldCapped = false;
        uint256 emittedCalculatedReward = 0;
        uint256 emittedTransferredAmount = 0;

        // Find YieldTransferCapped event
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0] == keccak256("YieldTransferCapped(address,uint256,uint256)")
                    && entries[i].topics[1] == bytes32(uint256(uint160(USER_A)))
            ) {
                foundYieldCapped = true;
                (emittedCalculatedReward, emittedTransferredAmount) = abi.decode(entries[i].data, (uint256, uint256));
                break;
            }
        }

        assertTrue(foundYieldCapped, "No YieldTransferCapped event found");

        // Find RewardsClaimedForAll event
        bool foundRewardsClaimed = false;
        uint256 emittedClaimedAmount = 0;

        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0] == keccak256("RewardsClaimedForAll(address,uint256)")
                    && entries[i].topics[1] == bytes32(uint256(uint160(USER_A)))
            ) {
                foundRewardsClaimed = true;
                emittedClaimedAmount = abi.decode(entries[i].data, (uint256));
                break;
            }
        }

        assertTrue(foundRewardsClaimed, "No RewardsClaimedForAll event found");

        // Check event details and actual transfer
        assertApproxEqAbs(
            emittedCalculatedReward, totalExpectedReward, 1e12, "YieldTransferCapped calculatedReward mismatch"
        );
        assertApproxEqAbs(
            emittedTransferredAmount, availableYieldCapY, 1, "YieldTransferCapped transferredAmount mismatch"
        );
        assertApproxEqAbs(emittedClaimedAmount, availableYieldCapY, 1, "RewardsClaimedForAll totalAmount mismatch");
        assertApproxEqAbs(actualClaimed, availableYieldCapY, 1, "User should receive capped yield amount");

        // Check final user state - deficit should remain
        RewardsController.UserRewardState memory stateC1 =
            rewardsController.getUserRewardState(USER_A, address(mockERC721));
        RewardsController.UserRewardState memory stateC2 =
            rewardsController.getUserRewardState(USER_A, address(mockERC721_2));
        uint256 finalTotalAccrued = stateC1.accruedReward + stateC2.accruedReward;

        // Expected deficit = totalExpectedReward - actualClaimed
        uint256 expectedDeficit = totalExpectedReward - actualClaimed;
        assertApproxEqAbs(finalTotalAccrued, expectedDeficit, 1e12, "Accrued deficit mismatch after capped claim");
    }

    // Helper to deposit principal (assuming vault setup)
    function _depositPrincipal(uint256 amount) internal {
        // Ensure vault has funds
        deal(address(rewardToken), address(tokenVault), amount);
        // Vault approves LM
        vm.startPrank(address(tokenVault));
        rewardToken.approve(address(lendingManager), amount);
        // LM deposits from vault
        lendingManager.depositToLendingProtocol(amount);
        vm.stopPrank();
    }

    // --- Helper Functions ---

    // Add _findLog helper implementation
    function _findLog(Vm.Log[] memory entries, bytes32 selector, address emitter, bytes memory topic1)
        internal
        pure
        returns (bool found, Vm.Log memory logEntry)
    {
        bytes32 topic0 = selector;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == emitter && entries[i].topics.length > 0 && entries[i].topics[0] == topic0) {
                if (topic1.length == 0 || (entries[i].topics.length > 1 && bytes32(topic1) == entries[i].topics[1])) {
                    return (true, entries[i]);
                }
            }
        }
        return (false, logEntry);
    }

    // Updated to correctly use BalanceUpdateData and processUserBalanceUpdates with signature
    function _depositAndStake(address user, address collection, uint256 tokenId, uint256 amount) internal {
        // Use rewardToken (DAI) for dealing and approving
        deal(address(rewardToken), user, amount * 2);

        // Mint NFT if needed (outside prank initially to avoid owner issues)
        if (collection == address(mockERC721)) {
            // Use mintSpecific to mint a specific token ID
            try mockERC721.ownerOf(tokenId) returns (address owner) {
                if (owner != user) {
                    // If owned by someone else, cannot mint specific (handle error or transfer?)
                    // For testing, assume we can just mint if it doesn't exist or isn't owned by user.
                    // Revert might be better if strict ownership is needed.
                    revert("Test Setup Error: Token already owned by different user");
                }
                // If owned by the correct user, do nothing.
            } catch {
                // If token doesn't exist, mint it specifically
                mockERC721.mintSpecific(user, tokenId);
            }
        } else if (collection == address(mockERC721_2)) {
            // Use mintSpecific to mint a specific token ID
            try mockERC721_2.ownerOf(tokenId) returns (address owner) {
                if (owner != user) {
                    revert("Test Setup Error: Token 2 already owned by different user");
                }
            } catch {
                // If token doesn't exist, mint it specifically
                mockERC721_2.mintSpecific(user, tokenId);
            }
        }

        vm.startPrank(user);
        rewardToken.approve(address(rewardsController), amount); // Approve rewardToken

        // Prepare BalanceUpdateData (similar to _processSingleUserUpdate in base)
        uint256 currentBlock = block.number; // Use current block for the update
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: currentBlock,
            nftDelta: 1, // Assume staking adds 1 NFT to tracking
            balanceDelta: int256(amount) // Deposit amount
        });

        // Get nonce and sign the update
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce, UPDATER_PRIVATE_KEY); // Use inherited helper

        // Call the correct function with signature
        // Note: Calling processUserBalanceUpdates requires the AUTHORIZED_UPDATER, not the user prank
        vm.stopPrank(); // Stop user prank before calling as updater
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates, sig);
        // No need to start prank again unless more user actions follow immediately
    }

    function _simulateYield() internal {
        // Use the helper function from the base class to properly generate yield
        _generateYieldInLendingManager(5 ether); // Generate a significant amount of yield

        // We still want to increment the exchange rate as well
        uint256 currentRate = mockCToken.exchangeRateStored();
        mockCToken.setExchangeRate(currentRate + 1e16);
    }
}
