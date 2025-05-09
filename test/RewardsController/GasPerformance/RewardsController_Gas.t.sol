// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RewardsController_Test_Base} from "../RewardsController_Test_Base.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";
import {IRewardsController} from "../../../src/interfaces/IRewardsController.sol";

contract RewardsController_Gas_BalanceUpdates_Test is RewardsController_Test_Base {
    uint256 constant BATCH_SIZE_10 = 10;
    uint256 constant BATCH_SIZE_50 = 50;
    uint256 constant BATCH_SIZE_100 = 100;

    function setUp() public virtual override {
        RewardsController_Test_Base.setUp();
        // Additional setup specific to balance update gas tests if needed
    }

    // --- Balance Updates ---

    function test_Gas_ProcessUserBalanceUpdates_Single() public {
        // Collection (mockERC721) is already whitelisted in RewardsController_Test_Base.setUp()

        // Prepare a single update
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: address(mockERC721),
            blockNumber: block.number,
            nftDelta: 1,
            balanceDelta: 1 ether
        });

        // Execute and measure gas
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);
        vm.prank(AUTHORIZED_UPDATER);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, signature);
    }

    function test_Gas_ProcessUserBalanceUpdates_Batch_10() public {
        // Collection (mockERC721) is already whitelisted in RewardsController_Test_Base.setUp()

        // Prepare batch updates
        IRewardsController.BalanceUpdateData[] memory updates =
            _prepareUserBalanceUpdates(address(mockERC721), BATCH_SIZE_10, block.number);

        // Execute and measure gas
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);
        vm.prank(AUTHORIZED_UPDATER);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, signature);
    }

    function test_Gas_ProcessUserBalanceUpdates_Batch_50() public {
        // Collection (mockERC721) is already whitelisted in RewardsController_Test_Base.setUp()

        // Prepare batch updates
        IRewardsController.BalanceUpdateData[] memory updates =
            _prepareUserBalanceUpdates(address(mockERC721), BATCH_SIZE_50, block.number);

        // Execute and measure gas
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);
        vm.prank(AUTHORIZED_UPDATER);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, signature);
    }

    function test_Gas_ProcessUserBalanceUpdates_Batch_100() public {
        // Collection (mockERC721) is already whitelisted in RewardsController_Test_Base.setUp()

        // Prepare batch updates
        IRewardsController.BalanceUpdateData[] memory updates =
            _prepareUserBalanceUpdates(address(mockERC721), BATCH_SIZE_100, block.number);

        // Execute and measure gas
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signUserBalanceUpdates(USER_A, updates, nonce, UPDATER_PRIVATE_KEY);
        vm.prank(AUTHORIZED_UPDATER);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, USER_A, updates, signature);
    }

    function test_Gas_ProcessBalanceUpdates_Batch_10() public {
        // Collection (mockERC721) is already whitelisted in RewardsController_Test_Base.setUp()

        // Prepare multi-user batch updates
        IRewardsController.UserBalanceUpdateData[] memory updatesStruct =
            _prepareBalanceUpdates(address(mockERC721), BATCH_SIZE_10, block.number);

        address[] memory users = new address[](BATCH_SIZE_10);
        address[] memory collections = new address[](BATCH_SIZE_10);
        uint256[] memory blockNumbers = new uint256[](BATCH_SIZE_10);
        int256[] memory nftDeltas = new int256[](BATCH_SIZE_10);
        int256[] memory balanceDeltas = new int256[](BATCH_SIZE_10);

        for (uint256 i = 0; i < BATCH_SIZE_10; i++) {
            users[i] = updatesStruct[i].user;
            collections[i] = updatesStruct[i].collection;
            blockNumbers[i] = updatesStruct[i].blockNumber;
            nftDeltas[i] = updatesStruct[i].nftDelta;
            balanceDeltas[i] = updatesStruct[i].balanceDelta;
        }

        // Execute and measure gas
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signBalanceUpdatesArrays(
            users, collections, blockNumbers, nftDeltas, balanceDeltas, nonce, UPDATER_PRIVATE_KEY
        );
        vm.prank(AUTHORIZED_UPDATER);
        rewardsController.processBalanceUpdates(
            AUTHORIZED_UPDATER, users, collections, blockNumbers, nftDeltas, balanceDeltas, signature
        );
    }

    function test_Gas_ProcessBalanceUpdates_Batch_50() public {
        // Collection (mockERC721) is already whitelisted in RewardsController_Test_Base.setUp()

        // Prepare multi-user batch updates
        IRewardsController.UserBalanceUpdateData[] memory updatesStruct =
            _prepareBalanceUpdates(address(mockERC721), BATCH_SIZE_50, block.number);

        address[] memory users = new address[](BATCH_SIZE_50);
        address[] memory collections = new address[](BATCH_SIZE_50);
        uint256[] memory blockNumbers = new uint256[](BATCH_SIZE_50);
        int256[] memory nftDeltas = new int256[](BATCH_SIZE_50);
        int256[] memory balanceDeltas = new int256[](BATCH_SIZE_50);

        for (uint256 i = 0; i < BATCH_SIZE_50; i++) {
            users[i] = updatesStruct[i].user;
            collections[i] = updatesStruct[i].collection;
            blockNumbers[i] = updatesStruct[i].blockNumber;
            nftDeltas[i] = updatesStruct[i].nftDelta;
            balanceDeltas[i] = updatesStruct[i].balanceDelta;
        }

        // Execute and measure gas
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signBalanceUpdatesArrays(
            users, collections, blockNumbers, nftDeltas, balanceDeltas, nonce, UPDATER_PRIVATE_KEY
        );
        vm.prank(AUTHORIZED_UPDATER);
        rewardsController.processBalanceUpdates(
            AUTHORIZED_UPDATER, users, collections, blockNumbers, nftDeltas, balanceDeltas, signature
        );
    }

    function test_Gas_ProcessBalanceUpdates_Batch_100() public {
        // Collection (mockERC721) is already whitelisted in RewardsController_Test_Base.setUp()

        // Prepare multi-user batch updates
        IRewardsController.UserBalanceUpdateData[] memory updatesStruct =
            _prepareBalanceUpdates(address(mockERC721), BATCH_SIZE_100, block.number);

        address[] memory users = new address[](BATCH_SIZE_100);
        address[] memory collections = new address[](BATCH_SIZE_100);
        uint256[] memory blockNumbers = new uint256[](BATCH_SIZE_100);
        int256[] memory nftDeltas = new int256[](BATCH_SIZE_100);
        int256[] memory balanceDeltas = new int256[](BATCH_SIZE_100);

        for (uint256 i = 0; i < BATCH_SIZE_100; i++) {
            users[i] = updatesStruct[i].user;
            collections[i] = updatesStruct[i].collection;
            blockNumbers[i] = updatesStruct[i].blockNumber;
            nftDeltas[i] = updatesStruct[i].nftDelta;
            balanceDeltas[i] = updatesStruct[i].balanceDelta;
        }

        // Execute and measure gas
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        bytes memory signature = _signBalanceUpdatesArrays(
            users, collections, blockNumbers, nftDeltas, balanceDeltas, nonce, UPDATER_PRIVATE_KEY
        );
        vm.prank(AUTHORIZED_UPDATER);
        rewardsController.processBalanceUpdates(
            AUTHORIZED_UPDATER, users, collections, blockNumbers, nftDeltas, balanceDeltas, signature
        );
    }

    // --- Helper Functions ---

    function _prepareUserBalanceUpdates(address collection, uint256 count, uint256 currentBlockNumber)
        internal
        pure
        returns (IRewardsController.BalanceUpdateData[] memory updates)
    {
        updates = new IRewardsController.BalanceUpdateData[](count);
        for (uint256 i = 0; i < count; i++) {
            updates[i] = IRewardsController.BalanceUpdateData({
                collection: collection,
                blockNumber: currentBlockNumber,
                nftDelta: 1,
                balanceDelta: int256((i + 1) * 1 ether) // Cast to int256
            });
        }
    }

    function _prepareBalanceUpdates(address collection, uint256 count, uint256 currentBlockNumber)
        internal
        returns (IRewardsController.UserBalanceUpdateData[] memory updates)
    {
        updates = new IRewardsController.UserBalanceUpdateData[](count);
        for (uint256 i = 0; i < count; i++) {
            // Use different users for multi-user updates
            address user = address(uint160(uint256(keccak256(abi.encodePacked("user", i + 1)))));
            updates[i] = IRewardsController.UserBalanceUpdateData({
                user: user,
                collection: collection,
                blockNumber: currentBlockNumber,
                nftDelta: 1,
                balanceDelta: int256((i + 1) * 1 ether) // Cast to int256
            });
        }
    }

    // Placeholders removed as tests are moved to separate files
}
