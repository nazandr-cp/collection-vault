// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {CErc20Immutable} from "compound-protocol-2.8.1/contracts/CErc20Immutable.sol";
import {ComptrollerInterface} from "compound-protocol-2.8.1/contracts/ComptrollerInterface.sol";

contract DepositAndBorrow is Script {
    function run() external {
        // Load addresses from .env
        address assetAddress = vm.envAddress("ASSET_ADDRESS");
        address cTokenAddress = vm.envAddress("CTOKEN_ADDRESS");
        address comptrollerAddress = vm.envAddress("COMPTROLLER_ADDRESS");

        // Load user details from .env
        address user2 = vm.envAddress("USER2");
        uint256 user2Key = vm.envUint("USER2_PRIVATE_KEY");
        address user3 = vm.envAddress("USER3");
        uint256 user3Key = vm.envUint("USER3_PRIVATE_KEY");

        // Create contract instances
        MockERC20 asset = MockERC20(assetAddress);
        CErc20Immutable cToken = CErc20Immutable(cTokenAddress);
        ComptrollerInterface comptroller = ComptrollerInterface(comptrollerAddress);

        // Define amounts
        uint8 decimals = asset.decimals();
        uint256 supply2Amount = 5000 * (10 ** decimals);
        uint256 borrow2Amount = 3000 * (10 ** decimals);
        uint256 supply3Amount = 10000 * (10 ** decimals);
        uint256 borrow3Amount = 5000 * (10 ** decimals);

        // --- USER2 Actions ---
        console.log("== USER2: Approve, Supply, Enter Market, Borrow ==");
        vm.startBroadcast(user2Key);

        asset.approve(cTokenAddress, supply2Amount);
        cToken.mint(supply2Amount);
        address[] memory markets = new address[](1);
        markets[0] = cTokenAddress;
        comptroller.enterMarkets(markets);
        cToken.borrow(borrow2Amount);

        vm.stopBroadcast();

        // --- USER3 Actions ---
        console.log("== USER3: Approve, Supply, Enter Market, Borrow ==");
        vm.startBroadcast(user3Key);

        asset.approve(cTokenAddress, supply3Amount);
        cToken.mint(supply3Amount);
        comptroller.enterMarkets(markets);
        cToken.borrow(borrow3Amount);

        vm.stopBroadcast();

        console.log("All done!");
    }
}
