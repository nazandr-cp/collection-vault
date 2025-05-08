// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {LendingManager} from "../src/LendingManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockCToken} from "../src/mocks/MockCToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CTokenInterface, CErc20Interface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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
        lendingManager =
            new LendingManager(OWNER, VAULT_ADDRESS, REWARDS_CONTROLLER, address(assetToken), address(cToken));

        // Rewards Controller address is set in constructor and role granted
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
        vm.expectCall(address(cToken), abi.encodeWithSelector(CErc20Interface.mint.selector, depositAmount), 1); // <-- Use CErc20Interface
        cToken.setMintResult(0); // Success

        // Simulate LendingManager calling deposit
        vm.startPrank(VAULT_ADDRESS); // Called by Vault
        bool success = lendingManager.depositToLendingProtocol(depositAmount);
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
        vm.expectCall(address(cToken), abi.encodeWithSelector(CErc20Interface.mint.selector, depositAmount), 1); // <-- Use CErc20Interface
        cToken.setMintResult(1); // Error code 1

        vm.startPrank(VAULT_ADDRESS);
        vm.expectRevert(LendingManager.MintFailed.selector);
        lendingManager.depositToLendingProtocol(depositAmount);
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
        // This initialFunding is directly held by LM and should NOT be part of totalAssets() if it\'s cToken only
        // uint256 initialAmount = 1_000_000 ether;
        // assetToken.deal(address(lendingManager), initialAmount);

        uint256 depositAmount = 1_000 ether; // Vault deposits this amount
        uint256 withdrawAmount = 100 ether; // Vault withdraws this amount

        // Vault deposits
        vm.deal(VAULT_ADDRESS, depositAmount); // Corrected: Use vm.deal(address, uint256)
        vm.startPrank(VAULT_ADDRESS);
        assetToken.approve(address(lendingManager), depositAmount);
        lendingManager.depositToLendingProtocol(depositAmount);
        vm.stopPrank();

        // Check initial totalAssets() - it should reflect the cToken holdings from the deposit
        cToken.accrueInterest(); // Ensure interest is accrued for accurate totalAssets
        uint256 initialTotalAssets = lendingManager.totalAssets();

        // Withdraw
        // Mock cToken redeem interaction
        vm.expectCall(
            address(cToken),
            abi.encodeWithSelector(CErc20Interface.redeemUnderlying.selector, withdrawAmount),
            1 // <-- Use CErc20Interface
        );
        cToken.setRedeemResult(0); // Success

        // Simulate LendingManager calling withdraw
        vm.startPrank(VAULT_ADDRESS); // Called by Vault
        bool success = lendingManager.withdrawFromLendingProtocol(withdrawAmount);
        vm.stopPrank();

        assertTrue(success, "Withdraw should succeed");
        // Vault balance should increase by the withdraw amount
        assertEq(assetToken.balanceOf(VAULT_ADDRESS), depositAmount - withdrawAmount, "Vault balance after");
        // LM direct balance should be 0 if all was withdrawn
        assertEq(assetToken.balanceOf(address(lendingManager)), 0, "LM direct balance after");
        // totalAssets should decrease by the withdraw amount
        assertEq(lendingManager.totalAssets(), initialTotalAssets - withdrawAmount, "LM total assets after withdraw");
    }

    function test_RevertIf_Withdraw_RedeemFails() public {
        // Setup: Deposit
        uint256 depositAmount = 10_000 ether;
        vm.expectCall(address(cToken), abi.encodeWithSelector(CErc20Interface.mint.selector, depositAmount), 1); // <-- Use CErc20Interface
        cToken.setMintResult(0); // Need to set mint result for setup
        vm.prank(VAULT_ADDRESS);
        lendingManager.depositToLendingProtocol(depositAmount);
        uint256 initialVaultBalance = assetToken.balanceOf(VAULT_ADDRESS);

        // Withdraw attempt, mock redeem failure
        uint256 withdrawAmount = 2_000 ether;

        // Mock cToken state before withdraw attempt

        vm.expectCall(
            address(cToken),
            abi.encodeWithSelector(CErc20Interface.redeemUnderlying.selector, withdrawAmount),
            1 // <-- Use CErc20Interface
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
        vm.expectRevert(LendingManager.InsufficientBalanceInProtocol.selector);
        lendingManager.withdrawFromLendingProtocol(withdrawAmount);
        vm.stopPrank();
    }

    function test_TotalAssets() public {
        uint256 initialFunding = 1_000_000 ether; // LM directly holds this
        uint256 depositAmount = 500_000 ether; // LM will deposit this portion to cToken

        // Fund LendingManager directly
        vm.deal(address(lendingManager), initialFunding); // Corrected: Use vm.deal(address, uint256)
        assertEq(assetToken.balanceOf(address(lendingManager)), initialFunding, "Initial funding failed");

        // LendingManager deposits a portion of its holdings to the cToken protocol
        // This deposit comes from its own balance, so it's an internal transfer to the protocol part
        vm.prank(address(lendingManager)); // For internal operations if any require it, though depositToLendingProtocol is external
            // For this specific call, it's the vault role that matters.
            // Let's assume vault calls it, and LM has approved itself or handles assets appropriately.

        // To simulate LM depositing its own funds, we need to ensure it has VAULT_ROLE or use a test setup
        // where the vault (msg.sender for depositToLendingProtocol) has the funds and deposits them.
        // For this test, let's assume the `depositAmount` is what the vault deposits into LendingManager,
        // and LM puts it into the cToken. The `initialFunding` is separate and NOT part of `totalAssets` if `totalAssets` is only cToken holdings.

        // Let's re-frame: Vault deposits `depositAmount` into LendingManager, which then puts it into cTokens.
        // `initialFunding` is irrelevant to `lendingManager.totalAssets()` if it only tracks cToken assets.
        // So, we simulate vault depositing `depositAmount`.
        vm.deal(VAULT_ADDRESS, depositAmount); // Corrected: Use vm.deal(address, uint256)
        vm.startPrank(VAULT_ADDRESS);
        assetToken.approve(address(lendingManager), depositAmount);
        lendingManager.depositToLendingProtocol(depositAmount);
        vm.stopPrank();

        uint256 actualTotalAssets = lendingManager.totalAssets();
        uint256 expectedTotalAssets = depositAmount; // totalAssets should only reflect what's in cTokens

        // console.log("Actual Total Assets (cToken part only): ", actualTotalAssets);
        // console.log("Expected Total Assets (depositAmount): ", expectedTotalAssets);

        assertApproxEqAbs(
            actualTotalAssets,
            expectedTotalAssets,
            1e18, // Allow for some minor interest accrual if any happened during mint
            "Total assets mismatch after deposit"
        );
    }

    function test_GetBaseRewardPerBlock() public {
        // Setup: Deposit
        uint256 depositAmount = 100_000 ether;
        vm.expectCall(address(cToken), abi.encodeWithSelector(CErc20Interface.mint.selector, depositAmount), 1); // <-- Use CErc20Interface
        cToken.setMintResult(0); // Need to set mint result for setup
        vm.prank(VAULT_ADDRESS);
        lendingManager.depositToLendingProtocol(depositAmount);

        // Use the contract's totalAssets to calculate expected reward
        uint256 currentTotalAssets = lendingManager.totalAssets();
        uint256 expectedReward = (
            currentTotalAssets
                * (lendingManager.R0_BASIS_POINTS() * PRECISION / lendingManager.BASIS_POINTS_DENOMINATOR())
        ) / PRECISION;
        assertEq(lendingManager.getBaseRewardPerBlock(), expectedReward, "Base reward calculation mismatch");

        // Check with 0 assets
        // Use dummy addresses for vault and controller for this isolated test instance
        LendingManager newLM =
            new LendingManager(OWNER, address(0xdead1), address(0xdead2), address(assetToken), address(cToken));
        assertEq(newLM.getBaseRewardPerBlock(), 0, "Base reward with zero assets");
    }

    function test_TransferYield_Success() public {
        uint256 amountToDeposit = 1_000_000 ether;
        address recipient = makeAddr("yieldRecipient");

        // Vault deposits into LendingManager
        vm.startPrank(VAULT_ADDRESS);
        assetToken.approve(address(lendingManager), amountToDeposit);
        lendingManager.depositToLendingProtocol(amountToDeposit);
        vm.stopPrank();

        // Simulate some yield generation by advancing time/blocks or manually adjusting cToken exchange rate
        // For simplicity, MockCToken accrues a tiny bit on each call like mint/redeem/balanceOfUnderlying
        // Let's ensure some yield is present by calling balanceOfUnderlying which triggers accrueInterest
        uint256 assetsBeforeYield = lendingManager.totalAssets(); // This is ~amountToDeposit
        // console.log("Assets before explicit yield generation: ", assetsBeforeYield);
        // console.log("Total Principal Deposited: ", lendingManager.totalPrincipalDeposited());

        // To make yield more significant for the test:
        vm.warp(block.timestamp + 1 days); // Advance time to generate more yield
        cToken.accrueInterest(); // Explicitly accrue interest

        uint256 currentTotalAssets = lendingManager.totalAssets();
        // console.log("Total assets after yield: ", currentTotalAssets);
        uint256 yieldGenerated = currentTotalAssets > lendingManager.totalPrincipalDeposited()
            ? currentTotalAssets - lendingManager.totalPrincipalDeposited()
            : 0;

        // console.log("Calculated Yield Generated: ", yieldGenerated);
        assertTrue(yieldGenerated > 0, "Yield should be generated");

        uint256 amountToTransfer = yieldGenerated;

        vm.startPrank(REWARDS_CONTROLLER);
        uint256 transferredAmount = lendingManager.transferYield(amountToTransfer, recipient);
        vm.stopPrank();

        // console.log("Transferred Amount: ", transferredAmount);
        // console.log("Recipient Balance: ", assetToken.balanceOf(recipient));

        assertApproxEqAbs(transferredAmount, amountToTransfer, 1e15, "Transferred amount mismatch"); // Allow small delta for precision
        assertApproxEqAbs(assetToken.balanceOf(recipient), amountToTransfer, 1e15, "Recipient balance mismatch");

        // After transferring all yield, totalAssets should be back to totalPrincipalDeposited (approximately)
        assertApproxEqAbs(
            lendingManager.totalAssets(),
            lendingManager.totalPrincipalDeposited(), // Or amountToDeposit if no further deposits/withdrawals of principal
            1e16, // Allow for minor fluctuations / precision of mock cToken
            "Total assets after transferring yield should be approx totalPrincipalDeposited"
        );
    }

    function test_RevertIf_TransferYield_NotController() public {
        uint256 yieldAmount = 10 ether;
        vm.prank(OWNER);
        assetToken.transfer(address(lendingManager), yieldAmount);

        vm.startPrank(OTHER_USER); // Call from wrong address
        vm.expectRevert(abi.encodeWithSelector(LendingManager.LM_CallerNotRewardsController.selector, OTHER_USER));
        lendingManager.transferYield(yieldAmount, OTHER_USER);
        vm.stopPrank();
    }

    function test_TransferYield_InsufficientBalance_ReturnsZero() public {
        // Renamed for clarity
        uint256 yieldAmount = 10 ether;
        // LM has 0 direct balance and 0 principal deposited, so availableYield is 0

        vm.startPrank(REWARDS_CONTROLLER);
        // Expect the function to return 0 because availableYield is 0, no revert expected
        uint256 amountTransferred = lendingManager.transferYield(yieldAmount, REWARDS_CONTROLLER);
        vm.stopPrank();

        assertEq(amountTransferred, 0, "Should return 0 when available yield is 0");
    }

    function test_TransferYield_ZeroAmount() public {
        uint256 initialControllerBalance = assetToken.balanceOf(REWARDS_CONTROLLER);
        uint256 initialLMBalance = assetToken.balanceOf(address(lendingManager));

        vm.startPrank(REWARDS_CONTROLLER);
        uint256 amountTransferred = lendingManager.transferYield(0, REWARDS_CONTROLLER);
        vm.stopPrank();

        assertEq(amountTransferred, 0, "Transfer 0 yield should return 0");
        assertEq(assetToken.balanceOf(REWARDS_CONTROLLER), initialControllerBalance, "Controller balance unchanged");
        assertEq(assetToken.balanceOf(address(lendingManager)), initialLMBalance, "LM balance unchanged");
    }

    // --- Admin Functions Tests ---

    // Removed obsolete tests for setRewardsController as it's replaced by AccessControl roles
    // The corresponding functions (setRewardsController, rewardsController) and event (RewardsControllerSet)
    // are no longer present in LendingManager.sol. Role management is tested implicitly
    // by other tests requiring the REWARDS_CONTROLLER_ROLE.
    // Removed obsolete test code for setRewardsController

    // Removed obsolete test: test_RevertIf_SetRewardsController_NotOwner
    // Removed obsolete test: test_RevertIf_SetRewardsController_ZeroAddress
}
