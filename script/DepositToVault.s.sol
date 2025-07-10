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
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address lendingManagerAddress = vm.envAddress("LENDING_MANAGER_ADDRESS");

        MockERC20 asset = MockERC20(assetAddress);
        CollectionsVault vault = CollectionsVault(vaultAddress);
        LendingManager lendingManager = LendingManager(lendingManagerAddress);

        uint8 decimals = asset.decimals();
        uint256 depositAmount = 100000 * (10 ** decimals);
        address sender = vm.envAddress("SENDER");

        vm.startBroadcast(deployerKey);

        lendingManager.grantRole(Roles.OPERATOR_ROLE, vaultAddress);
        vault.grantRole(Roles.COLLECTION_MANAGER_ROLE, sender);
        asset.approve(vaultAddress, depositAmount);
        vault.depositForCollection(depositAmount, sender, nftAddress);

        vm.stopBroadcast();
    }
}
