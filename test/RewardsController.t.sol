// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol"; // Remove StdStorage from here
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol"; // Import struct and library
import {StdCheats} from "forge-std/StdCheats.sol";

import {RewardsController} from "../src/RewardsController.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendingManager} from "../src/mocks/MockLendingManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingManager} from "../src/interfaces/ILendingManager.sol";
// Explicitly import AccessControl and IAccessControl to access errors (No longer needed for these tests)
// import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
// import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol"; // Import OwnableUpgradeable for error selector
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // For ProxyAdmin tests
import {IRewardsController} from "../src/interfaces/IRewardsController.sol";
import {MockTokenVault} from "../src/mocks/MockTokenVault.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
// Use specific version path for clarity if remappings are uncertain
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; // Use remapped path
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol"; // Import for Upgraded event
// import {IERC1967Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1967Upgradeable.sol"; // Removed - Not needed for Transparent Proxy
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol"; // Use remapped path
import {Vm} from "forge-std/Vm.sol"; // Import Vm for Log struct

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
    // using stdStorage for StdStorage; // REMOVED: No longer used
    // using StdStorage for StdStorage; // Remove this line

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
    // EIP-1967 Storage Slots
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // --- Contracts ---
    RewardsController rewardsController; // This will point to the proxy
    RewardsController rewardsControllerImpl; // V1 implementation
    TransparentUpgradeableProxy rewardsControllerProxy; // Add state variable for the proxy contract itself
    ProxyAdmin proxyAdmin; // REMOVED: No longer needed as state var, internal admin used
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
        assertNotEq(address(rewardToken), address(0), "MockERC20 deployment failed");

        // Deploy Mock Lending Manager
        mockLM = new MockLendingManager(address(rewardToken));
        assertNotEq(address(mockLM), address(0), "MockLendingManager deployment failed");

        // Deploy RewardsController V1 implementation
        rewardsControllerImpl = new RewardsController();
        assertNotEq(address(rewardsControllerImpl), address(0), "RewardsController implementation deployment failed");

        // Deploy Mock Vault (Only needs asset address)
        mockVault = new MockTokenVault(address(rewardToken));
        assertNotEq(address(mockVault), address(0), "MockTokenVault deployment failed");

        // Prepare initialization data (using deployed mock addresses)
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            OWNER, // Initial owner set via initialize
            address(mockLM),
            address(mockVault), // Pass the deployed mock vault address
            DEFAULT_FOUNDRY_SENDER // Use default Foundry address as authorized updater
        );

        // Deploy TransparentUpgradeableProxy
        rewardsControllerProxy =
            new TransparentUpgradeableProxy(address(rewardsControllerImpl), OWNER, initData);
        assertNotEq(address(rewardsControllerProxy), address(0), "RewardsController proxy deployment failed");

        // Assign proxy address to the RewardsController interface variable
        rewardsController = RewardsController(address(rewardsControllerProxy));

        // Whitelist some collections (using the proxy address)
        rewardsController.addNFTCollection(NFT_COLLECTION_1, BETA_1);
        rewardsController.addNFTCollection(NFT_COLLECTION_2, BETA_2);

        // Fund mock LM with some reward tokens for transferYield calls
        bool sentToLM = rewardToken.transfer(address(mockLM), 250_000 ether);
        assertTrue(sentToLM, "Failed to send tokens to MockLM");
        assertEq(rewardToken.balanceOf(address(mockLM)), 250_000 ether, "MockLM balance mismatch");

        // Fund mock Vault with reward tokens for claimRewards calls
        bool sentToVault = rewardToken.transfer(address(mockVault), 250_000 ether);
        assertTrue(sentToVault, "Failed to send tokens to MockVault");
        assertEq(rewardToken.balanceOf(address(mockVault)), 250_000 ether, "MockVault balance mismatch");

        // Set the rewards controller address in the mock LM
        mockLM.setRewardsController(address(rewardsController)); // Use proxy address

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
        // Expect Ownable error
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
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
        // Expect Ownable error
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
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
        // Expect Ownable error
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OTHER_ADDRESS));
        rewardsController.updateBeta(NFT_COLLECTION_1, 1 ether);
        vm.stopPrank();
    }

    // Removed obsolete tests related to setAuthorizedUpdater

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

        // address authorizedSigner = DEFAULT_FOUNDRY_SENDER; // Unused variable
        uint256 signerPrivateKey = DEFAULT_FOUNDRY_PRIVATE_KEY;

        uint256 nonce = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        // (bytes32 digest, bytes memory signature) = // digest unused
        bytes memory signature = _signUserBalanceUpdates(user, updates, nonce, signerPrivateKey); // Assign single return value

        vm.warp(updateBlock2); // Warp to the last update block

        vm.expectEmit(true, false, false, false, address(rewardsController)); // user indexed, nonce/numUpdates not
        emit IRewardsController.UserBalanceUpdatesProcessed(user, nonce, updates.length);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, updates, signature);

        uint256 finalNonce = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
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

        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        bytes memory signature = _signMultiUserBalanceUpdates(updates, nonce0, signerPrivateKey); // Use correct function name and argument order

        vm.warp(blockNum);
        vm.expectEmit(true, false, false, false, address(rewardsController)); // signer indexed, nonce/numUpdates not
        emit IRewardsController.BalanceUpdatesProcessed(authorizedSigner, nonce0, 2);
        rewardsController.processBalanceUpdates(DEFAULT_FOUNDRY_SENDER, updates, signature);

        // Check nonce increment
        uint256 nonce1 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        assertEq(nonce1, nonce0 + 1, "Nonce should increment");

        // Check internal state (requires view functions or internal inspection mocks)
        // Need to check state for user1 and user2
    }

    function test_RevertIf_ProcessMultiUserBatchUpdate_InvalidNonceReplay() public {
        // address authorizedSigner = DEFAULT_FOUNDRY_SENDER; // REMOVED: Unused variable
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

        uint256 nonce = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);

        // Sign the batch update
        bytes memory signature = _signMultiUserBalanceUpdates(updates, nonce, signerPrivateKey);

        // First call: Should succeed (No need for prank, call directly)
        // vm.prank(authorizedSigner);
        rewardsController.processBalanceUpdates(DEFAULT_FOUNDRY_SENDER, updates, signature);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce + 1,
            "Nonce did not increment after first call"
        );

        // Second call with the same signature: Should revert due to nonce mismatch
        // vm.prank(authorizedSigner);
        vm.expectRevert(RewardsController.InvalidSignature.selector); // Expect InvalidSignature for replay
        rewardsController.processBalanceUpdates(DEFAULT_FOUNDRY_SENDER, updates, signature);
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
            false, // check data (DISABLED)
            address(rewardsController)
        );
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce0, 1); // Check nonce0 and 1 update

        // Sign and call the correct batch update function
        bytes memory nftSig = _signUserBalanceUpdates(USER_A, nftUpdates, nonce0, ownerPrivateKey);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, USER_A, nftUpdates, nftSig);
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
            false, // check data (DISABLED)
            address(rewardsController)
        );
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce1, 1); // Check nonce1 and 1 update

        // Sign and call the correct batch update function
        bytes memory depositSig = _signUserBalanceUpdates(USER_A, depositUpdates, nonce1, ownerPrivateKey);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, USER_A, depositUpdates, depositSig);
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

        int256 nftDelta1 = 1;
        int256 nftDelta2 = 1;

        // Nonces
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        uint256 nonce1 = nonce0 + 1;

        // 1. Prepare and sign first update (N+10)
        IRewardsController.BalanceUpdateData[] memory updates1 = new IRewardsController.BalanceUpdateData[](1);
        updates1[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: updateBlock1,
            nftDelta: nftDelta1,
            depositDelta: 0
        });
        bytes memory sig1 = _signUserBalanceUpdates(USER_A, updates1, nonce0, ownerPrivateKey);

        // 2. Prepare and sign second update (N+5)
        IRewardsController.BalanceUpdateData[] memory updates2 = new IRewardsController.BalanceUpdateData[](1);
        updates2[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1, // Block N+5
            blockNumber: updateBlock2,
            nftDelta: nftDelta2,
            depositDelta: 0
        });
        // Sign the second update with the *next* expected nonce (nonce1)
        bytes memory sig2 = _signUserBalanceUpdates(USER_A, updates2, nonce1, ownerPrivateKey);

        // Process the first update (N+10) successfully
        vm.roll(updateBlock1);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, USER_A, updates1, sig1);
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
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, USER_A, updates2, sig2);
        // Check nonce didn't increment after failed call
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce1,
            "Nonce should not increment after failed update"
        );
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
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, update1, sig1);

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
        vm.expectRevert(abi.encodeWithSelector(RewardsController.BalanceUpdateUnderflow.selector, 1, 2)); // Expecting BalanceUpdateUnderflow(currentValue: 1, deltaMagnitude: 2)
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, update2, sig2);
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
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, update1, sig1);

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
        // vm.prank(DEFAULT_FOUNDRY_SENDER); // Removed: Caller is implicitly the updater via signature
        vm.expectRevert(
            abi.encodeWithSelector(RewardsController.BalanceUpdateUnderflow.selector, initialDeposit, 60 ether)
        ); // Expecting BalanceUpdateUnderflow(currentValue: 50 ether, deltaMagnitude: 60 ether)
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, update2, sig2);
    }

    // --- Test Multi-User Batch Updates --- //

    function test_ProcessBalanceUpdates_SkipsNonWhitelisted() public {
        uint256 startBlock = block.number;
        address user = USER_A;
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
        uint256 nonce2 = nonce1 + 1; // Nonce for the C3 attempt

        // Process C1 updates (should succeed)
        // Combine C1 NFT and Deposit into one batch for simplicity
        vm.roll(c1UpdateBlock);
        // Prepare the update data structure for C1 NFT update
        IRewardsController.BalanceUpdateData[] memory nftUpdatesC1 = new IRewardsController.BalanceUpdateData[](1);
        nftUpdatesC1[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_1,
            blockNumber: c1UpdateBlock,
            nftDelta: nftDeltaC1,
            depositDelta: 0 // Process NFT first
        });

        // Expect the correct batch event
        // UserBalanceUpdatesProcessed(address indexed user, uint256 nonce, uint256 numUpdates)
        // The assertion on line 833 expects nonce1.
        vm.expectEmit(
            true, // user indexed
            false, // nonce not indexed
            false, // numUpdates not indexed
            false, // check data (DISABLED)
            address(rewardsController)
        );
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce0, 1); // Check nonce0 and 1 update
        // Sign and call the correct batch update function
        bytes memory nftSigC1 = _signUserBalanceUpdates(USER_A, nftUpdatesC1, nonce0, ownerPrivateKey);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, USER_A, nftUpdatesC1, nftSigC1);
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
            false, // check data (DISABLED)
            address(rewardsController)
        );
        emit IRewardsController.UserBalanceUpdatesProcessed(USER_A, nonce1, 1); // Check nonce1 and 1 update
        // Sign and call the correct batch update function
        bytes memory depositSigC1 = _signUserBalanceUpdates(USER_A, depositUpdatesC1, nonce1, ownerPrivateKey);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, USER_A, depositUpdatesC1, depositSigC1);
        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce1 + 1,
            "Nonce mismatch after C1 Deposit update"
        );

        // Attempt to process C3 update using processUserBalanceUpdates (should revert)
        vm.roll(c3UpdateBlock);
        // Prepare batch for C3 update
        IRewardsController.BalanceUpdateData[] memory updatesC3 = new IRewardsController.BalanceUpdateData[](1);
        updatesC3[0] = IRewardsController.BalanceUpdateData({
            collection: NFT_COLLECTION_3, // Non-whitelisted
            blockNumber: c3UpdateBlock,
            nftDelta: nftDeltaC3,
            depositDelta: depositDeltaC3
        });

        // Sign with the next expected nonce (nonce2)
        bytes memory sigC3 = _signUserBalanceUpdates(user, updatesC3, nonce2, ownerPrivateKey);

        bytes memory expectedRevertData =
            abi.encodeWithSelector(RewardsController.CollectionNotWhitelisted.selector, NFT_COLLECTION_3);

        vm.expectRevert(expectedRevertData);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, updatesC3, sigC3);

        assertEq(
            rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER),
            nonce2, // Nonce should NOT have incremented from the failed call (still nonce1+1)
            "Nonce should be unchanged after failed C3 update"
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
            blockNumber: updateBlock, // The block the deposit *happened*
            nftDelta: 0, // No NFTs
            depositDelta: int256(depositAmount)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, updates, sig);

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
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, updates, sig);

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
            collection: collection, // Add collection
            blockNumber: updateBlock, // Add blockNumber
            nftDelta: 0, // Add nftDelta
            depositDelta: 100 ether
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, updates, sig);

        // Still no time passed since deposit, so no rewards accrued
        vm.startPrank(user);
        vm.expectRevert(RewardsController.NoRewardsToClaim.selector);
        rewardsController.claimRewardsForCollection(collection);
        vm.stopPrank();
    }

    function test_ClaimRewards_SingleCollection_Success() public {
        address user = USER_A;
        address collection = NFT_COLLECTION_1;
        uint256 depositAmount = 100 ether;
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

        // --- Process Historical Deposit Update ---
        // Roll time to the update block *before* processing the update
        vm.roll(updateBlock);

        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock, // The block the deposit *happened*
            nftDelta: 0, // No NFTs
            depositDelta: int256(depositAmount)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, updates, sig);

        // --- Advance Time AFTER processing update ---
        vm.roll(endBlock);

        // --- Calculate Expected Reward ---
        uint256 expectedIndexIncrease = blocksPassed * expectedRatePerUnitPerBlock; // 10 * 1e13 = 1e14
        uint256 expectedReward = (depositAmount * expectedIndexIncrease) / PRECISION; // 100e18 * 1e14 / 1e18 = 0.01 ether

        // --- Mock LM transferYield ---
        // Ensure mockLM has funds to transfer (Needs to be done by OWNER)
        vm.startPrank(OWNER);
        rewardToken.transfer(address(mockLM), expectedReward); // Fund the mock LM
        vm.stopPrank();
        // Mock the transferYield call to succeed and return the expected amount
        // mockLM.setMockTransferYieldAmount(expectedReward); // Incorrect function
        mockLM.setExpectedTransferYield(expectedReward, address(rewardsController), true); // Expect transfer to RewardsController, not user

        // --- Claim Rewards ---
        console.log("--- Before Claim ---");
        console.log("User balance:", rewardToken.balanceOf(user));
        console.log("MockLM balance:", rewardToken.balanceOf(address(mockLM)));
        console.log("MockVault balance:", rewardToken.balanceOf(address(mockVault)));
        console.log("RewardsController balance:", rewardToken.balanceOf(address(rewardsController)));

        vm.startPrank(user);
        uint256 initialUserBalance = rewardToken.balanceOf(user);

        vm.expectEmit(true, true, false, false, address(rewardsController)); // user, collection indexed
        // emit IRewardsController.RewardsClaimed(user, collection, expectedReward, 0); // Incorrect event name and params
        emit IRewardsController.RewardsClaimedForCollection(user, collection, expectedReward); // Correct event

        rewardsController.claimRewardsForCollection(collection);
        vm.stopPrank();

        // --- Verify ---
        uint256 finalUserBalance = rewardToken.balanceOf(user);
        assertEq(finalUserBalance, initialUserBalance + expectedReward, "User balance mismatch after claim");

        // Verify internal state reset (accrued rewards should be 0)
        (
            uint256 finalIdx,
            uint256 finalAccruedReward, // Combined accrued reward
            , // accruedBonusRewardState (always 0 in userNFTData)
            , // nft balance
            , // deposit balance
            uint256 finalUpdateBlk
        ) = rewardsController.userNFTData(user, collection);

        assertEq(finalAccruedReward, 0, "Accrued reward should be reset");
        assertEq(finalUpdateBlk, endBlock, "Last update block should be claim block");

        // Verify the user's index was updated correctly to the final global index
        // The user's lastRewardIndex should match the globalRewardIndex at the time of the claim.
        uint256 expectedFinalIndex = rewardsController.globalRewardIndex();
        assertEq(finalIdx, expectedFinalIndex, "User index mismatch after claim");
    }

    // --- Test Upgradeability --- //

    function test_UpgradeProxy() public {
        // 1. Deploy a new implementation contract
        vm.startPrank(OWNER); // Owner deploys new implementation
        RewardsController newImplementation = new RewardsController();

        // REMOVED: Check/manipulation of new implementation's owner slot.
        // This is not relevant for Transparent Proxy upgrades via ProxyAdmin.

        vm.stopPrank(); // Stop OWNER prank after deployment and setup

        // 2. Get the current implementation address
        // Get implementation address using EIP-1967 storage slot
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address initialImplementation =
            address(uint160(uint256(vm.load(address(rewardsController), implementationSlot))));
        assertEq(initialImplementation, address(rewardsControllerImpl), "Initial implementation mismatch");

        // 3. Check pre-upgrade state (whitelisted collections)
        address[] memory collectionsBefore = rewardsController.getWhitelistedCollections();
        assertTrue(collectionsBefore.contains(NFT_COLLECTION_1), "C1 should be whitelisted before upgrade");
        assertTrue(collectionsBefore.contains(NFT_COLLECTION_2), "C2 should be whitelisted before upgrade");
        assertEq(collectionsBefore.length, 2, "Should have 2 collections before upgrade");

        // 4. Upgrade the proxy (as OWNER via the *internal* ProxyAdmin)
        // Get the address of the internal ProxyAdmin deployed by the proxy
        address internalAdminAddr = address(uint160(uint256(vm.load(address(rewardsControllerProxy), ADMIN_SLOT))));
        ProxyAdmin internalProxyAdmin = ProxyAdmin(payable(internalAdminAddr)); // Cast to ProxyAdmin

        vm.startPrank(OWNER); // OWNER is the owner of the internalProxyAdmin
        vm.recordLogs(); // Start recording logs
        internalProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(rewardsController)), address(newImplementation), ""
        ); // Use upgradeAndCall with empty data
        vm.stopPrank();

        // 5. Verify the implementation address changed
        // Get implementation address using EIP-1967 storage slot
        // bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc; // Already declared above
        address finalImplementation = address(uint160(uint256(vm.load(address(rewardsController), implementationSlot))));
        assertEq(finalImplementation, address(newImplementation), "Final implementation mismatch after upgrade");
        assertTrue(finalImplementation != initialImplementation, "Implementation address should have changed");

        // Verify the Upgraded event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1, "Expected exactly one log entry (Upgraded event)");

        Vm.Log memory upgradedLog = entries[0];
        bytes32 expectedTopic0 = keccak256("Upgraded(address)"); // Event signature hash
        bytes32 expectedTopic1 = bytes32(uint256(uint160(address(newImplementation)))); // Padded implementation address

        assertEq(upgradedLog.emitter, address(rewardsControllerProxy), "Log emitter should be the proxy address");
        assertEq(upgradedLog.topics.length, 2, "Upgraded event should have 2 topics");
        assertEq(upgradedLog.topics[0], expectedTopic0, "Topic 0 mismatch (event signature)");
        assertEq(upgradedLog.topics[1], expectedTopic1, "Topic 1 mismatch (new implementation address)");

        // 6. Verify state preservation (whitelisted collections)
        // Interact with the *proxy* address (rewardsController)
        address[] memory collectionsAfter = rewardsController.getWhitelistedCollections();
        assertTrue(collectionsAfter.contains(NFT_COLLECTION_1), "C1 should still be whitelisted after upgrade");
        assertTrue(collectionsAfter.contains(NFT_COLLECTION_2), "C2 should still be whitelisted after upgrade");
        assertEq(collectionsAfter.length, 2, "Should still have 2 collections after upgrade");
        assertEq(rewardsController.getCollectionBeta(NFT_COLLECTION_1), BETA_1, "C1 Beta mismatch after upgrade");
        assertEq(rewardsController.getCollectionBeta(NFT_COLLECTION_2), BETA_2, "C2 Beta mismatch after upgrade");

        // Optional: Verify admin slot still holds the internal admin address
        bytes32 adminSlotValue = vm.load(address(rewardsController), ADMIN_SLOT);
        address finalInternalAdminAddress = address(uint160(uint256(adminSlotValue)));
        assertTrue(finalInternalAdminAddress != address(0), "Final internal admin address should not be zero");
        // We don't have the initial internal admin address stored easily here, but we know it shouldn't be zero.
    }
}
