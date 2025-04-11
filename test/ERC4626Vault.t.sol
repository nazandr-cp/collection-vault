// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {ERC4626Vault} from "../src/ERC4626Vault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendingManager} from "../src/mocks/MockLendingManager.sol";
import {ILendingManager} from "../src/interfaces/ILendingManager.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";

contract ERC4626VaultTest is Test {
    // --- Constants & Config ---
    address constant USER_ALICE = address(0x111);
    address constant USER_BOB = address(0x222);
    address constant OWNER = address(0x001);
    address constant VAULT_ADDRESS = address(0xABC);
    uint256 constant INITIAL_ASSET_SUPPLY = 1_000_000 ether;
    uint256 constant USER_INITIAL_ASSET = 10_000 ether;
    uint256 constant LENDING_MANAGER_INITIAL_ASSETS = 500_000 ether;

    // --- Contracts ---
    ERC4626Vault vault;
    MockERC20 assetToken;
    MockLendingManager lendingManager;

    // --- Setup ---
    function setUp() public {
        // Deploy Asset Token
        vm.startPrank(OWNER);
        assetToken = new MockERC20("Asset Token", "AST", INITIAL_ASSET_SUPPLY);

        // Deploy Mock Lending Manager
        lendingManager = new MockLendingManager(address(assetToken));
        // Do not fund Lending Manager initially, start with 0 assets
        // assetToken.transfer(address(lendingManager), LENDING_MANAGER_INITIAL_ASSETS);
        // lendingManager.setTotalAssets(LENDING_MANAGER_INITIAL_ASSETS);
        lendingManager.setTotalAssets(0); // Explicitly start LM with 0 assets

        // Deploy Vault with Mock Lending Manager
        // changePrank is deprecated
        // changePrank(OWNER);
        vault = new ERC4626Vault(IERC20(address(assetToken)), "Vault Shares", "vAST", OWNER, address(lendingManager));
        vm.stopPrank();

        // Fund Users
        vm.prank(OWNER);
        assetToken.transfer(USER_ALICE, USER_INITIAL_ASSET);
        vm.prank(OWNER);
        assetToken.transfer(USER_BOB, USER_INITIAL_ASSET);

        // Approve Vault for Users
        vm.startPrank(USER_ALICE);
        assetToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(USER_BOB);
        assetToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // --- ERC4626 Core Function Tests ---

    function test_Deposit_Success() public {
        uint256 depositAmount = 100 ether;
        uint256 initialTotalAssets = lendingManager.totalAssets();
        uint256 expectedTotalAssetsAfter = initialTotalAssets + depositAmount;

        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.depositToLendingProtocol.selector, depositAmount),
            1
        );
        lendingManager.setExpectedDepositResult(true);

        vm.prank(USER_ALICE);
        uint256 sharesAlice = vault.deposit(depositAmount, USER_ALICE);

        assertEq(sharesAlice, depositAmount, "Initial deposit should be 1:1 shares");
        assertTrue(sharesAlice > 0, "Should receive some shares");

        assertEq(
            assetToken.balanceOf(USER_ALICE), USER_INITIAL_ASSET - depositAmount, "Alice asset balance after deposit"
        );
        assertEq(assetToken.balanceOf(address(vault)), 0, "Vault direct asset balance should be 0");
        assertEq(vault.balanceOf(USER_ALICE), sharesAlice, "Alice vault share balance");

        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Vault total assets after deposit");
    }

    function test_Withdraw_Success() public {
        uint256 depositAmount = 500 ether;
        // uint256 initialTotalAssets = lendingManager.totalAssets(); // Not strictly needed for this test's assertions

        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.depositToLendingProtocol.selector, depositAmount),
            1
        );
        lendingManager.setExpectedDepositResult(true);
        vm.prank(USER_ALICE);
        uint256 sharesAlice = vault.deposit(depositAmount, USER_ALICE);

        uint256 withdrawAmount = 100 ether;
        uint256 vaultTotalAssetsBeforeWithdraw = vault.totalAssets(); // Get state before withdraw

        // Calculate expected shares *before* the state changes
        uint256 expectedSharesToWithdraw = vault.previewWithdraw(withdrawAmount);

        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.withdrawFromLendingProtocol.selector, withdrawAmount),
            1
        );
        lendingManager.setExpectedWithdrawResult(true);

        vm.startPrank(USER_ALICE);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, USER_ALICE, USER_ALICE);
        vm.stopPrank();

        assertEq(sharesBurned, expectedSharesToWithdraw, "Shares burned mismatch");

        assertEq(
            assetToken.balanceOf(USER_ALICE),
            USER_INITIAL_ASSET - depositAmount + withdrawAmount,
            "Alice asset balance after withdraw"
        );
        assertEq(assetToken.balanceOf(address(vault)), 0, "Vault direct asset balance should be 0 after withdraw");
        assertEq(vault.balanceOf(USER_ALICE), sharesAlice - sharesBurned, "Alice shares after withdraw");

        // Assert total assets changed correctly
        assertEq(
            vault.totalAssets(), vaultTotalAssetsBeforeWithdraw - withdrawAmount, "Vault total assets after withdraw"
        );
    }

    function test_Mint_Success() public {
        uint256 mintShares = 200 ether;
        uint256 initialTotalAssets = lendingManager.totalAssets();

        uint256 requiredAssets = vault.previewMint(mintShares);
        uint256 expectedTotalAssetsAfter = initialTotalAssets + requiredAssets;

        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.depositToLendingProtocol.selector, requiredAssets),
            1
        );
        lendingManager.setExpectedDepositResult(true);

        vm.prank(USER_BOB);
        uint256 assetsMinted = vault.mint(mintShares, USER_BOB);

        assertEq(assetsMinted, requiredAssets, "Mint asset amount mismatch");
        assertEq(assetToken.balanceOf(USER_BOB), USER_INITIAL_ASSET - assetsMinted, "Bob asset after mint");
        assertEq(assetToken.balanceOf(address(vault)), 0, "Vault asset balance after mint should be 0");
        assertEq(vault.balanceOf(USER_BOB), mintShares, "Bob share balance after mint");

        assertEq(vault.totalAssets(), expectedTotalAssetsAfter, "Vault total assets after mint");
    }

    function test_Redeem_Success() public {
        uint256 mintShares = 500 ether;
        uint256 initialTotalAssets = lendingManager.totalAssets();

        uint256 requiredAssets = vault.previewMint(mintShares);
        uint256 totalAssetsAfterMint = initialTotalAssets + requiredAssets;

        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.depositToLendingProtocol.selector, requiredAssets),
            1
        );
        lendingManager.setExpectedDepositResult(true);
        vm.prank(USER_BOB);
        vault.mint(mintShares, USER_BOB);

        uint256 redeemSharesAmount = mintShares / 2;

        uint256 expectedAssetsFromRedeem = vault.previewRedeem(redeemSharesAmount);
        uint256 expectedTotalAssetsAfterRedeem = totalAssetsAfterMint - expectedAssetsFromRedeem;

        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.withdrawFromLendingProtocol.selector, expectedAssetsFromRedeem),
            1
        );
        lendingManager.setExpectedWithdrawResult(true);

        vm.startPrank(USER_BOB);
        uint256 assetsRedeemed = vault.redeem(redeemSharesAmount, USER_BOB, USER_BOB);
        vm.stopPrank();

        assertEq(assetsRedeemed, expectedAssetsFromRedeem, "Redeem asset amount mismatch");
        assertEq(
            assetToken.balanceOf(USER_BOB),
            USER_INITIAL_ASSET - requiredAssets + assetsRedeemed,
            "Bob asset balance after redeem"
        );
        assertEq(assetToken.balanceOf(address(vault)), 0, "Vault asset balance after redeem should be 0");
        assertEq(vault.balanceOf(USER_BOB), mintShares - redeemSharesAmount, "Bob shares after redeem");

        assertEq(vault.totalAssets(), expectedTotalAssetsAfterRedeem, "Vault total assets after redeem");
    }

    function test_RevertIf_Deposit_LMFails() public {
        uint256 depositAmount = 100 ether;

        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.depositToLendingProtocol.selector, depositAmount),
            1
        );
        lendingManager.setExpectedDepositResult(false);

        vm.prank(USER_ALICE);
        vm.expectRevert(ERC4626Vault.LendingManagerDepositFailed.selector);
        vault.deposit(depositAmount, USER_ALICE);
    }

    function test_RevertIf_Withdraw_LMFails() public {
        uint256 depositAmount = 100 ether;
        // uint256 initialTotalAssets = lendingManager.totalAssets(); // Unused
        // uint256 totalAssetsAfterDeposit = initialTotalAssets + depositAmount; // Unused

        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.depositToLendingProtocol.selector, depositAmount),
            1
        );
        lendingManager.setExpectedDepositResult(true);
        vm.prank(USER_ALICE);
        vault.deposit(depositAmount, USER_ALICE);

        uint256 withdrawAmount = 50 ether;
        vm.expectCall(
            address(lendingManager),
            abi.encodeWithSelector(ILendingManager.withdrawFromLendingProtocol.selector, withdrawAmount),
            1
        );
        lendingManager.setExpectedWithdrawResult(false);

        vm.prank(USER_ALICE);
        vm.expectRevert(ERC4626Vault.LendingManagerWithdrawFailed.selector);
        vault.withdraw(withdrawAmount, USER_ALICE, USER_ALICE);

        lendingManager.setExpectedWithdrawResult(true);
    }

    function test_RevertIf_Constructor_LMMismatch() public {
        MockERC20 wrongAsset = new MockERC20("Wrong Asset", "WST", 1);
        MockLendingManager tempLM = new MockLendingManager(address(assetToken));

        vm.prank(OWNER);
        vm.expectRevert(ERC4626Vault.LendingManagerMismatch.selector);
        new ERC4626Vault(IERC20(address(wrongAsset)), "Vault", "V", OWNER, address(tempLM));
    }

    function test_Deposit_Zero() public {
        uint256 aliceAssetsBefore = assetToken.balanceOf(USER_ALICE);
        uint256 aliceSharesBefore = vault.balanceOf(USER_ALICE);
        uint256 vaultTotalAssetsBefore = vault.totalAssets();

        vm.prank(USER_ALICE);
        uint256 shares = vault.deposit(0, USER_ALICE);

        assertEq(shares, 0, "Shares for 0 deposit");
        assertEq(assetToken.balanceOf(USER_ALICE), aliceAssetsBefore, "Alice assets unchanged");
        assertEq(vault.balanceOf(USER_ALICE), aliceSharesBefore, "Alice shares unchanged");
        assertEq(vault.totalAssets(), vaultTotalAssetsBefore, "Vault total assets unchanged");
    }

    // --- Ownable Tests ---

    function test_Ownable_TransferOwnership() public {
        assertEq(vault.owner(), OWNER, "Initial owner mismatch");

        vm.prank(OWNER);
        vault.transferOwnership(USER_ALICE);

        assertEq(vault.owner(), USER_ALICE, "New owner mismatch");
    }
}
