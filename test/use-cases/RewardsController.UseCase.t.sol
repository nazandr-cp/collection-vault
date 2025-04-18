// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol"; // <-- Add this import

import {RewardsController} from "../../src/RewardsController.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockLendingManager} from "../../src/mocks/MockLendingManager.sol";
import {IERC20} from "@openzeppelin-contracts-5.3.0/token/ERC20/IERC20.sol";
import {ILendingManager} from "../../src/interfaces/ILendingManager.sol";

import {Ownable} from "@openzeppelin-contracts-5.3.0/access/Ownable.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";
import {MockTokenVault} from "../../src/mocks/MockTokenVault.sol";
import {ECDSA} from "@openzeppelin-contracts-5.3.0/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin-contracts-5.3.0/utils/cryptography/EIP712.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin-contracts-5.3.0/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin-contracts-5.3.0/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts-5.3.0/proxy/transparent/ProxyAdmin.sol";

contract RewardsControllerUseCaseTest is Test {
    // EIP-712 Type Hashes
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
    address constant OWNER = address(0x001);
    address constant OTHER_ADDRESS = address(0x123);
    address constant NFT_UPDATER = address(0xBAD); // Simulate NFTDataUpdater
    // Define Foundry constants at contract level
    address constant DEFAULT_FOUNDRY_SENDER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant DEFAULT_FOUNDRY_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    uint256 constant PRECISION = 1e18;
    uint256 constant BETA_1 = 0.1 ether; // Example beta (10% per NFT)
    uint256 constant BETA_2 = 0.05 ether; // Example beta (5% per NFT)
    // EIP-1967 Storage Slots
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // --- Contracts ---
    RewardsController rewardsController; // This will point to the proxy
    RewardsController rewardsControllerImpl; // V1 implementation
    ProxyAdmin proxyAdmin;
    MockLendingManager mockLM;
    MockERC20 rewardToken; // Same as LM asset
    MockTokenVault mockVault;

    // --- Helper Functions --- //

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
                    BALANCE_UPDATE_DATA_TYPEHASH,
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

    // --- Setup ---
    function setUp() public {
        vm.startPrank(OWNER);

        // Deploy Reward Token (Asset)
        rewardToken = new MockERC20("Reward Token", "RWD", 1_000_000 ether);

        // Deploy Mock Lending Manager
        mockLM = new MockLendingManager(address(rewardToken));

        // Deploy Mock Vault (needs asset)
        mockVault = new MockTokenVault(address(rewardToken));

        // Deploy ProxyAdmin (owned by OWNER)
        proxyAdmin = new ProxyAdmin(OWNER);

        // Deploy RewardsController V1 implementation
        rewardsControllerImpl = new RewardsController();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            OWNER,
            address(mockLM),
            address(mockVault),
            DEFAULT_FOUNDRY_SENDER // Use default Foundry address as authorized updater
        );

        // Deploy TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(rewardsControllerImpl), address(proxyAdmin), initData);

        // Point rewardsController variable to the proxy address
        rewardsController = RewardsController(address(proxy));

        // Whitelist collections
        rewardsController.addNFTCollection(NFT_COLLECTION_1, BETA_1);
        rewardsController.addNFTCollection(NFT_COLLECTION_2, BETA_2);

        // Fund mock LM with reward tokens
        rewardToken.transfer(address(mockLM), 500_000 ether);
        // Fund the RewardsController proxy itself with some tokens initially for transfers
        // This simulates yield being available *before* the first claim
        rewardToken.transfer(address(rewardsController), 1000 ether);

        // Set the rewards controller address in the mock LM
        mockLM.setRewardsController(address(rewardsController));

        vm.stopPrank();
    }

    // --- Use Case Tests --- //

    /// @notice Use Case: A user deposits assets, holds NFTs from a whitelisted collection,
    ///         accrues rewards over time based on deposit, NFT count, and collection beta,
    ///         and then claims the accrued rewards for that specific collection.
    function test_UseCase_Deposit_HoldNFT_Accrue_Claim() public {
        // --- 1. Setup Test Parameters ---
        address user = USER_A;
        address collection = NFT_COLLECTION_1; // Beta = 0.1 ether
        uint256 depositAmount = 500 ether;
        uint256 nftCount = 5; // User holds 5 NFTs
        uint256 startBlock = block.number;
        uint256 updateBlock = startBlock + 1; // Block for initial state update
        uint256 blocksToAccrue = 100; // Let 100 blocks pass for rewards
        uint256 claimBlock = updateBlock + blocksToAccrue; // Block for claiming
        console.log("--- Step 1: Parameters Set ---");
        console.log("User:", user);
        console.log("Collection:", collection);
        console.log("Deposit Amount:", depositAmount);
        console.log("NFT Count:", nftCount);
        console.log("Start Block:", startBlock);
        console.log("Update Block:", updateBlock);
        console.log("Claim Block:", claimBlock);

        // --- 2. Configure Mock Lending Manager ---
        uint256 mockRewardPerBlock = 0.1 ether; // 0.1 RWD per block total from LM
        uint256 mockTotalLMAssets = 10000 ether; // Assume 10k total assets in LM
        mockLM.setMockBaseRewardPerBlock(mockRewardPerBlock);
        mockLM.setMockTotalAssets(mockTotalLMAssets);
        console.log("--- Step 2: Mock LM Configured ---");
        console.log("Mock Reward Per Block:", mockRewardPerBlock);
        console.log("Mock Total LM Assets:", mockTotalLMAssets);

        // --- 3. Action: Process Initial State Update (Deposit + NFT Balance) ---
        console.log("--- Step 3: Processing Initial Update (Block %s) ---", updateBlock);
        vm.roll(updateBlock); // Advance to the block where the update occurs
        uint256 nonce0 = rewardsController.authorizedUpdaterNonce(DEFAULT_FOUNDRY_SENDER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: updateBlock, // Use the current block number for the update
            nftDelta: int256(nftCount),
            depositDelta: int256(depositAmount)
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce0, DEFAULT_FOUNDRY_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(DEFAULT_FOUNDRY_SENDER, user, updates, sig);
        console.log("Initial update processed for user %s at block %s", user, block.number);

        // --- 4. Action: Advance Time for Reward Accrual ---
        console.log("--- Step 4: Advancing time to block %s for accrual ---", claimBlock);
        vm.roll(claimBlock); // Advance to the block where the claim will happen
        console.log("Current block after advancing time:", block.number);

        // --- 5. Verification: Calculate Expected Rewards (using preview) ---
        console.log("--- Step 5: Previewing Rewards ---");
        address[] memory collectionsToPreview = new address[](1);
        collectionsToPreview[0] = collection;
        IRewardsController.BalanceUpdateData[] memory noSimulatedUpdates; // Empty array for preview
        uint256 expectedTotalReward = rewardsController.previewRewards(user, collectionsToPreview, noSimulatedUpdates);
        console.log("Expected Total Reward (from previewRewards):", expectedTotalReward);

        // --- 6. Action: Claim Rewards ---
        console.log("--- Step 6: Claiming Rewards for user %s at block %s ---", user, block.number);
        vm.startPrank(user);
        uint256 balanceBefore = rewardToken.balanceOf(user);
        console.log("User balance before claim:", balanceBefore);
        vm.recordLogs(); // Start recording logs to capture the event
        rewardsController.claimRewardsForCollection(collection); // Perform the claim
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Get recorded logs
        uint256 actualClaimBlockNumber = block.number; // Block number *after* the claim finished
        vm.stopPrank();
        console.log("Claim action finished at block:", actualClaimBlockNumber);

        // --- 7. Verification: Reward Transfer ---
        console.log("--- Step 7: Verifying Reward Transfer ---");
        uint256 balanceAfter = rewardToken.balanceOf(user);
        console.log("User balance after claim:", balanceAfter);
        assertEq(balanceAfter - balanceBefore, expectedTotalReward, "User reward token balance mismatch after claim");
        console.log("Reward transfer verified.");

        // --- 8. Verification: Event Emission (Manual Check) ---
        console.log("--- Step 8: Verifying Event Emission ---");
        bool eventFound = false;
        bytes32 expectedTopic0 = keccak256("RewardsClaimedForCollection(address,address,uint256)");
        bytes32 expectedTopic1 = bytes32(uint256(uint160(user)));
        bytes32 expectedTopic2 = bytes32(uint256(uint160(collection)));
        for (uint256 i = 0; i < entries.length; i++) {
            Vm.Log memory entry = entries[i];
            if (
                entry.topics.length == 3 && entry.topics[0] == expectedTopic0 && entry.topics[1] == expectedTopic1
                    && entry.topics[2] == expectedTopic2
            ) {
                uint256 emittedAmount = abi.decode(entry.data, (uint256));
                console.log("Found RewardsClaimedForCollection event with amount:", emittedAmount);
                assertEq(emittedAmount, expectedTotalReward, "Emitted reward amount mismatch");
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "RewardsClaimedForCollection event not found or topics mismatch");
        console.log("Event emission verified.");

        // --- 9. Verification: Internal State Reset ---
        console.log("--- Step 9: Verifying Internal State Reset ---");
        (uint256 lastIdx, uint256 accrued,, uint256 nftBal, uint256 depAmt, uint256 lastUpdateBlk) =
            rewardsController.userNFTData(user, collection);
        uint256 expectedGlobalIndexAtClaim = rewardsController.globalRewardIndex(); // Index *after* claim processed it
        console.log("User Accrued after claim:", accrued);
        console.log("User Last Index after claim:", lastIdx);
        console.log("Expected Global Index at claim:", expectedGlobalIndexAtClaim);
        console.log("User Last Update Block after claim:", lastUpdateBlk);
        console.log("Actual Claim Block Number:", actualClaimBlockNumber);
        console.log("User NFT Balance after claim:", nftBal);
        console.log("User Deposit Amount after claim:", depAmt);

        assertEq(accrued, 0, "Accrued reward should be reset to 0 after claim");
        assertEq(lastIdx, expectedGlobalIndexAtClaim, "User last reward index mismatch after claim");
        assertEq(lastUpdateBlk, actualClaimBlockNumber, "User last update block mismatch after claim");
        assertEq(nftBal, nftCount, "NFT balance should persist after claim");
        assertEq(depAmt, depositAmount, "Deposit amount should persist after claim");
        console.log("Internal state reset verified.");

        // --- 10. Verification: Claiming Again Fails ---
        console.log("--- Step 10: Verifying second claim fails ---");
        vm.startPrank(user);
        vm.expectRevert(RewardsController.NoRewardsToClaim.selector);
        rewardsController.claimRewardsForCollection(collection);
        vm.stopPrank();
        console.log("Verified that claiming again reverts as expected.");
    }

    // Add more use case tests here...
}
