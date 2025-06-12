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
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol"; // Assuming this path is correct from FullIntegration
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract FullEpochFlowTest is Test {
    // Mock Contracts
    MockERC20 internal asset;
    MockERC721 internal nft;
    SimpleMockCToken internal cToken;

    // Core Contracts
    LendingManager internal lendingManager;
    CollectionsVault internal vault;
    EpochManager internal epochManager;
    DebtSubsidizer internal debtSubsidizer;

    // Users
    address internal constant OWNER = address(0x1);
    address internal constant ADMIN = address(0x2); // Vault Admin
    address internal constant AUTOMATION = address(0x3); // EpochManager Automation
    address internal constant USER_DEPOSITOR = address(0x4);
    // address internal constant BORROWER = address(0xB0B); // For DebtSubsidizer if needed for subsidy target

    // Signer for DebtSubsidizer
    uint256 internal constant SUBSIDY_SIGNER_PK = uint256(keccak256("SUBSIDY_SIGNER"));
    address internal SUBSIDY_SIGNER;

    // Constants
    uint256 internal constant INITIAL_EXCHANGE_RATE = 2e28; // cToken exchange rate (2 * 10^18 * 10^10)
    uint256 internal constant ONE_DAY = 1 days;
    uint256 internal constant DEFAULT_YIELD_SHARE_BPS = 5000; // 50%

    function setUp() public {
        SUBSIDY_SIGNER = vm.addr(SUBSIDY_SIGNER_PK);

        // 1. Deploy Mock Asset (e.g., USDC)
        asset = new MockERC20("Mock USDC", "mUSDC", 6, 0); // 6 decimals like USDC

        // 2. Deploy Mock NFT Collection
        nft = new MockERC721("Test NFT", "TNFT");

        // 3. Deploy Mock cToken (e.g., cUSDC)
        // For ComptrollerInterface and InterestRateModel, we can pass address(this) or deploy simple mocks if needed.
        // For FullIntegration, address(this) was used.
        cToken = new SimpleMockCToken(
            address(asset),
            ComptrollerInterface(payable(address(0xDEAD))), // Mock Comptroller
            InterestRateModel(payable(address(0xBEEF))), // Mock Interest Rate Model
            INITIAL_EXCHANGE_RATE,
            "Mock cUSDC",
            "mcUSDC",
            8, // cToken decimals often 8
            payable(OWNER) // Admin of cToken
        );

        // 4. Deploy LendingManager
        // LendingManager needs owner, vault address (initially this, then updated), asset, cToken
        lendingManager = new LendingManager(OWNER, address(this), address(asset), address(cToken));

        // 5. Deploy CollectionsVault
        // CollectionsVault needs asset, name, symbol, admin, lendingManager
        vault = new CollectionsVault(
            IERC20(address(asset)), "Collections Vault Token", "CVT", ADMIN, address(lendingManager)
        );

        // Grant VAULT_ROLE from LendingManager to CollectionsVault
        vm.startPrank(OWNER);
        lendingManager.revokeVaultRole(address(this)); // Revoke from initial deployer if set
        lendingManager.grantVaultRole(address(vault));
        vm.stopPrank();

        // 6. Deploy EpochManager
        // EpochManager needs epochDuration, automation address, owner
        epochManager = new EpochManager(ONE_DAY, AUTOMATION, OWNER);

        // Grant vault role and set EpochManager
        vm.startPrank(OWNER);
        epochManager.grantVaultRole(address(vault));
        vm.stopPrank();
        vm.prank(ADMIN);
        vault.setEpochManager(address(epochManager));

        // 7. Deploy DebtSubsidizer (Upgradeable Proxy)
        DebtSubsidizer debtImpl = new DebtSubsidizer();
        bytes memory initData = abi.encodeWithSelector(DebtSubsidizer.initialize.selector, OWNER, SUBSIDY_SIGNER);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(debtImpl), OWNER, initData);
        debtSubsidizer = DebtSubsidizer(address(proxy));

        // Add CollectionsVault to DebtSubsidizer
        vm.prank(OWNER);
        debtSubsidizer.addVault(address(vault), address(lendingManager));

        // Set DebtSubsidizer in CollectionsVault (grant role)
        vm.prank(ADMIN);
        vault.setDebtSubsidizer(address(debtSubsidizer));

        // 8. Configure Collection in DebtSubsidizer
        vm.prank(OWNER);
        debtSubsidizer.whitelistCollection(
            address(vault),
            address(nft),
            IDebtSubsidizer.CollectionType.ERC721,
            IDebtSubsidizer.RewardBasis.DEPOSIT, // Or other basis as per design
            DEFAULT_YIELD_SHARE_BPS // Example: 50% of subsidized amount goes to this collection's users
        );

        // 9. Configure Collection in CollectionsVault
        vm.prank(ADMIN);
        vault.setCollectionYieldSharePercentage(address(nft), DEFAULT_YIELD_SHARE_BPS); // 50% of passive yield

        // Initial asset mint for user
        asset.mint(USER_DEPOSITOR, 1_000_000 * (10 ** asset.decimals())); // 1M assets
    }

    // Helper to simulate yield generation by increasing cToken's underlying balance and updating exchange rate
    function _simulateYield(uint256 yieldAmount) internal {
        asset.mint(address(cToken), yieldAmount); // Increase underlying in cToken contract

        uint256 currentUnderlying = cToken.getCash();
        uint256 currentTotalSupply = cToken.totalSupply(); // Total cTokens minted by the cToken contract

        if (currentTotalSupply == 0) {
            // Avoid division by zero if no cTokens were ever minted (e.g., before any deposit to LM)
            // Exchange rate doesn't make sense yet or should remain initial.
            // For this test, we assume deposits happened, so totalSupply > 0.
            return;
        }
        // Exchange rate is Underlying / cTokens. For SimpleMockCToken, it's scaled.
        // exchangeRateStored = (totalUnderlying * 1e18) / totalCTokens (if cToken decimals = 18)
        // Since SimpleMockCToken's exchange rate is stored with 1e18 precision on top of its value.
        // And SimpleMockCToken constructor takes _decimals for the cToken itself.
        // Let's assume the exchange rate is (Underlying / cTokens) and then scaled by 1e(18 + assetDecimals - cTokenDecimals)
        // The INITIAL_EXCHANGE_RATE is 2e28.
        // A simpler way for mock: if exchangeRate is X, it means 1 cToken = X underlying.
        // If underlying increases, X should increase if cToken supply is constant.
        // newExchangeRate = totalUnderlying / totalCTokens (actual value)
        // The stored rate in SimpleMockCToken is already scaled.
        // Let's use the formula: newRate = (totalUnderlyingInCToken * exchangeRatePrecision) / totalCTokensMinted
        // The SimpleMockCToken's INITIAL_EXCHANGE_RATE is already the scaled value.
        // So, newRate = (currentUnderlying * INITIAL_EXCHANGE_RATE) / (initialUnderlyingThatProducedCurrentSupply)
        // This is getting complex. A simpler mock approach:
        // If SimpleMockCToken's exchange rate is set directly, it reflects the new value.
        // The rate should be (total underlying value in cToken) / (total cToken supply).
        // The `INITIAL_EXCHANGE_RATE` is `value of 1 cToken in underlying * 10^18` (if cToken has 18 decimals).
        // Or more generally `value of 1 cToken in underlying * 10^(18 + asset.decimals() - cToken.decimals())`
        // Let's assume `exchangeRateStored` is `(totalUnderlying / totalCTokens) * 10^18` (if asset and ctoken decimals are same)
        // For SimpleMockCToken, `exchangeRateStored` is just a number.
        // `mint` uses `amountUnderlying * 1e18 / exchangeRateStored` to get cTokens.
        // So `exchangeRateStored` is `(amountUnderlying / cTokensMinted) * 1e18`.
        // New exchange rate = (cToken.getCash() * 1e18) / cToken.totalSupply()
        // This assumes asset and cToken decimals are effectively handled by the 1e18 factor or are equal.
        // Given asset is 6 dec, cToken is 8 dec.
        // exchangeRate = (underlyingAmount / 10^asset.decimals()) / (cTokenAmount / 10^cToken.decimals())
        // exchangeRateStored in SimpleMockCToken is used as: cTokens = (underlyingAmount * 10^cToken.decimals()) / exchangeRateStored
        // This implies exchangeRateStored is units of (underlying * 10^cToken.decimals() / cTokens)
        // Let's use the formula from Compound: exchangeRate = (getCash() + totalBorrows() - totalReserves()) / totalSupply()
        // For our mock, totalBorrows and totalReserves are 0.
        // So, exchangeRateValue = cToken.getCash() / cToken.totalSupply() (this is the true rate)
        // The stored rate needs to be scaled: newRateToStore = (cToken.getCash() * (10**18) * (10**cToken.decimals())) / (cToken.totalSupply() * (10**asset.decimals())); (This is too complex for a mock)

        // Simpler: The exchange rate is `totalUnderlying / totalCTokens`.
        // The `SimpleMockCToken` stores `exchangeRateStored`.
        // When minting: `mintTokens = underlyingTokens * 10^cTokenDecimals / exchangeRateStored`.
        // This means `exchangeRateStored` has units of `(underlyingTokens * 10^cTokenDecimals) / cTokens`.
        // If `asset` has 6 decimals, `cToken` has 8 decimals.
        // `exchangeRateStored` = `(underlying_val_in_smallest_unit / 10^6) * 10^8 / (cTokens_in_smallest_unit / 10^8)`
        // `exchangeRateStored` = `(underlying_val_in_smallest_unit * 10^8) / (cTokens_in_smallest_unit)`
        // So, `newRate = (cToken.getCash() * (10**cToken.decimals())) / cToken.totalSupply()`.
        // This is if `cToken.getCash()` is in asset's smallest unit, and `cToken.totalSupply()` is in cToken's smallest unit.
        // `cToken.getCash()` returns `asset.balanceOf(address(cToken))`, which is in asset's smallest unit.
        // `cToken.totalSupply()` is in cToken's smallest unit.
        uint256 newCalculatedRate = (currentUnderlying * (10 ** cToken.decimals())) / currentTotalSupply;
        // The INITIAL_EXCHANGE_RATE = 2e28. This is a large scaled number.
        // Let's assume the `exchangeRateStored` is `(TrueExchangeRate * 10^(18 + cToken.decimals() - asset.decimals()))`
        // TrueExchangeRate = UnderlyingPerCToken
        // StoredRate = (UnderlyingTokens / CTokens) * ScaleFactor
        // ScaleFactor for SimpleMockCToken's rate seems to be 1e(18 + cTokenDecimals - assetDecimals)
        // For USDC (6) and cUSDC (8), scale is 1e(18+8-6) = 1e20.
        // So, TrueRate = StoredRate / 1e20.
        // NewTrueRate = cToken.getCash() / cToken.totalSupply() (value in asset units per 1 cToken unit)
        // NewStoredRate = (cToken.getCash() * (10**(18 + cToken.decimals() - asset.decimals()))) / cToken.totalSupply();
        uint256 scaleFactor = 10 ** (18 + cToken.decimals() - asset.decimals());
        newCalculatedRate = (currentUnderlying * scaleFactor) / currentTotalSupply;

        cToken.setExchangeRate(newCalculatedRate);
    }

    function testFullEpochLifecycle() public {
        // Test steps will be implemented here
        // 1. User deposits into CollectionsVault
        // 2. Yield accrues (simulated)
        // 3. EpochManager: allocateEpochYield is called by CollectionsVault (via admin)
        // 4. CollectionsVault: applyCollectionYieldForEpoch is called for the collection (via admin)
        // 5. DebtSubsidizer: subsidize() is called for a user
        // Assert balances and events at each step.

        uint256 depositAmount = 100_000 * (10 ** asset.decimals()); // 100k assets

        // User approves vault
        vm.startPrank(USER_DEPOSITOR);
        asset.approve(address(vault), depositAmount);

        // 1. User deposits into CollectionsVault for the NFT collection
        vm.expectEmit(true, true, true, true, address(vault));
        emit ICollectionsVault.CollectionDeposit(
            address(nft),
            USER_DEPOSITOR,
            USER_DEPOSITOR,
            depositAmount,
            vault.previewDeposit(depositAmount),
            vault.previewDeposit(depositAmount)
        ); // cTokenAmount is placeholder
        uint256 sharesReceived = vault.depositForCollection(depositAmount, USER_DEPOSITOR, address(nft));
        vm.stopPrank();

        assertEq(vault.balanceOf(USER_DEPOSITOR), sharesReceived, "User share balance incorrect after deposit");
        assertEq(
            vault.collectionTotalAssetsDeposited(address(nft)),
            depositAmount,
            "Collection total assets incorrect after deposit"
        );
        uint256 initialTotalPrincipalInLM = lendingManager.totalPrincipalDeposited();
        assertEq(initialTotalPrincipalInLM, depositAmount, "LM total principal incorrect after deposit");

        // 2. Simulate Yield Accrual
        uint256 yieldGenerated = 10_000 * (10 ** asset.decimals()); // 10k assets yield
        _simulateYield(yieldGenerated); // This will update cToken's exchange rate

        // Admin indexes collections deposits to update global index and accrue passive yield
        vm.prank(ADMIN);
        // Expect CollectionYieldAccrued if conditions met (globalDepositIndex > lastIndex, yieldSharePercentage > 0)
        // For this first accrual, it should happen.
        // The amount depends on (depositAmount * (newGlobalIndex - oldGlobalIndex) * yieldShareBps) / (PRECISION * 10000)
        // Predicting exact event values for CollectionYieldAccrued is complex here without running the math.
        // We can check that totalAssetsDeposited for the collection increases.
        uint256 assetsBeforeIndex = vault.collectionTotalAssetsDeposited(address(nft));
        vault.indexCollectionsDeposits();
        uint256 assetsAfterIndex = vault.collectionTotalAssetsDeposited(address(nft));
        assertTrue(assetsAfterIndex > assetsBeforeIndex, "Collection assets should increase after indexing yield");
        // The increase should be yieldGenerated * DEFAULT_YIELD_SHARE_BPS / 10000
        // This assumes globalDepositIndex reflects the full yield and collection gets its share.
        // globalDepositIndex = (LM.totalAssets * PRECISION) / LM.totalPrincipal
        // LM.totalAssets = (cTokens_held_by_LM * newExchangeRate) / 1e18
        // LM.totalAssets should be initialTotalPrincipalInLM + yieldGenerated
        assertEq(
            lendingManager.totalAssets(),
            initialTotalPrincipalInLM + yieldGenerated,
            "LM total assets not reflecting full yield"
        );
        uint256 expectedPassiveYieldToCollection = (yieldGenerated * DEFAULT_YIELD_SHARE_BPS) / 10000;
        assertEq(
            assetsAfterIndex,
            assetsBeforeIndex + expectedPassiveYieldToCollection,
            "Passive yield to collection mismatch"
        );

        // 3. EpochManager: Start new epoch & CollectionsVault allocates yield to it
        vm.prank(AUTOMATION);
        vm.expectEmit(true, true, true, true, address(epochManager));
        // block.timestamp will be start time, endTime = startTime + ONE_DAY
        // emit EpochStarted(1, block.timestamp, block.timestamp + ONE_DAY); // Cannot predict exact timestamp
        epochManager.startNewEpoch();
        uint256 currentEpochId = epochManager.currentEpochId();
        assertEq(currentEpochId, 1, "Epoch ID should be 1");
        (,,,, EpochManager.EpochStatus initialStatus) = epochManager.getEpochDetails(currentEpochId);
        assertEq(uint8(initialStatus), uint8(EpochManager.EpochStatus.Active), "Epoch not active");

        // CollectionsVault admin allocates a portion of the *overall available yield* to this epoch
        // The yield available in vault for allocation is totalLMYield - alreadyAllocatedToEpochs
        // totalLMYield = LM.totalAssets() - LM.totalPrincipalDeposited() = yieldGenerated
        uint256 yieldToAllocateToEpoch = yieldGenerated / 2; // Allocate half of the generated yield

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true, address(vault));
        emit ICollectionsVault.VaultYieldAllocatedToEpoch(currentEpochId, yieldToAllocateToEpoch);
        vm.expectEmit(true, true, true, true, address(epochManager));
        emit EpochManager.VaultYieldAllocated(currentEpochId, address(vault), yieldToAllocateToEpoch);
        vault.allocateEpochYield(yieldToAllocateToEpoch);
        vm.stopPrank();

        assertEq(
            vault.getEpochYieldAllocated(currentEpochId), yieldToAllocateToEpoch, "Vault epoch allocation incorrect"
        );
        assertEq(
            epochManager.getVaultYieldForEpoch(currentEpochId, address(vault)),
            yieldToAllocateToEpoch,
            "EpochManager vault yield incorrect"
        );
        (,,, uint256 epochTotalYield,,) = epochManager.getEpochDetails(currentEpochId);
        assertEq(epochTotalYield, yieldToAllocateToEpoch, "EpochManager total yield incorrect");

        // 4. Advance time & Process Epoch: CollectionsVault applies its share of epoch yield
        vm.warp(block.timestamp + ONE_DAY + 1); // Advance time past epoch end

        vm.prank(AUTOMATION);
        vm.expectEmit(true, true, true, true, address(epochManager));
        emit EpochManager.EpochProcessingStarted(currentEpochId);
        epochManager.beginEpochProcessing(currentEpochId);
        (,,,, EpochManager.EpochStatus processingStatus) = epochManager.getEpochDetails(currentEpochId);
        assertEq(uint8(processingStatus), uint8(EpochManager.EpochStatus.Processing), "Epoch not processing");
        vm.stopPrank();

        // Admin calls applyCollectionYieldForEpoch for the specific collection
        uint256 assetsBeforeEpochYieldApply = vault.collectionTotalAssetsDeposited(address(nft));
        uint256 collectionShareOfEpochYield = (yieldToAllocateToEpoch * DEFAULT_YIELD_SHARE_BPS) / 10000;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true, address(vault));
        emit ICollectionsVault.CollectionYieldAppliedForEpoch(
            currentEpochId,
            address(nft),
            DEFAULT_YIELD_SHARE_BPS,
            collectionShareOfEpochYield,
            assetsBeforeEpochYieldApply + collectionShareOfEpochYield
        );
        vault.applyCollectionYieldForEpoch(address(nft), currentEpochId);
        vm.stopPrank();
        assertEq(
            vault.collectionTotalAssetsDeposited(address(nft)),
            assetsBeforeEpochYieldApply + collectionShareOfEpochYield,
            "Collection assets incorrect after epoch yield apply"
        );

        // 5. DebtSubsidizer: subsidize() is called for a user
        // This part assumes the `subsidize` function in DebtSubsidizer uses the yield from CollectionsVault
        // which is triggered by `repayBorrowBehalfBatch`.
        // The amount for subsidy here is distinct from the passive yield or epoch yield applied above.
        // It's a new amount that the subsidizer decides to give, sourced from the collection's yield pool in the vault.
        uint256 subsidyAmount = collectionShareOfEpochYield / 2; // Subsidize with half of what the collection got from epoch
        if (subsidyAmount == 0 && collectionShareOfEpochYield > 0) subsidyAmount = 1; // ensure non-zero if possible for test

        IDebtSubsidizer.Subsidy[] memory subsidies = new IDebtSubsidizer.Subsidy[](1);
        uint64 nonce = debtSubsidizer.userNonce(address(vault), USER_DEPOSITOR);
        subsidies[0] = IDebtSubsidizer.Subsidy({
            account: USER_DEPOSITOR,
            collection: address(nft),
            vault: address(vault),
            amount: subsidyAmount,
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });

        bytes32 subsidiesHash = keccak256(abi.encode(subsidies));
        bytes32 digest = debtSubsidizer.DOMAIN_SEPARATOR(); // This is wrong, need _hashTypedDataV4
        // The _hashTypedDataV4 in DebtSubsidizer takes the keccak256 of the abi.encode(subsidies) as the message hash.
        // For EIP712, the digest is constructed as follows, matching DebtSubsidizer's internal _hashTypedDataV4 call:
        digest =
            keccak256(abi.encodePacked("\x19\x01", debtSubsidizer.DOMAIN_SEPARATOR(), keccak256(abi.encode(subsidies))));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SUBSIDY_SIGNER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 userSecondsClaimedBefore = debtSubsidizer.userSecondsClaimed(USER_DEPOSITOR);

        // Expect DebtSubsidized from DebtSubsidizer
        vm.expectEmit(true, true, true, true, address(debtSubsidizer));
        emit IDebtSubsidizer.DebtSubsidized(address(vault), USER_DEPOSITOR, address(nft), subsidyAmount);
        // Expect YieldBatchRepaid from CollectionsVault (called by DebtSubsidizer)
        vm.expectEmit(true, true, false, true, address(vault)); // Not checking data for YieldBatchRepaid fully
        emit ICollectionsVault.YieldBatchRepaid(subsidyAmount, address(debtSubsidizer));

        debtSubsidizer.subsidize(address(vault), subsidies, signature);

        assertEq(debtSubsidizer.userNonce(address(vault), USER_DEPOSITOR), nonce + 1, "Nonce not incremented");
        assertEq(
            debtSubsidizer.userSecondsClaimed(USER_DEPOSITOR),
            userSecondsClaimedBefore + subsidyAmount,
            "User seconds claimed incorrect"
        );

        // 6. Finalize Epoch in EpochManager
        uint256 totalSubsidiesForEpoch = subsidyAmount; // In this simple test, only one subsidy.
        vm.prank(AUTOMATION);
        vm.expectEmit(true, true, true, true, address(epochManager));
        emit EpochManager.EpochFinalized(currentEpochId, epochTotalYield, totalSubsidiesForEpoch);
        epochManager.finalizeEpoch(currentEpochId, totalSubsidiesForEpoch);
        vm.stopPrank();

        (,,,, EpochManager.EpochStatus finalStatus) = epochManager.getEpochDetails(currentEpochId);
        assertEq(uint8(finalStatus), uint8(EpochManager.EpochStatus.Completed), "Epoch not completed");

        // Further assertions on balances if relevant (e.g., if subsidy actually moved underlying)
        // The subsidy mechanism calls repayBorrowBehalfBatch on the vault, which then calls repayBorrowBehalf on LM.
        // This implies the subsidized amount is taken from the vault's yield pool and used to repay a user's debt in LM.
        // For this test, USER_DEPOSITOR doesn't have debt, so repayBorrowBehalf might not do much or revert if user has no debt.
        // The mock LM's repayBorrowBehalf needs to be checked.
        // SimpleMockCToken.repayBorrowBehalf returns 0 (no error). It reduces totalBorrows.
        // For this test, we are not creating borrows, so this part might be a NOP in terms of balance changes for USER_DEPOSITOR.
        // The key is that the subsidy flow is invoked.
    }
}
