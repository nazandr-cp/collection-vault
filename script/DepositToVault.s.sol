// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {Roles} from "../src/Roles.sol";

contract DepositToVault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address assetAddress = vm.envAddress("ASSET_ADDRESS");
        address nftAddress = vm.envAddress("NFT_ADDRESS");

        // Use vault address from environment
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");

        MockERC20 asset = MockERC20(assetAddress);
        CollectionsVault vault = CollectionsVault(vaultAddress);

        // Amount to deposit: 100,000 MDAI
        uint8 decimals = asset.decimals();
        uint256 depositAmount = 100000 * (10 ** decimals);

        address sender = vm.addr(deployerKey);

        // Use the DefaultSender who has DEFAULT_ADMIN_ROLE to grant ADMIN_ROLE to sender
        address roleHolder = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38; // DefaultSender that gets roles

        // Grant ADMIN_ROLE to sender first
        vm.startPrank(roleHolder);
        vault.grantRole(Roles.ADMIN_ROLE, sender);
        vm.stopPrank();

        console.log("Granted ADMIN_ROLE to sender for vault operations");

        vm.startBroadcast(deployerKey);

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
