// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";

contract DepositToVault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address assetAddress = vm.envAddress("ASSET_ADDRESS");
        address nftAddress = vm.envAddress("NFT_ADDRESS");

        // Use the new vault address from recent deployment
        address vaultAddress = 0x4A4be724F522946296a51d8c82c7C2e8e5a62655;

        MockERC20 asset = MockERC20(assetAddress);
        CollectionsVault vault = CollectionsVault(vaultAddress);

        // Amount to deposit: 100,000 MDAI
        uint8 decimals = asset.decimals();
        uint256 depositAmount = 100000 * (10 ** decimals);

        vm.startBroadcast(deployerKey);

        // Grant collection operator access to the deployer
        vault.grantCollectionAccess(nftAddress, msg.sender);

        // Approve the vault to spend MDAI tokens
        asset.approve(vaultAddress, depositAmount);

        // Deposit to the vault for the NFT collection
        vault.depositForCollection(depositAmount, msg.sender, nftAddress);

        vm.stopBroadcast();

        console.log("Deposited", depositAmount, "MDAI to vault for collection", nftAddress);
        console.log("Vault address:", vaultAddress);
        console.log("Asset address:", assetAddress);
    }
}
