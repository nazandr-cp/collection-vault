// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {RewardsController} from "../../../src/RewardsController.sol";
import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";

contract RewardsController_View is RewardsController_Test_Base {
    // --- View Function Tests ---

    function test_GetUserCollectionTracking() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, address(mockERC721), block1, 2, 100 ether); // Use mock address
        uint256 block2 = block.number + 1;
        vm.roll(block2);
        _processSingleUserUpdate(USER_A, address(mockERC721_2), block2, 1, 50 ether); // Use mock address

        address[] memory collections = new address[](2);
        collections[0] = address(mockERC721); // Use mock address
        collections[1] = address(mockERC721_2); // Use mock address

        IRewardsController.UserCollectionTracking[] memory tracking =
            rewardsController.getUserCollectionTracking(USER_A, collections);

        assertEq(tracking.length, 2);
        // Collection 1
        assertEq(tracking[0].lastUpdateBlock, block1);
        assertEq(tracking[0].lastNFTBalance, 2);
        assertEq(tracking[0].lastBalance, 100 ether);
        assertTrue(tracking[0].lastUserRewardIndex > 0);
        // Collection 2
        assertEq(tracking[1].lastUpdateBlock, block2);
        assertEq(tracking[1].lastNFTBalance, 1);
        assertEq(tracking[1].lastBalance, 50 ether);
        assertTrue(tracking[1].lastUserRewardIndex > 0);
    }

    function test_Revert_GetUserCollectionTracking_EmptyArray() public {
        address[] memory collections; // Empty
        vm.expectRevert(IRewardsController.CollectionsArrayEmpty.selector);
        rewardsController.getUserCollectionTracking(USER_A, collections);
    }

    function test_GetCollectionBeta() public view {
        assertEq(rewardsController.getCollectionBeta(address(mockERC721)), BETA_1); // Use mock address
        assertEq(rewardsController.getCollectionBeta(address(mockERC721_2)), BETA_2); // Use mock address
    }

    function test_Revert_GetCollectionBeta() public {
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.getCollectionBeta(NFT_COLLECTION_3); // Keep non-whitelisted constant
    }

    function test_GetCollectionRewardBasis() public view {
        assertEq(
            uint256(rewardsController.getCollectionRewardBasis(address(mockERC721))), // Use mock address
            uint256(IRewardsController.RewardBasis.BORROW)
        );
        assertEq(
            uint256(rewardsController.getCollectionRewardBasis(address(mockERC721_2))), // Use mock address
            uint256(IRewardsController.RewardBasis.DEPOSIT)
        );
    }

    function test_Revert_GetCollectionRewardBasis_NotWhitelisted() public {
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.getCollectionRewardBasis(NFT_COLLECTION_3); // Keep non-whitelisted constant
    }

    function test_GetUserNFTCollections() public {
        // No collections initially
        address[] memory active0 = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active0.length, 0);

        // Add one collection
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, address(mockERC721), block1, 1, 10 ether); // Use mock address
        address[] memory active1 = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active1.length, 1);
        assertEq(active1[0], address(mockERC721)); // Use mock address

        // Add another collection
        uint256 block2 = block.number + 1;
        vm.roll(block2);
        _processSingleUserUpdate(USER_A, address(mockERC721_2), block2, 1, 10 ether); // Use mock address
        address[] memory active2 = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active2.length, 2);
        // Order might not be guaranteed, check for presence
        assertTrue(active2[0] == address(mockERC721) || active2[1] == address(mockERC721)); // Use mock address
        assertTrue(active2[0] == address(mockERC721_2) || active2[1] == address(mockERC721_2)); // Use mock address

        // Remove one collection by zeroing balance/nft
        uint256 block3 = block.number + 1;
        vm.roll(block3);
        _processSingleUserUpdate(USER_A, address(mockERC721), block3, -1, -10 ether); // Use mock address
        address[] memory active3 = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active3.length, 1);
        assertEq(active3[0], address(mockERC721_2)); // Use mock address
    }

    function test_IsCollectionWhitelisted() public view {
        assertTrue(rewardsController.isCollectionWhitelisted(address(mockERC721))); // Use mock address
        assertTrue(rewardsController.isCollectionWhitelisted(address(mockERC721_2))); // Use mock address
        assertFalse(rewardsController.isCollectionWhitelisted(NFT_COLLECTION_3)); // Keep non-whitelisted constant
    }

    function test_GetWhitelistedCollections() public {
        address[] memory whitelisted = rewardsController.getWhitelistedCollections();
        assertEq(whitelisted.length, 2); // Initially added 2
        // Order might not be guaranteed
        assertTrue(whitelisted[0] == address(mockERC721) || whitelisted[1] == address(mockERC721)); // Use mock address
        assertTrue(whitelisted[0] == address(mockERC721_2) || whitelisted[1] == address(mockERC721_2)); // Use mock address

        // Add another
        vm.startPrank(OWNER);
        rewardsController.addNFTCollection(
            NFT_COLLECTION_3, BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
        );
        vm.stopPrank();
        whitelisted = rewardsController.getWhitelistedCollections();
        assertEq(whitelisted.length, 3);
        // Check for all three now
        bool found1 = false;
        bool found2 = false;
        bool found3 = false;
        for (uint256 i = 0; i < whitelisted.length; i++) {
            if (whitelisted[i] == address(mockERC721)) found1 = true;
            if (whitelisted[i] == address(mockERC721_2)) found2 = true;
            if (whitelisted[i] == NFT_COLLECTION_3) found3 = true;
        }
        assertTrue(found1 && found2 && found3, "Did not find all whitelisted collections");
    }

    function test_UserNFTData() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, address(mockERC721), block1, 2, 100 ether); // Use mock address

        // (
        //     uint256 lastRewardIndex,
        //     uint256 accruedReward,
        //     uint256 lastNFTBalance,
        //     uint256 lastBalance,
        //     uint256 lastUpdateBlock
        // ) = rewardsController.userNFTData(USER_A, address(mockERC721)); // Use mock address
        RewardsController.UserRewardState memory state =
            rewardsController.getUserRewardState(USER_A, address(mockERC721));

        assertTrue(state.lastRewardIndex > 0);
        assertEq(state.accruedReward, 0);
        assertEq(state.lastNFTBalance, 2);
        assertEq(state.lastBalance, 100 ether);
        assertEq(state.lastUpdateBlock, block1);
    }

    function test_CollectionRewardSharePercentages_Success() public {
        // Collection 1 added in setUp with VALID_REWARD_SHARE_PERCENTAGE
        assertEq(
            rewardsController.getCollectionRewardSharePercentage(address(mockERC721)), // Use new getter
            VALID_REWARD_SHARE_PERCENTAGE,
            "Share percentage mismatch for collection 1"
        );
        // Collection 2 added in setUp with VALID_REWARD_SHARE_PERCENTAGE
        assertEq(
            rewardsController.getCollectionRewardSharePercentage(address(mockERC721_2)), // Use new getter
            VALID_REWARD_SHARE_PERCENTAGE,
            "Share percentage mismatch for collection 2"
        );
        // Non-whitelisted collection should revert or return 0 depending on implementation.
        // The current getter `getCollectionRewardSharePercentage` has `onlyWhitelistedCollection` modifier.
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.getCollectionRewardSharePercentage(NFT_COLLECTION_3); // This should revert
    }

    function test_UserNFTData_Initial() public view {
        // Check data for a user and collection that have had no interactions
        // (
        //     uint256 lastRewardIndex,
        //     uint256 accruedReward,
        //     uint256 lastNFTBalance,
        //     uint256 lastBalance,
        //     uint256 lastUpdateBlock
        // ) = rewardsController.userNFTData(USER_C, address(mockERC721)); // USER_C has no activity, use mock address
        RewardsController.UserRewardState memory state1 =
            rewardsController.getUserRewardState(USER_C, address(mockERC721));

        assertEq(state1.lastRewardIndex, 0, "Initial lastRewardIndex should be 0");
        assertEq(state1.accruedReward, 0, "Initial accruedReward should be 0");
        assertEq(state1.lastNFTBalance, 0, "Initial lastNFTBalance should be 0");
        assertEq(state1.lastBalance, 0, "Initial lastBalance should be 0");
        assertEq(state1.lastUpdateBlock, 0, "Initial lastUpdateBlock should be 0");

        // Also check for a whitelisted collection the user hasn't interacted with
        // (lastRewardIndex, accruedReward, lastNFTBalance, lastBalance, lastUpdateBlock) =
        //     rewardsController.userNFTData(USER_A, address(mockERC721_2)); // USER_A hasn't interacted with C2 yet, use mock address
        RewardsController.UserRewardState memory state2 =
            rewardsController.getUserRewardState(USER_A, address(mockERC721_2));

        assertEq(state2.lastRewardIndex, 0, "Initial lastRewardIndex for C2 should be 0");
        assertEq(state2.accruedReward, 0, "Initial accruedReward for C2 should be 0");
        assertEq(state2.lastNFTBalance, 0, "Initial lastNFTBalance for C2 should be 0");
        assertEq(state2.lastBalance, 0, "Initial lastBalance for C2 should be 0");
        assertEq(state2.lastUpdateBlock, 0, "Initial lastUpdateBlock for C2 should be 0");
    }
}

// Minimal Mock ERC20 for testing Vault mismatch
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
    // Implement other IERC20 functions as needed (can be empty for this test)

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}
