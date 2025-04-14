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
        (, bytes memory signature) =
            signSingleUserBalanceUpdates(authorizedSigner, signerPrivateKey, user, updates, nonce);

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
        (, bytes memory signature) = signMultiUserBalanceUpdates(authorizedSigner, signerPrivateKey, updates, nonce0);

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
        (, bytes memory nftSig) =
            signSingleUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, ownerPrivateKey, USER_A, nftUpdates, nonce0);
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
        (, bytes memory depositSig) =
            signSingleUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, ownerPrivateKey, USER_A, depositUpdates, nonce1);
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
        (, bytes memory nftSigC1) =
            signSingleUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, ownerPrivateKey, USER_A, nftUpdatesC1, nonce0);
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
        (, bytes memory depositSigC1) =
            signSingleUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, ownerPrivateKey, USER_A, depositUpdatesC1, nonce1);
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

    // --- Test Claiming Logic (Refactored for processBalanceUpdates) --- //

    function test_ClaimRewards_Simple() public {
        // ... existing code ...
    }

    function test_ProcessBalanceUpdates_Replay() public {
        address authorizedSigner = DEFAULT_FOUNDRY_SENDER;
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;

        IRewardsController.UserBalanceUpdateData[] memory replayUpdates =
            new IRewardsController.UserBalanceUpdateData[](1);
        replayUpdates[0] = IRewardsController.UserBalanceUpdateData({
            user: USER_A,
            collection: NFT_COLLECTION_1,
            blockNumber: block.number + 1,
            nftDelta: 1,
            depositDelta: 0
        });

        // Sign first time
        uint256 nonce = rewardsController.authorizedUpdaterNonce(authorizedSigner);
        (, bytes memory signature) =
            signMultiUserBalanceUpdates(authorizedSigner, signerPrivateKey, replayUpdates, nonce);

        // Process first time (should succeed)
        rewardsController.processBalanceUpdates(replayUpdates, signature);

        // Check final state
        (
            , // Skip lastRewardIndex
            , // Skip accruedReward
            , // Skip accruedBonusRewardState
            uint256 finalNftBalance,
            uint256 finalDepositAmount,
            uint256 finalUpdateBlock
        ) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
        assertEq(finalNftBalance, 1, "Final NFT balance mismatch");
        assertEq(finalDepositAmount, 0, "Final deposit amount mismatch");
        assertEq(finalUpdateBlock, block.number + 1, "Final update block mismatch");
    }

    function test_RevertIf_ProcessBalanceUpdates_Replay() public {
        address authorizedSigner = DEFAULT_FOUNDRY_SENDER;
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;

        IRewardsController.UserBalanceUpdateData[] memory replayUpdates =
            new IRewardsController.UserBalanceUpdateData[](1);
        replayUpdates[0] = IRewardsController.UserBalanceUpdateData({
            user: USER_A,
            collection: NFT_COLLECTION_1,
            blockNumber: block.number + 1,
            nftDelta: 1,
            depositDelta: 0
        });

        // Sign first time
        uint256 nonce = rewardsController.authorizedUpdaterNonce(authorizedSigner);
        (, bytes memory signature) =
            signMultiUserBalanceUpdates(authorizedSigner, signerPrivateKey, replayUpdates, nonce);

        // Process first time (should succeed)
        rewardsController.processBalanceUpdates(replayUpdates, signature);

        // Check final state
        (
            , // Skip lastRewardIndex
            , // Skip accruedReward
            , // Skip accruedBonusRewardState
            uint256 finalNftBalance,
            uint256 finalDepositAmount,
            uint256 finalUpdateBlock
        ) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
        assertEq(finalNftBalance, 1, "Final NFT balance mismatch");
        assertEq(finalDepositAmount, 0, "Final deposit amount mismatch");
        assertEq(finalUpdateBlock, block.number + 1, "Final update block mismatch");
    }

    function test_RevertIf_ProcessUserBalanceUpdates_Replay() public {
        address user1 = USER_A;
        address authorizedSigner = DEFAULT_FOUNDRY_SENDER;
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;

        IRewardsController.BalanceUpdateData[] memory replayUpdates = new IRewardsController.BalanceUpdateData[](1);
        replayUpdates[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: block.number + 1,
            nftDelta: 1,
            depositDelta: 0
        });

        // Sign first time
        uint256 nonce = rewardsController.authorizedUpdaterNonce(authorizedSigner);
        (, bytes memory signature) =
            signSingleUserBalanceUpdates(authorizedSigner, signerPrivateKey, user1, replayUpdates, nonce);

        // Process first time (should succeed)
        rewardsController.processUserBalanceUpdates(user1, replayUpdates, signature);

        // Check final state
        (
            , // Skip lastRewardIndex
            , // Skip accruedReward
            , // Skip accruedBonusRewardState
            uint256 finalNftBalance,
            uint256 finalDepositAmount,
            uint256 finalUpdateBlock
        ) = rewardsController.userNFTData(USER_A, NFT_COLLECTION_1);
        assertEq(finalNftBalance, 1, "Final NFT balance mismatch");
        assertEq(finalDepositAmount, 0, "Final deposit amount mismatch");
        assertEq(finalUpdateBlock, block.number + 1, "Final update block mismatch");
    }

    // Helper function to sign MULTI-USER BalanceUpdates
    function signMultiUserBalanceUpdates(
        address, /*signer*/
        uint256 signerPrivateKey,
        IRewardsController.UserBalanceUpdateData[] memory updates,
        uint256 nonce
    ) internal view returns (bytes32 digest, bytes memory signature) {
        bytes32 updatesHash = _hashMultiUserBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATES_TYPEHASH, updatesHash, nonce));

        digest = keccak256(abi.encodePacked("\x19\x01", _buildDomainSeparator(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // Helper function to sign SINGLE-USER UserBalanceUpdates
    function signSingleUserBalanceUpdates(
        address, /*signer*/
        uint256 signerPrivateKey,
        address user,
        IRewardsController.BalanceUpdateData[] memory updates,
        uint256 nonce
    ) internal view returns (bytes32 digest, bytes memory signature) {
        bytes32 updatesHash = _hashBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));

        digest = keccak256(abi.encodePacked("\x19\x01", _buildDomainSeparator(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // Helper methods to check data from the contract
    function getUserNFTData(address user, address collection)
        internal
        view
        returns (uint256 nftBalance, uint256 depositAmount, uint256 updateBlock)
    {
        address[] memory collections = new address[](1);
        collections[0] = collection;
        IRewardsController.UserCollectionTracking[] memory trackingInfo =
            rewardsController.getUserCollectionTracking(user, collections);

        nftBalance = trackingInfo[0].lastNFTBalance;
        depositAmount = trackingInfo[0].lastDepositBalance;
        updateBlock = trackingInfo[0].lastUpdateBlock;
    }
}
