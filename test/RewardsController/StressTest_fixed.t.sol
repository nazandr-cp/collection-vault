// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "./RewardsController_Test_Base.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";
import {MockERC721} from "../../src/mocks/MockERC721.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title StressTest
 * @notice Performs stress testing scenarios for the RewardsController
 * @dev Tests extreme scenarios, high loads, and performance under varying conditions
 */
contract StressTest is RewardsController_Test_Base {
    using Strings for uint256;
    // Define constants for stress testing

    uint256 constant NUM_COLLECTIONS = 5; // Number of collections to test with
    uint256 constant NUM_USERS = 10; // Number of users to test with
    uint256 constant NFT_PER_USER = 20; // Number of NFTs per user
    uint256 constant BLOCKS_TO_ADVANCE = 1000; // Number of blocks to advance for reward accrual
    uint256 constant YIELD_AMOUNT = 1000 ether; // Amount of yield to add

    // Arrays to track test data
    address[] public collections;
    address[] public users;

    function setUp() public override {
        super.setUp();

        // Create collections
        for (uint256 i = 0; i < NUM_COLLECTIONS; i++) {
            MockERC721 mockNFT = new MockERC721(
                string(abi.encodePacked("Mock NFT ", i.toString())), string(abi.encodePacked("MNFT", i.toString()))
            );
            collections.push(address(mockNFT));
        }

        // Create user addresses
        for (uint256 i = 0; i < NUM_USERS; i++) {
            users.push(address(uint160(uint256(keccak256(abi.encodePacked("user", i))))));
        }
    }

    /**
     * @notice Tests system performance with multiple collections and many users
     * @dev Creates a complex system state and measures performance of key operations
     */
    function test_StressTest_MultiCollectionManyUsers() public {
        uint256 gasStart;
        uint256 gasUsed;

        // Step 1: Whitelist multiple collections with varying percentages
        vm.startPrank(ADMIN);
        uint16 sharePercentage = uint16(10000 / NUM_COLLECTIONS); // Equal distribution

        gasStart = gasleft();
        for (uint256 i = 0; i < NUM_COLLECTIONS; i++) {
            rewardsController.whitelistCollection(
                collections[i],
                IRewardsController.CollectionType.ERC721,
                IRewardsController.RewardBasis.DEPOSIT,
                sharePercentage
            );
        }
        gasUsed = gasStart - gasleft();
        console.log("Gas used to whitelist %d collections: %d", NUM_COLLECTIONS, gasUsed);

        // Step 2: Mint NFTs to users across collections
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];

            for (uint256 j = 0; j < NUM_COLLECTIONS; j++) {
                MockERC721 nft = MockERC721(collections[j]);

                for (uint256 k = 1; k <= NFT_PER_USER; k++) {
                    uint256 tokenId = i * 1000 + j * 100 + k;
                    nft.mintSpecific(user, tokenId);
                }
            }
        }
        vm.stopPrank();

        // Step 3: Sync all user accounts for all collections
        gasStart = gasleft();
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];

            vm.startPrank(user);
            for (uint256 j = 0; j < NUM_COLLECTIONS; j++) {
                rewardsController.syncAccount(user, collections[j]);
            }
            vm.stopPrank();
        }
        gasUsed = gasStart - gasleft();
        console.log("Gas used to sync %d users across %d collections: %d", NUM_USERS, NUM_COLLECTIONS, gasUsed);

        // Step 4: Add significant yield and advance blocks
        vm.startPrank(ADMIN);
        mockERC20.mint(address(tokenVault), YIELD_AMOUNT);
        vm.stopPrank();
        vm.roll(block.number + BLOCKS_TO_ADVANCE);

        // Step 5: Refresh rewards
        vm.startPrank(AUTHORIZED_UPDATER);
        gasStart = gasleft();
        rewardsController.refreshRewardPerBlock(address(tokenVault));
        gasUsed = gasStart - gasleft();
        console.log("Gas used for refreshRewardPerBlock with many users: %d", gasUsed);
        vm.stopPrank();

        // Step 6: Test claim for each user
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];

            // For each user, create claim for one collection
            IRewardsController.Claim[] memory claims = new IRewardsController.Claim[](1);
            claims[0] = IRewardsController.Claim({
                account: user,
                collection: collections[0], // Use first collection for simplicity
                secondsUser: 0,
                secondsColl: 0,
                incRPS: 0,
                yieldSlice: 0,
                nonce: rewardsController.userNonce(address(tokenVault), user),
                deadline: block.timestamp + 1000
            });

            // Sign the claim
            bytes32 domainSeparator = _buildDomainSeparator();
            // The contract expects just the hash of the claims array directly, not with the ClaimBatch typehash
            bytes32 structHash = keccak256(abi.encode(claims));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(UPDATER_PRIVATE_KEY, digest);
            bytes memory signature = abi.encodePacked(r, s, v);

            vm.startPrank(user);
            gasStart = gasleft();
            rewardsController.claimLazy(claims, signature);
            gasUsed = gasStart - gasleft();
            vm.stopPrank();

            console.log("Gas used for claim by user %d: %d", i, gasUsed);
        }
    }

    /**
     * @notice Tests performance with varying numbers of claims
     * @dev Measures gas usage scaling with claim batch size
     */
    function test_StressTest_ClaimBatchSizeScaling() public {
        // Setup a collection and user with NFTs
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            address(mockERC721), IRewardsController.CollectionType.ERC721, IRewardsController.RewardBasis.DEPOSIT, 10000
        );

        // Mint many NFTs to user for high weight
        for (uint256 i = 1; i <= 50; i++) {
            mockERC721.mintSpecific(USER_A, i);
        }
        vm.stopPrank();

        // Sync the user's account
        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721));
        vm.stopPrank();

        // Add yield and advance blocks
        vm.startPrank(ADMIN);
        mockERC20.mint(address(tokenVault), 1000 ether);
        vm.stopPrank();
        vm.roll(block.number + 1000);

        // Refresh rewards
        vm.startPrank(AUTHORIZED_UPDATER);
        rewardsController.refreshRewardPerBlock(address(tokenVault));
        vm.stopPrank();

        // Test with different claim batch sizes
        uint256[] memory batchSizes = new uint256[](5);
        batchSizes[0] = 1;
        batchSizes[1] = 5;
        batchSizes[2] = 10;
        batchSizes[3] = 20;
        batchSizes[4] = 50; // This is quite large for Ethereum transactions

        for (uint256 b = 0; b < batchSizes.length; b++) {
            uint256 batchSize = batchSizes[b];
            IRewardsController.Claim[] memory claims = new IRewardsController.Claim[](batchSize);

            // Create the claim batch
            for (uint256 i = 0; i < batchSize; i++) {
                claims[i] = IRewardsController.Claim({
                    account: USER_A,
                    collection: address(mockERC721),
                    secondsUser: 0,
                    secondsColl: 0,
                    incRPS: 0,
                    yieldSlice: 0,
                    nonce: rewardsController.userNonce(address(tokenVault), USER_A) + i,
                    deadline: block.timestamp + 1000
                });
            }

            // Sign the batch
            bytes32 domainSeparator = _buildDomainSeparator();
            // The contract expects just the hash of the claims array directly, not with the ClaimBatch typehash
            bytes32 structHash = keccak256(abi.encode(claims));
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(UPDATER_PRIVATE_KEY, digest);
            bytes memory signature = abi.encodePacked(r, s, v);

            // Measure gas for this batch size
            uint256 gasStart = gasleft();

            vm.startPrank(USER_A);
            rewardsController.claimLazy(claims, signature);
            vm.stopPrank();

            uint256 gasUsed = gasStart - gasleft();
            console.log("Batch size %d claims - Gas used: %d", batchSize, gasUsed);

            // Reset state for next test by adding more yield
            vm.startPrank(ADMIN);
            mockERC20.mint(address(tokenVault), 1000 ether);
            vm.stopPrank();
            vm.roll(block.number + 100);

            vm.startPrank(AUTHORIZED_UPDATER);
            rewardsController.refreshRewardPerBlock(address(tokenVault));
            vm.stopPrank();
        }
    }

    /**
     * @notice Tests timestamp dependencies in claimLazy
     * @dev Verifies correct behavior with varying timestamps and deadlines
     */
    function test_TimestampDependencies_ClaimDeadlines() public {
        // Setup
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            address(mockERC721), IRewardsController.CollectionType.ERC721, IRewardsController.RewardBasis.DEPOSIT, 10000
        );
        mockERC721.mintSpecific(USER_A, 1);
        vm.stopPrank();

        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721));
        vm.stopPrank();

        // Add yield and refresh
        vm.startPrank(ADMIN);
        mockERC20.mint(address(tokenVault), 10 ether);
        vm.stopPrank();
        vm.roll(block.number + 100);

        vm.startPrank(AUTHORIZED_UPDATER);
        rewardsController.refreshRewardPerBlock(address(tokenVault));
        vm.stopPrank();

        // Test with different timestamp scenarios

        // Case 1: Current time exactly at deadline
        IRewardsController.Claim[] memory claims = new IRewardsController.Claim[](1);
        claims[0] = IRewardsController.Claim({
            account: USER_A,
            collection: address(mockERC721),
            secondsUser: 0,
            secondsColl: 0,
            incRPS: 0,
            yieldSlice: 0,
            nonce: rewardsController.userNonce(address(tokenVault), USER_A),
            deadline: block.timestamp // Deadline = current time
        });

        // Sign the claim
        bytes32 domainSeparator = _buildDomainSeparator();
        // The contract expects just the hash of the claims array directly, not with the ClaimBatch typehash
        bytes32 structHash = keccak256(abi.encode(claims));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(UPDATER_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // This should succeed as deadline = current time is valid
        vm.startPrank(USER_A);
        rewardsController.claimLazy(claims, signature);
        vm.stopPrank();

        // Add more yield for next test
        vm.startPrank(ADMIN);
        mockERC20.mint(address(tokenVault), 10 ether);
        vm.stopPrank();
        vm.roll(block.number + 100);

        vm.startPrank(AUTHORIZED_UPDATER);
        rewardsController.refreshRewardPerBlock(address(tokenVault));
        vm.stopPrank();

        // Case 2: Current time just after deadline
        claims[0] = IRewardsController.Claim({
            account: USER_A,
            collection: address(mockERC721),
            secondsUser: 0,
            secondsColl: 0,
            incRPS: 0,
            yieldSlice: 0,
            nonce: rewardsController.userNonce(address(tokenVault), USER_A),
            deadline: block.timestamp - 1 // Deadline 1 second in the past
        });

        // Sign the claim
        structHash = keccak256(abi.encode(claims));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(UPDATER_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v);

        // This should fail as we're past the deadline
        vm.startPrank(USER_A);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.ClaimExpired.selector));
        rewardsController.claimLazy(claims, signature);
        vm.stopPrank();

        // Case 3: Current time far in the future (large timestamps)
        // Warp to a very far future time
        vm.warp(type(uint64).max - 1000);

        // Create a claim with deadline in this far future
        claims[0] = IRewardsController.Claim({
            account: USER_A,
            collection: address(mockERC721),
            secondsUser: 0,
            secondsColl: 0,
            incRPS: 0,
            yieldSlice: 0,
            nonce: rewardsController.userNonce(address(tokenVault), USER_A),
            deadline: type(uint64).max // Maximum timestamp
        });

        // Sign the claim
        structHash = keccak256(abi.encode(claims));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(UPDATER_PRIVATE_KEY, digest);
        (v, r, s) = vm.sign(UPDATER_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v);

        // This should succeed as we're still before the deadline
        vm.startPrank(USER_A);
        rewardsController.claimLazy(claims, signature);
        vm.stopPrank();
    }
}
