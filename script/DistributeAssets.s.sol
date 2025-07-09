// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";

contract DistributeAssets is Script {
    function run() external {
        // Load environment variables
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address assetAddr = vm.envAddress("ASSET_ADDRESS");
        address nftAddr = vm.envAddress("NFT_ADDRESS");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address user2 = vm.envAddress("USER2");
        address user3 = vm.envAddress("USER3");

        vm.startBroadcast(deployerKey);

        // Attach to deployed contracts
        MockERC20 asset = MockERC20(assetAddr);
        MockERC721 nft = MockERC721(nftAddr);

        // Distribute mDAI
        uint8 decimals = asset.decimals();
        uint256 amount2 = 5000 * 10 ** decimals;
        uint256 amount3 = 10000 * 10 ** decimals;
        asset.transfer(user2, amount2);
        asset.transfer(user3, amount3);

        // Distribute NFTs
        for (uint256 i = 0; i < 2; i++) {
            nft.mint(user2);
        }
        for (uint256 i = 0; i < 4; i++) {
            nft.mint(user3);
        }

        // Log results
        console.log("Distributed", amount2, "tokens to", user2);
        console.log("Distributed", amount3, "tokens to", user3);
        console.log("Minted 2 NFTs to", user2);
        console.log("Minted 4 NFTs to", user3);

        // Whitelist collection and deposit to vault
        CollectionsVault vault = CollectionsVault(vaultAddr);
        vault.grantRole(vault.COLLECTION_MANAGER_ROLE(), msg.sender);
        uint256 depositAmount = 100000 * 10 ** decimals;
        // Approve vault to transfer tokens on behalf of deployer
        asset.approve(vaultAddr, depositAmount);
        vault.depositForCollection(depositAmount, msg.sender, nftAddr);
        console.log("Deposited", depositAmount, "tokens into vault for collection", nftAddr);

        vm.stopBroadcast();
    }
}
