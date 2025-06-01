// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {DeployConfig} from "./utils/DeployConfig.sol";
// TODO: Import core contract interfaces and implementations
// import {MarketVault} from "src/MarketVault.sol";
// import {SubsidyDistributor} from "src/SubsidyDistributor.sol";
// import {RootGuardian} from "src/RootGuardian.sol";
// import {BountyKeeper} from "src/BountyKeeper.sol";
// import {ILendingManager} from "src/interfaces/ILendingManager.sol";

contract DeployCore is Script {
    // struct DeployedCoreContracts {
    //     address marketVault;
    //     address subsidyDistributor;
    //     address rootGuardian;
    //     address bountyKeeper;
    // }

    function run(
        address, /* library_fullMath512 */
        address, /* library_rateLimiter */
        address, /* library_transient */
        DeployConfig.NetworkConfig memory /* networkConfig */
    ) external /* DeployedCoreContracts memory */ {
        vm.startBroadcast();

        // TODO: Deploy MarketVault
        // MarketVault marketVault = new MarketVault(/* constructor params */);
        // console.log("MarketVault deployed to:", address(marketVault));

        // TODO: Deploy SubsidyDistributor
        // SubsidyDistributor subsidyDistributor = new SubsidyDistributor(/* constructor params */);
        // console.log("SubsidyDistributor deployed to:", address(subsidyDistributor));

        // TODO: Deploy RootGuardian
        // RootGuardian rootGuardian = new RootGuardian(/* constructor params */);
        // console.log("RootGuardian deployed to:", address(rootGuardian));

        // TODO: Deploy BountyKeeper
        // BountyKeeper bountyKeeper = new BountyKeeper(/* constructor params */);
        // console.log("BountyKeeper deployed to:", address(bountyKeeper));

        vm.stopBroadcast();

        // return DeployedCoreContracts({
        //     marketVault: address(marketVault),
        //     subsidyDistributor: address(subsidyDistributor),
        //     rootGuardian: address(rootGuardian),
        //     bountyKeeper: address(bountyKeeper)
        // });
    }
}
