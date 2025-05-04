// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";

contract RewardsController_Admin is RewardsController_Test_Base {
    // --- Admin Function Tests ---

    // --- setAuthorizedUpdater ---
    function test_Revert_SetAuthorizedUpdater_NotOwner() public virtual {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.setAuthorizedUpdater(NEW_UPDATER);
        vm.stopPrank();
    }

    function test_Revert_SetAuthorizedUpdater_ZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.setAuthorizedUpdater(address(0));
        vm.stopPrank();
    }

    // --- addNFTCollection ---
    function test_Revert_AddNFTCollection_NotOwner() public {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.addNFTCollection(
            NFT_COLLECTION_3, BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
        );
        vm.stopPrank();
    }

    function test_Revert_AddNFTCollection_ZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.addNFTCollection(
            address(0), BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
        );
        vm.stopPrank();
    }

    function test_Revert_AddNFTCollection_AlreadyExists() public {
        vm.startPrank(OWNER);
        // Use the actual whitelisted mock address
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionAlreadyExists.selector, address(mockERC721)));
        rewardsController.addNFTCollection(
            address(mockERC721), BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
        );
        vm.stopPrank();
    }

    function test_Revert_AddNFTCollection_InvalidSharePercentage() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(
            NFT_COLLECTION_3, BETA_1, IRewardsController.RewardBasis.BORROW, INVALID_REWARD_SHARE_PERCENTAGE
        );
        vm.stopPrank();
    }

    // --- removeNFTCollection ---
    function test_Revert_RemoveNFTCollection_NotOwner() public {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        // Use the actual whitelisted mock address
        rewardsController.removeNFTCollection(address(mockERC721));
        vm.stopPrank();
    }

    function test_Revert_RemoveNFTCollection_NotWhitelisted() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.removeNFTCollection(NFT_COLLECTION_3);
        vm.stopPrank();
    }

    // --- updateBeta ---
    function test_Revert_UpdateBeta_NotOwner() public {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        // Use the actual whitelisted mock address
        rewardsController.updateBeta(address(mockERC721), 0.15 ether);
        vm.stopPrank();
    }

    function test_Revert_UpdateBeta_NotWhitelisted() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.updateBeta(NFT_COLLECTION_3, 0.15 ether);
        vm.stopPrank();
    }

    // --- setCollectionRewardSharePercentage ---

    function test_Revert_SetCollectionRewardSharePercentage_NotOwner() public {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        // Use the actual whitelisted mock address
        rewardsController.setCollectionRewardSharePercentage(address(mockERC721), 7500);
        vm.stopPrank();
    }

    function test_Revert_SetCollectionRewardSharePercentage_NotWhitelisted() public {
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.setCollectionRewardSharePercentage(NFT_COLLECTION_3, 7500);
        vm.stopPrank();
    }

    function test_Revert_SetCollectionRewardSharePercentage_InvalidPercentage() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        // Use the actual whitelisted mock address
        rewardsController.setCollectionRewardSharePercentage(address(mockERC721), INVALID_REWARD_SHARE_PERCENTAGE);
        vm.stopPrank();
    }

    // --- setEpochDuration ---
    function test_Revert_SetEpochDuration_NotOwner() public {
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.setEpochDuration(86400);
        vm.stopPrank();
    }

    function test_Revert_SetEpochDuration_ZeroDuration() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IRewardsController.InvalidEpochDuration.selector);
        rewardsController.setEpochDuration(0);
        vm.stopPrank();
    }

    // --- Admin Functions (Happy Path - As per todo_initialization_admin_view.md) ---

    function test_SetAuthorizedUpdater_Success() public {
        vm.startPrank(OWNER);
        address oldUpdater = rewardsController.authorizedUpdater();
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.AuthorizedUpdaterChanged(oldUpdater, NEW_UPDATER);
        rewardsController.setAuthorizedUpdater(NEW_UPDATER);
        assertEq(rewardsController.authorizedUpdater(), NEW_UPDATER);
        vm.stopPrank();
    }

    function test_AddNFTCollection_Success() public {
        vm.startPrank(OWNER);
        uint256 beta = 0.08 ether;
        IRewardsController.RewardBasis basis = IRewardsController.RewardBasis.DEPOSIT;
        uint256 share = 8000; // 80%
        // Use a different collection address to avoid conflict with existing tests/setup
        address NEW_COLLECTION = address(0xC4);
        vm.label(NEW_COLLECTION, "NEW_COLLECTION_FOR_TEST");

        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.NFTCollectionAdded(NEW_COLLECTION, beta, basis, share);
        rewardsController.addNFTCollection(NEW_COLLECTION, beta, basis, share);

        assertTrue(rewardsController.isCollectionWhitelisted(NEW_COLLECTION));
        assertEq(rewardsController.getCollectionBeta(NEW_COLLECTION), beta);
        assertEq(uint256(rewardsController.getCollectionRewardBasis(NEW_COLLECTION)), uint256(basis));
        assertEq(rewardsController.collectionRewardSharePercentages(NEW_COLLECTION), share);
        vm.stopPrank();
    }

    function test_RemoveNFTCollection_Success() public {
        vm.startPrank(OWNER);
        // Use the actual whitelisted mock address
        address collectionToRemove = address(mockERC721);
        assertTrue(rewardsController.isCollectionWhitelisted(collectionToRemove));
        vm.expectEmit(true, true, false, false, address(rewardsController)); // Only collection is indexed
        emit IRewardsController.NFTCollectionRemoved(collectionToRemove);
        rewardsController.removeNFTCollection(collectionToRemove);
        assertFalse(rewardsController.isCollectionWhitelisted(collectionToRemove));
        // Check associated state is deleted (should revert or return 0)
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collectionToRemove));
        rewardsController.getCollectionBeta(collectionToRemove);
        assertEq(rewardsController.collectionRewardSharePercentages(collectionToRemove), 0);
        vm.stopPrank();
    }

    function test_UpdateBeta_Success() public {
        vm.startPrank(OWNER);
        // Use the actual whitelisted mock address
        address collectionToUpdate = address(mockERC721);
        uint256 oldBeta = rewardsController.getCollectionBeta(collectionToUpdate);
        uint256 newBeta = 0.15 ether; // 15%
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.BetaUpdated(collectionToUpdate, oldBeta, newBeta);
        rewardsController.updateBeta(collectionToUpdate, newBeta);
        assertEq(rewardsController.getCollectionBeta(collectionToUpdate), newBeta);
        vm.stopPrank();
    }

    function test_SetCollectionRewardSharePercentage_Success() public {
        vm.startPrank(OWNER);
        // Use the actual whitelisted mock address
        address collectionToUpdate = address(mockERC721);
        uint256 oldShare = rewardsController.collectionRewardSharePercentages(collectionToUpdate);
        uint256 newShare = 7500; // 75%
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.CollectionRewardShareUpdated(collectionToUpdate, oldShare, newShare);
        rewardsController.setCollectionRewardSharePercentage(collectionToUpdate, newShare);
        assertEq(rewardsController.collectionRewardSharePercentages(collectionToUpdate), newShare);
        vm.stopPrank();
    }

    function test_SetEpochDuration_Success() public {
        vm.startPrank(OWNER);
        // uint256 oldDuration = rewardsController.epochDuration();
        uint256 newDuration = 86400; // 1 day
        // No specific event for epoch duration change in the interface/contract
        rewardsController.setEpochDuration(newDuration);
        assertEq(rewardsController.epochDuration(), newDuration);
        vm.stopPrank();
    }
}
