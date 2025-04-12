// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {LendingManager} from "../src/LendingManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockCToken} from "../src/mocks/MockCToken.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {MinimalCTokenInterface} from "../src/interfaces/MinimalCTokenInterface.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";

contract LendingManagerTest is Test {
    // --- Constants & Config ---
    address constant VAULT_ADDRESS = address(0xABC); // Simulated Vault
    address constant REWARDS_CONTROLLER = address(0xDEF);
    address constant OTHER_USER = address(0x123);
    address constant OWNER = address(0x001);
    address constant MOCK_NFT_COLLECTION = address(0x111); // Placeholder NFT Collection
    uint256 constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 constant VAULT_INITIAL_ASSET = 100_000 ether;
    uint256 constant PRECISION = 1e18;

    // --- Contracts ---
    LendingManager lendingManager;
    MockERC20 assetToken;
    MockCToken cToken;

    // --- Setup ---
    function setUp() public {
        // Deploy Asset Token
        vm.startPrank(OWNER);
        assetToken = new MockERC20("Asset Token", "AST", INITIAL_SUPPLY);

        // Deploy Mock cToken
        cToken = new MockCToken(address(assetToken));

        // Deploy Lending Manager
        lendingManager = new LendingManager(OWNER, address(assetToken), address(cToken));

        // Set Rewards Controller address
        lendingManager.setRewardsController(REWARDS_CONTROLLER);
        vm.stopPrank();

        // Fund Vault Address
        vm.prank(OWNER);
        assetToken.transfer(VAULT_ADDRESS, VAULT_INITIAL_ASSET);

        // Approve Lending Manager for Vault
        vm.startPrank(VAULT_ADDRESS);
        assetToken.approve(address(lendingManager), type(uint256).max);
        vm.stopPrank();
    }

    // --- ILendingManager Tests ---

    function test_DepositToLendingProtocol_Success() public {
        uint256 depositAmount = 10_000 ether;
        uint256 initialLMUnderlying = assetToken.balanceOf(address(lendingManager));
        uint256 initialCTokenUnderlying = cToken.balanceOfUnderlying(address(lendingManager));

        // Mock cToken mint interaction
        // Expect transferFrom from Vault, then transfer to cToken by LM
        vm.expectCall(address(cToken), abi.encodeWithSelector(MinimalCTokenInterface.mint.selector, depositAmount), 1);
        cToken.setMintResult(0); // Success

        // Simulate LendingManager calling deposit
        vm.startPrank(VAULT_ADDRESS); // Called by Vault
        bool success = lendingManager.depositToLendingProtocol(depositAmount, MOCK_NFT_COLLECTION);
        vm.stopPrank();

        assertTrue(success, "Deposit should succeed");
        // Vault should have transferred assets
        assertEq(assetToken.balanceOf(VAULT_ADDRESS), VAULT_INITIAL_ASSET - depositAmount, "Vault balance after");
        // LM should have briefly held assets, then transferred to cToken (mock handles this)
        assertEq(assetToken.balanceOf(address(lendingManager)), initialLMUnderlying, "LM direct balance after");
        // Check mock cToken state (simplified tracking)
        assertEq(
            cToken.balanceOfUnderlying(address(lendingManager)),
            initialCTokenUnderlying + depositAmount,
            "cToken underlying balance after"
        );
    }

    function test_RevertIf_Deposit_MintFails() public {
        uint256 depositAmount = 1000 ether;

        // Mock cToken mint to fail (return non-zero)
        vm.expectCall(address(cToken), abi.encodeWithSelector(MinimalCTokenInterface.mint.selector, depositAmount), 1);
        cToken.setMintResult(1); // Error code 1

        vm.startPrank(VAULT_ADDRESS);
        vm.expectRevert(LendingManager.MintFailed.selector);
        lendingManager.depositToLendingProtocol(depositAmount, MOCK_NFT_COLLECTION);
        vm.stopPrank();

        // Ensure assets were pulled but not stuck in LM
        assertEq(
            assetToken.balanceOf(VAULT_ADDRESS),
            VAULT_INITIAL_ASSET, // Should not change on revert
            "Vault balance after failed deposit"
        );
        // Assert LM *does not* hold the funds if mint failed, as transferFrom reverts
        assertEq(assetToken.balanceOf(address(lendingManager)), 0, "LM balance after failed deposit");
    }

    function test_WithdrawFromLendingProtocol_Success() public {
        // Setup: Deposit first
        uint256 depositAmount = 20_000 ether;
        uint256 initialExchangeRate = cToken.exchangeRateStored();
        uint256 expectedCTokens = (depositAmount * 1e18) / initialExchangeRate; // Based on MockCToken logic

        vm.expectCall(address(cToken), abi.encodeWithSelector(MinimalCTokenInterface.mint.selector, depositAmount), 1);
        cToken.setMintResult(0);
        vm.prank(VAULT_ADDRESS);
        lendingManager.depositToLendingProtocol(depositAmount, MOCK_NFT_COLLECTION);
        uint256 initialVaultBalance = assetToken.balanceOf(VAULT_ADDRESS);
        // Check balance via LM's totalAssets
        assertEq(lendingManager.totalAssets(), depositAmount, "Total assets after deposit");

        // Withdraw
        uint256 withdrawAmount = 5_000 ether;

        // Mock cToken state *before* withdraw
        // No need to mock exchangeRateStored if using default
        // No need to explicitly mock balanceOfUnderlying - tested via totalAssets

        // Mock cToken redeem interaction
        vm.expectCall(
            address(cToken), abi.encodeWithSelector(MinimalCTokenInterface.redeemUnderlying.selector, withdrawAmount), 1
        );
        cToken.setRedeemResult(0); // Success

        // Simulate LendingManager calling withdraw
        vm.startPrank(VAULT_ADDRESS); // Called by Vault
        bool success = lendingManager.withdrawFromLendingProtocol(withdrawAmount);
        vm.stopPrank();

        assertTrue(success, "Withdraw should succeed");
        assertEq(assetToken.balanceOf(VAULT_ADDRESS), initialVaultBalance + withdrawAmount, "Vault balance after");
        assertEq(assetToken.balanceOf(address(lendingManager)), 0, "LM direct balance after");
        // Check mock cToken state via totalAssets
        assertEq(
            lendingManager.totalAssets(), // Use LM totalAssets which uses the formula
            depositAmount - withdrawAmount,
            "LM total assets after withdraw"
        );
    }

    function test_RevertIf_Withdraw_RedeemFails() public {
        // Setup: Deposit
        uint256 depositAmount = 10_000 ether;
        vm.expectCall(address(cToken), abi.encodeWithSelector(MinimalCTokenInterface.mint.selector, depositAmount), 1);
        vm.prank(VAULT_ADDRESS);
        lendingManager.depositToLendingProtocol(depositAmount, MOCK_NFT_COLLECTION);
        uint256 initialVaultBalance = assetToken.balanceOf(VAULT_ADDRESS);

        // Withdraw attempt, mock redeem failure
        uint256 withdrawAmount = 2_000 ether;

        // Mock cToken state before withdraw attempt

        vm.expectCall(
            address(cToken), abi.encodeWithSelector(MinimalCTokenInterface.redeemUnderlying.selector, withdrawAmount), 1
        );
        cToken.setRedeemResult(1); // Error code 1

        vm.startPrank(VAULT_ADDRESS);
        vm.expectRevert(LendingManager.RedeemFailed.selector);
        lendingManager.withdrawFromLendingProtocol(withdrawAmount);
        vm.stopPrank();

        // Ensure vault balance is unchanged
        assertEq(assetToken.balanceOf(VAULT_ADDRESS), initialVaultBalance, "Vault balance after failed withdraw");
    }

    function test_RevertIf_Withdraw_InsufficientBalanceInProtocol() public {
        // No deposit, try withdrawing
        uint256 withdrawAmount = 1 ether;

        // Mock cToken balance check (returns 0)
        // balanceOfUnderlying is view, no need for expectCall?

        vm.startPrank(VAULT_ADDRESS);
        vm.expectRevert("LM: Insufficient balance in protocol");
        lendingManager.withdrawFromLendingProtocol(withdrawAmount);
        vm.stopPrank();
    }

    function test_TotalAssets() public {
        // Setup: Deposit
        uint256 depositAmount = 15_000 ether;
        uint256 initialExchangeRate = cToken.exchangeRateStored(); // Mock returns raw rate
        // Calculate expected cTokens based on mock's mint logic
        uint256 expectedCTokens = (depositAmount * 1e18) / initialExchangeRate;

        vm.expectCall(address(cToken), abi.encodeWithSelector(MinimalCTokenInterface.mint.selector, depositAmount), 1);
        vm.prank(VAULT_ADDRESS);
        lendingManager.depositToLendingProtocol(depositAmount, MOCK_NFT_COLLECTION);

        // Check totalAssets immediately after deposit
        assertEq(lendingManager.totalAssets(), depositAmount, "Total assets mismatch after deposit");

        // Simulate yield by changing the exchange rate in the mock cToken
        uint256 yieldAmount = 1000 ether;
        uint256 newUnderlyingTotal = depositAmount + yieldAmount;
        // Calculate the new exchange rate needed to produce the target underlying total
        uint256 newExchangeRate = (newUnderlyingTotal * 1e18) / expectedCTokens; // Recalculate based on expected cTokens
        cToken.setExchangeRate(newExchangeRate);

        // Assert totalAssets is close to the target, allowing for dust
        uint256 actualTotalAssets = lendingManager.totalAssets();
        assertApproxEqAbs(actualTotalAssets, newUnderlyingTotal, 250000, "Total assets after yield (rate change)"); // Allow larger delta for precision
    }

    function test_GetBaseRewardPerBlock() public {
        // Setup: Deposit
        uint256 depositAmount = 100_000 ether;
        vm.expectCall(address(cToken), abi.encodeWithSelector(MinimalCTokenInterface.mint.selector, depositAmount), 1);
        vm.prank(VAULT_ADDRESS);
        lendingManager.depositToLendingProtocol(depositAmount, MOCK_NFT_COLLECTION);

        // Use the contract's totalAssets to calculate expected reward
        uint256 currentTotalAssets = lendingManager.totalAssets();
        uint256 expectedReward = (
            currentTotalAssets
                * (lendingManager.R0_BASIS_POINTS() * PRECISION / lendingManager.BASIS_POINTS_DENOMINATOR())
        ) / PRECISION;
        assertEq(lendingManager.getBaseRewardPerBlock(), expectedReward, "Base reward calculation mismatch");

        // Check with 0 assets
        LendingManager newLM = new LendingManager(OWNER, address(assetToken), address(cToken));
        assertEq(newLM.getBaseRewardPerBlock(), 0, "Base reward with zero assets");
    }

    function test_TransferYield_Success() public {
        uint256 yieldAmount = 50 ether;
        // Manually fund LM with assets to simulate yield being available
        vm.prank(OWNER);
        assetToken.transfer(address(lendingManager), yieldAmount);
        uint256 initialControllerBalance = assetToken.balanceOf(REWARDS_CONTROLLER);

        // Call transferYield from Rewards Controller address
        vm.startPrank(REWARDS_CONTROLLER);
        bool success = lendingManager.transferYield(yieldAmount, REWARDS_CONTROLLER);
        vm.stopPrank();

        assertTrue(success, "Transfer yield should succeed");
        assertEq(assetToken.balanceOf(address(lendingManager)), 0, "LM balance after yield transfer");
        assertEq(
            assetToken.balanceOf(REWARDS_CONTROLLER),
            initialControllerBalance + yieldAmount,
            "Rewards controller balance after yield transfer"
        );
    }

    function test_RevertIf_TransferYield_NotController() public {
        uint256 yieldAmount = 10 ether;
        vm.prank(OWNER);
        assetToken.transfer(address(lendingManager), yieldAmount);

        vm.startPrank(OTHER_USER); // Call from wrong address
        vm.expectRevert(LendingManager.CallerNotRewardsController.selector);
        lendingManager.transferYield(yieldAmount, OTHER_USER);
        vm.stopPrank();
    }

    function test_RevertIf_TransferYield_InsufficientBalance() public {
        uint256 yieldAmount = 10 ether;
        // LM has 0 direct balance

        vm.startPrank(REWARDS_CONTROLLER);
        vm.expectRevert(LendingManager.TransferYieldFailed.selector);
        lendingManager.transferYield(yieldAmount, REWARDS_CONTROLLER);
        vm.stopPrank();
    }

    function test_TransferYield_ZeroAmount() public {
        uint256 initialControllerBalance = assetToken.balanceOf(REWARDS_CONTROLLER);
        uint256 initialLMBalance = assetToken.balanceOf(address(lendingManager));

        vm.startPrank(REWARDS_CONTROLLER);
        bool success = lendingManager.transferYield(0, REWARDS_CONTROLLER);
        vm.stopPrank();

        assertTrue(success, "Transfer 0 yield should succeed");
        assertEq(assetToken.balanceOf(REWARDS_CONTROLLER), initialControllerBalance, "Controller balance unchanged");
        assertEq(assetToken.balanceOf(address(lendingManager)), initialLMBalance, "LM balance unchanged");
    }

    // --- Admin Functions Tests ---

    function test_SetRewardsController() public {
        address newController = address(0x999);
        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true, address(lendingManager));
        emit LendingManager.RewardsControllerSet(newController);
        lendingManager.setRewardsController(newController);
        vm.stopPrank();

        assertEq(lendingManager.rewardsController(), newController, "Controller address mismatch");
    }

    function test_RevertIf_SetRewardsController_NotOwner() public {
        address newController = address(0x999);
        vm.startPrank(OTHER_USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER_USER));
        lendingManager.setRewardsController(newController);
        vm.stopPrank();
    }

    function test_RevertIf_SetRewardsController_ZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert(LendingManager.AddressZero.selector);
        lendingManager.setRewardsController(address(0));
        vm.stopPrank();
    }
}
