// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {RewardsController} from "../src/RewardsController.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendingManager} from "../src/mocks/MockLendingManager.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {ILendingManager} from "../src/interfaces/ILendingManager.sol";
import {IRewardsController} from "../src/interfaces/IRewardsController.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {MockTokenVault} from "../src/mocks/MockTokenVault.sol";
import {ECDSA} from "@openzeppelin-contracts-5.2.0/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin-contracts-5.2.0/utils/cryptography/EIP712.sol";

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

    // EIP-712 Type Hashes (Copied from RewardsController for signing tests)
    bytes32 public constant USER_BALANCE_UPDATE_DATA_TYPEHASH = keccak256(
        "UserBalanceUpdateData(address user,address collection,uint256 blockNumber,int256 nftDelta,int256 depositDelta)"
    );
    bytes32 public constant BALANCE_UPDATES_TYPEHASH =
        keccak256("BalanceUpdates(UserBalanceUpdateData[] updates,uint256 nonce)");
    bytes32 public constant BALANCE_UPDATE_DATA_TYPEHASH =
        keccak256("BalanceUpdateData(address collection,uint256 blockNumber,int256 nftDelta,int256 depositDelta)");
    bytes32 public constant USER_BALANCE_UPDATES_TYPEHASH =
        keccak256("UserBalanceUpdates(address user,BalanceUpdateData[] updates,uint256 nonce)");

    // --- Constants & Config ---
    address constant USER_A = address(0xAAA);
    address constant USER_B = address(0xBBB);
    address constant NFT_COLLECTION_1 = address(0xC1);
    address constant NFT_COLLECTION_2 = address(0xC2);
    address constant NFT_COLLECTION_3 = address(0xC3); // Unregistered
    address constant OWNER = address(0x001);
    address constant OTHER_ADDRESS = address(0x123);
    address constant NFT_UPDATER = address(0xBAD); // Simulate NFTDataUpdater
    // Define Foundry constants at contract level
    address constant DEFAULT_FOUNDRY_SENDER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant DEFAULT_FOUNDRY_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    uint256 constant PRECISION = 1e18;
    uint256 constant BETA_1 = 0.1 ether; // Example beta (needs scaling definition)
    uint256 constant BETA_2 = 0.05 ether; // Example beta

    // --- Contracts ---
    RewardsController rewardsController;
    MockLendingManager mockLM;
    MockERC20 rewardToken; // Same as LM asset
    MockTokenVault mockVault;

    // --- Helper Functions (Moved Up) --- //

    // Helper to create hash for BalanceUpdateData array (used inside UserBalanceUpdates)
    function _hashBalanceUpdates(IRewardsController.BalanceUpdateData[] memory updates)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory dataHashes = new bytes32[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            dataHashes[i] = keccak256(
                abi.encode(
                    BALANCE_UPDATE_DATA_TYPEHASH, // Use constant instead of function call
                    updates[i].collection,
                    updates[i].blockNumber,
                    updates[i].nftDelta,
                    updates[i].depositDelta
                )
            );
        }
        return keccak256(abi.encodePacked(dataHashes));
    }

    // Helper to sign UserBalanceUpdates (single user batch)
    function _signUserBalanceUpdates(
        address user,
        IRewardsController.BalanceUpdateData[] memory updates,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 updatesHash = _hashBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));

        // Use EIP712 compliant hashing to match contract implementation
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _buildDomainSeparator(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // Helper function to calculate domain separator the same way as the contract
    function _buildDomainSeparator() internal view returns (bytes32) {
        bytes32 typeHashDomain =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHashDomain = keccak256(bytes("RewardsController"));
        bytes32 versionHashDomain = keccak256(bytes("1"));

        return keccak256(
            abi.encode(typeHashDomain, nameHashDomain, versionHashDomain, block.chainid, address(rewardsController))
        );
    }

    // Helper to hash UserBalanceUpdateData array (used inside BalanceUpdates)
    function _hashMultiUserBalanceUpdates(IRewardsController.UserBalanceUpdateData[] memory updates)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory dataHashes = new bytes32[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            dataHashes[i] = keccak256(
                abi.encode(
                    USER_BALANCE_UPDATE_DATA_TYPEHASH, // Use the correct typehash for the inner struct
                    updates[i].user,
                    updates[i].collection,
                    updates[i].blockNumber,
                    updates[i].nftDelta,
                    updates[i].depositDelta
                )
            );
        }
        return keccak256(abi.encodePacked(dataHashes));
    }

    // Helper to sign BalanceUpdates (multi-user batch)
    function _signMultiUserBalanceUpdates(
        IRewardsController.UserBalanceUpdateData[] memory updates,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 updatesHash = _hashMultiUserBalanceUpdates(updates); // Helper to hash the inner structs correctly
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATES_TYPEHASH, updatesHash, nonce));
        // Calculate Domain Separator locally
        bytes32 typeHashDomain =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHashDomain = keccak256(bytes("RewardsController"));
        bytes32 versionHashDomain = keccak256(bytes("1"));
        bytes32 domainSeparator = keccak256(
            abi.encode(typeHashDomain, nameHashDomain, versionHashDomain, block.chainid, address(rewardsController))
        );
        // Construct the final digest according to EIP-712
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // --- Setup ---
    function setUp() public {
        vm.startPrank(OWNER);

        // Deploy Reward Token (Asset)
        rewardToken = new MockERC20("Reward Token", "RWD", 1_000_000 ether);

        // Deploy Mock Lending Manager
        mockLM = new MockLendingManager(address(rewardToken));

        // Deploy Mock Vault (needs asset)
        mockVault = new MockTokenVault(address(rewardToken));

        // Deploy RewardsController with mocks and OWNER as authorized updater
        rewardsController = new RewardsController(
            OWNER,
            address(mockLM),
            address(mockVault),
            DEFAULT_FOUNDRY_SENDER // Use default Foundry address as authorized updater
        );

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

    function test_Admin_SetAuthorizedUpdater() public {
        address newUpdater = address(0xABC);
        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.AuthorizedUpdaterChanged(DEFAULT_FOUNDRY_SENDER, newUpdater);
        rewardsController.setAuthorizedUpdater(newUpdater);
        vm.stopPrank();
        assertEq(rewardsController.authorizedUpdater(), newUpdater, "Updater address mismatch");
    }

    function test_RevertIf_SetAuthorizedUpdater_NotOwner() public {
        address newUpdater = address(0xABC);
        vm.startPrank(OTHER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.setAuthorizedUpdater(newUpdater);
        vm.stopPrank();
    }

    function test_RevertIf_SetAuthorizedUpdater_ZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(RewardsController.AddressZero.selector);
        rewardsController.setAuthorizedUpdater(address(0));
        vm.stopPrank();
    }

    // --- Test Balance Update Processing --- //

    // Simplified test using processUserBalanceUpdates
    function test_ProcessSingleUserBatchUpdate_Success() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        uint256 startBlock = block.number;
        uint256 updateBlock1 = startBlock + 1;
        uint256 updateBlock2 = startBlock + 5;

        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](4);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock1,
            nftDelta: 1,
            depositDelta: 0
        });
        updates[1] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock2,
            nftDelta: 0,
            depositDelta: 100 ether
        });
        updates[2] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock2,
            nftDelta: 2,
            depositDelta: 0
        });
        updates[3] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock2,
            nftDelta: 0,
            depositDelta: -50 ether
        });

        address authorizedSigner = DEFAULT_FOUNDRY_SENDER;
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;

        uint256 nonce = rewardsController.authorizedUpdaterNonce(authorizedSigner);
        // (bytes32 digest, bytes memory signature) = // digest unused
        bytes memory signature = _signUserBalanceUpdates(user, updates, nonce, signerPrivateKey); // Assign single return value

        vm.warp(updateBlock2); // Warp to the last update block

        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.UserBalanceUpdatesProcessed(user, nonce, updates.length);
        rewardsController.processUserBalanceUpdates(user, updates, signature);

        uint256 finalNonce = rewardsController.authorizedUpdaterNonce(authorizedSigner);
        assertEq(finalNonce, nonce + 1, "Nonce should increment");

        // Need view functions to check final user state (nft=3, deposit=50e18, block=updateBlock2)
    }

    function test_ProcessMultiUserBatchUpdate_Success() public {
        address user1 = USER_A;
        address user2 = USER_B;
        address collection1 = NFT_COLLECTION_1;
        address collection2 = NFT_COLLECTION_2;
        uint256 blockNum = block.number + 1;

        IRewardsController.UserBalanceUpdateData[] memory updates = new IRewardsController.UserBalanceUpdateData[](2);
        updates[0] = IRewardsController.UserBalanceUpdateData({
            user: user1,
            collection: collection1,
            blockNumber: blockNum,
            nftDelta: 1,
            depositDelta: 100 ether
        });
        updates[1] = IRewardsController.UserBalanceUpdateData({
            user: user2,
            collection: collection2,
            blockNumber: blockNum,
            nftDelta: 2,
            depositDelta: 0
        });

        address authorizedSigner = DEFAULT_FOUNDRY_SENDER;
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;

        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(authorizedSigner);
        bytes memory signature = _signMultiUserBalanceUpdates(updates, nonce0, signerPrivateKey); // Use correct function name and argument order

        vm.warp(blockNum);
        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.BalanceUpdatesProcessed(authorizedSigner, nonce0, 2);
        rewardsController.processBalanceUpdates(updates, signature);

        // Check nonce increment
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(authorizedSigner);
        assertEq(nonce1, nonce0 + 1, "Nonce should increment");

        // Check internal state (requires view functions or internal inspection mocks)
        // Need to check state for user1 and user2
    }

    function test_RevertIf_ProcessMultiUserBatchUpdate_InvalidNonceReplay() public {
        address authorizedSigner = DEFAULT_FOUNDRY_SENDER;
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;
        uint256 startBlock = block.number;

        // Create a simple multi-user batch update
        IRewardsController.UserBalanceUpdateData[] memory updates = new IRewardsController.UserBalanceUpdateData[](1);
        updates[0] = IRewardsController.UserBalanceUpdateData({
            user: USER_A,
            collection: NFT_COLLECTION_1,
            blockNumber: startBlock + 1,
            nftDelta: 1,
            depositDelta: 0
        });

        uint256 nonce = rewardsController.authorizedUpdaterNonce(authorizedSigner);

        // Sign the batch update
        bytes memory signature = _signMultiUserBalanceUpdates(updates, nonce, signerPrivateKey);

        // First call: Should succeed
        vm.prank(authorizedSigner);
        rewardsController.processBalanceUpdates(updates, signature);
        assertEq(
            rewardsController.authorizedUpdaterNonce(authorizedSigner),
            nonce + 1,
            "Nonce did not increment after first call"
        );

        // Second call with the same signature: Should revert due to nonce mismatch (detected as InvalidSignature)
        vm.prank(authorizedSigner);
        vm.expectRevert(RewardsController.InvalidSignature.selector);
        rewardsController.processBalanceUpdates(updates, signature);
    }

    function test_ProcessBalanceUpdates_SameBlock() public {
        uint256 updateBlock = block.number + 1;
        uint256 ownerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Default Foundry Anvil PK for 0xf39...

        // Update 1: NFT +1
        int256 nftDelta = 1;
        // Update 2: Deposit +100 (same block)
        int256 depositDelta = 100 ether;

        // Signatures
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        uint256 nonce1 = nonce0 + 1;

        // Mock initial deposits (can often be skipped)
        // vm.prank(OWNER);
        // mockVault.setDeposit(USER_A, NFT_COLLECTION_1, 0);
        // vm.stopPrank();

        vm.roll(updateBlock);

        // Process NFT update
        // Prepare the update data structure
        IRewardsController.BalanceUpdateData[] memory nftUpdates = new IRewardsController.BalanceUpdateData[](1);
        nftUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: updateBlock,
            nftDelta: nftDelta,
            depositDelta: 0 // Only NFT update in this call
        });

        // Expect the correct batch event
        // UserBalanceUpdatesProcessed(address indexed user, uint256 nonce, uint256 numUpdates)
        vm.expectEmit(
            true, // user indexed
            false, // nonce not indexed
            false, // numUpdates not indexed
            false, // check data (TEMPORARILY DISABLED)
            address(rewardsController)
        );
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce0, 1); // Check nonce0 and 1 update

        // Sign and call the correct batch update function
        bytes memory nftSig = _signUserBalanceUpdates(USER_A, nftUpdates, nonce0, ownerPrivateKey); // Use correct function name and argument order
        rewardsController.processUserBalanceUpdates(USER_A, nftUpdates, nftSig);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER), nonce1, "Nonce mismatch after NFT update"
        );

        // Process Deposit update (same block)
        // Prepare the update data structure for deposit
        IRewardsController.BalanceUpdateData[] memory depositUpdates = new IRewardsController.BalanceUpdateData[](1);
        depositUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: updateBlock,
            nftDelta: 0, // Only deposit update in this call
            depositDelta: depositDelta
        });

        // Expect the correct batch event
        // UserBalanceUpdatesProcessed(address indexed user, uint256 nonce, uint256 numUpdates)
        // Note: The nonce check should reflect the expected increment from the previous call.
        // The assertion on line 549 expects nonce1 + 1.
        vm.expectEmit(
            true, // user indexed
            false, // nonce not indexed
            false, // numUpdates not indexed
            false, // check data (TEMPORARILY DISABLED)
            address(rewardsController)
        );
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce1, 1); // Check nonce1 and 1 update

        // Sign and call the correct batch update function
        bytes memory depositSig = _signUserBalanceUpdates(USER_A, depositUpdates, nonce1, ownerPrivateKey); // Use correct function name and argument order
        rewardsController.processUserBalanceUpdates(USER_A, depositUpdates, depositSig);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce1 + 1,
            "Nonce mismatch after Deposit update"
        );

        // Verify final state - only balances change, no rewards accrue as no time passed
        (
            , // _lastRewardIndexState unused
            uint256 accruedBaseRewardState,
            uint256 accruedBonusRewardState,
            uint256 finalNFTBalanceState,
            uint256 finalDepositAmountState,
            uint256 finalUpdateBlockState
        ) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);

        assertEq(finalNFTBalanceState, 1, "Final NFT balance mismatch");
        assertEq(finalDepositAmountState, 100 ether, "Final deposit amount mismatch");
        assertEq(finalUpdateBlockState, updateBlock, "Final update block mismatch");

        // Read the full UserRewardState to check accrued rewards
        assertEq(accruedBaseRewardState, 0, "Accrued base reward should be 0");
        assertEq(accruedBonusRewardState, 0, "Accrued bonus reward should be 0");
    }

    function test_RevertIf_ProcessBalanceUpdates_OutOfOrder() public {
        // Setup Initial Update at block N+10
        uint256 updateBlock1 = block.number + 10;
        uint256 updateBlock2 = block.number + 5; // Out of order
        uint256 ownerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY; // Use default PK

        vm.prank(OWNER);
        int256 nftDelta1 = 1;
        int256 nftDelta2 = 1;

        // Signatures
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        uint256 nonce1 = nonce0 + 1;

        // Calculate Domain Separator manually
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256(bytes("RewardsController"));
        bytes32 versionHash = keccak256(bytes("1"));
        bytes32 domainSeparator =
            keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(rewardsController)));

        // 1. Sign first update (N+10)
        bytes32 nftStructHash1 = keccak256(
            abi.encode(
                rewardsController.BALANCE_UPDATE_DATA_TYPEHASH(),
                NFT_COLLECTION_1,
                updateBlock1,
                nftDelta1,
                0 // depositDelta placeholder
            )
        );
        bytes32 nftDigest1 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, nftStructHash1));
        console.log("--- OutOfOrder Test Debug NFT Sign 1 ---");
        console.logBytes32(nftDigest1);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPrivateKey, nftDigest1);
        bytes memory nftSig1 = abi.encodePacked(r1, s1, v1);

        // 2. Sign second update (N+5)
        bytes32 nftStructHash2 = keccak256(
            abi.encode(
                rewardsController.BALANCE_UPDATE_DATA_TYPEHASH(),
                NFT_COLLECTION_1,
                updateBlock2, // Block N+5
                nftDelta2,
                0 // depositDelta placeholder
            )
        );
        bytes32 nftDigest2 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, nftStructHash2));
        console.log("--- OutOfOrder Test Debug NFT Sign 2 ---");
        console.logBytes32(nftDigest2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ownerPrivateKey, nftDigest2);
        bytes memory nftSig2 = abi.encodePacked(r2, s2, v2);

        // Process the first update (N+10) successfully
        vm.roll(updateBlock1);
        rewardsController.processNFTBalanceUpdate(USER_A, NFT_COLLECTION_1, updateBlock1, nftDelta1, nftSig1);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce1,
            "Nonce mismatch after first update"
        );

        // Attempt to process the second update (N+5) - should revert
        // No need to roll block again, just try processing
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsController.UpdateOutOfOrder.selector,
                USER_A,
                NFT_COLLECTION_1,
                updateBlock2, // The block causing the error
                updateBlock1 // The last processed block
            )
        );
        rewardsController.processNFTBalanceUpdate(USER_A, NFT_COLLECTION_1, updateBlock2, nftDelta2, nftSig2);
    }

    function test_RevertIf_BalanceUpdateUnderflow_NFT() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        uint256 startBlock = block.number;

        // Process initial update (NFT = 1)
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory update1 = new IRewardsController.BalanceUpdateData[](1);
        update1[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: startBlock + 1,
            nftDelta: 1,
            depositDelta: 0
        });
        bytes memory sig1 = _signUserBalanceUpdates(user, update1, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        vm.prank(rewardsController.authorizedUpdater());
        rewardsController.processUserBalanceUpdates(user, update1, sig1);

        // Attempt to process underflow update (NFT delta = -2)
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory update2 = new IRewardsController.BalanceUpdateData[](1);
        // Current balance is 1, delta is -2, should underflow
        update2[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: startBlock + 2,
            nftDelta: -2,
            depositDelta: 0
        });
        bytes memory sig2 = _signUserBalanceUpdates(user, update2, nonce1, DEFAULT_FOUNDRY_PRIVATE_KEY);
        vm.prank(rewardsController.authorizedUpdater());
        vm.expectRevert(abi.encodeWithSelector(RewardsController.BalanceUpdateUnderflow.selector, 1, 2)); // current=1, deltaMag=2
        rewardsController.processUserBalanceUpdates(user, update2, sig2);
    }

    function test_RevertIf_BalanceUpdateUnderflow_Deposit() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        uint256 startBlock = block.number;
        uint256 initialDeposit = 50 ether;

        // Process initial update (Deposit = 50)
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory update1 = new IRewardsController.BalanceUpdateData[](1);
        update1[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: startBlock + 1,
            nftDelta: 0,
            depositDelta: int256(initialDeposit)
        });
        bytes memory sig1 = _signUserBalanceUpdates(user, update1, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        vm.prank(rewardsController.authorizedUpdater());
        rewardsController.processUserBalanceUpdates(user, update1, sig1);

        // Attempt to process underflow update (Deposit delta = -60)
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory update2 = new IRewardsController.BalanceUpdateData[](1);
        update2[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: startBlock + 2,
            nftDelta: 0,
            depositDelta: -60 ether
        });
        bytes memory sig2 = _signUserBalanceUpdates(user, update2, nonce1, DEFAULT_FOUNDRY_PRIVATE_KEY);
        vm.prank(rewardsController.authorizedUpdater());
        vm.expectRevert(
            abi.encodeWithSelector(RewardsController.BalanceUpdateUnderflow.selector, initialDeposit, 60 ether)
        ); // current=50, deltaMag=60
        rewardsController.processUserBalanceUpdates(user, update2, sig2);
    }

    // --- Test Multi-User Batch Updates --- //

    function test_ProcessBalanceUpdates_SkipsNonWhitelisted() public {
        uint256 startBlock = block.number;
        uint256 c1UpdateBlock = startBlock + 1;
        uint256 c3UpdateBlock = startBlock + 2;
        uint256 ownerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY; // Use default PK

        // Update 1: Whitelisted C1 (NFT +1, Deposit +100)
        int256 nftDeltaC1 = 1;
        int256 depositDeltaC1 = 100 ether;

        // Update 2: Non-whitelisted C3 (NFT +1, Deposit +50)
        int256 nftDeltaC3 = 1;
        int256 depositDeltaC3 = 50 ether;

        // Signatures
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        uint256 nonce1 = nonce0 + 1;
        // Nonces for C3 (not used for processUserBalanceUpdates calls)
        // uint256 nonce2 = nonce1 + 1; // Unused variable removed

        // Signatures for C3 (manual, potentially for processNFT/DepositUpdate calls later)
        // Calculate Domain Separator manually
        bytes32 typeHashDomain =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHashDomain = keccak256(bytes("RewardsController"));
        bytes32 versionHashDomain = keccak256(bytes("1"));
        bytes32 domainSeparator = keccak256(
            abi.encode(typeHashDomain, nameHashDomain, versionHashDomain, block.chainid, address(rewardsController))
        );
        // 3. Sign C3 NFT Update (N+2) - Expected to fail
        bytes32 nftStructHashC3 = keccak256(
            abi.encode(
                rewardsController.BALANCE_UPDATE_DATA_TYPEHASH(),
                NFT_COLLECTION_3,
                c3UpdateBlock,
                nftDeltaC3,
                0 // depositDelta placeholder
            )
        );
        bytes32 nftDigestC3 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, nftStructHashC3));
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(ownerPrivateKey, nftDigestC3);
        bytes memory nftSigC3 = abi.encodePacked(r3, s3, v3);

        // 4. Sign C3 Deposit Update (N+2) - Expected to fail
        bytes32 depositStructHashC3 = keccak256(
            abi.encode(
                rewardsController.BALANCE_UPDATE_DATA_TYPEHASH(),
                NFT_COLLECTION_3,
                c3UpdateBlock,
                0, // nftDelta placeholder
                depositDeltaC3
            )
        );
        bytes32 depositDigestC3 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, depositStructHashC3));
        (uint8 v4, bytes32 r4, bytes32 s4) = vm.sign(ownerPrivateKey, depositDigestC3);
        bytes memory depositSigC3 = abi.encodePacked(r4, s4, v4);

        // Process C1 updates (should succeed)
        vm.roll(c1UpdateBlock);
        // Prepare the update data structure for C1 NFT update
        IRewardsController.BalanceUpdateData[] memory nftUpdatesC1 = new IRewardsController.BalanceUpdateData[](1);
        nftUpdatesC1[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: c1UpdateBlock,
            nftDelta: nftDeltaC1,
            depositDelta: 0
        });

        // Expect the correct batch event
        // UserBalanceUpdatesProcessed(address indexed user, uint256 nonce, uint256 numUpdates)
        // The assertion on line 833 expects nonce1.
        vm.expectEmit(
            true, // user indexed
            false, // nonce not indexed
            false, // numUpdates not indexed
            true, // check data
            address(rewardsController)
        );
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce0, 1); // Check nonce0 and 1 update

        // Sign and call the correct batch update function
        bytes memory nftSigC1 = _signUserBalanceUpdates(USER_A, nftUpdatesC1, nonce0, ownerPrivateKey); // Use correct function name and argument order
        rewardsController.processUserBalanceUpdates(USER_A, nftUpdatesC1, nftSigC1);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce0 + 1,
            "Nonce mismatch after C1 NFT update"
        );

        // Prepare the update data structure for C1 deposit update
        IRewardsController.BalanceUpdateData[] memory depositUpdatesC1 = new IRewardsController.BalanceUpdateData[](1);
        depositUpdatesC1[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: c1UpdateBlock,
            nftDelta: 0,
            depositDelta: depositDeltaC1
        });

        // Expect the correct batch event
        // UserBalanceUpdatesProcessed(address indexed user, uint256 nonce, uint256 numUpdates)
        // The assertion on line 864 expects nonce2.
        vm.expectEmit(
            true, // user indexed
            false, // nonce not indexed
            false, // numUpdates not indexed
            true, // check data
            address(rewardsController)
        );
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce1, 1); // Check nonce1 and 1 update

        // Sign and call the correct batch update function
        bytes memory depositSigC1 = _signUserBalanceUpdates(USER_A, depositUpdatesC1, nonce1, ownerPrivateKey); // Use correct function name and argument order
        rewardsController.processUserBalanceUpdates(USER_A, depositUpdatesC1, depositSigC1);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce1 + 1,
            "Nonce mismatch after C1 Deposit update"
        );

        // Attempt to process C3 updates (should revert)
        vm.roll(c3UpdateBlock);
        bytes memory expectedRevertData =
            abi.encodeWithSelector(RewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3);

        vm.expectRevert(expectedRevertData);
        rewardsController.processNFTBalanceUpdate(USER_A, NFT_COLLECTION_3, c3UpdateBlock, nftDeltaC3, nftSigC3);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce1 + 1, // Nonce should not have incremented from the failed call
            "Nonce unchanged after failed C3 NFT update"
        );

        vm.expectRevert(expectedRevertData);
        rewardsController.processDepositUpdate(USER_A, NFT_COLLECTION_3, c3UpdateBlock, depositDeltaC3, depositSigC3);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce1 + 1, // Nonce should not have incremented from the failed call
            "Nonce unchanged after failed C3 Deposit update"
        );

        // Verify state for C1 is updated
        address[] memory collectionsToTrackC1 = new address[](1);
        collectionsToTrackC1[0] = NFT_COLLECTION_1;
        IRewardsController.UserCollectionTracking[] memory trackingInfoC1 =
            rewardsController.getUserCollectionTracking(USER_A, collectionsToTrackC1);
        uint256 finalNftC1 = trackingInfoC1[0].lastNFTBalance;
        uint256 finalDepositC1 = trackingInfoC1[0].lastDepositBalance;
        uint256 finalBlockC1 = trackingInfoC1[0].lastUpdateBlock;

        assertEq(finalNftC1, 1, "Final C1 NFT balance mismatch");
        assertEq(finalDepositC1, 100 ether, "Final C1 Deposit balance mismatch");
        assertEq(finalBlockC1, c1UpdateBlock, "Final C1 update block mismatch");

        // Verify state for C3 is unchanged (lastUpdateBlock should still be 0)
        address[] memory collectionsToTrackC3 = new address[](1);
        collectionsToTrackC3[0] = NFT_COLLECTION_3;
        IRewardsController.UserCollectionTracking[] memory trackingInfoC3 =
            rewardsController.getUserCollectionTracking(USER_A, collectionsToTrackC3);
        uint256 finalNftC3 = trackingInfoC3[0].lastNFTBalance;
        uint256 finalDepositC3 = trackingInfoC3[0].lastDepositBalance;
        uint256 finalBlockC3 = trackingInfoC3[0].lastUpdateBlock;

        assertEq(finalNftC3, 0, "Final C3 NFT balance should be 0");
        assertEq(finalDepositC3, 0, "Final C3 Deposit balance should be 0");
        assertEq(finalBlockC3, 0, "Final C3 update block should be 0");
    }

    // --- Test Reward Calculation & Boost --- //

    function test_CalculateBoost_ZeroNFTs() public view {
        uint256 boost = rewardsController.calculateBoost(0, BETA_1);
        assertEq(boost, 0, "Boost should be 0 for 0 NFTs");
    }

    function test_CalculateBoost_OneNFT() public view {
        uint256 expectedBoost = 1 * BETA_1; // 1 * 0.1e18 = 0.1e18
        uint256 boost = rewardsController.calculateBoost(1, BETA_1);
        assertEq(boost, expectedBoost, "Boost mismatch for 1 NFT");
    }

    function test_CalculateBoost_MultipleNFTs() public view {
        uint256 nftCount = 5;
        uint256 expectedBoost = nftCount * BETA_1; // 5 * 0.1e18 = 0.5e18
        uint256 boost = rewardsController.calculateBoost(nftCount, BETA_1);
        assertEq(boost, expectedBoost, "Boost mismatch for multiple NFTs");
    }

    function test_CalculateBoost_MaxBoostCapped() public view {
        // Beta = 0.1e18. Max boost is 9 * PRECISION = 9e18.
        // Need 91 NFTs to exceed max boost (91 * 0.1e18 = 9.1e18)
        uint256 nftCount = 91;
        uint256 expectedMaxBoost = 9 * PRECISION;
        uint256 boost = rewardsController.calculateBoost(nftCount, BETA_1);
        assertEq(boost, expectedMaxBoost, "Boost should be capped at 900%");

        // Test exactly at cap boundary
        nftCount = 90;
        expectedMaxBoost = 90 * BETA_1; // 90 * 0.1e18 = 9e18
        boost = rewardsController.calculateBoost(nftCount, BETA_1);
        assertEq(boost, expectedMaxBoost, "Boost should be exactly 900% at boundary");
    }

    function test_RewardCalculation_Basic_NoBoost() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        uint256 depositAmount = 100 ether;
        uint256 startBlock = block.number;
        uint256 updateBlock = startBlock + 1;
        uint256 blockDiffForIndexCalc = updateBlock - startBlock; // Calculate diff *before* rolling time
        uint256 blocksPassed = 10;
        uint256 endBlock = updateBlock + blocksPassed;
        // --- Setup Mock LM ---
        // Rate = 0.01 RWD per block / 1000 RWD total assets = 0.00001 per unit per block
        uint256 mockRewardPerBlock = 0.01 ether;
        uint256 mockTotalLMAssets = 1000 ether;
        mockLM.setMockBaseRewardPerBlock(mockRewardPerBlock);
        mockLM.setMockTotalAssets(mockTotalLMAssets);
        uint256 expectedRatePerUnitPerBlock = (mockRewardPerBlock * PRECISION) / mockTotalLMAssets; // 1e13
        // console.log("expectedRatePerUnitPerBlock:", expectedRatePerUnitPerBlock); // Cleaned up log

        // --- Process Deposit Update ---
        vm.roll(updateBlock); // Move to update block
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock,
            nftDelta: 0, // No NFTs
            depositDelta: int256(depositAmount)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(user, updates, sig);

        // --- Check Rewards After Time Passes ---
        vm.roll(endBlock); // Move forward 10 blocks

        // Expected index increase = blocksPassed * ratePerUnitPerBlock
        uint256 expectedIndexIncrease = blocksPassed * expectedRatePerUnitPerBlock; // 10 * 1e13 = 1e14
        // Expected reward = depositAmount * indexIncrease / PRECISION
        uint256 expectedReward = (depositAmount * expectedIndexIncrease) / PRECISION; // 100e18 * 1e14 / 1e18 = 100e14 = 0.01 ether

        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collection;
        IRewardsController.BalanceUpdateData[] memory noSimulatedUpdates; // Empty array

        uint256 pendingReward = rewardsController.previewRewards(user, collectionsToPreview, noSimulatedUpdates);

        assertEq(pendingReward, expectedReward, "Pending reward mismatch (no boost)");

        // --- Verify internal state update ---
        // userNFTData is a VIEW function, it returns the state as recorded at the last actual update (updateBlock).
        (uint256 lastIdx,,,,, uint256 lastUpdateBlk) = rewardsController.userNFTData(user, collection);

        // Expected index is the global index *at updateBlock* when the state was last written.
        // Index increase from startBlock to updateBlock = (updateBlock - startBlock) * rate.
        // expectedRatePerUnitPerBlock is calculated on line 913
        // console.log("Calculating expectedIndexAtUpdateBlock..."); // Cleaned up log
        // console.log("PRECISION:", PRECISION); // Cleaned up log
        // console.log("Value of updateBlock just before subtraction:", updateBlock); // Cleaned up log
        // console.log("Using pre-calculated blockDiffForIndexCalc:", blockDiffForIndexCalc); // Cleaned up log
        // console.log( // Cleaned up log
        //     "blockDiffForIndexCalc * expectedRatePerUnitPerBlock:", // Cleaned up log
        //     blockDiffForIndexCalc * expectedRatePerUnitPerBlock // Cleaned up log
        // ); // Cleaned up log
        uint256 expectedIndexAtUpdateBlock = PRECISION + blockDiffForIndexCalc * expectedRatePerUnitPerBlock; // Use pre-calculated diff
        // console.log("expectedIndexAtUpdateBlock:", expectedIndexAtUpdateBlock); // Cleaned up log

        // The state read by userNFTData should match the state written at updateBlock.
        assertEq(lastIdx, expectedIndexAtUpdateBlock, "User last index mismatch (should match index at updateBlock)");
        assertEq(lastUpdateBlk, updateBlock, "User last update block mismatch (should be updateBlock)");
    }

    function test_RewardCalculation_WithBoost() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1; // Beta = 0.1 ether
        uint256 depositAmount = 100 ether;
        uint256 nftCount = 2;
        uint256 startBlock = block.number;
        uint256 updateBlock = startBlock + 1;
        uint256 blocksPassed = 10;
        uint256 endBlock = updateBlock + blocksPassed;

        // --- Setup Mock LM ---
        uint256 mockRewardPerBlock = 0.01 ether;
        uint256 mockTotalLMAssets = 1000 ether;
        mockLM.setMockBaseRewardPerBlock(mockRewardPerBlock);
        mockLM.setMockTotalAssets(mockTotalLMAssets);
        uint256 expectedRatePerUnitPerBlock = (mockRewardPerBlock * PRECISION) / mockTotalLMAssets; // 1e13

        // --- Process Deposit & NFT Update ---
        vm.roll(updateBlock);
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection, // Add the missing collection field
            blockNumber: updateBlock,
            nftDelta: int256(nftCount),
            depositDelta: int256(depositAmount)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(user, updates, sig);

        // --- Check Rewards After Time Passes ---
        vm.roll(endBlock);

        // Expected index increase = blocksPassed * ratePerUnitPerBlock = 1e14
        uint256 expectedIndexIncrease = blocksPassed * expectedRatePerUnitPerBlock;
        // Expected base reward = depositAmount * indexIncrease / PRECISION = 0.01 ether
        uint256 expectedBaseReward = (depositAmount * expectedIndexIncrease) / PRECISION;
        // Expected boost factor = nftCount * beta = 2 * 0.1e18 = 0.2e18
        uint256 expectedBoostFactor = nftCount * BETA_1;
        // Expected bonus reward = baseReward * boostFactor / PRECISION = 0.01e18 * 0.2e18 / 1e18 = 0.002 ether
        uint256 expectedBonusReward = (expectedBaseReward * expectedBoostFactor) / PRECISION;
        // Expected total reward = base + bonus = 0.01 + 0.002 = 0.012 ether
        uint256 expectedTotalReward = expectedBaseReward + expectedBonusReward;

        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collection;
        IRewardsController.BalanceUpdateData[] memory noSimulatedUpdates;

        uint256 pendingReward = rewardsController.previewRewards(user, collectionsToPreview, noSimulatedUpdates);

        assertEq(pendingReward, expectedTotalReward, "Pending reward mismatch (with boost)");
    }

    // --- Test Claiming Logic --- //

    function test_ClaimRewards_ZeroRewards() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;

        // User has no deposits or NFTs, no time passed
        vm.startPrank(user);
        vm.expectRevert(RewardsController.NoRewardsToClaim.selector);
        rewardsController.claimRewardsForCollection(collection);
        vm.stopPrank();

        // Add a deposit but don't advance time
        uint256 updateBlock = block.number + 1;
        vm.roll(updateBlock);
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock,
            nftDelta: 0,
            depositDelta: 100 ether
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(user, updates, sig);

        // Still no time passed since deposit, so no rewards
        vm.startPrank(user);
        vm.expectRevert(RewardsController.NoRewardsToClaim.selector);
        rewardsController.claimRewardsForCollection(collection);
        vm.stopPrank();
    }

    function test_ClaimRewards_SingleCollection_Success() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1; // Beta = 0.1 ether
        uint256 depositAmount = 100 ether;
        uint256 nftCount = 2;
        uint256 startBlock = block.number;
        uint256 updateBlock = startBlock + 1;
        uint256 blocksPassed = 10;
        uint256 claimBlock = updateBlock + blocksPassed;

        // --- Setup Mock LM ---
        uint256 mockRewardPerBlock = 0.01 ether;
        uint256 mockTotalLMAssets = 1000 ether;
        mockLM.setMockBaseRewardPerBlock(mockRewardPerBlock);
        mockLM.setMockTotalAssets(mockTotalLMAssets);
        uint256 expectedRatePerUnitPerBlock = (mockRewardPerBlock * PRECISION) / mockTotalLMAssets; // 1e13

        // --- Process Deposit & NFT Update ---
        vm.roll(updateBlock);
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock,
            nftDelta: int256(nftCount),
            depositDelta: int256(depositAmount)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(user, updates, sig);

        // --- Advance time and calculate expected reward ---
        vm.roll(claimBlock);

        uint256 expectedIndexIncrease = blocksPassed * expectedRatePerUnitPerBlock; // 1e14
        uint256 expectedBaseReward = (depositAmount * expectedIndexIncrease) / PRECISION; // 0.01 ether
        uint256 expectedBoostFactor = nftCount * BETA_1; // 0.2e18
        uint256 expectedBonusReward = (expectedBaseReward * expectedBoostFactor) / PRECISION; // 0.002 ether
        uint256 expectedTotalReward = expectedBaseReward + expectedBonusReward; // 0.012 ether

        // --- Claim Rewards ---
        vm.startPrank(user);
        uint256 balanceBefore = rewardToken.balanceOf(user);

        vm.expectEmit(true, true, true, true, address(rewardsController));
        emit IRewardsController.RewardsClaimedForCollection(user, collection, expectedTotalReward);
        rewardsController.claimRewardsForCollection(collection);

        uint256 balanceAfter = rewardToken.balanceOf(user);
        assertEq(balanceAfter - balanceBefore, expectedTotalReward, "User RWD balance mismatch after claim");

        // --- Verify internal state reset ---
        (uint256 lastIdx, uint256 accrued,, uint256 nftBal, uint256 depAmt, uint256 lastUpdateBlk) =
            rewardsController.userNFTData(user, collection);

        uint256 expectedGlobalIndexAtClaim = rewardsController.globalRewardIndex(); // Index should be updated by claim

        assertEq(accrued, 0, "Accrued reward should be 0 after claim");
        assertEq(lastIdx, expectedGlobalIndexAtClaim, "User last index mismatch after claim");
        assertEq(lastUpdateBlk, claimBlock, "User last update block mismatch after claim");
        assertEq(nftBal, nftCount, "NFT balance should persist after claim");
        assertEq(depAmt, depositAmount, "Deposit amount should persist after claim");

        // --- Try claiming again immediately (should fail) ---
        vm.expectRevert(RewardsController.NoRewardsToClaim.selector);
        rewardsController.claimRewardsForCollection(collection);
        vm.stopPrank();
    }

    function test_ClaimRewards_ForAll_MultipleCollections() public {
        address user = USER_A;
        address collection1 = NFT_COLLECTION_1; // Beta = 0.1 ether
        address collection2 = NFT_COLLECTION_2; // Beta = 0.05 ether
        uint256 deposit1 = 100 ether;
        uint256 nft1 = 1;
        uint256 deposit2 = 50 ether;
        uint256 nft2 = 3;

        uint256 startBlock = block.number;
        uint256 updateBlock = startBlock + 1;
        uint256 blocksPassed = 20;
        uint256 claimBlock = updateBlock + blocksPassed;

        // --- Setup Mock LM ---
        uint256 mockRewardPerBlock = 0.02 ether; // Higher rate
        uint256 mockTotalLMAssets = 1000 ether;
        mockLM.setMockBaseRewardPerBlock(mockRewardPerBlock);
        mockLM.setMockTotalAssets(mockTotalLMAssets);
        uint256 expectedRatePerUnitPerBlock = (mockRewardPerBlock * PRECISION) / mockTotalLMAssets; // 2e13

        // --- Process Updates for Both Collections ---
        vm.roll(updateBlock);
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](2);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection1,
            blockNumber: updateBlock,
            nftDelta: int256(nft1),
            depositDelta: int256(deposit1)
        });
        updates[1] = IRewardsController.BalanceUpdateData({
            collection: collection2,
            blockNumber: updateBlock,
            nftDelta: int256(nft2),
            depositDelta: int256(deposit2)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(user, updates, sig);

        // --- Advance time and calculate expected rewards ---
        vm.roll(claimBlock);

        uint256 expectedIndexIncrease = blocksPassed * expectedRatePerUnitPerBlock; // 20 * 2e13 = 4e14

        // Collection 1
        uint256 base1 = (deposit1 * expectedIndexIncrease) / PRECISION; // 100e18 * 4e14 / 1e18 = 400e14 = 0.04 ether
        uint256 boostFactor1 = nft1 * BETA_1; // 1 * 0.1e18 = 0.1e18
        uint256 bonus1 = (base1 * boostFactor1) / PRECISION; // 0.04e18 * 0.1e18 / 1e18 = 0.004 ether
        uint256 total1 = base1 + bonus1; // 0.044 ether

        // Collection 2
        uint256 base2 = (deposit2 * expectedIndexIncrease) / PRECISION; // 50e18 * 4e14 / 1e18 = 200e14 = 0.02 ether
        uint256 boostFactor2 = nft2 * BETA_2; // 3 * 0.05e18 = 0.15e18
        uint256 bonus2 = (base2 * boostFactor2) / PRECISION; // 0.02e18 * 0.15e18 / 1e18 = 0.003 ether
        uint256 total2 = base2 + bonus2; // 0.023 ether

        uint256 expectedTotalReward = total1 + total2; // 0.067 ether

        // --- Claim All Rewards ---
        vm.startPrank(user);
        uint256 balanceBefore = rewardToken.balanceOf(user);

        vm.expectEmit(true, true, true, true, address(rewardsController)); // Emit for C1
        emit IRewardsController.RewardsClaimedForCollection(user, collection1, total1);
        vm.expectEmit(true, true, true, true, address(rewardsController)); // Emit for C2
        emit IRewardsController.RewardsClaimedForCollection(user, collection2, total2);
        vm.expectEmit(true, false, false, true, address(rewardsController)); // Emit for All
        emit IRewardsController.RewardsClaimedForAll(user, expectedTotalReward);

        rewardsController.claimRewardsForAll();

        uint256 balanceAfter = rewardToken.balanceOf(user);
        assertEq(balanceAfter - balanceBefore, expectedTotalReward, "User RWD balance mismatch after claim all");

        // --- Verify internal state reset for both collections ---
        uint256 expectedGlobalIndexAtClaim = rewardsController.globalRewardIndex();

        (uint256 lastIdx1, uint256 accrued1,,,, uint256 lastUpdateBlk1) =
            rewardsController.userNFTData(user, collection1);
        assertEq(accrued1, 0, "C1 Accrued reward should be 0");
        assertEq(lastIdx1, expectedGlobalIndexAtClaim, "C1 User last index mismatch");
        assertEq(lastUpdateBlk1, claimBlock, "C1 User last update block mismatch");

        (uint256 lastIdx2, uint256 accrued2,,,, uint256 lastUpdateBlk2) =
            rewardsController.userNFTData(user, collection2);
        assertEq(accrued2, 0, "C2 Accrued reward should be 0");
        assertEq(lastIdx2, expectedGlobalIndexAtClaim, "C2 User last index mismatch");
        assertEq(lastUpdateBlk2, claimBlock, "C2 User last update block mismatch");

        vm.stopPrank();
    }

    function test_RevertIf_ClaimRewards_TransferYieldFails() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        uint256 depositAmount = 100 ether;
        uint256 startBlock = block.number;
        uint256 updateBlock = startBlock + 1;
        uint256 blocksPassed = 10;
        uint256 claimBlock = updateBlock + blocksPassed;

        // --- Setup Mock LM to revert ---
        mockLM.setMockBaseRewardPerBlock(0.01 ether); // Need some reward rate
        mockLM.setMockTotalAssets(1000 ether);
        mockLM.setShouldTransferYieldRevert(true); // Force revert

        // --- Process Deposit Update ---
        vm.roll(updateBlock);
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock,
            nftDelta: 0,
            depositDelta: int256(depositAmount)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(user, updates, sig);

        // --- Advance time ---
        vm.roll(claimBlock);

        // --- Get state BEFORE claim attempt ---
        (uint256 lastIdxBefore, uint256 accruedBefore,,,, uint256 lastUpdateBlkBefore) =
            rewardsController.userNFTData(user, collection);
        // Calculate expected accrued reward before claim (should be non-zero based on test setup)
        // Use previewRewards to get the expected accrued amount just before the claim attempt
        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collection;
        uint256 expectedAccruedBefore =
            rewardsController.previewRewards(user, collectionsToPreview, new IRewardsController.BalanceUpdateData[](0));
        assertTrue(expectedAccruedBefore > 0, "Test setup error: No rewards accrued before claim attempt");
        // Sanity check: ensure the stored accrued value matches the preview calculation before the claim
        assertEq(accruedBefore, 0, "Stored accrued reward should be 0 before claim calculation"); // Accrued state is only updated in _processSingleUpdate

        // --- Attempt Claim (should revert due to LM revert) ---
        vm.startPrank(user);
        vm.expectRevert("MockLM: transferYield forced revert");
        rewardsController.claimRewardsForCollection(collection);
        vm.stopPrank();

        // --- Verify internal state NOT changed by the reverted transaction ---
        (uint256 lastIdxAfter, uint256 accruedAfter,,,, uint256 lastUpdateBlkAfter) =
            rewardsController.userNFTData(user, collection);

        assertEq(lastUpdateBlkAfter, lastUpdateBlkBefore, "User last update block should not change on failed claim");
        // The stored accruedReward state variable should remain 0 as it was before the claim attempt
        assertEq(accruedAfter, accruedBefore, "User stored accrued reward should not change on failed claim");
        assertEq(accruedAfter, 0, "User stored accrued reward should still be 0 after failed claim");
        assertEq(lastIdxAfter, lastIdxBefore, "User last index should not change on failed claim");
    }

    // --- Test Preview Logic --- //

    function test_PreviewRewards_WithSimulatedUpdates() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        uint256 depositAmount = 100 ether;
        uint256 startBlock = block.number;
        uint256 updateBlock1 = startBlock + 1; // Initial deposit
        uint256 blocksPassed1 = 10;
        uint256 updateBlock2 = updateBlock1 + blocksPassed1; // Simulate NFT add
        uint256 blocksPassed2 = 5;
        uint256 previewBlock = updateBlock2 + blocksPassed2; // Block to call preview

        // --- Setup Mock LM ---
        uint256 mockRewardPerBlock = 0.01 ether;
        uint256 mockTotalLMAssets = 1000 ether;
        mockLM.setMockBaseRewardPerBlock(mockRewardPerBlock);
        mockLM.setMockTotalAssets(mockTotalLMAssets);
        uint256 ratePerUnit = (mockRewardPerBlock * PRECISION) / mockTotalLMAssets; // 1e13

        // --- Process Initial Deposit ---
        vm.roll(updateBlock1);
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory initialUpdates = new IRewardsController.BalanceUpdateData[](1);
        initialUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock1,
            nftDelta: 0,
            depositDelta: int256(depositAmount)
        });
        bytes memory sig0 = _signUserBalanceUpdates(user, initialUpdates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(user, initialUpdates, sig0);

        // --- Prepare Simulated Update ---
        IRewardsController.BalanceUpdateData[] memory simulatedUpdates = new IRewardsController.BalanceUpdateData[](1);
        simulatedUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock2, // Simulate at this block
            nftDelta: 1, // Add 1 NFT
            depositDelta: 0
        });

        // --- Call Preview at previewBlock ---
        vm.roll(previewBlock);

        // --- Calculate Expected Reward Manually ---
        // Period 1: updateBlock1 to updateBlock2 (10 blocks, 0 NFTs)
        uint256 indexIncrease1 = blocksPassed1 * ratePerUnit; // 10 * 1e13 = 1e14
        uint256 reward1 = (depositAmount * indexIncrease1) / PRECISION; // 100e18 * 1e14 / 1e18 = 0.01 ether

        // Period 2: updateBlock2 to previewBlock (5 blocks, 1 NFT)
        uint256 indexIncrease2 = blocksPassed2 * ratePerUnit; // 5 * 1e13 = 5e13
        uint256 baseReward2 = (depositAmount * indexIncrease2) / PRECISION; // 100e18 * 5e13 / 1e18 = 50e13 = 0.0005 ether
        uint256 boostFactor = 1 * BETA_1; // 0.1e18
        uint256 bonusReward2 = (baseReward2 * boostFactor) / PRECISION; // 0.0005e18 * 0.1e18 / 1e18 = 0.00005 ether
        uint256 reward2 = baseReward2 + bonusReward2; // 0.00055 ether

        uint256 expectedTotalReward = reward1 + reward2; // 0.01055 ether

        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collection;

        uint256 pendingReward = rewardsController.previewRewards(user, collectionsToPreview, simulatedUpdates);

        assertEq(pendingReward, expectedTotalReward, "Preview reward mismatch with simulation");
    }

    function test_PreviewRewards_MultipleCollections_NoSimulation() public {
        address user = USER_A;
        address collection1 = NFT_COLLECTION_1; // Beta = 0.1 ether
        address collection2 = NFT_COLLECTION_2; // Beta = 0.05 ether
        uint256 deposit1 = 100 ether;
        uint256 nft1 = 1;
        uint256 deposit2 = 50 ether;
        uint256 nft2 = 3;

        uint256 startBlock = block.number;
        uint256 updateBlock = startBlock + 1;
        uint256 blocksPassed = 20;
        uint256 previewBlock = updateBlock + blocksPassed;

        // --- Setup Mock LM ---
        uint256 mockRewardPerBlock = 0.02 ether;
        uint256 mockTotalLMAssets = 1000 ether;
        mockLM.setMockBaseRewardPerBlock(mockRewardPerBlock);
        mockLM.setMockTotalAssets(mockTotalLMAssets);
        uint256 ratePerUnit = (mockRewardPerBlock * PRECISION) / mockTotalLMAssets; // 2e13

        // --- Process Updates for Both Collections ---
        vm.roll(updateBlock);
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](2);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection1,
            blockNumber: updateBlock,
            nftDelta: int256(nft1),
            depositDelta: int256(deposit1)
        });
        updates[1] = IRewardsController.BalanceUpdateData({
            collection: collection2,
            blockNumber: updateBlock,
            nftDelta: int256(nft2),
            depositDelta: int256(deposit2)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(user, updates, sig);

        // --- Advance time and calculate expected rewards ---
        vm.roll(previewBlock);

        uint256 expectedIndexIncrease = blocksPassed * ratePerUnit; // 20 * 2e13 = 4e14

        // Collection 1
        uint256 base1 = (deposit1 * expectedIndexIncrease) / PRECISION; // 0.04 ether
        uint256 boostFactor1 = nft1 * BETA_1; // 0.1e18
        uint256 bonus1 = (base1 * boostFactor1) / PRECISION; // 0.004 ether
        uint256 total1 = base1 + bonus1; // 0.044 ether

        // Collection 2
        uint256 base2 = (deposit2 * expectedIndexIncrease) / PRECISION; // 0.02 ether
        uint256 boostFactor2 = nft2 * BETA_2; // 0.15e18
        uint256 bonus2 = (base2 * boostFactor2) / PRECISION; // 0.003 ether
        uint256 total2 = base2 + bonus2; // 0.023 ether

        uint256 expectedTotalReward = total1 + total2; // 0.067 ether

        // --- Preview Rewards for both collections ---
        address[] memory collectionsToPreview = new address[](2);
        collectionsToPreview[0] = collection1;
        collectionsToPreview[1] = collection2;
        IRewardsController.BalanceUpdateData[] memory noSimulatedUpdates;

        uint256 pendingReward = rewardsController.previewRewards(user, collectionsToPreview, noSimulatedUpdates);

        assertEq(pendingReward, expectedTotalReward, "Preview reward mismatch for multiple collections");

        // --- Preview Rewards for only one collection ---
        address[] memory collectionsToPreviewOne = new address[](1);
        collectionsToPreviewOne[0] = collection1;
        pendingReward = rewardsController.previewRewards(user, collectionsToPreviewOne, noSimulatedUpdates);
        assertEq(pendingReward, total1, "Preview reward mismatch for single collection (C1)");

        // --- Preview Rewards including non-whitelisted (should be ignored) ---
        address[] memory collectionsToPreviewMixed = new address[](3);
        collectionsToPreviewMixed[0] = collection1;
        collectionsToPreviewMixed[1] = NFT_COLLECTION_3; // Not whitelisted
        collectionsToPreviewMixed[2] = collection2;
        pendingReward = rewardsController.previewRewards(user, collectionsToPreviewMixed, noSimulatedUpdates);
        assertEq(pendingReward, expectedTotalReward, "Preview reward mismatch with non-whitelisted collection included");
    }
    // --- Test Claiming Logic (Refactored for processBalanceUpdates) --- //

    function test_ClaimRewards_Simple() public {
        // ... existing code ...
    }

    // Removed redundant test_ProcessBalanceUpdates_Replay

    // Renamed from test_RevertIf_ProcessMultiUserBatchUpdate_InvalidNonceReplay
    function test_RevertIf_ProcessBalanceUpdates_Replay() public {
        address authorizedSigner = DEFAULT_FOUNDRY_SENDER;
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;
        uint256 startBlock = block.number;

        // Create a simple multi-user batch update
        IRewardsController.UserBalanceUpdateData[] memory updates = new IRewardsController.UserBalanceUpdateData[](1);
        updates[0] = IRewardsController.UserBalanceUpdateData({
            user: USER_A,
            collection: NFT_COLLECTION_1,
            blockNumber: startBlock + 1,
            nftDelta: 1,
            depositDelta: 0
        });

        uint256 nonce = rewardsController.authorizedUpdaterNonce(authorizedSigner);

        // Sign the batch update
        // Use the correct helper function name
        bytes memory signature = _signMultiUserBalanceUpdates(updates, nonce, signerPrivateKey);

        // First call: Should succeed
        // No need for prank if caller is the authorized updater
        // vm.prank(authorizedSigner);
        rewardsController.processBalanceUpdates(updates, signature);
        assertEq(
            rewardsController.authorizedUpdaterNonce(authorizedSigner),
            nonce + 1,
            "Nonce did not increment after first call"
        );

        // Second call with the same signature: Should revert due to nonce mismatch (detected as InvalidSignature)
        // vm.prank(authorizedSigner); // No need for prank if caller is the authorized updater
        vm.expectRevert(RewardsController.InvalidSignature.selector);
        rewardsController.processBalanceUpdates(updates, signature);
    }

    function test_RevertIf_ProcessUserBalanceUpdates_Replay() public {
        address user1 = USER_A;
        address authorizedSigner = DEFAULT_FOUNDRY_SENDER;
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;
        uint256 startBlock = block.number;

        IRewardsController.BalanceUpdateData[] memory replayUpdates = new IRewardsController.BalanceUpdateData[](1);
        replayUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: startBlock + 1,
            nftDelta: 1,
            depositDelta: 0
        });

        // Sign first time
        uint256 nonce = rewardsController.authorizedUpdaterNonce(authorizedSigner);
        // Use the correct helper function name
        bytes memory signature = _signUserBalanceUpdates(user1, replayUpdates, nonce, signerPrivateKey);

        // Process first time (should succeed)
        // No need for prank if caller is the authorized updater
        // vm.prank(authorizedSigner);
        rewardsController.processUserBalanceUpdates(user1, replayUpdates, signature);
        assertEq(
            rewardsController.authorizedUpdaterNonce(authorizedSigner),
            nonce + 1,
            "Nonce did not increment after first call"
        );

        // Second call with the same signature: Should revert due to nonce mismatch (detected as InvalidSignature)
        // vm.prank(authorizedSigner); // No need for prank if caller is the authorized updater
        vm.expectRevert(RewardsController.InvalidSignature.selector);
        rewardsController.processUserBalanceUpdates(user1, replayUpdates, signature);
    }
    // End of tests
}
// Removed extra closing brace
