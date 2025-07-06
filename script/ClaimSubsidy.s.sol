// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IDebtSubsidizer} from "../src/interfaces/IDebtSubsidizer.sol";

contract ClaimSubsidy is Script {
    function run() external {
        // Load addresses from .env
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address debtSubsidizerAddress = vm.envAddress("DEBT_SUBSIDIZER_ADDRESS");

        // Load user details from .env
        address user2 = vm.envAddress("USER2"); // 0x8F37c5C4fA708E06a656d858003EF7dc5F60A29B
        uint256 user2Key = vm.envUint("USER2_PRIVATE_KEY");
        address user3 = vm.envAddress("USER3"); // 0x3575B992C5337226AEcf4e7f93Dfbe80c576CE15
        uint256 user3Key = vm.envUint("USER3_PRIVATE_KEY");

        // Create contract instance
        IDebtSubsidizer debtSubsidizer = IDebtSubsidizer(debtSubsidizerAddress);

        console.log("=== Claiming Subsidies ===");
        console.log("Vault Address:", vaultAddress);
        console.log("DebtSubsidizer Address:", debtSubsidizerAddress);
        console.log("USER2:", user2);
        console.log("USER3:", user3);

        // Based on the latest epoch server data:
        // Merkle Root: 0x453af7ba13ef28bd50dc1ae0de59e0cbd4dfed58c2f1226f63a93d3e78b97e8c
        // USER2 (0x8F37...): totalEarned = 2093968
        // USER3 (0x3575...): totalEarned = 4187936

        // --- USER2 Claim ---
        console.log("\n== USER2 Claiming Subsidy ==");
        vm.startBroadcast(user2Key);

        // For USER2: 0x8F37c5C4fA708E06a656d858003EF7dc5F60A29B
        // Total earned: 2093968 (from epoch server logs)
        IDebtSubsidizer.ClaimData memory user2Claim =
            IDebtSubsidizer.ClaimData({recipient: user2, totalEarned: 2093968, merkleProof: _getMerkleProofForUser2()});

        try debtSubsidizer.claimSubsidy(vaultAddress, user2Claim) {
            console.log("USER2 subsidy claimed successfully!");
        } catch Error(string memory reason) {
            console.log("USER2 claim failed:", reason);
        } catch {
            console.log("USER2 claim failed with unknown error");
        }

        vm.stopBroadcast();

        // --- USER3 Claim ---
        console.log("\n== USER3 Claiming Subsidy ==");
        vm.startBroadcast(user3Key);

        // For USER3: 0x3575B992C5337226AEcf4e7f93Dfbe80c576CE15
        // Total earned: 4187936 (from epoch server logs)
        IDebtSubsidizer.ClaimData memory user3Claim =
            IDebtSubsidizer.ClaimData({recipient: user3, totalEarned: 4187936, merkleProof: _getMerkleProofForUser3()});

        try debtSubsidizer.claimSubsidy(vaultAddress, user3Claim) {
            console.log("USER3 subsidy claimed successfully!");
        } catch Error(string memory reason) {
            console.log("USER3 claim failed:", reason);
        } catch {
            console.log("USER3 claim failed with unknown error");
        }

        vm.stopBroadcast();

        console.log("\n=== Claim Process Complete ===");
    }

    // Generate merkle proof for USER2 (0x8F37c5C4fA708E06a656d858003EF7dc5F60A29B)
    // This is calculated based on the merkle tree structure from epoch server
    function _getMerkleProofForUser2() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);

        // For a 2-leaf tree, each leaf's proof is the sibling leaf hash
        // USER3 leaf hash (which comes first in sorted order)
        proof[0] = keccak256(abi.encodePacked(address(0x3575B992C5337226AEcf4e7f93Dfbe80c576CE15), uint256(4187936)));

        return proof;
    }

    // Generate merkle proof for USER3 (0x3575B992C5337226AEcf4e7f93Dfbe80c576CE15)
    function _getMerkleProofForUser3() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);

        // For a 2-leaf tree, each leaf's proof is the sibling leaf hash
        // USER2 leaf hash (which comes second in sorted order)
        proof[0] = keccak256(abi.encodePacked(address(0x8F37c5C4fA708E06a656d858003EF7dc5F60A29B), uint256(2093968)));

        return proof;
    }

    // Helper function to verify merkle root calculation
    function verifyMerkleRoot() external pure returns (bytes32) {
        // Calculate leaf hashes
        bytes32 user2Leaf =
            keccak256(abi.encodePacked(address(0x8F37c5C4fA708E06a656d858003EF7dc5F60A29B), uint256(2093968)));

        bytes32 user3Leaf =
            keccak256(abi.encodePacked(address(0x3575B992C5337226AEcf4e7f93Dfbe80c576CE15), uint256(4187936)));

        // Sort leaves for OpenZeppelin compatibility
        bytes32 left = user2Leaf < user3Leaf ? user2Leaf : user3Leaf;
        bytes32 right = user2Leaf < user3Leaf ? user3Leaf : user2Leaf;

        // Calculate root
        return keccak256(abi.encodePacked(left, right));
    }
}
