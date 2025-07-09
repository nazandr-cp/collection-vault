// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IDebtSubsidizer} from "../src/interfaces/IDebtSubsidizer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ClaimSubsidy is Script {
    function run() external {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address debtSubsidizerAddress = vm.envAddress("DEBT_SUBSIDIZER_ADDRESS");
        address cTokenAddress = vm.envAddress("CTOKEN_ADDRESS");

        address user2 = vm.envAddress("USER2");
        uint256 user2Key = vm.envUint("USER2_PRIVATE_KEY");
        uint256 user2TotalEarned = vm.envUint("USER2_TOTAL_EARNED");
        address user3 = vm.envAddress("USER3");
        uint256 user3Key = vm.envUint("USER3_PRIVATE_KEY");
        uint256 user3TotalEarned = vm.envUint("USER3_TOTAL_EARNED");

        IDebtSubsidizer debtSubsidizer = IDebtSubsidizer(debtSubsidizerAddress);
        IERC20 cToken = IERC20(cTokenAddress);

        console.log("=== Claiming Subsidies ===");
        console.log("Vault Address:", vaultAddress);
        console.log("DebtSubsidizer Address:", debtSubsidizerAddress);
        console.log("USER2:", user2);
        console.log("USER3:", user3);

        console.log("\n== USER2 Claiming Subsidy ==");

        uint256 user2BorrowBefore = cToken.balanceOf(user2);
        console.log("USER2 borrow balance before claim:", user2BorrowBefore);
        console.log("USER2 total earned to claim:", user2TotalEarned);

        vm.startBroadcast(user2Key);

        IDebtSubsidizer.ClaimData memory user2Claim = IDebtSubsidizer.ClaimData({
            recipient: user2,
            totalEarned: user2TotalEarned,
            merkleProof: _getMerkleProofForUser2()
        });

        bytes32 debtSubsidizerRoot = debtSubsidizer.getMerkleRoot(vaultAddress);
        console.log("Debt Subsidizer Merkle Root:");
        console.logBytes32(debtSubsidizerRoot);

        try debtSubsidizer.claimSubsidy(vaultAddress, user2Claim) {
            console.log("USER2 subsidy claimed successfully!");
        } catch Error(string memory reason) {
            console.log("USER2 claim failed:", reason);
        } catch {
            console.log("USER2 claim failed with unknown error");
        }

        vm.stopBroadcast();

        uint256 user2BorrowAfter = cToken.balanceOf(user2);
        console.log("USER2 borrow balance after claim:", user2BorrowAfter);
        console.log(
            "USER2 borrow reduction:", user2BorrowBefore > user2BorrowAfter ? user2BorrowBefore - user2BorrowAfter : 0
        );

        console.log("\n== USER3 Claiming Subsidy ==");

        uint256 user3BorrowBefore = cToken.balanceOf(user3);
        console.log("USER3 borrow balance before claim:", user3BorrowBefore);
        console.log("USER3 total earned to claim:", user3TotalEarned);

        vm.startBroadcast(user3Key);

        IDebtSubsidizer.ClaimData memory user3Claim = IDebtSubsidizer.ClaimData({
            recipient: user3,
            totalEarned: user3TotalEarned,
            merkleProof: _getMerkleProofForUser3()
        });

        try debtSubsidizer.claimSubsidy(vaultAddress, user3Claim) {
            console.log("USER3 subsidy claimed successfully!");
        } catch Error(string memory reason) {
            console.log("USER3 claim failed:", reason);
        } catch {
            console.log("USER3 claim failed with unknown error");
        }

        vm.stopBroadcast();

        uint256 user3BorrowAfter = cToken.balanceOf(user3);
        console.log("USER3 borrow balance after claim:", user3BorrowAfter);
        console.log(
            "USER3 borrow reduction:", user3BorrowBefore > user3BorrowAfter ? user3BorrowBefore - user3BorrowAfter : 0
        );

        console.log("\n=== Claim Process Complete ===");
    }

    function _getMerkleProofForUser2() internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);

        // Get the actual merkle proof from environment variable (populated from API)
        proof[0] = vm.envBytes32("USER2_MERKLE_PROOF");

        return proof;
    }

    function _getMerkleProofForUser3() internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);

        // Get the actual merkle proof from environment variable (populated from API)
        proof[0] = vm.envBytes32("USER3_MERKLE_PROOF");

        return proof;
    }
}
