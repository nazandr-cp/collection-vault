// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {SimpleMockCToken} from "../src/mocks/SimpleMockCToken.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {DebtSubsidizer} from "../src/DebtSubsidizer.sol";
import {ICollectionsVault} from "../src/interfaces/ICollectionsVault.sol";
import {IDebtSubsidizer} from "../src/interfaces/IDebtSubsidizer.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract EdgeCasesTest is Test {
    // Mock Contracts
    MockERC20 internal asset;
    MockERC721 internal nft1;
    MockERC721 internal nft2; // For transfer scenarios
    SimpleMockCToken internal cToken;

    // Core Contracts
    LendingManager internal lendingManager;
    CollectionsVault internal vault;
    EpochManager internal epochManager;
    DebtSubsidizer internal debtSubsidizer;

    // Users
    address internal constant OWNER = address(0x1);
    address internal constant ADMIN = address(0x2);
    address internal constant AUTOMATION = address(0x3);
    address internal constant USER_A = address(0xA);
    address internal constant USER_B = address(0xB);

    // Signer for DebtSubsidizer
    uint256 internal constant SUBSIDY_SIGNER_PK = uint256(keccak256("SUBSIDY_SIGNER_EDGE"));
    address internal SUBSIDY_SIGNER;

    // Constants
    uint256 internal constant INITIAL_EXCHANGE_RATE = 2e28;
    uint256 internal constant ONE_DAY = 1 days;
    uint16 internal constant DEFAULT_YIELD_SHARE_BPS = 5000; // 50%

    function setUp() public {
        SUBSIDY_SIGNER = vm.addr(SUBSIDY_SIGNER_PK);
        asset = new MockERC20("Mock USDC", "mUSDC", 6, 0);
        nft1 = new MockERC721("Test NFT 1", "TNFT1");
        nft2 = new MockERC721("Test NFT 2", "TNFT2");

        cToken = new SimpleMockCToken(
            address(asset),
            ComptrollerInterface(payable(address(0xDEAD))),
            InterestRateModel(payable(address(0xBEEF))),
            INITIAL_EXCHANGE_RATE,
            "Mock cUSDC",
            "mcUSDC",
            8,
            payable(OWNER)
        );

        lendingManager = new LendingManager(OWNER, address(this), address(asset), address(cToken));
        vault = new CollectionsVault(IERC20(address(asset)), "CVT_Edge", "CVTE", ADMIN, address(lendingManager));

        vm.startPrank(OWNER);
        lendingManager.revokeVaultRole(address(this));
        lendingManager.grantVaultRole(address(vault));
        vm.stopPrank();

        epochManager = new EpochManager(ONE_DAY, AUTOMATION, OWNER);
        vm.prank(ADMIN);
        vault.setEpochManager(address(epochManager));

        DebtSubsidizer debtImpl = new DebtSubsidizer();
        bytes memory initData = abi.encodeWithSelector(DebtSubsidizer.initialize.selector, OWNER, SUBSIDY_SIGNER);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(debtImpl), OWNER, initData);
        debtSubsidizer = DebtSubsidizer(address(proxy));

        vm.prank(OWNER);
        debtSubsidizer.addVault(address(vault), address(lendingManager));
        vm.prank(ADMIN);
        vault.setDebtSubsidizer(address(debtSubsidizer));

        // Grant DEBT_SUBSIDIZER_ROLE to ADMIN for direct testing of repayBorrowBehalfBatch edge cases
        vm.prank(ADMIN); // ADMIN is DEFAULT_ADMIN_ROLE holder
        vault.grantRole(vault.DEBT_SUBSIDIZER_ROLE(), ADMIN);

        // Configure Collection 1 in DebtSubsidizer & Vault
        vm.prank(OWNER);
        debtSubsidizer.whitelistCollection(
            address(vault),
            address(nft1),
            IDebtSubsidizer.CollectionType.ERC721,
            IDebtSubsidizer.RewardBasis.DEPOSIT,
            DEFAULT_YIELD_SHARE_BPS
        );
        vm.prank(ADMIN);
        vault.setCollectionYieldSharePercentage(address(nft1), DEFAULT_YIELD_SHARE_BPS);

        // Configure Collection 2 in DebtSubsidizer & Vault (for transfer scenarios if needed, or can use same collection)
        vm.prank(OWNER);
        debtSubsidizer.whitelistCollection(
            address(vault),
            address(nft2), // Using a different NFT collection for clarity in some tests
            IDebtSubsidizer.CollectionType.ERC721,
            IDebtSubsidizer.RewardBasis.DEPOSIT,
            DEFAULT_YIELD_SHARE_BPS
        );
        vm.prank(ADMIN);
        vault.setCollectionYieldSharePercentage(address(nft2), DEFAULT_YIELD_SHARE_BPS);

        // Initial asset mint for users
        asset.mint(USER_A, 1_000_000 * (10 ** asset.decimals()));
        asset.mint(USER_B, 1_000_000 * (10 ** asset.decimals()));
    }

    function _simulateYield(uint256 yieldAmount) internal {
        asset.mint(address(cToken), yieldAmount);
        uint256 currentUnderlying = cToken.getCash();
        uint256 currentTotalSupply = cToken.totalSupply();
        if (currentTotalSupply == 0) return;
        uint256 scaleFactor = 10 ** (18 + cToken.decimals() - asset.decimals());
        uint256 newCalculatedRate = (currentUnderlying * scaleFactor) / currentTotalSupply;
        cToken.setExchangeRate(newCalculatedRate);
    }

    /**
     * @notice Test: User transfers shares from CollectionsVault before attempting a withdrawal.
     * Assert correct behavior regarding totalAssetsDeposited for the collection and withdrawal amounts.
     */
    function testShareTransferBeforeWithdrawal() public {
        uint256 depositAmountA = 100_000 * (10 ** asset.decimals()); // User A deposits 100k

        // USER_A deposits into collection nft1
        vm.startPrank(USER_A);
        asset.approve(address(vault), depositAmountA);
        uint256 sharesA = vault.depositForCollection(depositAmountA, USER_A, address(nft1));
        vm.stopPrank();

        assertEq(vault.balanceOf(USER_A), sharesA, "USER_A initial shares incorrect");
        assertEq(
            vault.collectionTotalAssetsDeposited(address(nft1)),
            depositAmountA,
            "nft1 total assets incorrect after A's deposit"
        );
        (
            address _collectionAddress,
            uint256 _totalAssetsDeposited,
            uint256 collection1SharesMintedInitial,
            uint256 _totalCTokensMinted,
            uint16 _yieldSharePercentage,
            uint256 _totalYieldTransferred,
            uint256 _lastGlobalDepositIndex
        ) = vault.collections(address(nft1));
        assertEq(collection1SharesMintedInitial, sharesA, "nft1 total shares minted incorrect after A's deposit");

        // USER_A transfers half of their shares to USER_B
        uint256 sharesToTransfer = sharesA / 2;
        vm.startPrank(USER_A);
        vault.transfer(USER_B, sharesToTransfer);
        vm.stopPrank();

        assertEq(vault.balanceOf(USER_A), sharesA - sharesToTransfer, "USER_A shares incorrect after transfer");
        assertEq(vault.balanceOf(USER_B), sharesToTransfer, "USER_B shares incorrect after transfer");

        // IMPORTANT: totalAssetsDeposited for collection nft1 should NOT change due to a share transfer.
        // It tracks the underlying assets attributed to the collection, not who holds the shares.
        assertEq(
            vault.collectionTotalAssetsDeposited(address(nft1)),
            depositAmountA,
            "nft1 total assets changed after share transfer (should not)"
        );
        // totalSharesMinted for the collection should also NOT change due to a simple transfer between users.
        // It tracks shares minted *for* this collection's deposits.
        (
            address _collectionAddressAfterTransfer,
            uint256 _totalAssetsDepositedAfterTransfer,
            uint256 totalSharesMintedAfterTransfer,
            uint256 _totalCTokensMintedAfterTransfer,
            uint16 _yieldSharePercentageAfterTransfer,
            uint256 _totalYieldTransferredAfterTransfer,
            uint256 _lastGlobalDepositIndexAfterTransfer
        ) = vault.collections(address(nft1));
        assertEq(
            totalSharesMintedAfterTransfer,
            collection1SharesMintedInitial,
            "nft1 total shares minted changed after share transfer (should not)"
        );

        // Simulate some yield to make withdrawal values more interesting (optional, but good)
        uint256 yieldGenerated = 10_000 * (10 ** asset.decimals());
        _simulateYield(yieldGenerated);
        vm.prank(ADMIN);
        vault.indexCollectionsDeposits(); // Accrue passive yield
        vm.stopPrank();

        uint256 assetsInNft1AfterYield = vault.collectionTotalAssetsDeposited(address(nft1));
        assertTrue(assetsInNft1AfterYield > depositAmountA, "nft1 assets should have increased with yield");

        // USER_A attempts to withdraw their remaining shares from collection nft1
        // They own (sharesA - sharesToTransfer) shares.
        // The assets they get should be proportional to their share ownership of the vault's total assets.
        // The collectionAddress parameter in withdrawForCollection is for accounting the decrease in that collection's totalAssetsDeposited.
        uint256 sharesUserAHas = vault.balanceOf(USER_A);
        uint256 expectedAssetsForUserA = vault.previewRedeem(sharesUserAHas);

        vm.startPrank(USER_A);
        vm.expectEmit(true, true, true, true, address(vault));
        // Event: CollectionWithdraw(collectionAddress, msg.sender, receiver, assets, shares, cTokenAmount)
        // The `assets` in CollectionWithdraw should be `expectedAssetsForUserA`
        // The `shares` in CollectionWithdraw should be `sharesUserAHas`
        emit ICollectionsVault.CollectionWithdraw(
            address(nft1), USER_A, USER_A, expectedAssetsForUserA, sharesUserAHas, sharesUserAHas
        ); // cTokenAmount placeholder
        uint256 assetsWithdrawnA = vault.withdrawForCollection(expectedAssetsForUserA, USER_A, USER_A, address(nft1));
        vm.stopPrank();

        assertEq(assetsWithdrawnA, expectedAssetsForUserA, "Assets withdrawn by USER_A mismatch");
        assertEq(vault.balanceOf(USER_A), 0, "USER_A should have 0 shares after full withdrawal of their shares");

        // Check collection nft1's totalAssetsDeposited and totalSharesMinted
        // totalAssetsDeposited should decrease by assetsWithdrawnA
        // totalSharesMinted should decrease by sharesUserAHas
        assertEq(
            vault.collectionTotalAssetsDeposited(address(nft1)),
            assetsInNft1AfterYield - assetsWithdrawnA,
            "nft1 total assets incorrect after A's withdrawal"
        );
        (
            address _collectionAddressAfterAWithdraw,
            uint256 _totalAssetsDepositedAfterAWithdraw,
            uint256 totalSharesMintedAfterAWithdraw,
            uint256 _totalCTokensMintedAfterAWithdraw,
            uint16 _yieldSharePercentageAfterAWithdraw,
            uint256 _totalYieldTransferredAfterAWithdraw,
            uint256 _lastGlobalDepositIndexAfterAWithdraw
        ) = vault.collections(address(nft1));
        assertEq(
            totalSharesMintedAfterAWithdraw,
            collection1SharesMintedInitial - sharesUserAHas,
            "nft1 total shares minted incorrect after A's withdrawal"
        );

        // USER_B attempts to withdraw their received shares, also attributed to collection nft1 for accounting.
        // (Even though USER_B might not have "deposited" to nft1, the shares originated there)
        uint256 sharesUserBHas = vault.balanceOf(USER_B);
        uint256 expectedAssetsForUserB = vault.previewRedeem(sharesUserBHas);
        uint256 assetsInNft1BeforeBWithdraw = vault.collectionTotalAssetsDeposited(address(nft1));

        vm.startPrank(USER_B);
        vm.expectEmit(true, true, true, true, address(vault));
        emit ICollectionsVault.CollectionWithdraw(
            address(nft1), USER_B, USER_B, expectedAssetsForUserB, sharesUserBHas, sharesUserBHas
        );
        uint256 assetsWithdrawnB = vault.withdrawForCollection(expectedAssetsForUserB, USER_B, USER_B, address(nft1));
        vm.stopPrank();

        assertEq(assetsWithdrawnB, expectedAssetsForUserB, "Assets withdrawn by USER_B mismatch");
        assertEq(vault.balanceOf(USER_B), 0, "USER_B should have 0 shares after withdrawal");

        assertEq(
            vault.collectionTotalAssetsDeposited(address(nft1)),
            assetsInNft1BeforeBWithdraw - assetsWithdrawnB,
            "nft1 total assets incorrect after B's withdrawal"
        );
        (
            address _collectionAddressAfterBWithdraw,
            uint256 _totalAssetsDepositedAfterBWithdraw,
            uint256 totalSharesMintedAfterBWithdraw,
            uint256 _totalCTokensMintedAfterBWithdraw,
            uint16 _yieldSharePercentageAfterBWithdraw,
            uint256 _totalYieldTransferredAfterBWithdraw,
            uint256 _lastGlobalDepositIndexAfterBWithdraw
        ) = vault.collections(address(nft1));
        assertEq(
            totalSharesMintedAfterBWithdraw,
            collection1SharesMintedInitial - sharesUserAHas - sharesUserBHas,
            "nft1 total shares minted incorrect after B's withdrawal"
        );

        // After both withdrawals, if all original shares from depositA were redeemed,
        // totalSharesMinted for nft1 should be 0.
        (
            address _collectionAddressFinal,
            uint256 _totalAssetsDepositedFinal,
            uint256 totalSharesMintedFinal,
            uint256 _totalCTokensMintedFinal,
            uint16 _yieldSharePercentageFinal,
            uint256 _totalYieldTransferredFinal,
            uint256 _lastGlobalDepositIndexFinal
        ) = vault.collections(address(nft1));
        assertEq(totalSharesMintedFinal, 0, "nft1 total shares should be zero if all original shares redeemed");
    }

    // Test for EpochManager: markEpochFailed
    function testEpochMarkedAsFailed() public {
        // 1. Start a new epoch
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        uint256 epochId = epochManager.currentEpochId();
        vm.stopPrank();

        (,,,, uint256 _totalSubsidiesDistributed, EpochManager.EpochStatus statusBeforeFail) =
            epochManager.getEpochDetails(epochId);
        assertEq(uint8(statusBeforeFail), uint8(EpochManager.EpochStatus.Active), "Epoch should be Active");

        // 2. Mark the epoch as FAILED
        string memory reason = "Test failure reason";
        vm.prank(AUTOMATION); // or OWNER
        vm.expectEmit(true, true, true, false, address(epochManager)); // Not checking reason string for now
        emit EpochManager.EpochFailed(epochId, reason);
        epochManager.markEpochFailed(epochId, reason);
        vm.stopPrank();

        // 3. Assert epoch state
        (,,,,, EpochManager.EpochStatus statusAfterFail) = epochManager.getEpochDetails(epochId);
        assertEq(uint8(statusAfterFail), uint8(EpochManager.EpochStatus.Failed), "Epoch status should be Failed");

        // Assert any follow-on behavior (e.g., yield reallocation if logic exists)
        // For now, the primary assertion is the FAILED status.
        // If EpochManager.sol had logic to, for example, prevent starting a new epoch if current is Failed (and not Completed),
        // that could be tested here. Current EpochManager allows starting new if previous is Completed.
        // A failed epoch cannot be processed further (e.g. beginEpochProcessing or finalizeEpoch should fail).
        vm.warp(block.timestamp + ONE_DAY + 1); // Advance time past epoch end
        vm.prank(AUTOMATION);
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__InvalidEpochStatus.selector,
                epochId,
                EpochManager.EpochStatus.Failed,
                EpochManager.EpochStatus.Active
            )
        );
        epochManager.beginEpochProcessing(epochId);

        // Try to finalize, should also fail
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__InvalidEpochStatus.selector,
                epochId,
                EpochManager.EpochStatus.Failed,
                EpochManager.EpochStatus.Processing
            )
        );
        epochManager.finalizeEpoch(epochId, 0);
        vm.stopPrank();

        // Check if a new epoch can be started (it should not, as current is Failed, not Completed)
        vm.prank(AUTOMATION);
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__InvalidEpochStatus.selector,
                epochId,
                EpochManager.EpochStatus.Failed,
                EpochManager.EpochStatus.Completed
            )
        );
        epochManager.startNewEpoch();
        vm.stopPrank();
    }

    // Test for DebtSubsidizer: weight-function update mid-epoch
    function testDebtSubsidizerWeightFunctionUpdateMidEpoch() public {
        // Setup: User A has deposited into nft1. An epoch is active.
        uint256 depositAmountA = 50_000 * (10 ** asset.decimals());
        vm.startPrank(USER_A);
        asset.approve(address(vault), depositAmountA);
        vault.depositForCollection(depositAmountA, USER_A, address(nft1));
        vm.stopPrank();

        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        uint256 epochId = epochManager.currentEpochId();
        vm.stopPrank();

        // Simulate some yield and allocate to epoch, then apply to collection
        uint256 yieldGen = 2_000 * (10 ** asset.decimals());
        _simulateYield(yieldGen);
        vm.prank(ADMIN);
        vault.indexCollectionsDeposits();
        uint256 yieldToAllocate = yieldGen / 2;
        vault.allocateEpochYield(yieldToAllocate);
        vm.warp(block.timestamp + ONE_DAY + 1); // End epoch
        vm.prank(AUTOMATION);
        epochManager.beginEpochProcessing(epochId);
        vm.stopPrank();
        vm.prank(ADMIN);
        vault.applyCollectionEpochYield(address(nft1), epochId);
        vm.stopPrank();

        // Initial weight function (default is LINEAR, 0, 0)
        IDebtSubsidizer.WeightFunction memory initialWeightFn =
            debtSubsidizer.getCollectionWeightFunction(address(vault), address(nft1));
        assertEq(uint8(initialWeightFn.fnType), uint8(IDebtSubsidizer.WeightFunctionType.LINEAR));

        // Prepare subsidy data for USER_A
        uint256 subsidyAmount = 100 * (10 ** asset.decimals()); // Example amount
        IDebtSubsidizer.Subsidy[] memory subsidies1 = new IDebtSubsidizer.Subsidy[](1);
        uint64 nonce1 = debtSubsidizer.userNonce(address(vault), USER_A);
        subsidies1[0] = IDebtSubsidizer.Subsidy({
            account: USER_A,
            collection: address(nft1),
            vault: address(vault),
            amount: subsidyAmount, // This amount is pre-calculated by off-chain logic considering weight function
            nonce: nonce1,
            deadline: block.timestamp + 1 hours
        });
        bytes32 digest1 = keccak256(
            abi.encodePacked("\x19\x01", debtSubsidizer.getDomainSeparator(), keccak256(abi.encode(subsidies1)))
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(SUBSIDY_SIGNER_PK, digest1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        // Call subsidize() with initial weight function (implicitly used by off-chain logic to determine `amount`)
        uint256 userASecondsClaimedBefore1 = debtSubsidizer.userSecondsClaimed(USER_A);
        debtSubsidizer.subsidize(address(vault), subsidies1, signature1);
        uint256 userASecondsClaimedAfter1 = debtSubsidizer.userSecondsClaimed(USER_A);
        assertTrue(
            userASecondsClaimedAfter1 > userASecondsClaimedBefore1, "Claimed seconds should increase after 1st subsidy"
        );
        assertEq(
            userASecondsClaimedAfter1,
            userASecondsClaimedBefore1 + subsidyAmount,
            "Claimed seconds mismatch after 1st subsidy"
        );

        // Update weight function mid-epoch (epoch is 'Processing')
        IDebtSubsidizer.WeightFunction memory newWeightFn = IDebtSubsidizer.WeightFunction({
            fnType: IDebtSubsidizer.WeightFunctionType.EXPONENTIAL,
            p1: 1, // Example parameters
            p2: 2
        });
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(debtSubsidizer));
        emit DebtSubsidizer.WeightFunctionConfigUpdated(address(vault), address(nft1), initialWeightFn, newWeightFn);
        debtSubsidizer.setWeightFunction(address(vault), address(nft1), newWeightFn);
        vm.stopPrank();

        IDebtSubsidizer.WeightFunction memory currentWeightFn =
            debtSubsidizer.getCollectionWeightFunction(address(vault), address(nft1));
        assertEq(uint8(currentWeightFn.fnType), uint8(IDebtSubsidizer.WeightFunctionType.EXPONENTIAL));
        assertEq(currentWeightFn.p1, newWeightFn.p1);
        assertEq(currentWeightFn.p2, newWeightFn.p2);

        // Prepare another subsidy for USER_A. The `amount` would now be calculated off-chain using the *new* weight function.
        // For the test, we'll use a different amount to signify the change, though the contract itself doesn't use the weight function directly in `subsidize`.
        // The weight function's role is for the off-chain service to determine the `amount` in the signature.
        uint256 subsidyAmount2 = 150 * (10 ** asset.decimals()); // Different amount, implying new calculation
        IDebtSubsidizer.Subsidy[] memory subsidies2 = new IDebtSubsidizer.Subsidy[](1);
        uint64 nonce2 = debtSubsidizer.userNonce(address(vault), USER_A); // Nonce would have incremented
        subsidies2[0] = IDebtSubsidizer.Subsidy({
            account: USER_A,
            collection: address(nft1),
            vault: address(vault),
            amount: subsidyAmount2,
            nonce: nonce2,
            deadline: block.timestamp + 1 hours
        });
        bytes32 digest2 = keccak256(
            abi.encodePacked("\x19\x01", debtSubsidizer.getDomainSeparator(), keccak256(abi.encode(subsidies2)))
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(SUBSIDY_SIGNER_PK, digest2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        // Call subsidize() again. The behavior of subsidize() itself doesn't change based on the weight function directly,
        // but the input `amount` (which is signed) would be different if the off-chain logic used the new weight function.
        uint256 userASecondsClaimedBefore2 = debtSubsidizer.userSecondsClaimed(USER_A);
        debtSubsidizer.subsidize(address(vault), subsidies2, signature2);
        uint256 userASecondsClaimedAfter2 = debtSubsidizer.userSecondsClaimed(USER_A);

        assertTrue(
            userASecondsClaimedAfter2 > userASecondsClaimedBefore2, "Claimed seconds should increase after 2nd subsidy"
        );
        assertEq(
            userASecondsClaimedAfter2,
            userASecondsClaimedBefore2 + subsidyAmount2,
            "Claimed seconds mismatch after 2nd subsidy"
        );

        // The key assertion is that `subsidize` processes the new `amount` correctly,
        // and the configuration change event was emitted. The actual impact of the weight function
        // is on the off-chain generation of the subsidy `amount`.
    }

    // --- Edge cases for CollectionsVault.repayBorrowBehalfBatch ---

    function testRepayBorrowBehalfBatch_EmptyArrays_NonZeroTotalAmount() public {
        uint256 totalAmountToWithdraw = 100 * (10 ** asset.decimals());

        // Ensure vault has funds by depositing from USER_A to nft1
        vm.startPrank(USER_A);
        asset.approve(address(vault), totalAmountToWithdraw * 2); // Approve more
        vault.depositForCollection(totalAmountToWithdraw * 2, USER_A, address(nft1)); // Deposit more to ensure LM has enough
        vm.stopPrank();

        uint256 vaultAssetBalanceBefore = asset.balanceOf(address(vault));
        uint256 cTokenAssetBalanceBefore = asset.balanceOf(address(cToken));

        address[] memory emptyCollections = new address[](0);
        uint256[] memory emptyAmounts = new uint256[](0);
        address[] memory emptyBorrowers = new address[](0);

        vm.startPrank(ADMIN);
        // In CollectionsVault, _hookWithdraw(totalAmountToWithdraw) is called.
        // Then, since loops over borrowers are skipped, no actual repayment to LM happens for borrowers.
        // The withdrawn assets remain in the CollectionsVault contract.
        // The YieldBatchRepaid event will emit with actualTotalRepaid = 0.
        vm.expectEmit(true, true, false, true, address(vault));
        emit ICollectionsVault.YieldBatchRepaid(0, ADMIN); // actualTotalRepaid is 0

        vault.repayBorrowBehalfBatch(emptyCollections, emptyAmounts, emptyBorrowers, totalAmountToWithdraw);
        vm.stopPrank();

        uint256 vaultAssetBalanceAfter = asset.balanceOf(address(vault));
        uint256 cTokenAssetBalanceAfter = asset.balanceOf(address(cToken));

        assertEq(
            cTokenAssetBalanceAfter,
            cTokenAssetBalanceBefore - totalAmountToWithdraw,
            "cToken balance should decrease by totalAmountToWithdraw"
        );
        assertEq(
            vaultAssetBalanceAfter,
            vaultAssetBalanceBefore + totalAmountToWithdraw,
            "Vault balance should increase by totalAmountToWithdraw"
        );
    }

    function testRepayBorrowBehalfBatch_OneAmountIsZero() public {
        uint256 amountForUserA = 50 * (10 ** asset.decimals());
        uint256 amountForUserB = 0; // Zero amount
        address USER_C = vm.addr(uint256(keccak256("USER_C"))); // New user for this test
        asset.mint(USER_C, 10 * (10 ** asset.decimals()));

        uint256 amountForUserC = 30 * (10 ** asset.decimals());
        uint256 totalAmountForRepayment = amountForUserA + amountForUserC; // Sum of non-zero amounts
        uint256 totalAmountToWithdrawFromLM = totalAmountForRepayment; // This is what vault will try to withdraw and use

        // Ensure vault has funds
        vm.startPrank(USER_A);
        asset.approve(address(vault), totalAmountToWithdrawFromLM * 2);
        vault.depositForCollection(totalAmountToWithdrawFromLM * 2, USER_A, address(nft1));
        vm.stopPrank();

        address[] memory collections = new address[](3);
        collections[0] = address(nft1);
        collections[1] = address(nft1); // Collection for zero amount, won't be updated
        collections[2] = address(nft2);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountForUserA;
        amounts[1] = amountForUserB; // Zero
        amounts[2] = amountForUserC;

        address[] memory borrowers = new address[](3);
        borrowers[0] = USER_A;
        borrowers[1] = USER_B;
        borrowers[2] = USER_C;

        vm.startPrank(ADMIN);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ICollectionsVault.YieldBatchRepaid(totalAmountForRepayment, ADMIN);

        vault.repayBorrowBehalfBatch(collections, amounts, borrowers, totalAmountToWithdrawFromLM);
        vm.stopPrank();

        (,,,,, uint256 nft1TotalYieldTransferred,) = vault.collections(address(nft1));
        (,,,,, uint256 nft2TotalYieldTransferred,) = vault.collections(address(nft2));
        assertEq(nft1TotalYieldTransferred, amountForUserA, "nft1 yield transferred incorrect");
        assertEq(nft2TotalYieldTransferred, amountForUserC, "nft2 yield transferred incorrect");
        // For the collection associated with the zero amount, totalYieldTransferred should not change for that entry.
    }

    function testRepayBorrowBehalfBatch_TotalAmountLessThanSumOfIndividualRepayments() public {
        uint256 amount1 = 50 * (10 ** asset.decimals());
        uint256 amount2 = 60 * (10 ** asset.decimals());
        uint256 sumIndividualRepayments = amount1 + amount2; // 110
        uint256 totalAmountToWithdrawFromLM = 40 * (10 ** asset.decimals()); // Less than sum, and less than amount1

        // Ensure vault has funds
        vm.startPrank(USER_A);
        asset.approve(address(vault), sumIndividualRepayments * 2);
        vault.depositForCollection(sumIndividualRepayments * 2, USER_A, address(nft1));
        vm.stopPrank();

        address[] memory collections = new address[](2);
        collections[0] = address(nft1);
        collections[1] = address(nft1);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1; // 50
        amounts[1] = amount2; // 60
        address[] memory borrowers = new address[](2);
        borrowers[0] = USER_A;
        borrowers[1] = USER_B;

        vm.startPrank(ADMIN);
        // Vault withdraws `totalAmountToWithdrawFromLM` (40) from LM.
        // Vault approves LM for `totalAmountToWithdrawFromLM` (40).
        // LM.repayBorrowBehalf(USER_A, amount1=50) is called.
        // LM tries `asset.safeTransferFrom(address(vault), address(this), amount1=50)`.
        // This will fail because allowance (40) < amount1 (50).
        vm.expectRevert(); // Expecting ERC20: insufficient allowance, or similar
        vault.repayBorrowBehalfBatch(collections, amounts, borrowers, totalAmountToWithdrawFromLM);
        vm.stopPrank();
    }

    function testRepayBorrowBehalfBatch_TotalAmountGreaterThanSumOfIndividualRepayments() public {
        uint256 amount1 = 20 * (10 ** asset.decimals());
        uint256 amount2 = 30 * (10 ** asset.decimals());
        uint256 sumIndividualRepayments = amount1 + amount2; // 50
        uint256 totalAmountToWithdrawFromLM = 100 * (10 ** asset.decimals()); // Greater than sum

        // Ensure vault has funds
        vm.startPrank(USER_A);
        asset.approve(address(vault), totalAmountToWithdrawFromLM * 2);
        vault.depositForCollection(totalAmountToWithdrawFromLM * 2, USER_A, address(nft1));
        vm.stopPrank();

        uint256 vaultAssetBalanceBeforeOp = asset.balanceOf(address(vault)); // Vault has 0 from its perspective before op
        uint256 cTokenAssetBalanceBeforeOp = asset.balanceOf(address(cToken));

        address[] memory collections = new address[](2);
        collections[0] = address(nft1);
        collections[1] = address(nft2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        address[] memory borrowers = new address[](2);
        borrowers[0] = USER_A;
        borrowers[1] = USER_B;

        vm.startPrank(ADMIN);
        // Vault withdraws `totalAmountToWithdrawFromLM` (100) from LM. Vault balance becomes 100.
        // Allowance for LM is set to 100.
        // Repayments for amount1 (20) and amount2 (30) occur. Total actual repayment = 50.
        // Vault's YieldBatchRepaid event will show `actualTotalRepaid` as 50.
        // (totalAmountToWithdrawFromLM - sumIndividualRepayments) = 50 will remain in the vault contract.
        vm.expectEmit(true, true, false, true, address(vault));
        emit ICollectionsVault.YieldBatchRepaid(sumIndividualRepayments, ADMIN);

        vault.repayBorrowBehalfBatch(collections, amounts, borrowers, totalAmountToWithdrawFromLM);
        vm.stopPrank();

        uint256 vaultAssetBalanceAfterOp = asset.balanceOf(address(vault));
        uint256 cTokenAssetBalanceAfterOp = asset.balanceOf(address(cToken));

        assertEq(
            cTokenAssetBalanceAfterOp,
            cTokenAssetBalanceBeforeOp - totalAmountToWithdrawFromLM,
            "cToken balance change incorrect"
        );
        // Vault balance: starts at 0 (from its own view), gets totalAmountToWithdrawFromLM, then sumIndividualRepayments are sent to LM.
        // So, final balance = initial_vault_holdings + totalAmountToWithdrawFromLM - sumIndividualRepayments.
        // Since initial_vault_holdings (from its perspective for this op) is 0.
        assertEq(
            vaultAssetBalanceAfterOp,
            vaultAssetBalanceBeforeOp + (totalAmountToWithdrawFromLM - sumIndividualRepayments),
            "Vault final balance incorrect"
        );

        (,,,,, uint256 nft1TotalYieldTransferredFinal,) = vault.collections(address(nft1));
        (,,,,, uint256 nft2TotalYieldTransferredFinal,) = vault.collections(address(nft2));
        assertEq(nft1TotalYieldTransferredFinal, amount1, "nft1 yield transferred incorrect");
        assertEq(nft2TotalYieldTransferredFinal, amount2, "nft2 yield transferred incorrect");
    }

    // --- Edge cases for EpochManager ---

    function testEpochManager_AllocateYield_NoActiveEpoch() public {
        EpochManager localEpochManager = new EpochManager(ONE_DAY, AUTOMATION, OWNER);
        // currentEpochId is 0, or last epoch is not Active.

        vm.prank(address(vault)); // Caller is typically the vault
        vm.expectRevert(abi.encodeWithSelector(EpochManager.EpochManager__InvalidEpochId.selector, uint256(0)));
        localEpochManager.allocateVaultYield(address(vault), 100 ether);
    }

    function testEpochManager_BeginProcessing_EpochNotEnded() public {
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        uint256 epochId = epochManager.currentEpochId();
        vm.stopPrank();

        (,, uint256 endTime,,,) = epochManager.getEpochDetails(epochId);
        assertTrue(block.timestamp < endTime, "Timestamp should be before epoch end for this test");

        vm.prank(AUTOMATION);
        vm.expectRevert(abi.encodeWithSelector(EpochManager.EpochManager__EpochNotEnded.selector, epochId, endTime));
        epochManager.beginEpochProcessing(epochId);
        vm.stopPrank();
    }

    function testEpochManager_FinalizeEpoch_NotProcessing() public {
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        uint256 epochId = epochManager.currentEpochId(); // Epoch is 'Active'
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__InvalidEpochStatus.selector,
                epochId,
                EpochManager.EpochStatus.Active,
                EpochManager.EpochStatus.Processing
            )
        );
        epochManager.finalizeEpoch(epochId, 100 ether);
        vm.stopPrank();
    }

    // --- Edge cases for DebtSubsidizer ---

    function testDebtSubsidizer_Subsidize_ExpiredDeadline() public {
        // Ensure some funds in vault for repayBorrowBehalfBatch to not revert due to lack of funds in LM
        vm.startPrank(USER_A);
        asset.approve(address(vault), 1000 * 10 ** asset.decimals());
        vault.depositForCollection(1000 * 10 ** asset.decimals(), USER_A, address(nft1));
        vm.stopPrank();

        IDebtSubsidizer.Subsidy[] memory subsidies = new IDebtSubsidizer.Subsidy[](1);
        uint64 nonce = debtSubsidizer.userNonce(address(vault), USER_A);
        subsidies[0] = IDebtSubsidizer.Subsidy({
            account: USER_A,
            collection: address(nft1),
            vault: address(vault),
            amount: 10 * (10 ** asset.decimals()),
            nonce: nonce,
            deadline: block.timestamp - 1 // Expired
        });

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", debtSubsidizer.getDomainSeparator(), keccak256(abi.encode(subsidies)))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SUBSIDY_SIGNER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IDebtSubsidizer.ClaimExpired.selector);
        debtSubsidizer.subsidize(address(vault), subsidies, signature);
    }

    function testDebtSubsidizer_Subsidize_InvalidNonce() public {
        // Ensure some funds in vault
        vm.startPrank(USER_A);
        asset.approve(address(vault), 1000 * 10 ** asset.decimals());
        vault.depositForCollection(1000 * 10 ** asset.decimals(), USER_A, address(nft1));
        vm.stopPrank();

        IDebtSubsidizer.Subsidy[] memory subsidies = new IDebtSubsidizer.Subsidy[](1);
        uint64 actualNonce = debtSubsidizer.userNonce(address(vault), USER_A);
        subsidies[0] = IDebtSubsidizer.Subsidy({
            account: USER_A,
            collection: address(nft1),
            vault: address(vault),
            amount: 10 * (10 ** asset.decimals()),
            nonce: actualNonce + 1, // Invalid nonce
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", debtSubsidizer.getDomainSeparator(), keccak256(abi.encode(subsidies)))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SUBSIDY_SIGNER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IDebtSubsidizer.InvalidNonce.selector);
        debtSubsidizer.subsidize(address(vault), subsidies, signature);
    }

    function testDebtSubsidizer_Subsidize_UnauthorizedSigner() public {
        // Ensure some funds in vault
        vm.startPrank(USER_A);
        asset.approve(address(vault), 1000 * 10 ** asset.decimals());
        vault.depositForCollection(1000 * 10 ** asset.decimals(), USER_A, address(nft1));
        vm.stopPrank();

        IDebtSubsidizer.Subsidy[] memory subsidies = new IDebtSubsidizer.Subsidy[](1);
        uint64 nonce = debtSubsidizer.userNonce(address(vault), USER_A);
        subsidies[0] = IDebtSubsidizer.Subsidy({
            account: USER_A,
            collection: address(nft1),
            vault: address(vault),
            amount: 10 * (10 ** asset.decimals()),
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", debtSubsidizer.getDomainSeparator(), keccak256(abi.encode(subsidies)))
        );

        uint256 unauthorizedSignerPk = uint256(keccak256("UNAUTHORIZED_SIGNER"));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unauthorizedSignerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IDebtSubsidizer.InvalidSignature.selector);
        debtSubsidizer.subsidize(address(vault), subsidies, signature);
    }

    // --- More Edge Cases for CollectionsVault ---

    function testSetCollectionYieldSharePercentage_ExceedsMaxTotal() public {
        // Whitelist nft1 and nft2 in DebtSubsidizer first, as CollectionsVault might implicitly rely on this setup
        // (Though setCollectionYieldSharePercentage itself doesn't check DebtSubsidizer's whitelist)

        // Set initial percentages
        vm.prank(ADMIN);
        vault.setCollectionYieldSharePercentage(address(nft1), 6000); // 60%
        assertEq(vault.totalCollectionYieldShareBps(), 6000, "Total BPS incorrect after nft1 set");

        // Try to set percentage for nft2 that exceeds the remaining 40%
        vm.expectRevert(IDebtSubsidizer.InvalidYieldSharePercentage.selector);
        vault.setCollectionYieldSharePercentage(address(nft2), 5000); // 50%, total would be 110%
        vm.stopPrank();

        // Verify total BPS did not change
        assertEq(vault.totalCollectionYieldShareBps(), 6000, "Total BPS should not change after revert");

        // Try to update nft1's percentage to something that makes total exceed 100%
        // First, set nft2 to a valid value, e.g., 20% (total 80%)
        vm.prank(ADMIN);
        vault.setCollectionYieldSharePercentage(address(nft2), 2000); // 20%
        assertEq(vault.totalCollectionYieldShareBps(), 8000, "Total BPS incorrect after nft2 set");

        // Now try to update nft1 from 60% to 30% (total would be 20% + 30% = 50%, valid)
        vault.setCollectionYieldSharePercentage(address(nft1), 3000); // 30%
        assertEq(vault.totalCollectionYieldShareBps(), 5000, "Total BPS incorrect after nft1 update");

        // Now try to update nft1 to 90% (total would be 20% + 90% = 110%, invalid)
        vm.expectRevert(IDebtSubsidizer.InvalidYieldSharePercentage.selector);
        vault.setCollectionYieldSharePercentage(address(nft1), 9000); // 90%
        vm.stopPrank();
        assertEq(vault.totalCollectionYieldShareBps(), 5000, "Total BPS should not change after revert on update");
    }

    function testAllocateEpochYield_LossScenario() public {
        // Simulate a loss: LM totalAssets < totalPrincipalDeposited
        // 1. Deposit into vault, which deposits into LM
        uint256 depositAmount = 100_000 * (10 ** asset.decimals());
        vm.startPrank(USER_A);
        asset.approve(address(vault), depositAmount);
        vault.depositForCollection(depositAmount, USER_A, address(nft1));
        vm.stopPrank();

        // To correctly simulate a loss visible to CollectionsVault's allocateEpochYield,
        // we need LM.totalAssets() < LM.totalPrincipalDeposited().
        // LM.totalAssets() is cToken.balanceOfUnderlying(address(lendingManager)).
        // LM.totalPrincipalDeposited() is the sum of underlying deposited.
        // SimpleMockCToken.balanceOfUnderlying = (balanceOf[account] * exchangeRateStored) / 1e18
        // Let's make exchangeRateStored very small.
        uint256 currentLMcTokens = cToken.balanceOf(address(lendingManager));
        assertTrue(currentLMcTokens > 0, "LM should have cTokens");

        // Set exchange rate such that value of cTokens is less than principal
        // If LM has `P` principal, it has `P / initial_true_rate` cTokens.
        // `initial_true_rate = INITIAL_EXCHANGE_RATE / scaleFactor`
        // `scaleFactor = 10**(18 + cToken.decimals() - asset.decimals())`
        // We want `cTokens_in_LM * new_true_rate < P`
        // `(P / initial_true_rate) * new_true_rate < P` => `new_true_rate < initial_true_rate`
        // So, set `new_stored_rate < INITIAL_EXCHANGE_RATE`
        uint256 lossExchangeRate = INITIAL_EXCHANGE_RATE / 2; // Halve the value of cTokens
        cToken.setExchangeRate(lossExchangeRate);

        uint256 lmAssetsAfterLoss = lendingManager.totalAssets();
        uint256 lmPrincipal = lendingManager.totalPrincipalDeposited();
        assertTrue(lmAssetsAfterLoss < lmPrincipal, "LM assets should be less than principal after simulated loss");

        // 3. Start an epoch
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        vm.stopPrank();

        // 4. Try to allocate yield. Available yield should be 0 due to loss.
        // totalLMYield = Math.trySub(lendingManager.totalAssets(), totalPrincipalDeposited()) -> 0
        vm.prank(ADMIN);
        vm.expectRevert(IDebtSubsidizer.InsufficientYield.selector);
        vault.allocateEpochYield(1); // Try to allocate even 1 wei
        vm.stopPrank();

        // Allocating 0 should succeed
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, true, address(vault)); // Check event for 0 allocation
        emit ICollectionsVault.VaultYieldAllocatedToEpoch(epochManager.currentEpochId(), 0);
        vault.allocateEpochYield(0);
        vm.stopPrank();
        assertEq(vault.getEpochYieldAllocated(epochManager.currentEpochId()), 0, "0 yield should be allocated in loss");
    }

    // --- More Edge Cases for DebtSubsidizer ---

    function testWhitelistCollection_AlreadyWhitelisted() public {
        // nft1 is whitelisted in setUp
        assertTrue(
            debtSubsidizer.isCollectionWhitelisted(address(vault), address(nft1)),
            "nft1 should be whitelisted initially"
        );

        vm.prank(OWNER);
        vm.expectRevert(IDebtSubsidizer.CollectionAlreadyWhitelistedInVault.selector);
        debtSubsidizer.whitelistCollection(
            address(vault),
            address(nft1), // Already whitelisted
            IDebtSubsidizer.CollectionType.ERC721,
            IDebtSubsidizer.RewardBasis.DEPOSIT,
            1000
        );
        vm.stopPrank();
    }

    function testRemoveCollection_NotWhitelisted() public {
        MockERC721 nonWhitelistedNft = new MockERC721("Non Whitelisted", "NWL");
        assertFalse(
            debtSubsidizer.isCollectionWhitelisted(address(vault), address(nonWhitelistedNft)),
            "Should not be whitelisted"
        );

        vm.prank(OWNER);
        vm.expectRevert(IDebtSubsidizer.CollectionNotWhitelistedInVault.selector);
        debtSubsidizer.removeCollection(address(vault), address(nonWhitelistedNft));
        vm.stopPrank();
    }

    function testUpdateCollectionPercentageShare_NotWhitelisted() public {
        MockERC721 nonWhitelistedNft = new MockERC721("Non Whitelisted", "NWL");
        assertFalse(
            debtSubsidizer.isCollectionWhitelisted(address(vault), address(nonWhitelistedNft)),
            "Should not be whitelisted"
        );

        vm.prank(OWNER);
        vm.expectRevert(IDebtSubsidizer.CollectionNotWhitelistedInVault.selector);
        debtSubsidizer.updateCollectionPercentageShare(address(vault), address(nonWhitelistedNft), 2000);
        vm.stopPrank();
    }

    function testSetWeightFunction_NotWhitelisted() public {
        MockERC721 nonWhitelistedNft = new MockERC721("Non Whitelisted", "NWL");
        assertFalse(
            debtSubsidizer.isCollectionWhitelisted(address(vault), address(nonWhitelistedNft)),
            "Should not be whitelisted"
        );

        IDebtSubsidizer.WeightFunction memory newWeightFn =
            IDebtSubsidizer.WeightFunction({fnType: IDebtSubsidizer.WeightFunctionType.EXPONENTIAL, p1: 1, p2: 2});

        vm.prank(OWNER);
        vm.expectRevert(IDebtSubsidizer.CollectionNotWhitelistedInVault.selector);
        debtSubsidizer.setWeightFunction(address(vault), address(nonWhitelistedNft), newWeightFn);
        vm.stopPrank();
    }

    // --- Final Batch of Edge Cases ---

    // CollectionsVault: applyCollectionEpochYield with 0% yield share for collection
    function testApplyCollectionEpochYield_ZeroPercentShare() public {
        // Setup: Deposit, yield, start epoch, allocate vault yield to epoch
        uint256 depositAmount = 100_000 * (10 ** asset.decimals());
        vm.startPrank(USER_A);
        asset.approve(address(vault), depositAmount);
        vault.depositForCollection(depositAmount, USER_A, address(nft1));
        vm.stopPrank();

        _simulateYield(10_000 * (10 ** asset.decimals()));
        vm.prank(ADMIN);
        vault.indexCollectionsDeposits(); // Accrue some passive
        vm.stopPrank();

        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        uint256 epochId = epochManager.currentEpochId();
        vm.stopPrank();

        uint256 vaultYieldForEpoch = 5_000 * (10 ** asset.decimals());
        vm.prank(ADMIN);
        vault.allocateEpochYield(vaultYieldForEpoch);
        vm.stopPrank();

        // Set collection nft1's yield share to 0% for epoch yield
        uint16 oldShareBps = vault.collections(address(nft1)).epochYieldSharePercentageBps;
        vm.prank(ADMIN);
        vault.setCollectionYieldSharePercentage(address(nft1), 0); // This sets both passive and epoch share
        vm.stopPrank();
        assertEq(vault.collections(address(nft1)).epochYieldSharePercentageBps, 0, "nft1 epoch share should be 0");
        assertEq(vault.collections(address(nft1)).passiveYieldSharePercentageBps, 0, "nft1 passive share should be 0");

        // Advance time and begin epoch processing
        vm.warp(block.timestamp + ONE_DAY + 1);
        vm.prank(AUTOMATION);
        epochManager.beginEpochProcessing(epochId);
        vm.stopPrank();

        uint256 assetsBeforeApply = vault.collectionTotalAssetsDeposited(address(nft1));

        // Call applyCollectionEpochYield
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true, address(vault));
        // Expected yield for collection is 0
        emit ICollectionsVault.CollectionYieldAppliedForEpoch(epochId, address(nft1), 0, 0, assetsBeforeApply);
        vault.applyCollectionEpochYield(address(nft1), epochId);
        vm.stopPrank();

        // Assert collection's totalAssetsDeposited did not change
        assertEq(
            vault.collectionTotalAssetsDeposited(address(nft1)),
            assetsBeforeApply,
            "Assets should not change for 0% share"
        );

        // Restore old share for other tests if necessary
        vm.prank(ADMIN);
        vault.setCollectionYieldSharePercentage(address(nft1), oldShareBps);
        vm.stopPrank();
    }

    // CollectionsVault: applyCollectionEpochYield when epoch has 0 yield allocated
    function testApplyCollectionEpochYield_ZeroEpochYield() public {
        // Setup: Deposit, start epoch, but allocate 0 vault yield to epoch
        uint256 depositAmount = 100_000 * (10 ** asset.decimals());
        vm.startPrank(USER_A);
        asset.approve(address(vault), depositAmount);
        // nft1 by default has DEFAULT_YIELD_SHARE_BPS (5000) from setUp
        vault.depositForCollection(depositAmount, USER_A, address(nft1));
        vm.stopPrank();

        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();
        uint256 epochId = epochManager.currentEpochId();
        vm.stopPrank();

        vm.prank(ADMIN);
        vault.allocateEpochYield(0); // 0 yield allocated from vault to epoch
        vm.stopPrank();
        assertEq(epochManager.getVaultYieldForEpoch(epochId, address(vault)), 0, "Epoch should have 0 vault yield");
        (,,, uint256 totalEpochYield,,) = epochManager.getEpochDetails(epochId);
        assertEq(totalEpochYield, 0, "EpochManager total yield should be 0");

        // Advance time and begin epoch processing
        vm.warp(block.timestamp + ONE_DAY + 1);
        vm.prank(AUTOMATION);
        epochManager.beginEpochProcessing(epochId);
        vm.stopPrank();

        uint256 assetsBeforeApply = vault.collectionTotalAssetsDeposited(address(nft1));
        (
            address _collectionAddress,
            uint256 _totalAssetsDeposited,
            uint256 _totalSharesMinted,
            uint256 _totalCTokensMinted,
            uint16 collectionShareBps,
            uint256 _totalYieldTransferred,
            uint256 _lastGlobalDepositIndex
        ) = vault.collections(address(nft1));

        // Call applyCollectionEpochYield
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true, address(vault));
        // Expected yield for collection is 0 (collectionShareBps % of 0 is 0)
        emit ICollectionsVault.CollectionYieldAppliedForEpoch(
            epochId, address(nft1), collectionShareBps, 0, assetsBeforeApply
        );
        vault.applyCollectionEpochYield(address(nft1), epochId);
        vm.stopPrank();

        // Assert collection's totalAssetsDeposited did not change
        assertEq(
            vault.collectionTotalAssetsDeposited(address(nft1)),
            assetsBeforeApply,
            "Assets should not change for 0 epoch yield"
        );
    }

    // EpochManager: startNewEpoch when current epoch is Active
    function testStartNewEpoch_CurrentActive() public {
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch(); // Epoch 1 is Active
        uint256 epoch1Id = epochManager.currentEpochId();
        (,,,,, EpochManager.EpochStatus status1) = epochManager.getEpochDetails(epoch1Id);
        assertEq(uint8(status1), uint8(EpochManager.EpochStatus.Active), "Epoch 1 should be Active");

        // Try to start another epoch while Epoch 1 is still Active
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__InvalidEpochStatus.selector,
                epoch1Id,
                EpochManager.EpochStatus.Active,
                EpochManager.EpochStatus.Completed
            )
        );
        epochManager.startNewEpoch();
        vm.stopPrank();
    }

    // EpochManager: startNewEpoch when current epoch is Processing
    function testStartNewEpoch_CurrentProcessing() public {
        vm.prank(AUTOMATION);
        epochManager.startNewEpoch(); // Epoch 1 is Active
        uint256 epoch1Id = epochManager.currentEpochId();
        vm.stopPrank();

        // Move Epoch 1 to Processing
        vm.warp(block.timestamp + ONE_DAY + 1);
        vm.prank(AUTOMATION);
        epochManager.beginEpochProcessing(epoch1Id);
        (,,,,, EpochManager.EpochStatus status1) = epochManager.getEpochDetails(epoch1Id);
        assertEq(uint8(status1), uint8(EpochManager.EpochStatus.Processing), "Epoch 1 should be Processing");

        // Try to start another epoch while Epoch 1 is Processing
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochManager.EpochManager__InvalidEpochStatus.selector,
                epoch1Id,
                EpochManager.EpochStatus.Processing,
                EpochManager.EpochStatus.Completed
            )
        );
        epochManager.startNewEpoch();
        vm.stopPrank();
    }

    // DebtSubsidizer: subsidize with empty subsidies array
    function testSubsidize_EmptySubsidiesArray() public {
        IDebtSubsidizer.Subsidy[] memory emptySubsidies = new IDebtSubsidizer.Subsidy[](0);

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", debtSubsidizer.getDomainSeparator(), keccak256(abi.encode(emptySubsidies)))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SUBSIDY_SIGNER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(USER_A); // Ensure vault has some assets for potential internal operations
        asset.approve(address(vault), 1000 * 10 ** asset.decimals());
        vault.depositForCollection(1000 * 10 ** asset.decimals(), USER_A, address(nft1));
        vm.stopPrank();

        uint256 userANonceBefore = debtSubsidizer.userNonce(address(vault), USER_A);
        uint256 userASecondsClaimedBefore = debtSubsidizer.userSecondsClaimed(USER_A);

        // Expect YieldBatchRepaid(0, debtSubsidizer) from CollectionsVault

        debtSubsidizer.subsidize(address(vault), emptySubsidies, signature);

        assertEq(
            debtSubsidizer.userNonce(address(vault), USER_A),
            userANonceBefore,
            "Nonce should not change for empty subsidies"
        );
        assertEq(
            debtSubsidizer.userSecondsClaimed(USER_A),
            userASecondsClaimedBefore,
            "Seconds claimed should not change for empty subsidies"
        );
    }
}
