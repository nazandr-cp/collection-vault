// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {Roles} from "../src/Roles.sol";

contract DepositToVault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address assetAddress = vm.envAddress("ASSET_ADDRESS");
        address nftAddress = vm.envAddress("NFT_ADDRESS");

        // Use vault address from environment
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address lendingManagerAddress = vm.envAddress("LENDING_MANAGER_ADDRESS");

        MockERC20 asset = MockERC20(assetAddress);
        CollectionsVault vault = CollectionsVault(vaultAddress);
        LendingManager lendingManager = LendingManager(lendingManagerAddress);

        // Amount to deposit: 1,000 MDAI
        uint8 decimals = asset.decimals();
        uint256 depositAmount = 1000 * (10 ** decimals);

        // Use the actual SENDER address as admin (already has all required roles)
        address sender = vm.envAddress("SENDER");

        vm.startBroadcast(deployerKey);

        // Grant OPERATOR_ROLE to vault on LendingManager (needed for depositToLendingProtocol)
        lendingManager.grantRole(Roles.OPERATOR_ROLE, vaultAddress);

        // Grant collection operator access to the deployer
        vault.grantCollectionAccess(nftAddress, sender);

        // Approve the vault to spend MDAI tokens
        asset.approve(vaultAddress, depositAmount);

        // Deposit to the vault for the NFT collection
        vault.depositForCollection(depositAmount, sender, nftAddress);

        vm.stopBroadcast();

        console.log("Deposited", depositAmount, "MDAI to vault for collection", nftAddress);
        console.log("Vault address:", vaultAddress);
        console.log("Asset address:", assetAddress);
    }
}
