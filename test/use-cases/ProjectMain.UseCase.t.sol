// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
// Use OpenZeppelin's IERC20 interface for compatibility with the Vault's asset type
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// Import Compound V2 interfaces for interacting with cTokens and the Comptroller
import {CTokenInterface, CErc20Interface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {ComptrollerInterface} from "compound-protocol-2.8.1/contracts/ComptrollerInterface.sol";
// Import OpenZeppelin proxy contracts for upgradeability
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// ProxyAdmin import removed as we use the internal proxy admin feature of TransparentUpgradeableProxy

// Import Project Contracts being tested or interacted with
import {ERC4626Vault} from "../../src/ERC4626Vault.sol";
import {LendingManager} from "../../src/LendingManager.sol";
import {RewardsController} from "../../src/RewardsController.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol"; // Interface for type casting and clarity

/**
 * @title ProjectMainUseCaseTest
 * @notice End-to-end integration test for the core deposit, reward accrual/claim, and withdrawal flow.
 * @dev This test forks Mainnet to interact with real Compound V2 contracts (DAI/cDAI).
 *      It deploys the Vault, LendingManager, and RewardsController (behind a proxy),
 *      configures roles and settings, simulates user actions (deposit, claim, withdraw),
 *      and verifies the state changes and balances at each step.
 *      It also tests the NFT reward boost mechanism by simulating signed balance updates.
 */
contract ProjectMainUseCaseTest is Test {
    // --- Constants ---
    // Mainnet Addresses for Forking
    address internal constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // Underlying asset
    address internal constant CDAI_ADDRESS = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643; // Compound cToken for DAI
    address internal constant COMPTROLLER_ADDRESS = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B; // Compound Comptroller
    address internal constant COMP_ADDRESS = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP Token (Reference only, not used for rewards in this setup)
    // Mock/Test Specific Addresses & Values
    address internal constant MOCK_NFT_COLLECTION = address(0xdead); // Placeholder address for a simulated NFT collection
    uint256 internal constant NFT_BETA = 0.1 * 1e18; // Example reward boost: 10% bonus per NFT held in the collection

    // --- State Variables ---
    // External Contract Interfaces (Mainnet Fork)
    IERC20 internal dai; // Interface for the underlying DAI token
    CTokenInterface internal cDai; // Interface for the cDAI token (includes functions like balanceOfUnderlying, accrueInterest)
    ComptrollerInterface internal comptroller; // Interface for the Compound Comptroller (not directly used in this test flow but available)
    // IERC20 internal comp; // Removed as project rewards are configured in DAI

    // Project Contract Instances
    ERC4626Vault internal vault; // The ERC4626 Vault instance
    LendingManager internal lendingManager; // The Lending Manager instance
    RewardsController internal rewardsController; // The Rewards Controller instance (points to the proxy address)
    // ProxyAdmin internal proxyAdmin; // Removed - Using internal admin feature of TransparentUpgradeableProxy

    // User & Role Addresses
    address internal user = address(0x1); // A simulated user address for testing interactions
    address internal admin; // Address designated as the admin/owner for project contracts (set to this test contract)
    address internal authorizedUpdater; // Address authorized to submit signed balance updates to RewardsController
    uint256 internal authorizedUpdaterPrivateKey = 0xbeef; // Private key corresponding to the authorizedUpdater address (for signing)

    /**
     * @notice Sets up the test environment by forking Mainnet and deploying contracts.
     * @dev 1. Forks Mainnet at a specified block number.
     *      2. Initializes interfaces for external Mainnet contracts (DAI, cDAI, Comptroller).
     *      3. Sets up admin and authorized updater addresses.
     *      4. Deploys LendingManager.
     *      5. Deploys ERC4626Vault, linking it to the LendingManager.
     *      6. Deploys RewardsController implementation and a TransparentUpgradeableProxy, initializing the controller.
     *      7. Grants necessary roles (VAULT_ROLE, REWARDS_CONTROLLER_ROLE) from LendingManager to the Vault and RC Proxy.
     *      8. Whitelists the mock NFT collection in the RewardsController.
     *      9. Deals initial DAI balance to the test user.
     */
    function setUp() public {
        console.log("--- Starting Test Setup ---");

        // --- Fork Mainnet ---
        console.log("Forking Mainnet...");
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 FORK_BLOCK_NUMBER = vm.envOr("FORK_BLOCK_NUMBER", uint256(19000000)); // Default to block 19,000,000 if not set
        require(bytes(MAINNET_RPC_URL).length > 0, "Setup Error: MAINNET_RPC_URL environment variable not set.");
        vm.createSelectFork(MAINNET_RPC_URL, FORK_BLOCK_NUMBER);
        console.log("Fork created from RPC:", MAINNET_RPC_URL);
        console.log("Fork Block Number:", FORK_BLOCK_NUMBER);
        console.log("Current Block Number after fork:", block.number);
        console.log("Current Chain ID:", block.chainid);

        // --- Initialize External Contract Interfaces ---
        console.log("Initializing external contract interfaces...");
        dai = IERC20(DAI_ADDRESS);
        cDai = CTokenInterface(CDAI_ADDRESS);
        comptroller = ComptrollerInterface(COMPTROLLER_ADDRESS);
        console.log("DAI Interface initialized at:", DAI_ADDRESS);
        console.log("cDAI Interface initialized at:", CDAI_ADDRESS);
        console.log("Comptroller Interface initialized at:", COMPTROLLER_ADDRESS);

        // --- Setup Roles ---
        admin = address(this); // This test contract acts as the admin for deployed contracts
        authorizedUpdater = vm.addr(authorizedUpdaterPrivateKey); // Derive address from the private key
        console.log("Admin Address (Test Contract):", admin);
        console.log("Authorized Updater Address:", authorizedUpdater);
        console.log("Authorized Updater Private Key:", authorizedUpdaterPrivateKey); // Be cautious logging private keys, ok in local test

        // --- Deployment & Configuration Sequence ---
        // Step 1: Deploy LendingManager
        // Initially deployed with placeholder addresses for Vault and RC, roles granted later.
        console.log("Deploying LendingManager...");
        lendingManager = new LendingManager(admin, address(this), address(this), DAI_ADDRESS, CDAI_ADDRESS);
        console.log("LendingManager deployed at:", address(lendingManager));

        // Step 2: Deploy ERC4626Vault
        // Links the Vault to the underlying DAI token and the deployed LendingManager.
        console.log("Deploying ERC4626Vault...");
        vault = new ERC4626Vault(dai, "Vault Token", "VT", admin, address(lendingManager));
        console.log("ERC4626Vault deployed at:", address(vault));
        console.log("Vault Name:", vault.name());
        console.log("Vault Symbol:", vault.symbol());
        console.log("Vault Asset (DAI): %s", vault.asset());
        // console.log("Vault Lending Manager: %s", vault.lendingManager());

        // Step 3: Deploy RewardsController (Implementation + Proxy)
        // Deploys the logic contract and a proxy pointing to it, then initializes the proxied contract.
        console.log("Deploying RewardsController Implementation...");
        RewardsController rcImpl = new RewardsController();
        console.log("RewardsController Implementation deployed at:", address(rcImpl));
        // Prepare initialization data for the RewardsController's initializer function
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            admin, // `initialOwner` for RewardsController's OwnableUpgradeable
            address(lendingManager), // Link to LendingManager
            address(vault), // Link to Vault
            authorizedUpdater // Set the initial authorized updater address
        );
        console.log("Deploying TransparentUpgradeableProxy for RewardsController...");
        // Deploy the proxy, setting this test contract (`admin`) as the proxy admin.
        TransparentUpgradeableProxy rcProxy = new TransparentUpgradeableProxy(address(rcImpl), admin, initData);
        // Point the `rewardsController` variable to the proxy's address for interaction.
        rewardsController = RewardsController(payable(address(rcProxy)));
        console.log("RewardsController Proxy deployed at:", address(rewardsController));
        console.log("RewardsController Proxy Admin:", admin); // Confirms test contract is proxy admin
        // Verify initialization parameters were set correctly via proxy
        assertEq(rewardsController.owner(), admin, "RC Initial Owner mismatch");
        assertEq(address(rewardsController.lendingManager()), address(lendingManager), "RC LendingManager mismatch"); // Explicitly cast return value and added message back
        assertEq(address(rewardsController.vault()), address(vault), "RC Vault mismatch"); // Explicitly cast return value
        // assertTrue(rewardsController.isAuthorizedUpdater(authorizedUpdater), "RC Authorized Updater mismatch"); // Function might not be public
        console.log("RewardsController initialization verified via proxy.");

        // Step 4: Grant Roles in LendingManager
        // Now that Vault and RC Proxy exist, grant them the necessary roles in LendingManager.
        console.log("Granting roles in LendingManager...");
        // Grant VAULT_ROLE to the deployed Vault contract. Requires admin privileges.
        console.log("Granting VAULT_ROLE to Vault:", address(vault));
        vm.prank(admin); // Simulate the call coming from the admin address
        lendingManager.grantVaultRole(address(vault));
        assertTrue(lendingManager.hasRole(lendingManager.VAULT_ROLE(), address(vault)), "Vault role grant failed");
        console.log("VAULT_ROLE granted.");
        // Grant REWARDS_CONTROLLER_ROLE to the deployed RewardsController proxy address. Requires admin privileges.
        console.log("Granting REWARDS_CONTROLLER_ROLE to RewardsController Proxy:", address(rewardsController));
        vm.prank(admin); // Simulate the call coming from the admin address
        lendingManager.grantRewardsControllerRole(address(rewardsController));
        assertTrue(
            lendingManager.hasRole(lendingManager.REWARDS_CONTROLLER_ROLE(), address(rewardsController)),
            "Rewards Controller role grant failed"
        );
        console.log("REWARDS_CONTROLLER_ROLE granted.");

        // Step 5: Whitelist NFT Collection in RewardsController
        // Configure the RewardsController to recognize the mock NFT collection and its associated reward beta.
        console.log("Whitelisting Mock NFT Collection in RewardsController...");
        console.log("Collection Address:", MOCK_NFT_COLLECTION);
        console.log("Collection Beta:", NFT_BETA);
        vm.prank(admin); // Only the owner (admin) can add collections
        rewardsController.addNFTCollection(MOCK_NFT_COLLECTION, NFT_BETA, IRewardsController.RewardBasis.DEPOSIT); // Corrected RewardBasis
        // Verify the collection was added correctly
        assertEq(
            rewardsController.getCollectionBeta(MOCK_NFT_COLLECTION), NFT_BETA, "NFT Beta mismatch after whitelisting"
        );
        assertTrue(rewardsController.isCollectionWhitelisted(MOCK_NFT_COLLECTION), "NFT Collection not whitelisted");
        console.log("Mock NFT Collection whitelisted successfully.");

        // --- Initial User State ---
        // Provide the test user with starting capital (DAI).
        uint256 initialDaiAmount = 10000 * 1e18; // 10,000 DAI
        console.log("Dealing initial DAI to user address:", user);
        console.log("Amount:", initialDaiAmount);
        deal(DAI_ADDRESS, user, initialDaiAmount); // Use Foundry cheatcode to set user's DAI balance
        assertEq(dai.balanceOf(user), initialDaiAmount, "Initial DAI balance mismatch for user after deal");
        console.log("User initial DAI balance confirmed:", dai.balanceOf(user));
        console.log("--- Test Setup Complete ---");
    }

    // --- Hashing Logic Replication ---
    // This section replicates the EIP-712 hashing logic used within the RewardsController
    // contract. This is necessary for the test environment to generate valid signatures
    // that the RewardsController can verify when processing balance updates from the authorized updater.

    // EIP-712 type hash for the BalanceUpdateData struct, matching the definition in RewardsController.
    bytes32 internal constant BALANCE_UPDATE_DATA_TYPEHASH =
        keccak256("BalanceUpdateData(address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)");

    // EIP-712 type hash for the UserBalanceUpdates struct, matching the definition in RewardsController.
    bytes32 internal constant USER_BALANCE_UPDATES_TYPEHASH =
        keccak256("UserBalanceUpdates(address user,BalanceUpdateData[] updates,uint256 nonce)");

    /**
     * @notice Hashes an array of BalanceUpdateData structs according to EIP-712 struct hashing rules.
     * @dev This function is used to compute the `updatesHash` part of the UserBalanceUpdates struct hash.
     * @param updates The array of balance updates to hash.
     * @return The keccak256 hash of the tightly packed encoded update structs.
     */
    function _hashBalanceUpdates(IRewardsController.BalanceUpdateData[] memory updates)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory encodedUpdates = new bytes32[](updates.length);
        // console.log("Hashing BalanceUpdateData array (length %s):", updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            // Encode each struct using its specific type hash and parameters
            encodedUpdates[i] = keccak256(
                abi.encode(
                    BALANCE_UPDATE_DATA_TYPEHASH,
                    updates[i].collection,
                    updates[i].blockNumber,
                    updates[i].nftDelta,
                    updates[i].balanceDelta
                )
            );
            // console.log("  - Hashed update %s: %s", i, encodedUpdates[i]);
        }
        // Return the hash of the packed array of individual struct hashes
        bytes32 finalHash = keccak256(abi.encodePacked(encodedUpdates));
        // console.log("Final hash of updates array:", finalHash);
        return finalHash;
    }

    /**
     * @notice Constructs the final EIP-712 typed data hash (digest) to be signed.
     * @dev Replicates the logic of `EIP712._hashTypedDataV4`. It combines the EIP-712 domain separator
     *      of the RewardsController contract with the hash of the specific `UserBalanceUpdates` struct instance.
     *      The domain separator ensures the signature is valid only for the intended contract and chain.
     * @param structHash The hash of the `UserBalanceUpdates` structured data (`keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, ...))`).
     * @return The final EIP-712 digest (32 bytes) that needs to be signed by the authorized updater.
     */
    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        // console.log("Constructing EIP-712 Digest (hashTypedDataV4)...");
        // console.log("Input Struct Hash:", structHash);

        // Reconstruct the EIP-712 Domain Separator based on RewardsController's expected initialization.
        // Assumed Name: "RewardsController", Version: "1" (Must match the values used in RewardsController's __EIP712_init)
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256(bytes("RewardsController"));
        bytes32 versionHash = keccak256(bytes("1"));
        uint256 chainId = block.chainid; // Get the current chain ID from the forked environment
        address verifyingContract = address(rewardsController); // The address of the contract that will verify the signature

        // Calculate the domain separator
        bytes32 domainSeparator = keccak256(abi.encode(typeHash, nameHash, versionHash, chainId, verifyingContract));
        // console.log("Calculated Domain Separator Components:");
        // console.log("  TypeHash:", typeHash);
        // console.log("  NameHash:", nameHash);
        // console.log("  VersionHash:", versionHash);
        // console.log("  ChainID:", chainId);
        // console.log("  Verifying Contract:", verifyingContract);
        // console.log("Calculated Domain Separator:", domainSeparator);

        // Combine the domain separator and struct hash according to the EIP-712 standard:
        // digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash))
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        // console.log("Final EIP-712 Digest:", digest);
        return digest;
    }
    /**
     * @notice Tests the core user flow: deposit DAI, process NFT balance update, accrue interest/rewards, claim rewards, withdraw DAI.
     * @dev Covers interactions between User, Vault, LendingManager, RewardsController, and Compound (cDAI).
     */

    function testEndToEndDepositRewardWithdrawFlow() public {
        console.log("\n--- Starting testEndToEndDepositRewardWithdrawFlow ---");
        uint256 userInitialDai = dai.balanceOf(user);
        uint256 daiToDeposit = 1000 * 1e18; // User intends to deposit 1,000 DAI
        console.log("Test User:", user);
        console.log("Initial User DAI Balance:", userInitialDai);
        console.log("Intended Deposit Amount: ", daiToDeposit);

        // ======================================
        // === Step 1 & 2: User Deposit Flow ===
        // ======================================
        console.log("\n--- Step 1 & 2: User Approves Vault and Deposits DAI ---");
        vm.startPrank(user); // Simulate subsequent calls originating from the user address

        // 1. User approves the Vault contract to transfer `daiToDeposit` of their DAI.
        console.log("User approving Vault (%s) to spend %s DAI...", address(vault), daiToDeposit);
        dai.approve(address(vault), daiToDeposit);
        // Verification: Check the allowance set by the user for the vault.
        uint256 allowance = dai.allowance(user, address(vault));
        assertEq(allowance, daiToDeposit, "Vault DAI allowance check failed after approval");
        console.log("Vault DAI allowance confirmed:", allowance);

        // 2. User deposits DAI into the Vault.
        // The Vault should transfer the DAI, interact with LendingManager, which deposits into Compound,
        // and mint Vault shares back to the user.
        console.log("User calling vault.deposit(%s DAI, to user %s)...", daiToDeposit, user);
        uint256 sharesMinted = vault.deposit(daiToDeposit, user);
        uint256 depositBlock = block.number; // Record the block number when the deposit occurred.
        console.log("vault.deposit() executed at block:", depositBlock);
        assertTrue(sharesMinted > 0, "Deposit should mint a non-zero amount of vault shares");
        console.log("Vault Shares Minted to User:", sharesMinted);

        // --- Post-Deposit Assertions ---
        console.log("Verifying state changes after deposit...");
        // User's DAI balance should decrease by the deposit amount.
        assertEq(dai.balanceOf(user), userInitialDai - daiToDeposit, "User DAI balance incorrect after deposit");
        console.log("User DAI Balance After Deposit:", dai.balanceOf(user));
        // User's Vault share balance should equal the shares minted.
        assertEq(vault.balanceOf(user), sharesMinted, "User vault share balance incorrect after deposit");
        console.log("User Vault Share Balance:", vault.balanceOf(user));
        // Vault's total underlying assets should approximately equal the deposit amount immediately after.
        // Use approximate check due to potential minor rounding or pre-existing dust in LM/Compound.
        assertApproxEqAbs(
            vault.totalAssets(),
            daiToDeposit,
            1e12, // Tolerance of 1e12 wei (0.000001 DAI)
            "Vault total assets should approx equal deposit amount immediately after deposit"
        );
        console.log("Vault Total Assets:", vault.totalAssets());
        // LendingManager should have deposited the underlying DAI into Compound (cDAI).
        uint256 compoundUnderlying = cDai.balanceOfUnderlying(address(lendingManager));
        assertApproxEqAbs(
            compoundUnderlying,
            daiToDeposit,
            1e12, // Tolerance
            "LendingManager underlying balance in Compound mismatch after deposit"
        );
        console.log("LendingManager Underlying Balance (cDAI):", compoundUnderlying);
        // Neither Vault nor LendingManager should hold raw DAI after the deposit is processed.
        assertEq(dai.balanceOf(address(lendingManager)), 0, "LendingManager should not hold raw DAI after deposit");
        assertEq(dai.balanceOf(address(vault)), 0, "Vault should not hold raw DAI after deposit");
        console.log("Post-deposit state verified successfully.");

        vm.stopPrank(); // Stop simulating calls from the user address

        // =======================================================================
        // === Step 3: Process Signed Balance Update (Simulate NFT Holding) ===
        // =======================================================================
        console.log("\n--- Step 3: Process Signed Balance Update (Simulating NFT Holding & Deposit) ---");
        // This simulates an off-chain service observing the user's deposit and NFT holdings,
        // then submitting a signed update to the RewardsController via the authorized updater.

        // 3a. Prepare Balance Update Data structure array.
        // This update reflects the deposit event and assumes the user holds 2 NFTs from the whitelisted collection.
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: MOCK_NFT_COLLECTION, // The relevant NFT collection
            blockNumber: depositBlock, // Block number associated with the event (the deposit)
            nftDelta: 2, // Change in user's NFT balance for this collection (+2 implies they now hold 2)
            balanceDelta: int256(daiToDeposit) // Corrected field name
        });
        console.log("Prepared Balance Update Data [0]:");
        console.log("  Collection:", updates[0].collection);
        console.log("  Block Number:", updates[0].blockNumber);
        console.log("  NFT Delta:", updates[0].nftDelta);
        console.log("  Balance Delta:", updates[0].balanceDelta);

        // 3b. Generate the EIP-712 Signature for the update payload.
        console.log("Generating EIP-712 signature for the balance update...");
        uint256 nonce = rewardsController.authorizedUpdaterNonce(authorizedUpdater); // Get the current nonce for the signer
        console.log("Current Nonce for Authorized Updater (%s): %s", authorizedUpdater, nonce);
        bytes32 updatesHash = _hashBalanceUpdates(updates); // Hash the array of update structs
        console.log("Hashed Updates Array:"); // Log string separately
        console.logBytes32(updatesHash); // Log bytes32 value
        // Create the hash of the main UserBalanceUpdates struct
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
        console.log("UserBalanceUpdates Struct Hash:"); // Log string separately
        console.logBytes32(structHash); // Log bytes32 value
        // Create the final EIP-712 digest using the contract's domain separator
        bytes32 digest = _hashTypedDataV4(structHash);
        console.log("EIP-712 Digest to Sign:"); // Log string separately
        console.logBytes32(digest); // Log bytes32 value
        // Sign the digest using the authorized updater's private key (Foundry cheatcode)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizedUpdaterPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v); // Concatenate signature components (r, s, v)
        console.log("Generated Signature Components (v, r, s):");
        console.log("  v:", v); // Log uint8
        console.logBytes32(r); // Log bytes32
        console.logBytes32(s); // Log bytes32

        // 3c. Submit the Signed Balance Update to the RewardsController.
        // This call can be made by any address, but the signature proves authorization.
        console.log("Submitting signed balance update to RewardsController.processUserBalanceUpdates()...");
        rewardsController.processUserBalanceUpdates(authorizedUpdater, user, updates, signature);
        console.log("Balance update processed successfully by RewardsController.");
        // Verification: Check that the nonce for the authorized updater has incremented.
        uint256 newNonce = rewardsController.authorizedUpdaterNonce(authorizedUpdater);
        assertEq(newNonce, nonce + 1, "Nonce did not increment after processing update");
        console.log("Nonce increment confirmed. New Nonce:", newNonce);
        // Optional: Add checks for internal RewardsController state if view functions exist
        // e.g., assertEq(rewardsController.getUserNftBalance(user, MOCK_NFT_COLLECTION), 2, "User NFT balance mismatch");
        // e.g., assertEq(rewardsController.getUserDepositBalance(user), depositAmount, "User deposit balance mismatch");

        // =================================================
        // === Step 4: Advance Time & Accrue Interest ===
        // =================================================
        console.log("\n--- Step 4: Advance Time and Trigger Compound Interest Accrual ---");
        uint256 blocksToAdvance = 1000; // Simulate the passage of ~2.5 hours on Ethereum Mainnet
        uint256 startBlock = block.number;
        console.log("Current block number:", startBlock);
        console.log("Advancing time by rolling forward", blocksToAdvance, "blocks...");
        vm.roll(startBlock + blocksToAdvance); // Use Foundry cheatcode to advance the block number
        console.log("New block number:", block.number);

        // Manually trigger Compound's interest accrual for the cDAI market.
        // In a real network, this happens periodically or on interactions, but in tests, we trigger it explicitly.
        // This updates the cDAI exchange rate, reflecting earned interest.
        console.log("Triggering Compound interest accrual for cDAI market via cDai.accrueInterest()...");
        uint256 accrueInterestResult = cDai.accrueInterest(); // Returns an error code (0 for success)
        assertEq(accrueInterestResult, 0, "cDai.accrueInterest() failed");
        console.log("Compound interest accrued successfully (returned 0).");

        // Verification: Check that the Vault's total underlying assets have increased due to the accrued interest.
        uint256 assetsAfterInterest = vault.totalAssets();
        console.log("Vault Total Assets After Interest Accrual:", assetsAfterInterest);
        // The assets should now be greater than the initial deposit amount.
        assertTrue(assetsAfterInterest > daiToDeposit, "Vault total assets should increase due to accrued interest");
        console.log("Confirmed Vault assets increased. Increase:", assetsAfterInterest - daiToDeposit);

        // ==================================
        // === Step 5: User Claim Rewards ===
        // ==================================
        console.log("\n--- Step 5: User Claims Accumulated Rewards ---");
        // The user should have accrued DAI rewards based on their deposit duration, amount,
        // and the NFT boost factor applied due to the processed balance update.
        uint256 daiBeforeClaim = dai.balanceOf(user);
        console.log("User DAI Balance Before Claiming Rewards:", daiBeforeClaim);
        vm.startPrank(user); // Simulate transaction from the user
        console.log("User calling rewardsController.claimRewardsForAll()...");
        // This function calculates and transfers rewards for all collections the user has interacted with.
        rewardsController.claimRewardsForAll();
        vm.stopPrank();
        console.log("rewardsController.claimRewardsForAll() executed.");

        // Verification: Check the user's DAI balance increased.
        uint256 daiAfterClaim = dai.balanceOf(user);
        uint256 daiClaimed = daiAfterClaim - daiBeforeClaim;
        console.log("User DAI Balance After Claiming Rewards:", daiAfterClaim);
        console.log("Total DAI Rewards Claimed:", daiClaimed);
        // Since time advanced and an NFT boost was applied, rewards should be greater than zero.
        assertTrue(
            daiClaimed > 0, "User should have claimed non-zero DAI rewards due to deposit, time passage, and NFT bonus"
        );
        console.log("Confirmed positive DAI rewards were claimed.");

        // ===================================
        // === Step 6: User Withdraw Flow ===
        // ===================================
        console.log("\n--- Step 6: User Withdraws Full Deposit + Interest ---");
        vm.startPrank(user); // Simulate subsequent calls originating from the user address

        // 6a. User decides to redeem all their Vault shares.
        uint256 sharesToRedeem = vault.balanceOf(user); // Get user's current share balance
        console.log("User redeeming all Vault shares:", sharesToRedeem);
        assertTrue(sharesToRedeem > 0, "User should have shares to redeem");

        // 6b. Preview the expected DAI amount for redeeming shares.
        // This uses the current exchange rate (including accrued interest).
        uint256 expectedDaiOutPreview = vault.previewRedeem(sharesToRedeem);
        console.log("Previewed DAI out on redeem (using vault.previewRedeem):", expectedDaiOutPreview);
        // Expected output should be greater than the initial deposit due to interest.
        assertTrue(
            expectedDaiOutPreview >= daiToDeposit,
            "Expected DAI out from preview should be >= deposit amount due to interest (or equal if no interest)"
        );

        // --- Log Balances Before Redeem ---
        console.log("--- Balances Immediately Before Redeem Call ---");
        console.log("User DAI Balance (incl. claimed rewards):", dai.balanceOf(user));
        console.log("User Vault Shares:", vault.balanceOf(user));
        console.log("Vault Total Assets:", vault.totalAssets());
        console.log("LM Underlying Balance (cDAI):", cDai.balanceOfUnderlying(address(lendingManager)));
        console.log("Vault Raw DAI Balance:", dai.balanceOf(address(vault))); // Should be 0 or dust
        console.log("LM Raw DAI Balance:", dai.balanceOf(address(lendingManager))); // Should be 0 or dust

        // 6c. Execute the redeem operation.
        // User redeems `sharesToRedeem`, requesting the underlying DAI be sent back to `user`.
        console.log(
            "--- Executing vault.redeem(%s shares, to receiver %s, from owner %s) ---", sharesToRedeem, user, user
        );
        uint256 daiWithdrawn = vault.redeem(sharesToRedeem, user, user);
        console.log("--- vault.redeem() Call Completed ---");
        console.log("DAI amount returned by redeem() call:", daiWithdrawn);

        // --- Post-Redeem Assertions & Checks ---
        console.log("\n--- Verifying State After Full Redeem ---");
        uint256 userFinalDaiAfterWithdraw = dai.balanceOf(user);
        console.log("Final User DAI Balance After Withdraw:", userFinalDaiAfterWithdraw);

        // Calculate the actual net DAI transferred to the user during this withdraw operation.
        uint256 netDaiWithdrawn = userFinalDaiAfterWithdraw - daiAfterClaim; // Compare to balance *after* claim
        console.log("Actual Net DAI Transferred to User during Withdraw:", netDaiWithdrawn);

        // Check 1: User's Vault share balance should now be zero.
        assertEq(vault.balanceOf(user), 0, "User vault share balance should be 0 after full redeem");
        console.log("User Vault share balance confirmed to be 0.");

        // Check 2: The actual DAI transferred should match the value returned by the redeem function.
        // Use assertApproxEqAbs for robustness against potential 1 wei rounding differences.
        assertApproxEqAbs(
            netDaiWithdrawn,
            daiWithdrawn,
            1, // Allow 1 wei difference
            "Actual DAI transferred to user does not match redeem() return value (allowing 1 wei diff)"
        );
        console.log("Actual DAI transferred matches redeem() return value (within 1 wei).");

        // Check 3: Vault and LendingManager underlying balances should be effectively zero after full withdrawal.
        // Use assertLt with a small threshold (e.g., 1e6 wei = 0.000000000001 DAI) to account for potential dust.
        uint256 vaultAssetsFinal = vault.totalAssets();
        uint256 lmUnderlyingFinal = cDai.balanceOfUnderlying(address(lendingManager));
        console.log("Final Vault Total Assets:", vaultAssetsFinal);
        console.log("Final LM Underlying Balance (cDAI):", lmUnderlyingFinal);
        assertLt(vaultAssetsFinal, 1e6, "Vault total assets should be near 0 (less than 1e6 wei) after full redeem");
        assertLt(
            lmUnderlyingFinal,
            1e6,
            "LendingManager underlying balance should be near 0 (less than 1e6 wei) after full redeem"
        );
        console.log("Vault and LM underlying balances confirmed near zero.");

        vm.stopPrank(); // Stop simulating calls from the user address

        // ==============================================
        // === Final User Balance Consistency Check ===
        // ==============================================
        console.log("\n--- Final User Balance Consistency Check ---");
        // Verify the user's final DAI balance aligns with all operations performed during the test.
        // Formula: Initial Balance - Deposit Amount + Rewards Claimed + Amount Withdrawn == Final Balance
        uint256 expectedFinalUserDai = userInitialDai - daiToDeposit + daiClaimed + netDaiWithdrawn;
        console.log("Calculation Breakdown:");
        console.log("  Initial User DAI:", userInitialDai);
        console.log("  (-) Deposit Amount:", daiToDeposit);
        console.log("  (+) Rewards Claimed:", daiClaimed);
        console.log("  (+) Amount Withdrawn (Net):", netDaiWithdrawn);
        console.log("  = Expected Final User DAI:", expectedFinalUserDai);
        console.log("Actual Final User DAI:", userFinalDaiAfterWithdraw);

        // Use assertApproxEqAbs again to allow for minor cumulative rounding differences (1 wei).
        assertApproxEqAbs(
            expectedFinalUserDai,
            userFinalDaiAfterWithdraw,
            1, // Allow 1 wei difference overall
            "User final DAI balance does not match the expected value after all operations (within 1 wei)"
        );
        console.log("User final DAI balance consistency check passed.");
        console.log("--- testEndToEndDepositRewardWithdrawFlow Completed Successfully ---");
    }
}
