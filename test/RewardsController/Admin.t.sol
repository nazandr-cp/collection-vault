// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "./RewardsController_Test_Base.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";
import {MockERC721} from "../../src/mocks/MockERC721.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract AdminTest is RewardsController_Test_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Admin_UpdateTrustedSigner_Success() public {
        address oldSigner = rewardsController.claimSigner();
        address newSigner = NEW_UPDATER;

        vm.expectEmit(true, true, true, true);
        emit IRewardsController.TrustedSignerUpdated(oldSigner, newSigner, ADMIN);

        vm.startPrank(ADMIN);
        rewardsController.updateTrustedSigner(newSigner);
        vm.stopPrank();

        assertEq(rewardsController.claimSigner(), newSigner, "Trusted signer should be updated");
    }

    function test_Admin_UpdateTrustedSigner_Revert_NotOwner() public {
        address newSigner = NEW_UPDATER;

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER_A));
        vm.startPrank(USER_A);
        rewardsController.updateTrustedSigner(newSigner);
        vm.stopPrank();
    }

    function test_Admin_UpdateTrustedSigner_Revert_ZeroAddress() public {
        vm.expectRevert(IRewardsController.CannotSetSignerToZeroAddress.selector);
        vm.startPrank(ADMIN);
        rewardsController.updateTrustedSigner(address(0));
        vm.stopPrank();
    }

    function test_Admin_UpdateTrustedSigner_Idempotent() public {
        address newSigner = NEW_UPDATER;

        vm.startPrank(ADMIN);
        rewardsController.updateTrustedSigner(newSigner);
        assertEq(rewardsController.claimSigner(), newSigner, "Trusted signer should be updated on first call");

        // Call again with the same signer
        vm.expectEmit(true, true, true, true);
        emit IRewardsController.TrustedSignerUpdated(newSigner, newSigner, ADMIN);
        rewardsController.updateTrustedSigner(newSigner);
        vm.stopPrank();

        assertEq(
            rewardsController.claimSigner(), newSigner, "Trusted signer should remain the same on subsequent calls"
        );
    }

    function test_Admin_WhitelistCollection_ERC165_ERC721_Success() public {
        MockERC721 erc721Mock = new MockERC721("Test NFT", "TNFT");
        address collectionAddress = address(erc721Mock);

        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            collectionAddress, IRewardsController.CollectionType.ERC721, IRewardsController.RewardBasis.DEPOSIT, 1000
        );
        vm.stopPrank();

        assertTrue(rewardsController.isCollectionWhitelisted(collectionAddress), "Collection should be whitelisted");
    }

    function test_Admin_WhitelistCollection_ERC165_ERC1155_Success() public {
        // Mock ERC1155 contract (assuming it supports IERC1155 interfaceId)
        // For simplicity, we'll use a MockERC721 and manually make it support ERC1155 interface for testing
        MockERC721 erc1155Mock = new MockERC721("Test ERC1155", "T1155");
        address collectionAddress = address(erc1155Mock);

        // Manually set that this mock supports IERC1155 interface for testing purposes
        // In a real scenario, this would be a proper ERC1155 mock.
        vm.mockCall(
            collectionAddress,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IERC1155).interfaceId),
            abi.encode(true)
        );

        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            collectionAddress, IRewardsController.CollectionType.ERC1155, IRewardsController.RewardBasis.DEPOSIT, 1000
        );
        vm.stopPrank();

        assertTrue(rewardsController.isCollectionWhitelisted(collectionAddress), "Collection should be whitelisted");
    }

    function test_Admin_WhitelistCollection_ERC165_ERC721_Revert_InvalidInterface() public {
        // Deploy a contract that does NOT support ERC721 interface
        MockERC20 nonNftContract = new MockERC20("Non-NFT", "NNFT", 18, 1000);
        address collectionAddress = address(nonNftContract);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardsController.InvalidCollectionInterface.selector, collectionAddress, type(IERC721).interfaceId
            )
        );
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            collectionAddress, IRewardsController.CollectionType.ERC721, IRewardsController.RewardBasis.DEPOSIT, 1000
        );
        vm.stopPrank();
    }

    function test_Admin_WhitelistCollection_ERC165_ERC1155_Revert_InvalidInterface() public {
        // Deploy a contract that does NOT support ERC1155 interface
        MockERC20 nonNftContract = new MockERC20("Non-NFT", "NNFT", 18, 1000);
        address collectionAddress = address(nonNftContract);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardsController.InvalidCollectionInterface.selector, collectionAddress, type(IERC1155).interfaceId
            )
        );
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            collectionAddress, IRewardsController.CollectionType.ERC1155, IRewardsController.RewardBasis.DEPOSIT, 1000
        );
        vm.stopPrank();
    }
}
