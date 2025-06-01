// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {FullMath512} from "src/libraries/FullMath512.sol";
import {RateLimiter} from "src/libraries/RateLimiter.sol";
import {Transient} from "src/libraries/Transient.sol";

contract DeployLibraries is Script {
    function run() external returns (address, address, address) {
        vm.startBroadcast();

        // FullMath512 fullMath512 = new FullMath512();
        // console.log("FullMath512 deployed to:", address(fullMath512));

        // RateLimiter rateLimiter = new RateLimiter();
        // console.log("RateLimiter deployed to:", address(rateLimiter));

        // Transient transient = new Transient();
        // console.log("Transient deployed to:", address(transient));

        vm.stopBroadcast();
        return (address(0), address(0), address(0));
    }
}
