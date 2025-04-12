// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {RewardsController} from "../src/RewardsController.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendingManager} from "../src/mocks/MockLendingManager.sol";
import {MockNFTRegistry} from "../src/mocks/MockNFTRegistry.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {ILendingManager} from "../src/interfaces/ILendingManager.sol";
import {INFTRegistry} from "../src/interfaces/INFTRegistry.sol";
import {IRewardsController} from "../src/interfaces/IRewardsController.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {MockTokenVault} from "../src/mocks/MockTokenVault.sol";

// Helper function for checking if an address is in an array
library ArrayUtils {
    function contains(address[] memory self, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < self.length; i++) {
            if (self[i] == value) {
                return true;
            }
        }
        return false;
    }
}

contract RewardsControllerTest is Test {
    using ArrayUtils for address[];

    // --- Constants & Config ---
    address constant USER_A = address(0xAAA);
    address constant USER_B = address(0xBBB);
    address constant NFT_COLLECTION_1 = address(0xC1);
    address constant NFT_COLLECTION_2 = address(0xC2);
    address constant NFT_COLLECTION_3 = address(0xC3); // Unregistered
    address constant OWNER = address(0x001);
    address constant OTHER_ADDRESS = address(0x123);
    address constant NFT_UPDATER = address(0xBAD); // Simulate NFTDataUpdater

    uint256 constant PRECISION = 1e18;
    uint256 constant BETA_1 = 0.1 ether; // Example beta (needs scaling definition)
    uint256 constant BETA_2 = 0.05 ether; // Example beta

    // --- Contracts ---
    RewardsController rewardsController;
    MockLendingManager mockLM;
    MockNFTRegistry mockRegistry;
    MockERC20 rewardToken; // Same as LM asset
    MockTokenVault mockVault;

    // --- Setup ---
    function setUp() public {
        vm.startPrank(OWNER);

        // Deploy Reward Token (Asset)
        rewardToken = new MockERC20("Reward Token", "RWD", 1_000_000 ether);

        // Deploy Mock Lending Manager
        mockLM = new MockLendingManager(address(rewardToken));

        // Deploy Mock NFT Registry
        mockRegistry = new MockNFTRegistry();

        // Deploy Mock Vault (needs asset)
        mockVault = new MockTokenVault(address(rewardToken));

        // Deploy RewardsController
        rewardsController = new RewardsController(OWNER, address(mockLM), address(mockRegistry), address(mockVault));

        // Whitelist some collections
        rewardsController.addNFTCollection(NFT_COLLECTION_1, BETA_1);
        rewardsController.addNFTCollection(NFT_COLLECTION_2, BETA_2);

        // Optional: Fund mock LM with some reward tokens for transferYield calls
        rewardToken.transfer(address(mockLM), 500_000 ether);
        // Need a way to tell mockLM about its funds if it simulates transfers
        // mockLM.setTransferYieldFunds(500_000 ether);

        vm.stopPrank();
    }

    // --- Test Admin Functions --- //

    function test_Admin_AddCollection() public {
        address newCollection = address(0xC4);
        uint256 newBeta = 0.2 ether;

        assertFalse(rewardsController.getWhitelistedCollections().contains(newCollection), "New coll shouldn't exist");

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.NFTCollectionAdded(newCollection, newBeta);
        rewardsController.addNFTCollection(newCollection, newBeta);
        vm.stopPrank();

        assertTrue(rewardsController.getWhitelistedCollections().contains(newCollection), "New coll should exist");
        assertEq(rewardsController.getCollectionBeta(newCollection), newBeta, "Beta mismatch");
        address[] memory collections = rewardsController.getWhitelistedCollections();
        assertTrue(collections.length == 3, "Should have 3 collections");
    }

    function test_RevertIf_AddCollection_Exists() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(RewardsController.CollectionAlreadyExists.selector, NFT_COLLECTION_1));
        rewardsController.addNFTCollection(NFT_COLLECTION_1, BETA_1);
        vm.stopPrank();
    }

    function test_RevertIf_AddCollection_NotOwner() public {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.addNFTCollection(address(0xC4), BETA_1);
        vm.stopPrank();
    }

    function test_Admin_RemoveCollection() public {
        assertTrue(rewardsController.getWhitelistedCollections().contains(NFT_COLLECTION_1), "Coll 1 should exist");

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.NFTCollectionRemoved(NFT_COLLECTION_1);
        rewardsController.removeNFTCollection(NFT_COLLECTION_1);
        vm.stopPrank();

        assertFalse(rewardsController.getWhitelistedCollections().contains(NFT_COLLECTION_1), "Coll 1 shouldn't exist");

        // Check that getting beta for the removed collection reverts
        vm.expectRevert(abi.encodeWithSelector(RewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_1));
        rewardsController.getCollectionBeta(NFT_COLLECTION_1);

        address[] memory collections = rewardsController.getWhitelistedCollections();
        assertTrue(collections.length == 1, "Should have 1 collection left");
        assertEq(collections[0], NFT_COLLECTION_2, "Remaining collection mismatch");
    }

    function test_RevertIf_RemoveCollection_NotWhitelisted() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(RewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.removeNFTCollection(NFT_COLLECTION_3);
        vm.stopPrank();
    }

    function test_RevertIf_RemoveCollection_NotOwner() public {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.removeNFTCollection(NFT_COLLECTION_1);
        vm.stopPrank();
    }

    function test_Admin_UpdateBeta() public {
        uint256 oldBeta = rewardsController.getCollectionBeta(NFT_COLLECTION_1);
        uint256 newBeta = 0.5 ether;

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.BetaUpdated(NFT_COLLECTION_1, oldBeta, newBeta);
        rewardsController.updateBeta(NFT_COLLECTION_1, newBeta);
        vm.stopPrank();

        assertEq(rewardsController.getCollectionBeta(NFT_COLLECTION_1), newBeta, "Beta update mismatch");
    }

    function test_RevertIf_UpdateBeta_NotWhitelisted() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(RewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.updateBeta(NFT_COLLECTION_3, 1 ether);
        vm.stopPrank();
    }

    function test_RevertIf_UpdateBeta_NotOwner() public {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.updateBeta(NFT_COLLECTION_1, 1 ether);
        vm.stopPrank();
    }

    function test_Admin_SetNFTRegistry() public {
        MockNFTRegistry newRegistry = new MockNFTRegistry();
        vm.startPrank(OWNER);
        // vm.expectEmit - Add if event is implemented
        rewardsController.setNFTRegistry(address(newRegistry));
        vm.stopPrank();
        assertEq(address(rewardsController.nftRegistry()), address(newRegistry), "Registry address mismatch");
    }

    function test_RevertIf_SetNFTRegistry_NotOwner() public {
        MockNFTRegistry newRegistry = new MockNFTRegistry();
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.setNFTRegistry(address(newRegistry));
        vm.stopPrank();
    }

    function test_RevertIf_SetNFTRegistry_ZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(RewardsController.AddressZero.selector);
        rewardsController.setNFTRegistry(address(0));
        vm.stopPrank();
    }

    // --- Test NFT Update Functions --- //

    function test_UpdateNFTBalance_Success() public {
        address caller = OWNER;
        uint256 initialBalance = 0;
        uint256 newBalance = 5;

        // uint256 blockBefore = block.number; // Commented out unused variable

        vm.startPrank(caller);
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.NFTBalanceUpdated(USER_A, NFT_COLLECTION_1, newBalance, initialBalance, block.number);
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_1, newBalance);
        vm.stopPrank();

        IRewardsController.UserNFTInfo memory userInfo = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_1);
        assertEq(userInfo.lastUpdateBlock, block.number, "Last update block mismatch");
        assertEq(userInfo.lastNFTBalance, newBalance, "Last NFT balance mismatch");
        // Remove check for accruedBonus, as it was removed/recalculated
        // assertEq(userInfo.accruedBonus, 0, "Initial accrued bonus should be 0");

        address[] memory userCollections = rewardsController.getUserNFTCollections(USER_A);
        assertEq(userCollections.length, 1, "User A should have 1 active collection");
        assertEq(userCollections[0], NFT_COLLECTION_1, "User A active collection mismatch");
    }

    function test_UpdateNFTBalances_Success() public {
        address caller = OWNER;
        uint256 userA_C1_Initial = 0;
        uint256 userA_C2_Initial = 0;
        uint256 userA_C1_New = 3;
        uint256 userA_C2_New = 7;

        address[] memory collections = new address[](2);
        collections[0] = NFT_COLLECTION_1;
        collections[1] = NFT_COLLECTION_2;
        uint256[] memory balances = new uint256[](2);
        balances[0] = userA_C1_New;
        balances[1] = userA_C2_New;

        vm.startPrank(caller);
        // Expect multiple events
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.NFTBalanceUpdated(
            USER_A, NFT_COLLECTION_1, userA_C1_New, userA_C1_Initial, block.number
        );
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.NFTBalanceUpdated(
            USER_A, NFT_COLLECTION_2, userA_C2_New, userA_C2_Initial, block.number
        );
        rewardsController.updateNFTBalances(USER_A, collections, balances);
        vm.stopPrank();

        IRewardsController.UserNFTInfo memory userInfo1 = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_1);
        assertEq(userInfo1.lastUpdateBlock, block.number, "C1 Last update block");
        assertEq(userInfo1.lastNFTBalance, userA_C1_New, "C1 Last NFT balance");
        // Remove check for accruedBonus
        // assertEq(userInfo1.accruedBonus, 0, "C1 Initial accrued bonus");

        IRewardsController.UserNFTInfo memory userInfo2 = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_2);
        assertEq(userInfo2.lastUpdateBlock, block.number, "C2 Last update block");
        assertEq(userInfo2.lastNFTBalance, userA_C2_New, "C2 Last NFT balance");
        // Remove check for accruedBonus
        // assertEq(userInfo2.accruedBonus, 0, "C2 Initial accrued bonus");

        address[] memory userCollections = rewardsController.getUserNFTCollections(USER_A);
        assertEq(userCollections.length, 2, "User A should have 2 active collections");
        assertTrue(userCollections.contains(NFT_COLLECTION_1), "Missing C1");
        assertTrue(userCollections.contains(NFT_COLLECTION_2), "Missing C2");
    }

    function test_UpdateNFTBalances_IgnoresNotWhitelisted() public {
        address caller = OWNER;
        address[] memory collections = new address[](2);
        collections[0] = NFT_COLLECTION_1; // Whitelisted
        collections[1] = NFT_COLLECTION_3; // Not whitelisted
        uint256[] memory balances = new uint256[](2);
        balances[0] = 5;
        balances[1] = 10;

        vm.startPrank(caller);
        // Only expect event for C1
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.NFTBalanceUpdated(USER_A, NFT_COLLECTION_1, 5, 0, block.number);
        rewardsController.updateNFTBalances(USER_A, collections, balances);
        vm.stopPrank();

        // Check state for C1 updated
        IRewardsController.UserNFTInfo memory userInfo1 = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_1);
        assertEq(userInfo1.lastNFTBalance, 5, "C1 balance mismatch");
        assertEq(userInfo1.lastUpdateBlock, block.number, "C1 block mismatch");

        // Check state for C3 unchanged
        IRewardsController.UserNFTInfo memory userInfo3 = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_3);
        assertEq(userInfo3.lastNFTBalance, 0, "C3 balance should be 0");
        assertEq(userInfo3.lastUpdateBlock, 0, "C3 block should be 0");
        // Remove check for accruedBonus
        // assertEq(userInfo3.accruedBonus, 0, "C3 bonus should be 0");

        address[] memory userCollections = rewardsController.getUserNFTCollections(USER_A);
        assertEq(userCollections.length, 1, "User A should have 1 active collection (C1)");
        assertEq(userCollections[0], NFT_COLLECTION_1, "Active collection should be C1");
    }

    function test_RevertIf_UpdateNFTBalance_NotWhitelisted() public {
        address caller = OWNER;
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(RewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_3, 5);
        vm.stopPrank();
    }

    function test_RevertIf_UpdateNFTBalances_MismatchLengths() public {
        address caller = OWNER;
        address[] memory collections = new address[](2);
        collections[0] = NFT_COLLECTION_1;
        collections[1] = NFT_COLLECTION_2;
        uint256[] memory balances = new uint256[](1); // Mismatched length
        balances[0] = 5;

        vm.startPrank(caller);
        vm.expectRevert(RewardsController.ArrayLengthMismatch.selector);
        rewardsController.updateNFTBalances(USER_A, collections, balances);
        vm.stopPrank();
    }

    // --- Test Reward Calculation (PLACEHOLDER) --- //
    // These tests depend heavily on the final bonus calculation logic

    function test_Placeholder_AccrueBonus() public {
        // Update balance for User A in Collection 1
        uint256 initialBalance = 1;
        vm.prank(OWNER);
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_1, initialBalance);
        vm.stopPrank();
        uint256 blockAfterUpdate = block.number;

        // Warp time
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 10); // Advance 10 blocks
        uint256 blockAfterWarp = block.number;

        // Set mock deposit for USER_A in the mock vault before triggering update
        uint256 mockDepositAmount = 100 ether; // Example deposit
        vm.prank(OWNER);
        mockVault.setDeposit(USER_A, NFT_COLLECTION_1, mockDepositAmount);

        vm.startPrank(OWNER);
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_1, initialBalance);

        // Check accrued bonus
        IRewardsController.UserNFTInfo memory userInfo = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_1);

        console.log("--- test_Placeholder_AccrueBonus Log ---");
        console.log("Block after 1st update:", blockAfterUpdate);
        console.log("Block after warp:", blockAfterWarp);
        console.log("Current block (after 2nd update):", block.number);
        console.log("User Info Last Update Block:", userInfo.lastUpdateBlock);
        console.log("User Info Last NFT Balance:", userInfo.lastNFTBalance);
        console.log("User Info Last Reward Index:", userInfo.lastUserRewardIndex);
        console.log("Beta for Collection1:", rewardsController.getCollectionBeta(NFT_COLLECTION_1));
        console.log("Calculated blockDelta in test:", block.number - blockAfterUpdate);

        // Check that index increased or state changed, bonus is not directly stored
        assertTrue(userInfo.lastUserRewardIndex > 0, "Reward index should have been set"); // Check if index was set initially
            // assertTrue(userInfo.accruedBonus > 0, "Bonus should have accrued");
    }

    // --- Test Claim Functions (PLACEHOLDER) --- //

    function test_Placeholder_ClaimRewardsForCollection() public {
        // Setup: User A has 1 NFT in Collection 1 initially
        uint256 initialBalance = 1;
        // Setup: User A has a deposit in Collection 1
        uint256 userDeposit = 500 ether;
        vm.startPrank(OWNER);
        mockVault.setDeposit(USER_A, NFT_COLLECTION_1, userDeposit);
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_1, initialBalance);
        uint256 blockAfterUpdate = block.number;
        uint256 indexAfterUpdate = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_1).lastUserRewardIndex;
        vm.stopPrank();

        // Warp time
        uint256 blocksToSkip = 10;
        vm.warp(block.timestamp + 100); // Advance timestamp
        vm.roll(block.number + blocksToSkip); // Advance 10 blocks

        // 3. Calculate expected rewards based on contract logic
        // Use the simplified placeholder index update logic
        uint256 potentialGlobalIndex = rewardsController.globalRewardIndex() + blocksToSkip * PRECISION;
        uint256 indexDiff = potentialGlobalIndex - indexAfterUpdate;

        uint256 expectedBase = (userDeposit * indexDiff) / PRECISION;
        uint256 expectedBonus = 0;
        if (initialBalance > 0 && BETA_1 > 0) {
            expectedBonus = (expectedBase * BETA_1) / PRECISION;
        }
        uint256 expectedClaimAmount = expectedBase + expectedBonus;

        // Ensure mock LM has enough funds for the transfer
        vm.startPrank(OWNER);
        rewardToken.transfer(address(mockLM), expectedClaimAmount + 1 ether); // Ensure sufficient balance
        vm.stopPrank();

        // 4. Mock LM transferYield call - This is no longer done by RewardsController, LM balance checked directly
        // mockLM.setExpectedTransferYield(expectedClaimAmount, USER_A, true);

        // 5. Mock NFT Registry call (needed by claim function)
        mockRegistry.setBalance(USER_A, NFT_COLLECTION_1, initialBalance);

        // Fund RewardsController to allow transfer (replace with LM yield pull later)
        vm.prank(OWNER);
        rewardToken.transfer(address(rewardsController), expectedClaimAmount);

        // 6. Claim rewards
        vm.startPrank(USER_A);
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.RewardsClaimedForCollection(USER_A, NFT_COLLECTION_1, expectedClaimAmount);
        rewardsController.claimRewardsForCollection(NFT_COLLECTION_1);
        vm.stopPrank();

        // Verify balance was transferred (check USER_A balance)
        assertEq(rewardToken.balanceOf(USER_A), expectedClaimAmount, "User A reward token balance");
        IRewardsController.UserNFTInfo memory userInfo = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_1);
        // Remove check for accruedBonus
        // assertEq(userInfo.accruedBonus, 0, "Accrued bonus should be 0 after claim");
        assertEq(userInfo.lastUpdateBlock, block.number, "Last update block should be claim block");
        assertEq(userInfo.lastNFTBalance, initialBalance, "NFT balance should be updated during claim");
    }

    // --- Test View Functions --- //

    function test_View_GetPendingRewards() public {
        // 1. Update balance to establish initial state
        uint256 initialNFTBalance = 10;
        uint256 initialDeposit = 1000 ether;
        vm.startPrank(OWNER);
        mockVault.setDeposit(USER_A, NFT_COLLECTION_1, initialDeposit); // SET DEPOSIT
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_1, initialNFTBalance); // Example balance: 10 NFTs
        uint256 indexAfterUpdateView = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_1).lastUserRewardIndex;
        vm.stopPrank();

        uint256 blocksToSkip = 50;
        vm.warp(block.timestamp + blocksToSkip); // Also advance time
        vm.roll(block.number + blocksToSkip); // Use vm.roll explicitly

        // 2. Set registry balance for the view function to read (if needed, depends on _getCurrentNFTBalance impl)
        // mockRegistry.setBalance(USER_A, NFT_COLLECTION_1, 10); // Assuming view doesn't call registry

        // 3. Call getPendingRewards
        (uint256 actualPendingBase, uint256 actualPendingBonus) =
            rewardsController.getPendingRewards(USER_A, NFT_COLLECTION_1);

        // 4. Assert results (using contract placeholder calc)
        // Use the simplified placeholder index update logic for view function
        uint256 potentialGlobalIndexView = rewardsController.globalRewardIndex() + blocksToSkip * PRECISION;
        uint256 indexDiffView = potentialGlobalIndexView - indexAfterUpdateView;

        uint256 expectedBaseView = (initialDeposit * indexDiffView) / PRECISION;
        uint256 expectedBonusView = 50000 ether; // Corrected: (Base * (10 * 0.1e18)) / 1e18 = 50000e18

        // Calculate expected bonus using the calculated boost factor
        uint256 beta = rewardsController.getCollectionBeta(NFT_COLLECTION_1);
        uint256 boostFactor = rewardsController.calculateBoost(initialNFTBalance, beta);
        uint256 expectedPendingBonus = (expectedBaseView * boostFactor) / PRECISION;

        // Assertions
        assertEq(actualPendingBase, expectedBaseView, "Pending base mismatch");
        assertEq(actualPendingBonus, expectedPendingBonus, "Pending bonus mismatch");
    }

    function test_View_GetUserNFTInfo() public {
        vm.prank(OWNER);
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_1, 15);
        IRewardsController.UserNFTInfo memory info = rewardsController.getUserNFTInfo(USER_A, NFT_COLLECTION_1);
        assertEq(info.lastNFTBalance, 15);
        assertEq(info.lastUpdateBlock, block.number);
        // Remove check for accruedBonus
        // assertEq(info.accruedBonus, 0);
    }

    function test_View_GetWhitelistedCollections() public view {
        address[] memory collections = rewardsController.getWhitelistedCollections();
        assertEq(collections.length, 2);
        assertTrue(collections.contains(NFT_COLLECTION_1));
        assertTrue(collections.contains(NFT_COLLECTION_2));
    }

    function test_View_GetCollectionBeta() public view {
        assertEq(rewardsController.getCollectionBeta(NFT_COLLECTION_1), BETA_1);
        assertEq(rewardsController.getCollectionBeta(NFT_COLLECTION_2), BETA_2);
    }

    function test_View_RevertIf_GetCollectionBeta_NotWhitelisted() public {
        vm.expectRevert(abi.encodeWithSelector(RewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.getCollectionBeta(NFT_COLLECTION_3);
    }

    function test_View_GetUserNFTCollections() public {
        assertEq(rewardsController.getUserNFTCollections(USER_A).length, 0, "Initial user collections should be empty");

        vm.prank(OWNER);
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_1, 1);
        vm.prank(OWNER);
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_2, 5);
        // Update C1 again
        vm.prank(OWNER);
        rewardsController.updateNFTBalance(USER_A, NFT_COLLECTION_1, 2);

        address[] memory userCols = rewardsController.getUserNFTCollections(USER_A);
        assertEq(userCols.length, 2, "User collection count mismatch");
        assertTrue(userCols.contains(NFT_COLLECTION_1));
        assertTrue(userCols.contains(NFT_COLLECTION_2));
    }
}
