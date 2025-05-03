// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";
import {RewardsController} from "../../src/RewardsController.sol";
import {RewardsController_Test_Base} from "./RewardsController_Test_Base.sol";

contract RewardsController_Balance_Updates is RewardsController_Test_Base {
    // --- Balance Update Tests ---

    // --- _processSingleUpdate (Internal Logic via Public Functions) ---
    function test_ProcessSingleUpdate_NFTAndBalance_NewUser() public {
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        int256 nftDelta = 5;
        int256 balanceDelta = 1000 ether;

        uint256 nonceBefore = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        // _processSingleUserUpdate calls processUserBalanceUpdates which emits UserBalanceUpdatesProcessed (user, nonce indexed)
        vm.expectEmit(true, true, false, true, address(rewardsController)); // count is not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonceBefore, 1); // user, nonce, count=1

        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, nftDelta, balanceDelta);

        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER),
            (nonceBefore + 1),
            "Nonce mismatch after single update"
        );

        (uint256 lastIdx, uint256 accrued, uint256 nftBal, uint256 balance, uint256 lastUpdate) =
            rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        assertEq(lastIdx, rewardsController.globalRewardIndex(), "Initial index mismatch");
        assertEq(accrued, 0, "Initial accrued mismatch");
        assertEq(nftBal, uint256(nftDelta), "NFT balance mismatch");
        assertEq(balance, uint256(balanceDelta), "Balance mismatch");
        assertEq(lastUpdate, updateBlock, "Last update block mismatch");

        // Check user active collections
        address[] memory active = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active.length, 1, "Active collections length mismatch");
        assertEq(active[0], NFT_COLLECTION_1, "Active collection address mismatch");
    }

    function test_ProcessSingleUpdate_IncreaseNFTAndBalance() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        int256 nftDelta1 = 2;
        int256 balanceDelta1 = 500 ether;
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, nftDelta1, balanceDelta1);

        uint256 block2 = block.number + 5;
        vm.roll(block2);
        int256 nftDelta2 = 3; // +3 NFTs
        int256 balanceDelta2 = 200 ether; // +200 balance

        uint256 nonceBefore = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        // _processSingleUserUpdate calls processUserBalanceUpdates which emits UserBalanceUpdatesProcessed (user, nonce indexed)
        vm.expectEmit(true, true, false, true, address(rewardsController)); // count is not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonceBefore, 1); // user, nonce, count=1

        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block2, nftDelta2, balanceDelta2);

        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER),
            nonceBefore + 1,
            "Nonce mismatch after second update"
        );

        (uint256 lastIdx,, uint256 nftBal, uint256 balance, uint256 lastUpdate) =
            rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        assertEq(lastIdx, rewardsController.globalRewardIndex(), "Index mismatch after second update");
        assertEq(nftBal, uint256(nftDelta1 + nftDelta2), "NFT balance mismatch after increase");
        assertEq(balance, uint256(balanceDelta1 + balanceDelta2), "Balance mismatch after increase");
        assertEq(lastUpdate, block2, "Last update block mismatch after second update");
    }

    function test_ProcessSingleUpdate_DecreaseNFTAndBalance() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        int256 nftDelta1 = 5;
        int256 balanceDelta1 = 1000 ether;
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, nftDelta1, balanceDelta1);

        uint256 block2 = block.number + 5;
        vm.roll(block2);
        int256 nftDelta2 = -2; // -2 NFTs
        int256 balanceDelta2 = -300 ether; // -300 balance

        uint256 nonceBefore = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        // _processSingleUserUpdate calls processUserBalanceUpdates which emits UserBalanceUpdatesProcessed (user, nonce indexed)
        vm.expectEmit(true, true, false, true, address(rewardsController)); // count is not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonceBefore, 1); // user, nonce, count=1

        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block2, nftDelta2, balanceDelta2);

        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER),
            nonceBefore + 1,
            "Nonce mismatch after decrease"
        );

        (uint256 lastIdx,, uint256 nftBal, uint256 balance, uint256 lastUpdate) =
            rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        assertEq(lastIdx, rewardsController.globalRewardIndex(), "Index mismatch after decrease");
        assertEq(nftBal, uint256(nftDelta1 + nftDelta2), "NFT balance mismatch after decrease");
        assertEq(balance, uint256(balanceDelta1 + balanceDelta2), "Balance mismatch after decrease");
        assertEq(lastUpdate, block2, "Last update block mismatch after decrease");
    }

    function test_ProcessSingleUpdate_DecreaseToZero() public {
        uint256 block1 = block.number + 1;
        vm.roll(block1);
        int256 nftDelta1 = 2;
        int256 balanceDelta1 = 100 ether;
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block1, nftDelta1, balanceDelta1);

        uint256 block2 = block.number + 5;
        vm.roll(block2);
        int256 nftDelta2 = -2; // -2 NFTs (to 0)
        int256 balanceDelta2 = -100 ether; // -100 balance (to 0)

        uint256 nonceBefore = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        // _processSingleUserUpdate calls processUserBalanceUpdates which emits UserBalanceUpdatesProcessed (user, nonce indexed)
        vm.expectEmit(true, true, false, true, address(rewardsController)); // count is not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonceBefore, 1); // user, nonce, count=1

        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, block2, nftDelta2, balanceDelta2);

        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER),
            nonceBefore + 1,
            "Nonce mismatch after zeroing"
        );

        (uint256 lastIdx,, uint256 nftBal, uint256 balance, uint256 lastUpdate) =
            rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        assertEq(lastIdx, rewardsController.globalRewardIndex(), "Index mismatch after zeroing");
        assertEq(nftBal, 0, "NFT balance mismatch after zeroing");
        assertEq(balance, 0, "Balance mismatch after zeroing");
        assertEq(lastUpdate, block2, "Last update block mismatch after zeroing");

        // Check user active collections removed
        address[] memory active = rewardsController.getUserNFTCollections(USER_A);
        assertEq(active.length, 0, "Active collections should be empty after zeroing");
    }

    function test_Revert_ProcessSingleUpdate_BalanceUnderflow() public {
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        int256 nftDelta = 1;
        int256 balanceDelta = -100 ether; // Negative delta with 0 initial balance

        // Prepare the update data directly
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock,
            nftDelta: nftDelta,
            balanceDelta: balanceDelta
        });

        // Get nonce and sign
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce, UPDATER_PRIVATE_KEY);

        // Expect the internal revert from _applyDelta
        uint256 expectedCurrentValue = 0; // Initial balance is 0
        uint256 expectedUnderflowAmount = 100 ether;
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsController.BalanceUpdateUnderflow.selector, expectedCurrentValue, expectedUnderflowAmount
            )
        );

        // Call the function directly
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates, sig);
    }

    function test_Revert_ProcessSingleUpdate_NFTUnderflow() public {
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        int256 nftDelta = -1; // Negative delta with 0 initial balance
        int256 balanceDelta = 100 ether;

        // Prepare the update data directly
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock,
            nftDelta: nftDelta,
            balanceDelta: balanceDelta
        });

        // Get nonce and sign
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce, UPDATER_PRIVATE_KEY);

        // Expect the internal revert from _applyDelta (for NFT balance)
        uint256 expectedCurrentValue = 0; // Initial NFT balance is 0
        uint256 expectedNftUnderflowAmount = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsController.BalanceUpdateUnderflow.selector, expectedCurrentValue, expectedNftUnderflowAmount
            )
        );

        // Call the function directly
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates, sig);
    }

    function test_Revert_ProcessSingleUpdate_UpdateOutOfOrder() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;

        // --- First update (successful, using direct call) ---
        uint256 block1 = block.number + 5; // Update in the future
        vm.roll(block1);
        int256 nftDelta1 = 1;
        int256 balanceDelta1 = 100 ether;

        // Prepare update data 1
        IRewardsController.BalanceUpdateData[] memory updates1 = new IRewardsController.BalanceUpdateData[](1);
        updates1[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: block1,
            nftDelta: nftDelta1,
            balanceDelta: balanceDelta1
        });

        // Get nonce and sign for update 1
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory sig1 = _signUserBalanceUpdates(user, updates1, nonce1, UPDATER_PRIVATE_KEY);

        // Process update 1 directly
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates1, sig1);
        assertEq(
            rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce1 + 1, "Nonce mismatch after update 1"
        );

        // --- Second update (attempted in the past, should revert) ---
        uint256 attemptedUpdateBlock = block1 - 2; // Try to update in the past relative to block1
        int256 nftDelta2 = 1;
        int256 balanceDelta2 = 50 ether;

        // Prepare the update data directly for the second update
        IRewardsController.BalanceUpdateData[] memory updates2 = new IRewardsController.BalanceUpdateData[](1);
        updates2[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: attemptedUpdateBlock,
            nftDelta: nftDelta2,
            balanceDelta: balanceDelta2
        });

        // Get nonce and sign for the second update (nonce should have incremented from update 1)
        uint256 nonce2 = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory sig2 = _signUserBalanceUpdates(user, updates2, nonce2, UPDATER_PRIVATE_KEY);
        assertEq(nonce2, nonce1 + 1, "Nonce for update 2 should be nonce1 + 1");

        // Expect the internal revert from _processSingleUpdate (checking selector only)
        vm.expectRevert(RewardsController.UpdateOutOfOrder.selector);

        // Call the function directly for the second update, providing ample gas
        rewardsController.processUserBalanceUpdates{gas: 500_000}(AUTHORIZED_UPDATER, user, updates2, sig2);
    }

    function test_ProcessSingleUpdate_SameBlockUpdate() public {
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);

        // First update in the block
        int256 nftDelta1 = 2;
        int256 balanceDelta1 = 100 ether;
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, nftDelta1, balanceDelta1);

        (uint256 lastIdx1,,,,) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        // Second update in the same block
        int256 nftDelta2 = 1;
        int256 balanceDelta2 = 50 ether;
        _processSingleUserUpdate(USER_A, NFT_COLLECTION_1, updateBlock, nftDelta2, balanceDelta2);

        (uint256 lastIdx2, /* accrued */, uint256 nftBal, uint256 balance, uint256 lastUpdate2) =
            rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        // Index and lastUpdateBlock should NOT change for same-block updates
        assertEq(lastIdx1, lastIdx2, "Index should not change on same block update");
        assertEq(lastUpdate2, updateBlock, "Last update block should be the current block");

        // Balances should accumulate
        assertEq(nftBal, uint256(nftDelta1 + nftDelta2), "NFT balance mismatch after same block update");
        assertEq(balance, uint256(balanceDelta1 + balanceDelta2), "Balance mismatch after same block update");
    }

    // --- processUserBalanceUpdates (Batch, Single User) ---
    function test_ProcessUserBalanceUpdates_ValidBatch() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        uint256 block1 = block.number + 1;
        uint256 block2 = block.number + 2;
        vm.roll(block2); // Roll to the latest block in the batch

        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](2);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: block1,
            nftDelta: 2,
            balanceDelta: 100 ether
        });
        updates[1] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_2,
            blockNumber: block2,
            nftDelta: 1,
            balanceDelta: 50 ether
        });

        bytes memory sig = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);

        // Only the batch event is emitted
        vm.expectEmit(true, true, false, true, address(rewardsController)); // count is not indexed
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce, updates.length);

        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, sig);

        assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce + 1, "Nonce mismatch");

        // Verify state for collection 1
        (uint256 lastIdx1,, uint256 nftBal1, uint256 balance1, uint256 lastUpdate1) =
            rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
        assertEq(nftBal1, 2);
        assertEq(balance1, 100 ether);
        assertEq(lastUpdate1, block1); // Should be block of the update

        // Verify state for collection 2
        (uint256 lastIdx2,, uint256 nftBal2, uint256 balance2, uint256 lastUpdate2) =
            rewardsController.userNFTData(USER_A, NFT_COLLECTION_2);
        assertEq(nftBal2, 1);
        assertEq(balance2, 50 ether);
        assertEq(lastUpdate2, block2); // Should be block of the update
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
            collection: NFT_COLLECTION_1,
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
            collection: NFT_COLLECTION_1,
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
            collection: NFT_COLLECTION_1,
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
        address collection = NFT_COLLECTION_1;
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

        // Expect the event
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

        // Verify userNFTData state
        (uint256 lastIdx, uint256 accrued, uint256 nftBal, uint256 userBalance, uint256 lastUpdate) =
            rewardsController.userNFTData(user, collection);

        assertEq(lastIdx, rewardsController.globalRewardIndex(), "Initial index mismatch for new user");
        assertEq(accrued, 0, "Initial accrued reward should be 0");
        assertEq(nftBal, uint256(nftDelta), "NFT balance mismatch");
        assertEq(userBalance, uint256(balanceDelta), "Balance mismatch");
        assertEq(lastUpdate, updateBlock, "Last update block mismatch");

        // Verify user is added to active collections
        address[] memory activeCollections = rewardsController.getUserNFTCollections(user);
        assertEq(activeCollections.length, 1, "User should have one active collection");
        assertEq(activeCollections[0], collection, "Active collection mismatch");
    }

    // --- processBalanceUpdates (Batch, Multi User) ---
    // Similar tests as processUserBalanceUpdates, but using the multi-user structure and signing
    function test_ProcessBalanceUpdates_ValidBatch() public {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        uint256 block1 = block.number + 1;
        uint256 block2 = block.number + 2;
        vm.roll(block2);

        IRewardsController.UserBalanceUpdateData[] memory updates = new IRewardsController.UserBalanceUpdateData[](2);
        updates[0] = IRewardsController.UserBalanceUpdateData({
            user: USER_A,
            collection: NFT_COLLECTION_1,
            blockNumber: block1,
            nftDelta: 2,
            balanceDelta: 100 ether
        });
        updates[1] = IRewardsController.UserBalanceUpdateData({
            user: USER_B,
            collection: NFT_COLLECTION_2,
            blockNumber: block2,
            nftDelta: 1,
            balanceDelta: 50 ether
        });

        bytes memory sig = _signBalanceUpdates(updates, nonce, UPDATER_PRIVATE_KEY);

        // Only the batch event is emitted
        vm.expectEmit(true, true, false, true, address(rewardsController)); // count is not indexed
        emit IRewardsController.BalanceUpdatesProcessed(AUTHORIZED_UPDATER, nonce, updates.length);

        rewardsController.processBalanceUpdates(AUTHORIZED_UPDATER, updates, sig);

        assertEq(rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER), nonce + 1, "Nonce mismatch");
        // Verify state for USER_A, collection 1
        (,, uint256 nftBalA, uint256 balanceA,) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
        assertEq(nftBalA, 2);
        assertEq(balanceA, 100 ether);
        // Verify state for USER_B, collection 2
        (,, uint256 nftBalB, uint256 balanceB,) = rewardsController.userNFTData(USER_B, NFT_COLLECTION_2);
        assertEq(nftBalB, 1);
        assertEq(balanceB, 50 ether);
    }

    // Add more revert tests for processBalanceUpdates (similar to processUserBalanceUpdates: empty, signer, signature, nonce, non-whitelisted)

    // --- processNFTBalanceUpdate / processDepositUpdate (Deprecated?) ---
    // These seem superseded by the batch update functions based on the contract structure.
    // If they are intended to still be used, add tests similar to the batch ones but with single updates.
    // Example:
    /*
    function test_ProcessNFTBalanceUpdate_Valid() public {
        // ... setup signature for BALANCE_UPDATE_DATA_TYPEHASH ...
        // vm.expectRevert("Function deprecated or signature mismatch"); // If truly deprecated
        // rewardsController.processNFTBalanceUpdate(USER_A, NFT_COLLECTION_1, block.number, 1, sig);
    }
    */
}
