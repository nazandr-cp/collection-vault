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
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 2, 100 ether);
        uint256 block2 = block.number + 1;
        vm.roll(block2);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_2, block2, 1, 50 ether);

        address[] memory collections = new address[](2);
        collections[0] = NFT_COLLECTION_1;
        collections[1] = NFT_COLLECTION_2;

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
        assertEq(rewardsController.getCollectionBeta(NFT_COLLECTION_1), BETA_1);
    }

    function test_Revert_GetCollectionBeta() public {
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.getCollectionBeta(NFT_COLLECTION_3);
    }

    function test_GetCollectionRewardBasis() public view {
        assertEq(
            uint256(rewardsController.getCollectionRewardBasis(NFT_COLLECTION_1)),
            uint256(IRewardsController.RewardBasis.BORROW)
        );
        assertEq(
            uint256(rewardsController.getCollectionRewardBasis(NFT_COLLECTION_2)),
            uint256(IRewardsController.RewardBasis.DEPOSIT)
        );
    }

    function test_Revert_GetCollectionRewardBasis_NotWhitelisted() public {
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.getCollectionRewardBasis(NFT_COLLECTION_3);
    }

    function test_GetUserNFTCollections() public {
        // No collections initially
        address[] memory active0 = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active0.length, 0);

        // Add one collection
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 1, 10 ether);
        address[] memory active1 = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active1.length, 1);
        assertEq(active1[0], NFT_COLLECTION_1);

        // Add another collection
        uint256 block2 = block.number + 1;
        vm.roll(block2);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_2, block2, 1, 10 ether);
        address[] memory active2 = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active2.length, 2);
        // Order might not be guaranteed, check for presence
        assertTrue(active2[0] == NFT_COLLECTION_1 || active2[1] == NFT_COLLECTION_1);
        assertTrue(active2[0] == NFT_COLLECTION_2 || active2[1] == NFT_COLLECTION_2);

        // Remove one collection by zeroing balance/nft
        uint256 block3 = block.number + 1;
        vm.roll(block3);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block3, -1, -10 ether);
        address[] memory active3 = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active3.length, 1);
        assertEq(active3[0], NFT_COLLECTION_2);
    }

    function test_IsCollectionWhitelisted() public view {
        assertTrue(rewardsController.isCollectionWhitelisted(NFT_COLLECTION_1));
        assertFalse(rewardsController.isCollectionWhitelisted(NFT_COLLECTION_3));
    }

    function test_GetWhitelistedCollections() public {
        address[] memory whitelisted = rewardsController.getWhitelistedCollections();
        assertEq(whitelisted.length, 2); // Initially added 2
        // Order might not be guaranteed
        assertTrue(whitelisted[0] == NFT_COLLECTION_1 || whitelisted[1] == NFT_COLLECTION_1);
        assertTrue(whitelisted[0] == NFT_COLLECTION_2 || whitelisted[1] == NFT_COLLECTION_2);

        // Add another
        vm.startPrank(OWNER);
        rewardsController.addNFTCollection(
            NFT_COLLECTION_3, BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
        );
        vm.stopPrank();
        whitelisted = rewardsController.getWhitelistedCollections();
        assertEq(whitelisted.length, 3);
    }

    function test_UserNFTData() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, 2, 100 ether);

        (
            uint256 lastRewardIndex,
            uint256 accruedReward,
            uint256 lastNFTBalance,
            uint256 lastBalance,
            uint256 lastUpdateBlock
        ) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        assertTrue(lastRewardIndex > 0);
        assertEq(accruedReward, 0);
        assertEq(lastNFTBalance, 2);
        assertEq(lastBalance, 100 ether);
        assertEq(lastUpdateBlock, block1);
    }

    function test_CollectionRewardSharePercentages_Success() public view {
        // Collection 1 added in setUp with VALID_REWARD_SHARE_PERCENTAGE
        assertEq(
            rewardsController.collectionRewardSharePercentages(NFT_COLLECTION_1),
            VALID_REWARD_SHARE_PERCENTAGE,
            "Share percentage mismatch for collection 1"
        );
        // Collection 2 added in setUp with VALID_REWARD_SHARE_PERCENTAGE
        assertEq(
            rewardsController.collectionRewardSharePercentages(NFT_COLLECTION_2),
            VALID_REWARD_SHARE_PERCENTAGE,
            "Share percentage mismatch for collection 2"
        );
        // Non-whitelisted collection should have 0 share
        assertEq(
            rewardsController.collectionRewardSharePercentages(NFT_COLLECTION_3),
            0,
            "Share percentage should be 0 for non-whitelisted"
        );
    }

    function test_UserNFTData_Initial() public view {
        // Check data for a user and collection that have had no interactions
        (
            uint256 lastRewardIndex,
            uint256 accruedReward,
            uint256 lastNFTBalance,
            uint256 lastBalance,
            uint256 lastUpdateBlock
        ) = rewardsController.userNFTData(USER_C, NFT_COLLECTION_1); // USER_C has no activity

        assertEq(lastRewardIndex, 0, "Initial lastRewardIndex should be 0");
        assertEq(accruedReward, 0, "Initial accruedReward should be 0");
        assertEq(lastNFTBalance, 0, "Initial lastNFTBalance should be 0");
        assertEq(lastBalance, 0, "Initial lastBalance should be 0");
        assertEq(lastUpdateBlock, 0, "Initial lastUpdateBlock should be 0");

        // Also check for a whitelisted collection the user hasn't interacted with
        (lastRewardIndex, accruedReward, lastNFTBalance, lastBalance, lastUpdateBlock) =
            rewardsController.userNFTData(USER_A, NFT_COLLECTION_2); // Assume USER_A hasn't interacted with C2 yet

        assertEq(lastRewardIndex, 0, "Initial lastRewardIndex for C2 should be 0");
        assertEq(accruedReward, 0, "Initial accruedReward for C2 should be 0");
        assertEq(lastNFTBalance, 0, "Initial lastNFTBalance for C2 should be 0");
        assertEq(lastBalance, 0, "Initial lastBalance for C2 should be 0");
        assertEq(lastUpdateBlock, 0, "Initial lastUpdateBlock for C2 should be 0");
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
