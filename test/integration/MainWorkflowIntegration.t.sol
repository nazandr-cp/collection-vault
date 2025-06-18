// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../helpers/TestSetup.sol";
import {IDebtSubsidizer} from "../../src/interfaces/IDebtSubsidizer.sol";
import {IEpochManager} from "../../src/interfaces/IEpochManager.sol";
import {EpochManager} from "../../src/EpochManager.sol";

contract MainWorkflowIntegrationTest is TestSetup {
    struct WorkflowState {
        uint256 epochId;
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 availableYield;
        uint256 subsidiesDistributed;
        uint256 collection1Assets;
        uint256 collection2Assets;
    }

    event WorkflowPhaseCompleted(string phase, WorkflowState state);
    event SubsidyDistributed(address indexed user, uint256 amount, uint256 epochId);

    function setUp() public override {
        super.setUp();
        emit TestPhaseStarted("MainWorkflowIntegration", block.timestamp);
    }

    function test_CompleteWorkflow() public {
        WorkflowState memory initialState;
        WorkflowState memory currentState;

        // Phase 1: Initial Deposits
        emit TestPhaseStarted("Phase1_Deposits", block.timestamp);
        _executePhase1_Deposits();
        currentState = _captureState();
        emit WorkflowPhaseCompleted("Phase1_Deposits", currentState);
        _exportPhaseData("phase1-deposits.json", currentState);

        // Phase 2: Start Epoch and Generate Yield
        emit TestPhaseStarted("Phase2_EpochAndYield", block.timestamp);
        _executePhase2_EpochAndYield();
        currentState = _captureState();
        emit WorkflowPhaseCompleted("Phase2_EpochAndYield", currentState);
        _exportPhaseData("phase2-epoch-yield.json", currentState);

        // Phase 3: Simulate Borrowing Activity
        emit TestPhaseStarted("Phase3_BorrowingActivity", block.timestamp);
        _executePhase3_BorrowingActivity();
        currentState = _captureState();
        emit WorkflowPhaseCompleted("Phase3_BorrowingActivity", currentState);
        _exportPhaseData("phase3-borrowing.json", currentState);

        // Phase 4: Epoch Transition and Yield Allocation
        emit TestPhaseStarted("Phase4_EpochTransition", block.timestamp);
        _executePhase4_EpochTransition();
        currentState = _captureState();
        emit WorkflowPhaseCompleted("Phase4_EpochTransition", currentState);
        _exportPhaseData("phase4-epoch-transition.json", currentState);

        // Phase 5: Subsidy Distribution
        emit TestPhaseStarted("Phase5_SubsidyDistribution", block.timestamp);
        _executePhase5_SubsidyDistribution();
        currentState = _captureState();
        emit WorkflowPhaseCompleted("Phase5_SubsidyDistribution", currentState);
        _exportPhaseData("phase5-subsidy-distribution.json", currentState);

        // Final Verification
        emit TestPhaseStarted("FinalVerification", block.timestamp);
        _executePhase6_FinalVerification();
        currentState = _captureState();
        emit WorkflowPhaseCompleted("FinalVerification", currentState);
        _exportPhaseData("final-verification.json", currentState);

        emit TestPhaseCompleted("MainWorkflowIntegration", block.timestamp, true);
    }

    function _executePhase1_Deposits() internal {
        logTestState("Phase 1 - Initial Deposits");

        // Users deposit USDC into the vault for different collections
        depositForCollection(address(nftCollection1), 10_000e6, USER_1); // 10k USDC
        depositForCollection(address(nftCollection1), 5_000e6, USER_2); // 5k USDC
        depositForCollection(address(nftCollection2), 8_000e6, USER_2); // 8k USDC
        depositForCollection(address(nftCollection2), 7_000e6, USER_3); // 7k USDC

        // Verify deposits
        assertEq(getCollectionTotalAssets(address(nftCollection1)), 15_000e6, "Collection1 total assets incorrect");
        assertEq(getCollectionTotalAssets(address(nftCollection2)), 15_000e6, "Collection2 total assets incorrect");
        assertEq(collectionsVault.totalAssets(), 30_000e6, "Total vault assets incorrect");

        // Verify lending manager received funds
        assertGt(lendingManager.totalAssets(), 29_000e6, "LendingManager should have received deposits");
    }

    function _executePhase2_EpochAndYield() internal {
        logTestState("Phase 2 - Epoch and Yield");

        // Start a new epoch
        vm.prank(AUTOMATED_SYSTEM);
        epochManager.startNewEpoch();

        uint256 epochId = epochManager.getCurrentEpochId();
        assertEq(epochId, 1, "First epoch should have ID 1");

        // Simulate yield generation by setting higher exchange rate
        cUsdc.setExchangeRateForTesting(2.2e17); // 0.22 (was 0.2, 10% yield)

        // Update global deposit index to reflect yield
        vm.prank(ADMIN);
        collectionsVault.indexCollectionsDeposits();

        // Verify yield is available
        uint256 availableYield = getCurrentEpochYield();
        assertGt(availableYield, 2_000e6, "Should have generated yield");
    }

    function _executePhase3_BorrowingActivity() internal {
        logTestState("Phase 3 - Borrowing Activity");

        // Simulate borrowing activity to create debt that needs subsidies
        simulateBorrowing(BORROWER_1, 5_000e6);
        simulateBorrowing(BORROWER_2, 3_000e6);

        // Verify borrowing positions
        assertEq(cUsdc.borrowBalanceStored(BORROWER_1), 5_000e6, "Borrower1 balance incorrect");
        assertEq(cUsdc.borrowBalanceStored(BORROWER_2), 3_000e6, "Borrower2 balance incorrect");

        // Record borrow volume for collections (simulating collection-based borrowing)
        vm.startPrank(ADMIN);
        collectionsVault.recordCollectionBorrowVolume(address(nftCollection1), 5_000e6);
        collectionsVault.recordCollectionBorrowVolume(address(nftCollection2), 3_000e6);
        vm.stopPrank();
    }

    function _executePhase4_EpochTransition() internal {
        logTestState("Phase 4 - Epoch Transition");

        uint256 currentEpochId = epochManager.getCurrentEpochId();

        // Allocate yield to current epoch
        uint256 availableYield = getCurrentEpochYield();
        vm.prank(ADMIN);
        collectionsVault.allocateEpochYield(availableYield);

        // Advance time to end epoch
        vm.warp(block.timestamp + EPOCH_DURATION + 1);

        // Begin epoch processing
        vm.prank(AUTOMATED_SYSTEM);
        epochManager.beginEpochProcessing(currentEpochId);

        // Apply collection yield for the epoch
        vm.startPrank(ADMIN);
        collectionsVault.applyCollectionYieldForEpoch(address(nftCollection1), currentEpochId);
        collectionsVault.applyCollectionYieldForEpoch(address(nftCollection2), currentEpochId);
        vm.stopPrank();

        // Verify yield was distributed to collections based on their share percentages
        uint256 collection1NewAssets = getCollectionTotalAssets(address(nftCollection1));
        uint256 collection2NewAssets = getCollectionTotalAssets(address(nftCollection2));

        assertGt(collection1NewAssets, 15_000e6, "Collection1 should have received yield");
        assertGt(collection2NewAssets, 15_000e6, "Collection2 should have received yield");
    }

    function _executePhase5_SubsidyDistribution() internal {
        logTestState("Phase 5 - Subsidy Distribution");

        uint256 currentEpochId = epochManager.getCurrentEpochId();

        // Create mock merkle proofs for subsidy claims
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = keccak256("mock_proof_1");

        bytes32[] memory proof2 = new bytes32[](1);
        proof2[0] = keccak256("mock_proof_2");

        // Set up merkle root (simplified for testing)
        bytes32 mockRoot = keccak256(
            abi.encodePacked(
                keccak256(abi.encodePacked(BORROWER_1, uint256(1_000e6))),
                keccak256(abi.encodePacked(BORROWER_2, uint256(800e6)))
            )
        );

        vm.prank(ADMIN);
        debtSubsidizer.updateMerkleRoot(address(collectionsVault), mockRoot);

        // Add users as eligible
        vm.startPrank(ADMIN);
        debtSubsidizer.addEligibleUser(BORROWER_1);
        debtSubsidizer.addEligibleUser(BORROWER_2);
        vm.stopPrank();

        // Create claim data
        IDebtSubsidizer.ClaimData memory claim1 =
            IDebtSubsidizer.ClaimData({recipient: BORROWER_1, totalEarned: 1_000e6, merkleProof: proof1});

        IDebtSubsidizer.ClaimData memory claim2 =
            IDebtSubsidizer.ClaimData({recipient: BORROWER_2, totalEarned: 800e6, merkleProof: proof2});

        // Store borrower balances before subsidies
        uint256 borrower1BalanceBefore = cUsdc.borrowBalanceStored(BORROWER_1);
        uint256 borrower2BalanceBefore = cUsdc.borrowBalanceStored(BORROWER_2);

        // For testing purposes, we'll directly call repayBorrowBehalf to simulate subsidy distribution
        vm.startPrank(address(debtSubsidizer));
        collectionsVault.repayBorrowBehalf(1_000e6, BORROWER_1);
        collectionsVault.repayBorrowBehalf(800e6, BORROWER_2);
        vm.stopPrank();

        // Verify subsidies were applied
        uint256 borrower1BalanceAfter = cUsdc.borrowBalanceStored(BORROWER_1);
        uint256 borrower2BalanceAfter = cUsdc.borrowBalanceStored(BORROWER_2);

        assertEq(borrower1BalanceBefore - borrower1BalanceAfter, 1_000e6, "Borrower1 subsidy not applied");
        assertEq(borrower2BalanceBefore - borrower2BalanceAfter, 800e6, "Borrower2 subsidy not applied");

        emit SubsidyDistributed(BORROWER_1, 1_000e6, currentEpochId);
        emit SubsidyDistributed(BORROWER_2, 800e6, currentEpochId);
    }

    function _executePhase6_FinalVerification() internal {
        logTestState("Phase 6 - Final Verification");

        uint256 currentEpochId = epochManager.getCurrentEpochId();

        // Finalize the epoch
        vm.prank(AUTOMATED_SYSTEM);
        epochManager.finalizeEpoch(currentEpochId, 1_800e6); // 1k + 800 subsidies distributed

        // Verify epoch is completed
        (,,,,, EpochManager.EpochStatus status) = epochManager.getEpochDetails(currentEpochId);
        assertEq(uint256(status), uint256(EpochManager.EpochStatus.Completed), "Epoch should be completed");

        // Verify final state
        assertTrue(collectionsVault.totalAssets() > 30_000e6, "Vault should have grown from yield");
        assertTrue(debtSubsidizer.getTotalEligibleUsers() == 2, "Should have 2 eligible users");

        // Verify collection performance tracking
        assertGt(
            collectionsVault.getCollectionTotalBorrowVolume(address(nftCollection1)),
            0,
            "Collection1 should have borrow volume"
        );
        assertGt(
            collectionsVault.getCollectionTotalBorrowVolume(address(nftCollection2)),
            0,
            "Collection2 should have borrow volume"
        );
    }

    function _captureState() internal view returns (WorkflowState memory state) {
        state.epochId = epochManager.getCurrentEpochId();
        state.totalDeposited = collectionsVault.totalAssets();
        state.totalBorrowed = cUsdc.getTotalBorrowsForTesting();
        state.availableYield = getCurrentEpochYield();
        state.collection1Assets = getCollectionTotalAssets(address(nftCollection1));
        state.collection2Assets = getCollectionTotalAssets(address(nftCollection2));

        if (state.epochId > 0) {
            (,,,, state.subsidiesDistributed,) = epochManager.getEpochDetails(state.epochId);
        }
    }

    function _exportPhaseData(string memory fileName, WorkflowState memory state) internal {
        string memory data = string(
            abi.encodePacked(
                "{\n",
                '  "epochId": ',
                vm.toString(state.epochId),
                ",\n",
                '  "totalDeposited": ',
                vm.toString(state.totalDeposited),
                ",\n",
                '  "totalBorrowed": ',
                vm.toString(state.totalBorrowed),
                ",\n",
                '  "availableYield": ',
                vm.toString(state.availableYield),
                ",\n",
                '  "subsidiesDistributed": ',
                vm.toString(state.subsidiesDistributed),
                ",\n",
                '  "collection1Assets": ',
                vm.toString(state.collection1Assets),
                ",\n",
                '  "collection2Assets": ',
                vm.toString(state.collection2Assets),
                ",\n",
                '  "timestamp": ',
                vm.toString(block.timestamp),
                "\n",
                "}"
            )
        );

        emit TestDataExported(fileName, data);
        vm.writeFile(string(abi.encodePacked("test-exports/", fileName)), data);
    }

    function test_StateVerification() public {
        assertTrue(verifyContractDeployment(), "Contracts not properly deployed");
        assertTrue(verifyInitialBalances(), "Initial balances incorrect");
    }

    function test_BackendIntegrationDataExport() public {
        // Export comprehensive integration data for backend tests
        string memory integrationData = string(
            abi.encodePacked(
                "{\n",
                '  "testAccounts": {\n',
                '    "admin": "',
                vm.toString(ADMIN),
                '",\n',
                '    "user1": "',
                vm.toString(USER_1),
                '",\n',
                '    "user2": "',
                vm.toString(USER_2),
                '",\n',
                '    "borrower1": "',
                vm.toString(BORROWER_1),
                '",\n',
                '    "automatedSystem": "',
                vm.toString(AUTOMATED_SYSTEM),
                '"\n',
                "  },\n",
                '  "testConstants": {\n',
                '    "epochDuration": ',
                vm.toString(EPOCH_DURATION),
                ",\n",
                '    "initialSupply": ',
                vm.toString(INITIAL_SUPPLY),
                ",\n",
                '    "initialExchangeRate": ',
                vm.toString(INITIAL_EXCHANGE_RATE),
                "\n",
                "  }\n",
                "}"
            )
        );

        emit TestDataExported("backend-integration.json", integrationData);
        vm.writeFile("test-exports/backend-integration.json", integrationData);
    }
}
