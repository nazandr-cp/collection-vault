// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {VaultManager, CollectionClaimData} from "../src/VaultManager.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {INFTRegistry} from "../src/interfaces/INFTRegistry.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {MockNFTRegistry} from "../src/mocks/MockNFTRegistry.sol";
import {MockTokenVault} from "../src/mocks/MockTokenVault.sol";
import {IERC721} from "@openzeppelin-contracts-5.2.0/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/contracts/access/Ownable.sol";

contract VaultManagerTest is Test, StdCheats {
    // --- Constants & Config ---
    address constant USER_ALICE = address(0x111);
    address constant USER_BOB = address(0x222);
    address constant USER_CHARLIE = address(0x333); // User with no NFTs initially
    address constant OWNER = address(0x001);
    uint256 constant INITIAL_YIELD_TOKEN_SUPPLY = 1_000_000 ether;
    uint256 constant VAULT_FUNDING_AMOUNT = 100_000 ether;
    uint256 constant DEFAULT_MOCK_YIELD_A = 0.5 ether;
    uint256 constant DEFAULT_MOCK_YIELD_B = 0.25 ether;

    // --- Contracts ---
    VaultManager vaultManager;
    MockNFTRegistry nftRegistry;
    MockERC20 yieldTokenA;
    MockERC20 yieldTokenB;
    MockTokenVault vaultA; // Distributes yieldTokenA
    MockTokenVault vaultB; // Distributes yieldTokenB
    MockERC721 nftCollection1;
    MockERC721 nftCollection2;
    MockERC721 unregisteredNftCollection;

    // --- Setup ---
    function setUp() public {
        // Deploy Mock Tokens
        vm.prank(OWNER);
        yieldTokenA = new MockERC20("Yield Token A", "YTA", INITIAL_YIELD_TOKEN_SUPPLY);
        vm.prank(OWNER);
        yieldTokenB = new MockERC20("Yield Token B", "YTB", INITIAL_YIELD_TOKEN_SUPPLY);

        // Deploy Mock NFTs
        vm.prank(OWNER);
        nftCollection1 = new MockERC721("NFT Collection 1", "NFT1");
        vm.prank(OWNER);
        nftCollection2 = new MockERC721("NFT Collection 2", "NFT2");
        vm.prank(OWNER);
        unregisteredNftCollection = new MockERC721("Unregistered NFT", "UNFT");

        // Deploy Mock NFT Registry
        vm.prank(OWNER);
        nftRegistry = new MockNFTRegistry();

        // Deploy Mock Vaults
        vm.prank(OWNER);
        vaultA = new MockTokenVault(address(yieldTokenA));
        vm.prank(OWNER);
        vaultB = new MockTokenVault(address(yieldTokenB));

        // Deploy VaultManager
        vm.startPrank(OWNER);
        vaultManager = new VaultManager(OWNER, address(nftRegistry));

        // Configure VaultManager
        vaultManager.addCollection(address(nftCollection1));
        vaultManager.addCollection(address(nftCollection2));
        vaultManager.addVault(address(vaultA)); // Vault A added first
        vaultManager.addVault(address(vaultB)); // Vault B added second
        vm.stopPrank();

        // Configure Mock Vaults (Set default yield per NFT)
        vm.prank(OWNER);
        vaultA.setDefaultYieldAmount(DEFAULT_MOCK_YIELD_A);
        vm.prank(OWNER);
        vaultB.setDefaultYieldAmount(DEFAULT_MOCK_YIELD_B);

        // Fund Vaults with Yield Tokens
        vm.prank(OWNER);
        yieldTokenA.transfer(address(vaultA), VAULT_FUNDING_AMOUNT);
        vm.prank(OWNER);
        yieldTokenB.transfer(address(vaultB), VAULT_FUNDING_AMOUNT);

        // Mint NFTs to Users
        // Collection 1: Alice=2, Bob=1
        vm.prank(address(nftCollection1)); // Mint from the collection contract itself for simplicity
        nftCollection1.mint(USER_ALICE); // ID 1
        nftCollection1.mint(USER_ALICE); // ID 2
        nftCollection1.mint(USER_BOB); // ID 3
        vm.stopPrank();

        // Collection 2: Alice=1, Bob=2
        vm.startPrank(address(nftCollection2));
        nftCollection2.mint(USER_ALICE); // ID 1
        nftCollection2.mint(USER_BOB); // ID 2
        nftCollection2.mint(USER_BOB); // ID 3
        vm.stopPrank();

        // Unregistered Collection: Alice=1
        vm.startPrank(address(unregisteredNftCollection));
        unregisteredNftCollection.mint(USER_ALICE); // ID 1
        vm.stopPrank();
    }

    // --- Admin Function Tests ---

    function test_Admin_AddRemoveCollection() public {
        vm.startPrank(OWNER);
        address newCollection = address(new MockERC721("New NFT", "NEW"));
        vaultManager.addCollection(newCollection);
        assertTrue(vaultManager.isCollectionRegistered(newCollection));
        assertEq(vaultManager.getRegisteredCollections().length, 3);

        vaultManager.removeCollection(newCollection);
        assertFalse(vaultManager.isCollectionRegistered(newCollection));
        assertEq(vaultManager.getRegisteredCollections().length, 2);
        vm.stopPrank();
    }

    function test_Admin_AddRemoveVault() public {
        vm.startPrank(OWNER);
        address newYieldToken = address(new MockERC20("New Yield", "NYT", 0));
        address newVault = address(new MockTokenVault(newYieldToken));
        vaultManager.addVault(newVault);
        assertTrue(vaultManager.isVaultRegistered(newVault));
        assertEq(vaultManager.getRegisteredVaults().length, 3);

        vaultManager.removeVault(newVault);
        assertFalse(vaultManager.isVaultRegistered(newVault));
        assertEq(vaultManager.getRegisteredVaults().length, 2);
        vm.stopPrank();
    }

    function testFail_Admin_AddRemoveNonOwner() public {
        vm.startPrank(USER_ALICE);
        address newCollection = address(new MockERC721("New NFT", "NEW"));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_ALICE));
        vaultManager.addCollection(newCollection);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_ALICE));
        vaultManager.removeCollection(address(nftCollection1));

        address newYieldToken = address(new MockERC20("New Yield", "NYT", 0));
        address newVault = address(new MockTokenVault(newYieldToken));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_ALICE));
        vaultManager.addVault(newVault);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_ALICE));
        vaultManager.removeVault(address(vaultA));
        vm.stopPrank();
    }

    function testFail_Admin_AddRemoveZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(VaultManager.AddressZero.selector);
        vaultManager.addCollection(address(0));
        vm.expectRevert(VaultManager.AddressZero.selector);
        vaultManager.addVault(address(0));
        // Test removing non-existent zero address - should fail based on EnumerableSet logic
        vm.expectRevert(abi.encodeWithSelector(VaultManager.CollectionNotRegistered.selector, address(0)));
        vaultManager.removeCollection(address(0));
        vm.expectRevert(abi.encodeWithSelector(VaultManager.VaultNotRegistered.selector, address(0)));
        vaultManager.removeVault(address(0));
        vm.stopPrank();
    }

    // --- Claim For Collection Tests ---

    function test_ClaimForCollection_Success_Alice_Coll1() public {
        // Alice owns 2 NFTs in Collection 1
        // Vault A yields 0.5 YTA per NFT -> 2 * 0.5 = 1.0 YTA
        // Vault B yields 0.25 YTB per NFT -> 2 * 0.25 = 0.5 YTB
        uint256 expectedYieldA = 2 * DEFAULT_MOCK_YIELD_A;
        uint256 expectedYieldB = 2 * DEFAULT_MOCK_YIELD_B;

        uint256 balanceABefore = yieldTokenA.balanceOf(USER_ALICE);
        uint256 balanceBBefore = yieldTokenB.balanceOf(USER_ALICE);

        // Prepare expected event data
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = address(yieldTokenA);
        expectedTokens[1] = address(yieldTokenB);
        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = expectedYieldA;
        expectedAmounts[1] = expectedYieldB;

        // Expect Event
        vm.expectEmit(true, true, false, false); // Check user, collection indexed topics
        emit VaultManager.CollectionClaim(
            USER_ALICE,
            address(nftCollection1),
            expectedTokens,
            expectedAmounts,
            block.timestamp, // Forge checks timestamp automatically if emitted
            block.number // Forge checks block number automatically if emitted
        );

        // Action
        vm.prank(USER_ALICE);
        vaultManager.claimForCollection(address(nftCollection1));

        // Assert Balances
        assertEq(yieldTokenA.balanceOf(USER_ALICE), balanceABefore + expectedYieldA, "YTA balance mismatch");
        assertEq(yieldTokenB.balanceOf(USER_ALICE), balanceBBefore + expectedYieldB, "YTB balance mismatch");
    }

    function test_ClaimForCollection_Success_Bob_Coll2() public {
        // Bob owns 2 NFTs in Collection 2
        // Vault A yields 0.5 YTA per NFT -> 2 * 0.5 = 1.0 YTA
        // Vault B yields 0.25 YTB per NFT -> 2 * 0.25 = 0.5 YTB
        uint256 expectedYieldA = 2 * DEFAULT_MOCK_YIELD_A;
        uint256 expectedYieldB = 2 * DEFAULT_MOCK_YIELD_B;

        uint256 balanceABefore = yieldTokenA.balanceOf(USER_BOB);
        uint256 balanceBBefore = yieldTokenB.balanceOf(USER_BOB);

        // Prepare expected event data
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = address(yieldTokenA);
        expectedTokens[1] = address(yieldTokenB);
        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = expectedYieldA;
        expectedAmounts[1] = expectedYieldB;

        // Expect Event
        vm.expectEmit(true, true, false, false); // Check user, collection indexed topics
        emit VaultManager.CollectionClaim(
            USER_BOB, address(nftCollection2), expectedTokens, expectedAmounts, block.timestamp, block.number
        );

        // Action
        vm.prank(USER_BOB);
        vaultManager.claimForCollection(address(nftCollection2));

        // Assert Balances
        assertEq(yieldTokenA.balanceOf(USER_BOB), balanceABefore + expectedYieldA, "YTA balance mismatch");
        assertEq(yieldTokenB.balanceOf(USER_BOB), balanceBBefore + expectedYieldB, "YTB balance mismatch");
    }

    function testFail_ClaimForCollection_NotRegistered() public {
        vm.prank(USER_ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(VaultManager.CollectionNotRegistered.selector, address(unregisteredNftCollection))
        );
        vaultManager.claimForCollection(address(unregisteredNftCollection));
    }

    function testFail_ClaimForCollection_NoNFTs() public {
        // Charlie has no NFTs in Collection 1
        vm.prank(USER_CHARLIE);
        vm.expectRevert(VaultManager.NoYieldToClaim.selector);
        vaultManager.claimForCollection(address(nftCollection1));
    }

    function testFail_ClaimForCollection_ZeroYield() public {
        // Set vault yields to 0
        vm.prank(OWNER);
        vaultA.setDefaultYieldAmount(0);
        vm.prank(OWNER);
        vaultB.setDefaultYieldAmount(0);

        // Alice has NFTs, but yield is 0
        vm.prank(USER_ALICE);
        vm.expectRevert(VaultManager.NoYieldToClaim.selector);
        vaultManager.claimForCollection(address(nftCollection1));
    }

    function testFail_ClaimForCollection_VaultInsufficientBalance() public {
        // Burn yield tokens from vault A
        vm.prank(OWNER); // Owner doesn't hold vault tokens directly, Vault contract does
        uint256 vaultABalance = yieldTokenA.balanceOf(address(vaultA));
        // Need to transfer from vault to owner then burn, or add burn function to vault mock
        // Simpler: Just transfer out most tokens
        vm.prank(address(vaultA)); // Act as vault contract
        yieldTokenA.transfer(OWNER, vaultABalance - 1 wei); // Leave 1 wei

        // Alice tries to claim (needs 1 YTA), vault A has only 1 wei
        vm.prank(USER_ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultManager.ClaimFailed.selector, address(vaultA), USER_ALICE, 2 * DEFAULT_MOCK_YIELD_A
            )
        );
        vaultManager.claimForCollection(address(nftCollection1));
    }

    function testFail_ClaimForCollection_NoVaults() public {
        // Remove all vaults
        vm.prank(OWNER);
        vaultManager.removeVault(address(vaultA));
        vm.prank(OWNER);
        vaultManager.removeVault(address(vaultB));

        // Alice has NFTs, but no vaults exist
        vm.prank(USER_ALICE);
        vm.expectRevert(VaultManager.NoYieldToClaim.selector);
        vaultManager.claimForCollection(address(nftCollection1));
    }

    // --- Claim All Tests ---

    function test_ClaimAll_Success_Alice() public {
        // Alice:
        // Coll 1: 2 NFTs -> Vault A (2 * 0.5 = 1.0 YTA), Vault B (2 * 0.25 = 0.5 YTB)
        // Coll 2: 1 NFT  -> Vault A (1 * 0.5 = 0.5 YTA), Vault B (1 * 0.25 = 0.25 YTB)
        // Total: YTA = 1.0 + 0.5 = 1.5 YTA
        // Total: YTB = 0.5 + 0.25 = 0.75 YTB

        uint256 expectedTotalYieldA = (2 * DEFAULT_MOCK_YIELD_A) + (1 * DEFAULT_MOCK_YIELD_A);
        uint256 expectedTotalYieldB = (2 * DEFAULT_MOCK_YIELD_B) + (1 * DEFAULT_MOCK_YIELD_B);

        uint256 balanceABefore = yieldTokenA.balanceOf(USER_ALICE);
        uint256 balanceBBefore = yieldTokenB.balanceOf(USER_ALICE);

        // Prepare expected event data
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = address(yieldTokenA);
        expectedTokens[1] = address(yieldTokenB);
        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = expectedTotalYieldA;
        expectedAmounts[1] = expectedTotalYieldB;

        // Prepare expected details array (order: collections then vaults)
        CollectionClaimData[] memory expectedDetails = new CollectionClaimData[](4); // 2 collections * 2 vaults
        expectedDetails[0] = CollectionClaimData({
            collection: address(nftCollection1),
            yieldToken: address(yieldTokenA),
            amount: 2 * DEFAULT_MOCK_YIELD_A
        });
        expectedDetails[1] = CollectionClaimData({
            collection: address(nftCollection1),
            yieldToken: address(yieldTokenB),
            amount: 2 * DEFAULT_MOCK_YIELD_B
        });
        expectedDetails[2] = CollectionClaimData({
            collection: address(nftCollection2),
            yieldToken: address(yieldTokenA),
            amount: 1 * DEFAULT_MOCK_YIELD_A
        });
        expectedDetails[3] = CollectionClaimData({
            collection: address(nftCollection2),
            yieldToken: address(yieldTokenB),
            amount: 1 * DEFAULT_MOCK_YIELD_B
        });

        // Expect Event
        vm.expectEmit(true, false, false, false); // Check user indexed topic
        emit VaultManager.GlobalClaim(
            USER_ALICE,
            expectedTokens,
            expectedAmounts,
            block.timestamp, // Checked implicitly
            block.number, // Checked implicitly
            expectedDetails
        );

        // Action
        vm.prank(USER_ALICE);
        vaultManager.claimAll();

        // Assert Balances
        assertEq(yieldTokenA.balanceOf(USER_ALICE), balanceABefore + expectedTotalYieldA, "Total YTA balance mismatch");
        assertEq(yieldTokenB.balanceOf(USER_ALICE), balanceBBefore + expectedTotalYieldB, "Total YTB balance mismatch");
    }

    function test_ClaimAll_Success_Bob() public {
        // Bob:
        // Coll 1: 1 NFT -> Vault A (1 * 0.5 = 0.5 YTA), Vault B (1 * 0.25 = 0.25 YTB)
        // Coll 2: 2 NFTs -> Vault A (2 * 0.5 = 1.0 YTA), Vault B (2 * 0.25 = 0.5 YTB)
        // Total: YTA = 0.5 + 1.0 = 1.5 YTA
        // Total: YTB = 0.25 + 0.5 = 0.75 YTB
        uint256 expectedTotalYieldA = (1 * DEFAULT_MOCK_YIELD_A) + (2 * DEFAULT_MOCK_YIELD_A);
        uint256 expectedTotalYieldB = (1 * DEFAULT_MOCK_YIELD_B) + (2 * DEFAULT_MOCK_YIELD_B);

        uint256 balanceABefore = yieldTokenA.balanceOf(USER_BOB);
        uint256 balanceBBefore = yieldTokenB.balanceOf(USER_BOB);

        // Prepare expected event data
        address[] memory expectedTokens = new address[](2);
        expectedTokens[0] = address(yieldTokenA);
        expectedTokens[1] = address(yieldTokenB);
        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = expectedTotalYieldA;
        expectedAmounts[1] = expectedTotalYieldB;

        // Prepare expected details array
        CollectionClaimData[] memory expectedDetails = new CollectionClaimData[](4);
        expectedDetails[0] = CollectionClaimData({
            collection: address(nftCollection1),
            yieldToken: address(yieldTokenA),
            amount: 1 * DEFAULT_MOCK_YIELD_A
        });
        expectedDetails[1] = CollectionClaimData({
            collection: address(nftCollection1),
            yieldToken: address(yieldTokenB),
            amount: 1 * DEFAULT_MOCK_YIELD_B
        });
        expectedDetails[2] = CollectionClaimData({
            collection: address(nftCollection2),
            yieldToken: address(yieldTokenA),
            amount: 2 * DEFAULT_MOCK_YIELD_A
        });
        expectedDetails[3] = CollectionClaimData({
            collection: address(nftCollection2),
            yieldToken: address(yieldTokenB),
            amount: 2 * DEFAULT_MOCK_YIELD_B
        });

        // Expect Event
        vm.expectEmit(true, false, false, false); // Check user indexed topic
        emit VaultManager.GlobalClaim(
            USER_BOB, expectedTokens, expectedAmounts, block.timestamp, block.number, expectedDetails
        );

        // Action
        vm.prank(USER_BOB);
        vaultManager.claimAll();

        // Assert Balances
        assertEq(yieldTokenA.balanceOf(USER_BOB), balanceABefore + expectedTotalYieldA, "Total YTA balance mismatch");
        assertEq(yieldTokenB.balanceOf(USER_BOB), balanceBBefore + expectedTotalYieldB, "Total YTB balance mismatch");
    }

    function testFail_ClaimAll_NoNFTs() public {
        // Charlie has no NFTs in any registered collection
        vm.prank(USER_CHARLIE);
        vm.expectRevert(VaultManager.NoYieldToClaim.selector);
        vaultManager.claimAll();
    }

    function testFail_ClaimAll_ZeroYield() public {
        // Set vault yields to 0
        vm.prank(OWNER);
        vaultA.setDefaultYieldAmount(0);
        vm.prank(OWNER);
        vaultB.setDefaultYieldAmount(0);

        // Alice has NFTs, but yield is 0
        vm.prank(USER_ALICE);
        vm.expectRevert(VaultManager.NoYieldToClaim.selector);
        vaultManager.claimAll();
    }

    function testFail_ClaimAll_VaultInsufficientBalance() public {
        // Burn yield tokens from vault B
        vm.prank(OWNER);
        uint256 vaultBBalance = yieldTokenB.balanceOf(address(vaultB));
        vm.prank(address(vaultB)); // Act as vault contract
        yieldTokenB.transfer(OWNER, vaultBBalance - 1 wei); // Leave 1 wei

        // Alice tries to claim all.
        // Claim from Vault A (Coll 1 & 2) should succeed.
        // Claim from Vault B (Coll 1) will fail first as it needs 0.5 YTB.
        uint256 yieldBColl1 = 2 * DEFAULT_MOCK_YIELD_B; // 0.5 YTB

        vm.prank(USER_ALICE);
        // The failure happens on the first vault call that lacks funds in the inner loop
        vm.expectRevert(
            abi.encodeWithSelector(VaultManager.ClaimFailed.selector, address(vaultB), USER_ALICE, yieldBColl1)
        );
        vaultManager.claimAll();

        // Important: Test that partial claims didn't happen (state reverted)
        // Alice's balance for Token A should remain unchanged because the transaction reverted.
        assertEq(yieldTokenA.balanceOf(USER_ALICE), 0, "YTA should not have been claimed due to revert");
        assertEq(yieldTokenB.balanceOf(USER_ALICE), 0, "YTB should not have been claimed due to revert");
    }

    function testFail_ClaimAll_NoVaults() public {
        // Remove all vaults
        vm.prank(OWNER);
        vaultManager.removeVault(address(vaultA));
        vm.prank(OWNER);
        vaultManager.removeVault(address(vaultB));

        // Alice has NFTs, but no vaults exist
        vm.prank(USER_ALICE);
        vm.expectRevert(VaultManager.NoYieldToClaim.selector);
        vaultManager.claimAll();
    }

    function testFail_ClaimAll_NoCollections() public {
        // Remove all collections
        vm.prank(OWNER);
        vaultManager.removeCollection(address(nftCollection1));
        vm.prank(OWNER);
        vaultManager.removeCollection(address(nftCollection2));

        // Alice has NFTs in theory, but none are registered
        vm.prank(USER_ALICE);
        vm.expectRevert(VaultManager.NoYieldToClaim.selector);
        vaultManager.claimAll();
    }

    // --- View Function Tests ---

    function test_View_GetPendingYieldForCollection() public {
        // Alice, Collection 1 (2 NFTs)
        // Expected: YTA = 1.0, YTB = 0.5
        (address[] memory tokens1, uint256[] memory amounts1) =
            vaultManager.getPendingYieldForCollection(USER_ALICE, address(nftCollection1));
        assertEq(tokens1.length, 2, "Alice Coll1 Token Count");
        assertEq(amounts1.length, 2, "Alice Coll1 Amount Count");
        // Order depends on vault registration order (A then B)
        assertEq(tokens1[0], address(yieldTokenA), "Alice Coll1 Token 0");
        assertEq(amounts1[0], 2 * DEFAULT_MOCK_YIELD_A, "Alice Coll1 Amount 0");
        assertEq(tokens1[1], address(yieldTokenB), "Alice Coll1 Token 1");
        assertEq(amounts1[1], 2 * DEFAULT_MOCK_YIELD_B, "Alice Coll1 Amount 1");

        // Bob, Collection 2 (2 NFTs)
        // Expected: YTA = 1.0, YTB = 0.5
        (address[] memory tokens2, uint256[] memory amounts2) =
            vaultManager.getPendingYieldForCollection(USER_BOB, address(nftCollection2));
        assertEq(tokens2.length, 2, "Bob Coll2 Token Count");
        assertEq(amounts2.length, 2, "Bob Coll2 Amount Count");
        assertEq(tokens2[0], address(yieldTokenA), "Bob Coll2 Token 0");
        assertEq(amounts2[0], 2 * DEFAULT_MOCK_YIELD_A, "Bob Coll2 Amount 0");
        assertEq(tokens2[1], address(yieldTokenB), "Bob Coll2 Token 1");
        assertEq(amounts2[1], 2 * DEFAULT_MOCK_YIELD_B, "Bob Coll2 Amount 1");

        // Charlie, Collection 1 (0 NFTs)
        // Expected: empty arrays
        (address[] memory tokens3, uint256[] memory amounts3) =
            vaultManager.getPendingYieldForCollection(USER_CHARLIE, address(nftCollection1));
        assertEq(tokens3.length, 0, "Charlie Coll1 Token Count");
        assertEq(amounts3.length, 0, "Charlie Coll1 Amount Count");
    }

    function test_View_GetTotalPendingYield() public {
        // Alice:
        // Coll 1: 2 NFTs -> YTA=1.0, YTB=0.5
        // Coll 2: 1 NFT  -> YTA=0.5, YTB=0.25
        // Total: YTA = 1.5, YTB = 0.75
        uint256 expectedTotalA_Alice = (2 * DEFAULT_MOCK_YIELD_A) + (1 * DEFAULT_MOCK_YIELD_A);
        uint256 expectedTotalB_Alice = (2 * DEFAULT_MOCK_YIELD_B) + (1 * DEFAULT_MOCK_YIELD_B);

        (address[] memory tokensA, uint256[] memory amountsA) = vaultManager.getTotalPendingYield(USER_ALICE);
        assertEq(tokensA.length, 2);
        assertEq(amountsA.length, 2);
        // Order depends on vault/collection iteration order
        assertEq(tokensA[0], address(yieldTokenA));
        assertEq(amountsA[0], expectedTotalA_Alice);
        assertEq(tokensA[1], address(yieldTokenB));
        assertEq(amountsA[1], expectedTotalB_Alice);

        // Bob:
        // Coll 1: 1 NFT -> YTA=0.5, YTB=0.25
        // Coll 2: 2 NFTs -> YTA=1.0, YTB=0.5
        // Total: YTA = 1.5, YTB = 0.75
        uint256 expectedTotalA_Bob = (1 * DEFAULT_MOCK_YIELD_A) + (2 * DEFAULT_MOCK_YIELD_A);
        uint256 expectedTotalB_Bob = (1 * DEFAULT_MOCK_YIELD_B) + (2 * DEFAULT_MOCK_YIELD_B);

        (address[] memory tokensB, uint256[] memory amountsB) = vaultManager.getTotalPendingYield(USER_BOB);
        assertEq(tokensB.length, 2);
        assertEq(amountsB.length, 2);
        assertEq(tokensB[0], address(yieldTokenA));
        assertEq(amountsB[0], expectedTotalA_Bob);
        assertEq(tokensB[1], address(yieldTokenB));
        assertEq(amountsB[1], expectedTotalB_Bob);

        // Charlie (no NFTs)
        (address[] memory tokensC, uint256[] memory amountsC) = vaultManager.getTotalPendingYield(USER_CHARLIE);
        assertEq(tokensC.length, 0);
        assertEq(amountsC.length, 0);
    }

    function testFail_View_GetPendingYieldForCollection_NotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(VaultManager.CollectionNotRegistered.selector, address(unregisteredNftCollection))
        );
        vaultManager.getPendingYieldForCollection(USER_ALICE, address(unregisteredNftCollection));
    }

    // --- Reentrancy Tests (Basic) ---

    // Need a malicious contract to test reentrancy properly.
    // Placeholder for now.
    // function testFail_Reentrancy_ClaimForCollection() public {
    //     // Deploy Malicious Actor Contract
    //     // Malicious Actor calls claimForCollection and tries to re-enter
    //     revert("Reentrancy test not implemented");
    // }

    // function testFail_Reentrancy_ClaimAll() public {
    //     // Deploy Malicious Actor Contract
    //     // Malicious Actor calls claimAll and tries to re-enter
    //     revert("Reentrancy test not implemented");
    // }
}
