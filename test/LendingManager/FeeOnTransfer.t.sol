// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {LendingManager} from "src/LendingManager.sol";
import {MockFeeOnTransferERC20} from "src/mocks/MockFeeOnTransferERC20.sol";
import {MockCToken} from "src/mocks/MockCToken.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol";

contract LendingManager_FeeOnTransfer_Test is Test {
    using SafeERC20 for IERC20;

    LendingManager internal lendingManager;
    MockFeeOnTransferERC20 internal asset;
    MockCToken internal cToken;

    address internal owner;
    address internal alice;
    address internal bob;
    address internal rewardsControllerAddress;
    address internal feeCollector;

    uint256 internal constant INITIAL_ASSET_BALANCE = 1_000_000; // Amount in token units
    uint16 internal constant FEE_BPS = 100; // 1% fee

    bytes32 internal constant REWARDS_CONTROLLER_ROLE = keccak256("REWARDS_CONTROLLER_ROLE");

    error LendingManager__TransferFailed(address token, address to, uint256 amount);
    error LendingManager__BalanceCheckFailed(string reason, uint256 expected, uint256 actual);

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        rewardsControllerAddress = makeAddr("rewardsController");
        feeCollector = makeAddr("feeCollector");

        vm.startPrank(owner);
        // MockFeeOnTransferERC20 constructor: name, symbol, decimals, feeBpsSend, feeBpsReceive, feeCollector
        // Assuming feeBpsSend is 0 and feeBpsReceive is FEE_BPS for this test's purpose (fee on incoming transfers to LM)
        asset = new MockFeeOnTransferERC20("FeeToken", "FEE", 18, 0, FEE_BPS, feeCollector);
        cToken = new MockCToken(address(asset));
        // LendingManager constructor: initialAdmin, vaultAddress, rewardsControllerAddress, _assetAddress, _cTokenAddress
        lendingManager = new LendingManager(owner, owner, rewardsControllerAddress, address(asset), address(cToken));

        // Grant VAULT_ROLE to alice and bob so they can call deposit/withdraw
        // owner is already admin and vault by constructor.
        lendingManager.grantVaultRole(alice);
        lendingManager.grantVaultRole(bob);
        // rewardsControllerAddress already has REWARDS_CONTROLLER_ROLE from constructor.

        vm.stopPrank();

        // Mint assets to users (amount is in token units, not wei)
        asset.mint(alice, INITIAL_ASSET_BALANCE);
        asset.mint(bob, INITIAL_ASSET_BALANCE);
        // Mint some underlying to the cToken contract directly so it can fulfill redemptions.
        // This is a common pattern in Compound tests.
        asset.mint(address(cToken), INITIAL_ASSET_BALANCE * 3); // cToken has plenty of underlying

        // Approve LendingManager
        vm.startPrank(alice);
        asset.approve(address(lendingManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        asset.approve(address(lendingManager), type(uint256).max);
        vm.stopPrank();
    }

    function test_RevertDeposit_AssetTransferIn_ShortChanged() public {
        uint256 depositAmountTokens = 1000; // Amount in token units
        uint8 underlyingDecimals = asset.decimals();
        uint256 depositAmountWei = depositAmountTokens * (10 ** underlyingDecimals);

        vm.startPrank(alice); // Alice has VAULT_ROLE

        uint256 lmBalanceBeforeWei = asset.balanceOf(address(lendingManager));
        // Expected balance in LendingManager if the full amount was transferred without a fee
        uint256 expectedLMBalanceAfterIfNoFee = lmBalanceBeforeWei + depositAmountWei;
        // Actual amount LendingManager will receive after the fee-on-transfer-in
        uint256 feeOnTransferInWei = depositAmountWei * FEE_BPS / 10000;
        uint256 actualReceivedByLMWei = depositAmountWei - feeOnTransferInWei;
        uint256 actualLMBalanceAfterWithFee = lmBalanceBeforeWei + actualReceivedByLMWei;

        vm.expectRevert(
            abi.encodeWithSelector(
                LendingManager__BalanceCheckFailed.selector,
                "LM: deposit asset receipt mismatch", // Error reason string
                expectedLMBalanceAfterIfNoFee, // Expected balance by LM (amount + initial)
                actualLMBalanceAfterWithFee // Actual balance in LM after fee (amount - fee + initial)
            )
        );
        // Alice (VAULT_ROLE) calls depositToLendingProtocol
        lendingManager.depositToLendingProtocol(depositAmountWei);
        vm.stopPrank();
    }

    function test_RevertWithdraw_CTokenRedeem_ReceiptShortChanged() public {
        uint256 depositAmountTokens = 1000; // Alice wants to deposit 1000 underlying tokens
        uint8 underlyingDecimals = asset.decimals();
        uint256 depositAmountWei = depositAmountTokens * (10 ** underlyingDecimals);

        // --- Setup: Alice deposits, LM gets cTokens ---
        vm.startPrank(alice); // Alice has VAULT_ROLE
        // To make this deposit succeed (not revert due to fee mismatch for this setup),
        // we'll temporarily set the asset's receive fee to 0 for the LM.
        // This way, LM receives the full amount, and cToken minting is straightforward.
        asset.setFeeBpsReceive(address(lendingManager), 0);
        lendingManager.depositToLendingProtocol(depositAmountWei);
        asset.setFeeBpsReceive(address(lendingManager), FEE_BPS); // Reset fee for LM
        vm.stopPrank();

        uint256 lmCTokenBalance = cToken.balanceOf(address(lendingManager));
        assertTrue(lmCTokenBalance > 0, "LM should have cTokens after deposit");

        // --- Test: Alice withdraws, LM redeems cTokens ---
        // LM will redeem `lmCTokenBalance` of its own cTokens.
        // `cToken.redeemUnderlying` will attempt to transfer `expectedAssetsFromRedeem` to LM.
        // This transfer from cToken to LM will incur a fee because LM is the receiver.

        uint256 lmAssetBalanceBeforeWithdrawWei = asset.balanceOf(address(lendingManager));

        // This is the amount of underlying cToken *would* transfer if there were no fee on LM receiving it
        // We use balanceOfUnderlying which calculates: cTokens * exchangeRate / scale
        uint256 expectedAssetsFromRedeemPreFee = cToken.balanceOfUnderlying(address(lendingManager));

        // The fee LM will pay on receiving these assets from cToken
        uint256 feeOnRedeemReceiptWei = expectedAssetsFromRedeemPreFee * FEE_BPS / 10000;
        // The actual amount of assets LM will receive from cToken after the fee
        uint256 actualAssetsReceivedByLMFromRedeem = expectedAssetsFromRedeemPreFee - feeOnRedeemReceiptWei;

        // Expected LM asset balance after redeem if no fee was charged on receipt
        uint256 expectedLMBalanceAfterRedeemIfNoFee = lmAssetBalanceBeforeWithdrawWei + expectedAssetsFromRedeemPreFee;
        // Actual LM asset balance after redeem, considering the fee on receipt
        uint256 actualLMBalanceAfterRedeemWithFee = lmAssetBalanceBeforeWithdrawWei + actualAssetsReceivedByLMFromRedeem;

        vm.startPrank(alice); // Alice (VAULT_ROLE) initiates withdrawal
        vm.expectRevert(
            abi.encodeWithSelector(
                LendingManager__BalanceCheckFailed.selector,
                "LM: withdraw cToken.redeemUnderlying receipt mismatch", // Error reason
                expectedLMBalanceAfterRedeemIfNoFee, // Expected balance by LM (amount + initial)
                actualLMBalanceAfterRedeemWithFee // Actual balance in LM after fee (amount - fee + initial)
            )
        );
        // Alice requests to withdraw an amount of *underlying* that corresponds to all of LM's cTokens.
        // The `withdrawFromLendingProtocol` function takes underlying amount.
        // For this test, we want to trigger the redeem of all cTokens held by LM.
        // The amount passed to withdrawFromLendingProtocol should be the amount of underlying Alice expects.
        // However, the internal check is on the cToken.redeemUnderlying step.
        // Let's use `expectedAssetsFromRedeemPreFee` as the amount Alice requests to withdraw.
        // The function will then try to redeem cTokens to get this amount.
        lendingManager.withdrawFromLendingProtocol(expectedAssetsFromRedeemPreFee);
        vm.stopPrank();
    }

    function test_RevertTransferYield_CTokenRedeem_ReceiptShortChanged() public {
        uint256 yieldAmountTokens = 100; // Amount of underlying yield to generate
        uint8 underlyingDecimals = asset.decimals();
        uint256 yieldAmountWei = yieldAmountTokens * (10 ** underlyingDecimals);

        // --- Setup: LM has cTokens, cToken has underlying ---
        // To generate `yieldAmountWei` of underlying, LM needs to redeem a certain amount of cTokens.
        // Let's assume 1 cToken = 1 underlying for simplicity in mock, so LM needs `yieldAmountWei` of cTokens.
        // (In reality, exchange rate varies. MockCToken.redeemUnderlying uses 1:1 if not overridden)
        deal(address(cToken), address(lendingManager), yieldAmountWei); // Give cTokens to LM
        // Ensure cToken contract has enough underlying to cover the redemption
        asset.mint(address(cToken), yieldAmountWei * 2); // Mint underlying to cToken contract

        uint256 lmCTokenBalance = cToken.balanceOf(address(lendingManager));
        assertTrue(lmCTokenBalance >= yieldAmountWei, "LM must have enough cTokens for yield");

        // --- Test: transferYield is called ---
        // `transferYield` will call `_redeemCTokensInternal` which calls `cToken.redeemUnderlying`.
        // `cToken.redeemUnderlying` transfers `yieldAmountWei` (pre-fee) of asset to LendingManager.
        // This receipt by LendingManager incurs a fee.

        uint256 lmAssetBalanceBeforeWei = asset.balanceOf(address(lendingManager));

        // Amount LM expects to receive from redeem, before fee
        uint256 expectedAssetsFromRedeemPreFee = yieldAmountWei;
        // Fee LM pays on receiving these assets
        uint256 feeOnRedeemReceiptWei = expectedAssetsFromRedeemPreFee * FEE_BPS / 10000;
        // Actual amount LM receives
        uint256 actualAssetsReceivedByLMFromRedeem = expectedAssetsFromRedeemPreFee - feeOnRedeemReceiptWei;

        // Expected LM asset balance after redeem if no fee was charged on receipt
        uint256 expectedLMBalanceAfterRedeemIfNoFee = lmAssetBalanceBeforeWei + expectedAssetsFromRedeemPreFee;
        // Actual LM asset balance after redeem, considering the fee on receipt
        uint256 actualLMBalanceAfterRedeemWithFee = lmAssetBalanceBeforeWei + actualAssetsReceivedByLMFromRedeem;

        vm.startPrank(rewardsControllerAddress); // rewardsControllerAddress has REWARDS_CONTROLLER_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(
                LendingManager__BalanceCheckFailed.selector,
                "LM: withdraw cToken.redeem receipt mismatch", // Error reason from _redeemCTokensInternal
                expectedLMBalanceAfterRedeemIfNoFee,
                actualLMBalanceAfterRedeemWithFee
            )
        );
        // transferYield(uint256 amountUnderlying, address recipient)
        // The recipient here is where the yield ultimately goes *after* LM processes it.
        // The BalanceCheckFailed error happens *during* LM's internal processing (redeeming from cToken).
        lendingManager.transferYield(yieldAmountWei, rewardsControllerAddress);
        vm.stopPrank();
    }

    function test_RevertRedeemAllCTokens_RedeemReceipt_ShortChanged() public {
        uint256 cTokensToDealToLM = 1000 * (10 ** cToken.decimals()); // Amount of cTokens for LM
        uint8 underlyingDecimals = asset.decimals();

        // --- Setup: LM has cTokens, cToken has underlying ---
        deal(address(cToken), address(lendingManager), cTokensToDealToLM); // Give cTokens to LM

        // Determine underlying needed for these cTokens
        // Calculation: cTokenAmount * exchangeRateStored / scale (1e18)
        uint256 underlyingNeededForRedemption = (cTokensToDealToLM * cToken.exchangeRateStored()) / 1e18;
        asset.mint(address(cToken), underlyingNeededForRedemption * 2); // Ensure cToken can cover redemption

        uint256 lmCTokenBalance = cToken.balanceOf(address(lendingManager));
        assertTrue(lmCTokenBalance > 0, "LM should have cTokens");
        assertTrue(lmCTokenBalance == cTokensToDealToLM, "LM cToken balance mismatch after deal");

        // --- Test: redeemAllCTokens is called ---
        // `redeemAllCTokens` will call `_redeemCTokensInternal` for the full cToken balance of LM.
        // `cToken.redeemUnderlying` transfers assets to LendingManager.
        // This receipt by LendingManager incurs a fee.

        uint256 lmAssetBalanceBeforeWei = asset.balanceOf(address(lendingManager));

        // Amount LM expects to receive from redeeming all its cTokens, before fee
        // We use balanceOfUnderlying which calculates: cTokens * exchangeRate / scale
        uint256 expectedAssetsFromFullRedeemPreFee = cToken.balanceOfUnderlying(address(lendingManager));
        // Fee LM pays on receiving these assets
        uint256 feeOnRedeemReceiptWei = expectedAssetsFromFullRedeemPreFee * FEE_BPS / 10000;
        // Actual amount LM receives
        uint256 actualAssetsReceivedByLMFromRedeem = expectedAssetsFromFullRedeemPreFee - feeOnRedeemReceiptWei;

        // Expected LM asset balance after redeem if no fee was charged on receipt
        uint256 expectedLMBalanceAfterRedeemIfNoFee = lmAssetBalanceBeforeWei + expectedAssetsFromFullRedeemPreFee;
        // Actual LM asset balance after redeem, considering the fee on receipt
        uint256 actualLMBalanceAfterRedeemWithFee = lmAssetBalanceBeforeWei + actualAssetsReceivedByLMFromRedeem;

        vm.startPrank(owner); // Owner has ADMIN_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(
                LendingManager__BalanceCheckFailed.selector,
                "LM: redeemAll cToken.redeem receipt mismatch", // Error reason from _redeemCTokensInternal
                expectedLMBalanceAfterRedeemIfNoFee,
                actualLMBalanceAfterRedeemWithFee
            )
        );
        // redeemAllCTokens(address recipient)
        lendingManager.redeemAllCTokens(owner); // Assets will be sent to owner after successful redeem by LM
        vm.stopPrank();
    }
}
