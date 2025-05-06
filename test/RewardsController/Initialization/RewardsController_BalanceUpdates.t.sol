// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";
import {RewardsController} from "../../../src/RewardsController.sol";
import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";

contract RewardsController_Balance_Updates is RewardsController_Test_Base {
    // --- Balance Update Tests ---

    // --- _processSingleUpdate (Internal Logic via Public Functions) ---
    function test_ProcessSingleUpdate_NFTAndBalance_NewUser() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        vm.expectEmit(true, true, false, true, address(rewardsController)); // user, nonce indexed; count not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce, 1);

        _processSingleUserUpdate(USER_A, address(mockERC721), block.number, 1, 100 ether); // Use mock address

        // Correctly call getUserCollectionTracking and access the result
        address[] memory collections = new address[](1);
        collections[0] = address(mockERC721);
        IRewardsController.UserCollectionTracking[] memory trackingInfo =
            rewardsController.getUserCollectionTracking(USER_A, collections);
        assertEq(trackingInfo.length, 1, "Expected tracking info for one collection");
        IRewardsController.UserCollectionTracking memory tracking = trackingInfo[0];

        assertEq(tracking.lastNFTBalance, 1, "NFT balance mismatch");
        assertEq(tracking.lastBalance, 100 ether, "Balance mismatch");
        assertEq(tracking.lastUpdateBlock, block.number, "Last update block mismatch");
        assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce + 1);
    }

    function test_ProcessSingleUpdate_IncreaseNFTAndBalance() public {
        // Initial update
        _processSingleUserUpdate(USER_A, address(mockERC721), block.number, 1, 100 ether); // Use mock address
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);

        // Second update
        vm.warp(block.timestamp + 10);
        uint256 nextBlock = block.number + 1;
        vm.expectEmit(true, true, false, true, address(rewardsController)); // user, nonce indexed; count not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce, 1);

        _processSingleUserUpdate(USER_A, address(mockERC721), nextBlock, 2, 50 ether); // Use mock address

        // Correctly call getUserCollectionTracking and access the result
        address[] memory collections = new address[](1);
        collections[0] = address(mockERC721);
        IRewardsController.UserCollectionTracking[] memory trackingInfo =
            rewardsController.getUserCollectionTracking(USER_A, collections);
        assertEq(trackingInfo.length, 1, "Expected tracking info for one collection");
        IRewardsController.UserCollectionTracking memory tracking = trackingInfo[0];

        assertEq(tracking.lastNFTBalance, 3, "NFT balance mismatch (1+2)"); // 1 + 2
        assertEq(tracking.lastBalance, 150 ether, "Balance mismatch (100+50)"); // 100 + 50
        assertEq(tracking.lastUpdateBlock, nextBlock, "Last update block mismatch");
        assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce + 1);
    }

    function test_ProcessSingleUpdate_DecreaseNFTAndBalance() public {
        // Initial update
        _processSingleUserUpdate(USER_A, address(mockERC721), block.number, 5, 200 ether); // Use mock address
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);

        // Second update (decrease)
        vm.warp(block.timestamp + 10);
        uint256 nextBlock = block.number + 1;
        vm.expectEmit(true, true, false, true, address(rewardsController)); // user, nonce indexed; count not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce, 1);

        _processSingleUserUpdate(USER_A, address(mockERC721), nextBlock, -2, -50 ether); // Use mock address

        // Correctly call getUserCollectionTracking and access the result
        address[] memory collections = new address[](1);
        collections[0] = address(mockERC721);
        IRewardsController.UserCollectionTracking[] memory trackingInfo =
            rewardsController.getUserCollectionTracking(USER_A, collections);
        assertEq(trackingInfo.length, 1, "Expected tracking info for one collection");
        IRewardsController.UserCollectionTracking memory tracking = trackingInfo[0];

        assertEq(tracking.lastNFTBalance, 3, "NFT balance mismatch (5-2)"); // 5 - 2
        assertEq(tracking.lastBalance, 150 ether, "Balance mismatch (200-50)"); // 200 - 50
        assertEq(tracking.lastUpdateBlock, nextBlock, "Last update block mismatch");
        assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce + 1);
    }

    function test_ProcessSingleUpdate_DecreaseToZero() public {
        // Initial update
        _processSingleUserUpdate(USER_A, address(mockERC721), block.number, 1, 100 ether); // Use mock address
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);

        // Second update (decrease to zero)
        vm.warp(block.timestamp + 10);
        uint256 nextBlock = block.number + 1;
        vm.expectEmit(true, true, false, true, address(rewardsController)); // user, nonce indexed; count not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce, 1);

        _processSingleUserUpdate(USER_A, address(mockERC721), nextBlock, -1, -100 ether); // Use mock address

        // Correctly call getUserCollectionTracking and access the result
        address[] memory collections = new address[](1);
        collections[0] = address(mockERC721);
        IRewardsController.UserCollectionTracking[] memory trackingInfo =
            rewardsController.getUserCollectionTracking(USER_A, collections);
        assertEq(trackingInfo.length, 1, "Expected tracking info for one collection");
        IRewardsController.UserCollectionTracking memory tracking = trackingInfo[0];

        assertEq(tracking.lastNFTBalance, 0, "NFT balance mismatch (1-1)");
        assertEq(tracking.lastBalance, 0, "Balance mismatch (100-100)");
        assertEq(tracking.lastUpdateBlock, nextBlock, "Last update block mismatch");
        assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce + 1);
    }

    function test_ProcessSingleUpdate_SameBlockUpdate() public {
        // Initial update
        uint256 initialBlock = block.number;
        _processSingleUserUpdate(USER_A, address(mockERC721), initialBlock, 1, 100 ether); // Use mock address
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        assertEq(nonce1, 1, "Nonce should be 1 after first update");

        // Second update in the same block (should NOT revert according to contract logic)
        int256 nftDelta2 = 1;
        int256 balanceDelta2 = 50 ether;
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721), // Restore field names
            blockNumber: initialBlock,
            nftDelta: nftDelta2,
            balanceDelta: balanceDelta2
        });
        // Sign with the current nonce (nonce1)
        bytes memory sig = _signUserBalanceUpdates(USER_A, updates, nonce1, UPDATER_PRIVATE_KEY);

        // Call the contract function directly - NO expectRevert
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, sig);

        // Nonce should increment
        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER),
            nonce1 + 1,
            "Nonce should increment after second update"
        );

        // Check final state
        address[] memory collections = new address[](1);
        collections[0] = address(mockERC721);
        IRewardsController.UserCollectionTracking[] memory trackingInfo =
            rewardsController.getUserCollectionTracking(USER_A, collections);
        assertEq(trackingInfo[0].lastNFTBalance, 2, "NFT balance should be 1+1=2");
        assertEq(trackingInfo[0].lastBalance, 150 ether, "Balance should be 100+50=150");
        assertEq(trackingInfo[0].lastUpdateBlock, initialBlock, "Last update block should remain initialBlock");
    }

    function test_Revert_ProcessSingleUpdate_UpdateOutOfOrder() public {
        uint256 startBlock = 100;
        vm.roll(startBlock); // Start at a known block

        // Initial update at block 101
        uint256 block1 = startBlock + 1; // 101
        vm.roll(block1);
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        IRewardsController.BalanceUpdateData[] memory updates1 = new IRewardsController.BalanceUpdateData[](1);
        updates1[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721),
            blockNumber: block1, // 101
            nftDelta: 1,
            balanceDelta: 100 ether
        });
        bytes memory sig1 = _signUserBalanceUpdates(USER_A, updates1, nonce0, UPDATER_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates1, sig1);
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        assertEq(nonce1, nonce0 + 1, "Nonce should increment after first update");

        // Advance to block 102
        uint256 block2 = block1 + 1; // 102
        vm.roll(block2);

        // Attempt second update with block 100 (past block < lastUpdateBlock AND < current block)
        uint256 pastBlock = startBlock; // 100
        IRewardsController.BalanceUpdateData[] memory updates2 = new IRewardsController.BalanceUpdateData[](1);
        updates2[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721),
            blockNumber: pastBlock, // Use 100
            nftDelta: 1,
            balanceDelta: 50 ether
        });

        // Sign with the current nonce (nonce1)
        bytes memory sig2 = _signUserBalanceUpdates(USER_A, updates2, nonce1, UPDATER_PRIVATE_KEY);

        // Expect revert UpdateOutOfOrder with specific parameters
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsController.UpdateOutOfOrder.selector,
                USER_A, // user
                address(mockERC721), // collection
                pastBlock, // updateBlock (100)
                block1 // lastProcessedBlock (101)
            )
        );

        // Call the contract function directly
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates2, sig2);
    }

    function test_Revert_ProcessSingleUpdate_NFTUnderflow() public {
        // Initial update using processUserBalanceUpdates
        uint256 block0 = block.number;
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        assertEq(nonce0, 0, "Initial nonce should be 0");
        IRewardsController.BalanceUpdateData[] memory updates1 = new IRewardsController.BalanceUpdateData[](1);
        updates1[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721), // Restore field names
            blockNumber: block0,
            nftDelta: 1, // Set NFT balance to 1
            balanceDelta: 100 ether
        });
        bytes memory sig1 = _signUserBalanceUpdates(USER_A, updates1, nonce0, UPDATER_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates1, sig1);
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        assertEq(nonce1, 1, "Nonce should be 1 after first update");

        // Second update causing NFT underflow
        vm.warp(block.timestamp + 10);
        uint256 nextBlock = block.number + 1;
        vm.roll(nextBlock); // Ensure block number advances

        // Prepare data for the reverting call
        IRewardsController.BalanceUpdateData[] memory updates2 = new IRewardsController.BalanceUpdateData[](1);
        updates2[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721), // Restore field names
            blockNumber: nextBlock,
            nftDelta: -2, // Attempt to decrease NFT balance by 2 (1 - 2 < 0)
            balanceDelta: 0
        });
        // Sign with the current nonce (nonce1 = 1)
        bytes memory sig2 = _signUserBalanceUpdates(USER_A, updates2, nonce1, UPDATER_PRIVATE_KEY);

        // Expect revert BalanceUpdateUnderflow(currentValue, deltaMagnitude)
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsController.BalanceUpdateUnderflow.selector,
                1, // currentValue (NFT balance)
                2 // deltaMagnitude (absolute value of nftDelta)
            )
        );
        // Call the contract function directly
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates2, sig2);

        // Nonce should NOT increment because the transaction reverted before the state change was committed.
        // assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce1 + 1, "Nonce should increment even on internal revert"); // Removed incorrect assertion
    }

    function test_Revert_ProcessSingleUpdate_BalanceUnderflow() public {
        // Initial update using processUserBalanceUpdates
        uint256 block0 = block.number;
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        assertEq(nonce0, 0, "Initial nonce should be 0");
        IRewardsController.BalanceUpdateData[] memory updates1 = new IRewardsController.BalanceUpdateData[](1);
        updates1[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721), // Restore field names
            blockNumber: block0,
            nftDelta: 1,
            balanceDelta: 100 ether // Set balance to 100 ether
        });
        bytes memory sig1 = _signUserBalanceUpdates(USER_A, updates1, nonce0, UPDATER_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates1, sig1);
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        assertEq(nonce1, 1, "Nonce should be 1 after first update");

        // Second update causing balance underflow
        vm.warp(block.timestamp + 10);
        uint256 nextBlock = block.number + 1;
        vm.roll(nextBlock); // Ensure block number advances

        // Prepare data for the reverting call
        IRewardsController.BalanceUpdateData[] memory updates2 = new IRewardsController.BalanceUpdateData[](1);
        updates2[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721), // Restore field names
            blockNumber: nextBlock,
            nftDelta: 0,
            balanceDelta: -101 ether // Attempt to decrease balance by 101 ether (100 - 101 < 0)
        });
        // Sign with the current nonce (nonce1 = 1)
        bytes memory sig2 = _signUserBalanceUpdates(USER_A, updates2, nonce1, UPDATER_PRIVATE_KEY);

        // Expect revert BalanceUpdateUnderflow(currentValue, deltaMagnitude)
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsController.BalanceUpdateUnderflow.selector,
                100 ether, // currentValue (balance)
                101 ether // deltaMagnitude (absolute value of balanceDelta)
            )
        );
        // Call the contract function directly
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates2, sig2);

        // Nonce should NOT increment because the transaction reverted before the state change was committed.
        // assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce1 + 1, "Nonce should increment even on internal revert"); // Removed incorrect assertion
    }

    // --- processUserBalanceUpdates (Batch, Single User) ---
    function test_ProcessUserBalanceUpdates_ValidBatch() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        uint256 block1 = block.number + 1;
        uint256 block2 = block.number + 2;
        vm.roll(block2); // Roll to the latest block in the batch

        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](2);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721), // Restore field names
            blockNumber: block1,
            nftDelta: 2,
            balanceDelta: 100 ether
        });
        updates[1] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721_2), // Restore field names
            blockNumber: block2,
            nftDelta: 1,
            balanceDelta: 50 ether
        });

        bytes memory sig = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);

        vm.expectEmit(true, true, false, true, address(rewardsController)); // user, nonce indexed; count not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce, updates.length);

        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, sig);

        assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce + 1, "Nonce mismatch");

        // Verify state for collection 1 using getUserCollectionTracking
        address[] memory collections1 = new address[](1);
        collections1[0] = address(mockERC721);
        IRewardsController.UserCollectionTracking[] memory trackingInfo1 =
            rewardsController.getUserCollectionTracking(USER_A, collections1);
        assertEq(trackingInfo1.length, 1);
        assertEq(trackingInfo1[0].lastNFTBalance, 2);
        assertEq(trackingInfo1[0].lastBalance, 100 ether);
        assertEq(trackingInfo1[0].lastUpdateBlock, block1);

        // Verify state for collection 2 using getUserCollectionTracking
        address[] memory collections2 = new address[](1);
        collections2[0] = address(mockERC721_2);
        IRewardsController.UserCollectionTracking[] memory trackingInfo2 =
            rewardsController.getUserCollectionTracking(USER_A, collections2);
        assertEq(trackingInfo2.length, 1);
        assertEq(trackingInfo2[0].lastNFTBalance, 1);
        assertEq(trackingInfo2[0].lastBalance, 50 ether);
        assertEq(trackingInfo2[0].lastUpdateBlock, block2);
    }

    function test_Revert_ProcessUserBalanceUpdates_EmptyBatch() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        IRewardsController.BalanceUpdateData[] memory updates; // Empty array
        bytes memory sig = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);

        vm.expectRevert(IRewardsController.EmptyBatch.selector);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, sig);
    }

    function test_Revert_ProcessUserBalanceUpdates_InvalidSigner() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721), // Restore field names
            blockNumber: updateBlock,
            nftDelta: 1,
            balanceDelta: 10 ether
        });
        bytes memory sig = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);

        // Call with a different signer address
        // Expect InvalidSignature because the signature generated by UPDATER_PRIVATE_KEY
        // does not match the signer argument (OTHER_ADDRESS) provided to the function,
        // and the contract validates the signature against the authorizedUpdater.
        vm.expectRevert(IRewardsController.InvalidSignature.selector);
        rewardsController.processUserBalanceUpdates(OTHER_ADDRESS, USER_A, updates, sig);
    }

    function test_Revert_ProcessUserBalanceUpdates_InvalidSignature() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721), // Restore field names
            blockNumber: updateBlock,
            nftDelta: 1,
            balanceDelta: 10 ether
        });

        // Sign with a different private key
        uint256 otherPrivateKey = 0x12345;
        bytes memory badSig = _signUserBalanceUpdates(USER_A, updates, nonce, otherPrivateKey);

        vm.expectRevert(IRewardsController.InvalidSignature.selector);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, badSig);
    }

    function test_Revert_ProcessUserBalanceUpdates_NonceMismatch() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721),
            blockNumber: updateBlock,
            nftDelta: 1,
            balanceDelta: 10 ether
        });

        // Sign with incorrect nonce
        bytes memory sig = _signUserBalanceUpdates(USER_A, updates, nonce + 1, UPDATER_PRIVATE_KEY);

        vm.expectRevert(IRewardsController.InvalidSignature.selector); // Reverts due to digest mismatch
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, sig);
    }

    function test_Revert_ProcessUserBalanceUpdates_CollectionNotWhitelisted() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_3,
            blockNumber: updateBlock,
            nftDelta: 1,
            balanceDelta: 10 ether
        }); // Use non-whitelisted collection
        bytes memory sig = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);

        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3));
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, sig);
    }

    // --- Simple Balance Update (from todo_initialization_admin_view.md) ---

    function test_ProcessUserBalanceUpdates_Single_Success() public {
        // Use a new user (USER_C) and an existing whitelisted collection (NFT_COLLECTION_1)
        address user = USER_C;
        address collection = address(mockERC721); // Use mock address
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        int256 nftDelta = 1;
        int256 balanceDelta = 50 ether;

        uint256 nonceBefore = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);

        // Prepare the update data
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock,
            nftDelta: nftDelta,
            balanceDelta: balanceDelta
        });

        // Sign the update
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonceBefore, UPDATER_PRIVATE_KEY);

        // Expect the batch event
        vm.expectEmit(true, true, false, true, address(rewardsController)); // user, nonce indexed; count not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(user, nonceBefore, updates.length);

        // Process the update
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates, sig);

        // Verify nonce increment
        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER),
            nonceBefore + 1,
            "Nonce should increment after processing update"
        );

        // Verify userNFTData state using getUserCollectionTracking
        address[] memory collections = new address[](1);
        collections[0] = collection;
        IRewardsController.UserCollectionTracking[] memory trackingInfo =
            rewardsController.getUserCollectionTracking(user, collections);
        assertEq(trackingInfo.length, 1);
        IRewardsController.UserCollectionTracking memory tracking = trackingInfo[0];

        // Note: lastUserRewardIndex is not directly checked here as it depends on global index at time of update
        assertEq(tracking.lastNFTBalance, uint256(nftDelta), "NFT balance mismatch");
        assertEq(tracking.lastBalance, uint256(balanceDelta), "Balance mismatch");
        assertEq(tracking.lastUpdateBlock, updateBlock, "Last update block mismatch");

        address[] memory activeCollections = rewardsController.getUserNFTCollections(user);
        assertEq(activeCollections.length, 1, "User should have one active collection");
        assertEq(activeCollections[0], collection, "Active collection mismatch");
    }

    // --- processBalanceUpdates (Batch, Multi User) ---
    function test_ProcessBalanceUpdates_ValidBatch() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        uint256 block1 = block.number + 1;
        uint256 block2 = block.number + 2;
        vm.roll(block2);

        IRewardsController.UserBalanceUpdateData[] memory updatesStruct =
            new IRewardsController.UserBalanceUpdateData[](2);
        updatesStruct[0] = IRewardsController.UserBalanceUpdateData({
            user: USER_A,
            collection: address(mockERC721),
            blockNumber: block1,
            nftDelta: 1,
            balanceDelta: 100 ether
        });
        updatesStruct[1] = IRewardsController.UserBalanceUpdateData({
            user: USER_B,
            collection: address(mockERC721_2),
            blockNumber: block2,
            nftDelta: 2,
            balanceDelta: 50 ether
        });

        uint256 batchSize = updatesStruct.length;
        address[] memory users = new address[](batchSize);
        address[] memory collections = new address[](batchSize);
        uint256[] memory blockNumbers = new uint256[](batchSize);
        int256[] memory nftDeltas = new int256[](batchSize);
        int256[] memory balanceDeltas = new int256[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            users[i] = updatesStruct[i].user;
            collections[i] = updatesStruct[i].collection;
            blockNumbers[i] = updatesStruct[i].blockNumber;
            nftDeltas[i] = updatesStruct[i].nftDelta;
            balanceDeltas[i] = updatesStruct[i].balanceDelta;
        }

        bytes memory sig = _signBalanceUpdatesArrays(
            users, collections, blockNumbers, nftDeltas, balanceDeltas, nonce, UPDATER_PRIVATE_KEY
        );

        vm.expectEmit(true, true, false, true, address(rewardsController)); // signer, nonce indexed; count not indexed
        emit IRewardsController.BalanceUpdatesProcessed(AUTHORIZED_UPDATER, nonce, batchSize);

        rewardsController.processBalanceUpdates(
            AUTHORIZED_UPDATER, users, collections, blockNumbers, nftDeltas, balanceDeltas, sig
        );

        // Verify state for USER_A using getUserCollectionTracking
        address[] memory collectionsA = new address[](1);
        collectionsA[0] = address(mockERC721);
        IRewardsController.UserCollectionTracking[] memory trackingInfoA =
            rewardsController.getUserCollectionTracking(USER_A, collectionsA);
        assertEq(trackingInfoA.length, 1);
        assertEq(trackingInfoA[0].lastNFTBalance, 1);
        assertEq(trackingInfoA[0].lastBalance, 100 ether);
        assertEq(trackingInfoA[0].lastUpdateBlock, block1);

        // Verify state for USER_B using getUserCollectionTracking
        address[] memory collectionsB = new address[](1);
        collectionsB[0] = address(mockERC721_2);
        IRewardsController.UserCollectionTracking[] memory trackingInfoB =
            rewardsController.getUserCollectionTracking(USER_B, collectionsB);
        assertEq(trackingInfoB.length, 1);
        assertEq(trackingInfoB[0].lastNFTBalance, 2);
        assertEq(trackingInfoB[0].lastBalance, 50 ether);
        assertEq(trackingInfoB[0].lastUpdateBlock, block2);

        assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce + 1);
    }
}
