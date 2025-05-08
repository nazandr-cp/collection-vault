// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm, console} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {RewardsController} from "../../src/RewardsController.sol";
import {LendingManager} from "../../src/LendingManager.sol";
import {ERC4626Vault} from "../../src/ERC4626Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {ILendingManager} from "../../src/interfaces/ILendingManager.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol"; // Updated import path
import {MockERC721} from "../../src/mocks/MockERC721.sol"; // Import MockERC721
import {LendingManager} from "../../src/LendingManager.sol"; // Import real LendingManager
import {MockCToken} from "../../src/mocks/MockCToken.sol"; // Import MockCToken
import {console} from "forge-std/console.sol"; // Add console for debugging

contract RewardsController_Test_Base is Test {
    using Strings for uint256;

    // USER_BALANCE_UPDATE_DATA_TYPEHASH is no longer directly used by the refactored processBalanceUpdates in RewardsController
    // but might be used by other test helpers if they construct this struct for other purposes.
    // For now, let's keep it if other signing helpers for different functions use it.
    bytes32 public constant USER_BALANCE_UPDATE_DATA_TYPEHASH_OLD = keccak256( // Renamed to avoid conflict if needed elsewhere
    "UserBalanceUpdateData(address user,address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)");
    // This is for the new parallel array structure in processBalanceUpdates
    bytes32 public constant BALANCE_UPDATES_ARRAYS_TYPEHASH = keccak256(
        "BalanceUpdates(address[] users,address[] collections,uint256[] blockNumbers,int256[] nftDeltas,int256[] balanceDeltas,uint256 nonce)"
    );
    bytes32 public constant BALANCE_UPDATE_DATA_TYPEHASH = // Used by processUserBalanceUpdates and individual updates
     keccak256("BalanceUpdateData(address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)");
    bytes32 public constant USER_BALANCE_UPDATES_TYPEHASH = // Used by processUserBalanceUpdates
     keccak256("UserBalanceUpdates(address user,BalanceUpdateData[] updates,uint256 nonce)");

    address constant USER_A = address(0xAAA);
    address constant USER_B = address(0xBBB);
    address constant USER_C = address(0xCCC);
    address constant NFT_COLLECTION_1 = address(0xC1);
    address constant NFT_COLLECTION_2 = address(0xC2);
    address constant NFT_COLLECTION_3 = address(0xC3);
    address constant OWNER = address(0x001);
    address constant ADMIN = address(0xAD01);
    address constant OTHER_ADDRESS = address(0x123);
    address constant NEW_UPDATER = address(0x000000000000000000000000000000000000000d);
    address constant AUTHORIZED_UPDATER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant UPDATER_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant PRECISION = 1e18;
    uint256 constant BETA_1 = 0.1 ether;
    uint256 constant BETA_2 = 0.05 ether;
    uint256 constant MAX_REWARD_SHARE_PERCENTAGE = 10000;
    uint256 constant VALID_REWARD_SHARE_PERCENTAGE = 5000;
    uint256 constant INVALID_REWARD_SHARE_PERCENTAGE = 10001;
    address constant CDAI_ADDRESS = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 constant FORK_BLOCK_NUMBER = 19670000;
    address constant DAI_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    RewardsController internal rewardsController;
    RewardsController internal rewardsControllerImpl;
    LendingManager internal lendingManager; // Changed to real LendingManager
    ERC4626Vault internal tokenVault;
    IERC20 internal rewardToken; // Actual reward token (DAI)
    MockERC20 internal mockERC20; // Generic mock ERC20 for testing transfers etc.
    MockERC721 internal mockERC721; // Mock NFT Collection 1
    MockERC721 internal mockERC721_2; // Mock NFT Collection 2
    MockERC721 internal mockERC721_alt; // Mock NFT Collection Alt for testing specific scenarios
    MockCToken internal mockCToken; // Mock cToken for yield simulation
    ProxyAdmin public proxyAdmin;

    uint256 constant INITIAL_EXCHANGE_RATE = 2e28; // Define the constant if not already present

    function setUp() public virtual {
        uint256 forkId = vm.createFork("mainnet", FORK_BLOCK_NUMBER);
        vm.selectFork(forkId);

        rewardToken = IERC20(DAI_ADDRESS);

        vm.startPrank(OWNER);

        // Deploy Mocks
        mockERC20 = new MockERC20("Mock Token", "MOCK", 18);
        mockERC721 = new MockERC721("Mock NFT 1", "MNFT1");
        mockERC721_2 = new MockERC721("Mock NFT 2", "MNFT2");
        mockERC721_alt = new MockERC721("Mock NFT Alt", "MNFTA");
        mockCToken = new MockCToken(address(rewardToken)); // Mock cToken using DAI as underlying

        // *** Set initial exchange rate BEFORE LM/RC initialization ***
        mockCToken.setExchangeRate(INITIAL_EXCHANGE_RATE);

        // Deploy real LendingManager instead of the mock
        lendingManager = new LendingManager(
            OWNER, // initialAdmin
            address(1), // temporary vaultAddress, will be updated
            address(this), // rewardsControllerAddress (temporary)
            address(rewardToken), // assetAddress
            address(mockCToken) // cTokenAddress
        );

        // Initialize TokenVault with real LendingManager
        tokenVault = new ERC4626Vault(rewardToken, "Vaulted DAI Test", "vDAIt", OWNER, address(lendingManager));

        // Update vault role in LendingManager
        lendingManager.revokeVaultRole(address(1));
        lendingManager.grantVaultRole(address(tokenVault));

        // Deploy RewardsController Implementation
        rewardsControllerImpl = new RewardsController();

        vm.stopPrank();
        vm.startPrank(ADMIN);
        proxyAdmin = new ProxyAdmin(ADMIN);
        vm.stopPrank();

        // Initialize RewardsController via Proxy
        vm.startPrank(OWNER); // Ensure OWNER calls initialize
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            OWNER,
            address(lendingManager),
            address(tokenVault),
            AUTHORIZED_UPDATER
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(rewardsControllerImpl), address(proxyAdmin), initData);
        rewardsController = RewardsController(address(proxy));

        // Update the rewards controller role in LendingManager *after* RC is initialized
        lendingManager.revokeRewardsControllerRole(address(this));
        lendingManager.grantRewardsControllerRole(address(rewardsController));

        // Whitelist collections
        rewardsController.addNFTCollection(
            address(mockERC721), BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
        );
        rewardsController.addNFTCollection(
            address(mockERC721_2), BETA_2, IRewardsController.RewardBasis.DEPOSIT, VALID_REWARD_SHARE_PERCENTAGE
        );
        rewardsController.addNFTCollection(
            address(mockERC721_alt),
            BETA_1,
            IRewardsController.RewardBasis.DEPOSIT,
            VALID_REWARD_SHARE_PERCENTAGE // Whitelist alt collection
        );

        vm.stopPrank();

        uint256 initialFunding = 1_000_000 ether;
        uint256 userFunding = 10_000 ether;
        deal(DAI_ADDRESS, DAI_WHALE, initialFunding * 2);
        deal(address(rewardToken), address(lendingManager), initialFunding); // Fund Mock LM

        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(USER_A, userFunding);
        rewardToken.transfer(USER_B, userFunding);
        rewardToken.transfer(USER_C, userFunding);

        // USER_A deposits into TokenVault to ensure vault.totalSupply() is non-zero for reward calculations
        uint256 initialVaultDeposit = 1000 ether;
        if (userFunding >= initialVaultDeposit) {
            // DAI_WHALE is still the actor here.
            // DAI_WHALE has userFunding (actually, DAI_WHALE has a lot more from deal).
            // This check is more about ensuring initialVaultDeposit is reasonable.
            // DAI_WHALE approves tokenVault to spend DAI_WHALE's DAI
            rewardToken.approve(address(tokenVault), initialVaultDeposit);
            // DAI_WHALE deposits its DAI, USER_A is the receiver of the vault shares.
            // Use depositForCollection as the generic deposit is disabled.
            // Use mockERC721 as a placeholder collection for this initial seeding.
            tokenVault.depositForCollection(initialVaultDeposit, USER_A, address(mockERC721));
        }
        vm.stopPrank();

        vm.label(OWNER, "OWNER");
        vm.label(ADMIN, "ADMIN");
        vm.label(AUTHORIZED_UPDATER, "AUTHORIZED_UPDATER");
        vm.label(USER_A, "USER_A");
        vm.label(USER_B, "USER_B");
        vm.label(USER_C, "USER_C");
        vm.label(address(rewardsController), "RewardsController (Proxy)");
        vm.label(address(rewardsControllerImpl), "RewardsController (Impl)");
        vm.label(address(lendingManager), "LendingManager");
        vm.label(address(tokenVault), "TokenVault");
        vm.label(address(proxyAdmin), "ProxyAdmin");
        // Update labels to reflect actual mock addresses being whitelisted
        vm.label(address(mockERC721), "NFT_COLLECTION_1 (Mock)");
        vm.label(address(mockERC721_2), "NFT_COLLECTION_2 (Mock)");
        vm.label(address(mockERC721_alt), "NFT_COLLECTION_ALT (Mock)");
        vm.label(NFT_COLLECTION_3, "NFT_COLLECTION_3 (Constant, Non-WL)"); // Keep this label distinct if needed
    }

    // --- Helper Functions ---

    // Helper function to calculate domain separator the same way as the contract
    function _buildDomainSeparator() internal view returns (bytes32) {
        // Ensure these match the values used in RewardsController's EIP712 constructor/initializer
        bytes32 typeHashDomain =
            keccak256(bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"));
        bytes32 nameHashDomain = keccak256(bytes("RewardsController")); // Match contract name
        bytes32 versionHashDomain = keccak256(bytes("1")); // Match contract version

        return keccak256(
            abi.encode(typeHashDomain, nameHashDomain, versionHashDomain, block.chainid, address(rewardsController)) // Use proxy address
        );
    }
    // Helper to create hash for BalanceUpdateData array

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
                    updates[i].balanceDelta
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
        // Replicate _hashTypedDataV4 logic using the locally built domain separator
        bytes32 domainSeparator = _buildDomainSeparator(); // Use local helper
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // Helper to sign parallel arrays for processBalanceUpdates (multi-user batch)
    function _signBalanceUpdatesArrays(
        address[] memory users,
        address[] memory collections,
        uint256[] memory blockNumbers,
        int256[] memory nftDeltas,
        int256[] memory balanceDeltas,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 structHash = keccak256(
            abi.encode(
                BALANCE_UPDATES_ARRAYS_TYPEHASH, // Use the new typehash for parallel arrays
                keccak256(abi.encodePacked(users)),
                keccak256(abi.encodePacked(collections)),
                keccak256(abi.encodePacked(blockNumbers)),
                keccak256(abi.encodePacked(nftDeltas)),
                keccak256(abi.encodePacked(balanceDeltas)),
                nonce
            )
        );
        bytes32 domainSeparator = _buildDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // _hashUserBalanceUpdates and the old _signBalanceUpdates might still be needed if tests
    // call other functions that use the UserBalanceUpdateData struct directly for signing,
    // or if there are tests for the old hashing mechanism itself.
    // For now, we assume the primary path for processBalanceUpdates uses the new array signing.
    // If _hashUserBalanceUpdates is truly unused after refactoring tests, it can be removed.
    function _hashUserBalanceUpdates_OLD(
        IRewardsController.UserBalanceUpdateData[] memory updates // Renamed
    ) internal pure returns (bytes32) {
        bytes32[] memory dataHashes = new bytes32[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            dataHashes[i] = keccak256(
                abi.encode(
                    USER_BALANCE_UPDATE_DATA_TYPEHASH_OLD, // Use renamed old typehash
                    updates[i].user,
                    updates[i].collection,
                    updates[i].blockNumber,
                    updates[i].nftDelta,
                    updates[i].balanceDelta
                )
            );
        }
        return keccak256(abi.encodePacked(dataHashes));
    }

    // Helper to process a single user update for convenience
    function _processSingleUserUpdate(
        address user,
        address collection,
        uint256 blockNum,
        int256 nftDelta,
        int256 balanceDelta
    ) internal {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: blockNum,
            nftDelta: nftDelta,
            balanceDelta: balanceDelta
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce, UPDATER_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates, sig);
    }

    // --- Log Assertion Helpers ---

    function _assertRewardsClaimedForCollectionLog(
        Vm.Log[] memory entries,
        address expectedUser,
        address expectedCollection,
        uint256 expectedAmount,
        uint256 delta
    ) internal {
        bytes32 expectedTopic0 = keccak256("RewardsClaimedForCollection(address,address,uint256)");
        bytes32 userTopic = bytes32(uint256(uint160(expectedUser)));
        bytes32 collectionTopic = bytes32(uint256(uint160(expectedCollection)));
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics.length == 3 && entries[i].topics[0] == expectedTopic0
                    && entries[i].topics[1] == userTopic && entries[i].topics[2] == collectionTopic
            ) {
                (uint256 emittedAmount) = abi.decode(entries[i].data, (uint256));
                assertApproxEqAbs(emittedAmount, expectedAmount, delta, "RewardsClaimedForCollection amount mismatch");
                found = true;
                break;
            }
        }
        assertTrue(found, "RewardsClaimedForCollection log not found or topics mismatch");
    }

    function _assertRewardsClaimedForAllLog(
        Vm.Log[] memory entries,
        address expectedUser,
        uint256 expectedAmount,
        uint256 delta
    ) internal {
        bytes32 expectedTopic0 = keccak256("RewardsClaimedForAll(address,uint256)");
        bytes32 userTopic = bytes32(uint256(uint160(expectedUser)));
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics.length == 2 && entries[i].topics[0] == expectedTopic0
                    && entries[i].topics[1] == userTopic
            ) {
                (uint256 emittedAmount) = abi.decode(entries[i].data, (uint256));
                assertApproxEqAbs(emittedAmount, expectedAmount, delta, "RewardsClaimedForAll amount mismatch");
                found = true;
                break;
            }
        }
        assertTrue(found, "RewardsClaimedForAll log not found or user mismatch");
    }

    function _assertYieldTransferCappedLog(
        Vm.Log[] memory entries,
        address expectedUser,
        uint256 expectedTotalDue,
        uint256 expectedActualReceived,
        uint256 delta // Delta for comparing expectedTotalDue vs emittedTotalDue
    ) internal {
        bytes32 expectedTopic0 = keccak256("YieldTransferCapped(address,uint256,uint256)");
        bytes32 userTopic = bytes32(uint256(uint160(expectedUser)));
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics.length == 2 && entries[i].topics[0] == expectedTopic0
                    && entries[i].topics[1] == userTopic
            ) {
                (uint256 emittedTotalDue, uint256 emittedActualReceived) =
                    abi.decode(entries[i].data, (uint256, uint256));
                assertApproxEqAbs(emittedTotalDue, expectedTotalDue, delta, "YieldTransferCapped totalDue mismatch");
                // Use tighter delta (1 wei) for actual received amount as it should be exact
                assertApproxEqAbs(
                    emittedActualReceived, expectedActualReceived, 1, "YieldTransferCapped actualReceived mismatch"
                );
                found = true;
                break;
            }
        }
        assertTrue(found, "YieldTransferCapped log not found or user mismatch");
    }

    // Helper function to generate yield in the real LendingManager
    function _generateYieldInLendingManager(uint256 targetYield) internal {
        console.log("--- _generateYieldInLendingManager ---");
        console.log("Target Yield to Generate: %d", targetYield);

        // 1. Ensure principal is deposited
        uint256 currentPrincipal = lendingManager.totalPrincipalDeposited();
        console.log("Current Principal in LM (before any new deposit): %d", currentPrincipal);
        if (currentPrincipal == 0) {
            uint256 principalAmount = 100 ether; // Default principal deposit
            console.log("No principal found, depositing: %d", principalAmount);
            vm.startPrank(DAI_WHALE);
            rewardToken.transfer(address(tokenVault), principalAmount);
            vm.stopPrank();

            vm.startPrank(address(tokenVault));
            rewardToken.approve(address(lendingManager), principalAmount);
            lendingManager.depositToLendingProtocol(principalAmount);
            vm.stopPrank();
            currentPrincipal = lendingManager.totalPrincipalDeposited(); // Update after deposit
            console.log("Deposited Principal now: %d", currentPrincipal);
        }

        uint256 cTokenBalanceOfLM = mockCToken.balanceOf(address(lendingManager));
        console.log("cToken Balance of LM: %d", cTokenBalanceOfLM);
        uint256 exchangeRateToSetInitially;

        if (cTokenBalanceOfLM == 0) {
            if (targetYield > 0) {
                console.log("Warning: LM cToken balance is 0, but targetYield > 0. Cannot use exchange rate for yield.");
            }
            exchangeRateToSetInitially = mockCToken.exchangeRateStored(); // Keep current rate
            console.log("LM cToken balance is 0. Keeping current ER: %d", exchangeRateToSetInitially);
            // Note: If cTokenBalanceOfLM is 0, LM.totalAssets() won't reflect cToken-based yield.
            // LM.availableYieldInProtocol() will be 0 unless LM has direct underlying balance (which it shouldn't from this helper).
        } else {
            // cTokenBalanceOfLM > 0
            uint256 finalTargetTotalUnderlying = currentPrincipal + targetYield;
            console.log("Final Target Total Underlying (Principal + TargetYield): %d", finalTargetTotalUnderlying);

            uint256 finalTargetExchangeRate = (finalTargetTotalUnderlying * 1e18) / cTokenBalanceOfLM;
            console.log("Calculated Final Target Exchange Rate (ER_final): %d", finalTargetExchangeRate);

            uint256 increment = mockCToken.accrualIncrement();
            console.log("MockCToken Accrual Increment: %d", increment);

            if (finalTargetExchangeRate > increment) {
                exchangeRateToSetInitially = finalTargetExchangeRate - increment;
            } else {
                exchangeRateToSetInitially = finalTargetExchangeRate; // Cannot pre-compensate fully.
                if (finalTargetExchangeRate > 0 && finalTargetExchangeRate <= increment) {
                    console.log(
                        "Log: ER_final (%d) <= increment (%d). Setting ER_initial to ER_final.",
                        finalTargetExchangeRate,
                        increment
                    );
                }
            }
            if (exchangeRateToSetInitially == 0 && (currentPrincipal > 0 || targetYield > 0)) {
                exchangeRateToSetInitially = 1; // Minimum positive rate
                console.log("ER_initial was calculated as 0, set to 1.");
            }
            console.log("Exchange Rate to Set Initially in MockCToken (ER_initial): %d", exchangeRateToSetInitially);
            mockCToken.setExchangeRate(exchangeRateToSetInitially);
            console.log(
                "MockCToken ER after setExchangeRate (should be ER_initial): %d", mockCToken.exchangeRateStored()
            );
        }

        // 3. Fund MockCToken so it can execute transferUnderlyingTo for the targetYield amount.
        vm.startPrank(DAI_WHALE);
        // Fund generously, enough for MockCToken to cover the targetYield if LM requests it.
        uint256 fundingForMockCToken = targetYield > 0 ? targetYield * 5 : (100 ether / 2);
        console.log("Funding MockCToken with underlying: %d", fundingForMockCToken);
        rewardToken.transfer(address(mockCToken), fundingForMockCToken);
        vm.stopPrank();

        // Log LM's perspective of available yield *before* the natural accrual that happens during a claim
        uint256 lmTotalAssetsBeforeImplicitAccrual = lendingManager.totalAssets(); // Uses ER_initial
        uint256 lmAvailableYieldBeforeImplicitAccrual = lmTotalAssetsBeforeImplicitAccrual > currentPrincipal
            ? lmTotalAssetsBeforeImplicitAccrual - currentPrincipal
            : 0;
        console.log(
            "LM availableYield (using ER_initial, BEFORE claim's accrual): %d (Assets: %d, Principal: %d)",
            lmAvailableYieldBeforeImplicitAccrual,
            lmTotalAssetsBeforeImplicitAccrual,
            currentPrincipal
        );

        // Additionally, the LendingManager contract itself needs to hold the actual rewardTokens representing the yield
        // that it is supposed to be able to transfer. This simulates the LM having realized/skimmed this yield.
        // This should happen *after* all exchange rate manipulations, as the LM's ability to transfer
        // is based on its actual token holdings, not just the cToken's state.
        if (targetYield > 0) {
            console.log("Dealing %d rewardToken to LendingManager contract", targetYield);
            deal(address(rewardToken), address(lendingManager), targetYield);
        }

        console.log("--- End _generateYieldInLendingManager ---");
    }
}
