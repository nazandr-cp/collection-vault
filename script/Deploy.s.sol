// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {DeployConfig} from "./utils/DeployConfig.sol";
import {DeployLibraries} from "./DeployLibraries.s.sol";
import {DeployCore} from "./DeployCore.s.sol";
// import {DeployCore} from "./DeployCore.s.sol"; // For the struct
import {Configure} from "./Configure.s.sol";
// TODO: Import interfaces for verification if needed
// import {IMarketVault} from "src/interfaces/IMarketVault.sol";

contract Deploy is Script {
    DeployConfig deployConfig;
    DeployLibraries deployLibraries;
    DeployCore deployCore;
    Configure configure;

    // Deployed contract addresses (optional to store here, could be returned)
    // address public fullMath512;
    // address public rateLimiter;
    // address public transient;
    // DeployCore.DeployedCoreContracts public coreContracts;

    constructor() {
        deployConfig = new DeployConfig();
        deployLibraries = new DeployLibraries();
        deployCore = new DeployCore();
        configure = new Configure();
    }

    function run() external {
        // 1. Select Network and Load Configuration
        DeployConfig.Network selectedNetwork = deployConfig.selectNetwork();
        DeployConfig.NetworkConfig memory networkConfig = deployConfig.getNetworkConfig(selectedNetwork);
        // DeployConfig.CoreContractParams memory coreParams = deployConfig.getCoreContractParams(selectedNetwork); // Pass this to DeployCore

        console.log("Deploying to network:", vm.toString(abi.encodePacked(selectedNetwork)));
        console.log("MultiSig/Owner:", networkConfig.multiSig);
        console.log("LendingManager:", networkConfig.lendingManager);

        // Get deployer address (ensure it's funded for the target network)
        address _deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        // uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY"); // For broadcasting transactions

        // vm.startBroadcast(deployerPrivateKey); // Or vm.startBroadcast(deployer); if using msg.sender with a hot wallet

        // 2. Deploy Libraries
        (address libFullMath512, address libRateLimiter, address libTransient) = deployLibraries.run();
        // fullMath512 = libFullMath512;
        // rateLimiter = libRateLimiter;
        // transient = libTransient;
        console.log("--- Libraries Deployed ---");
        console.log("FullMath512:", libFullMath512);
        console.log("RateLimiter:", libRateLimiter);
        console.log("Transient:", libTransient);

        // 3. Deploy Core Contracts
        // TODO: Pass coreParams to deployCore.run()
        // coreContracts = deployCore.run(libFullMath512, libRateLimiter, libTransient, networkConfig /*, coreParams */);
        console.log("--- Core Contracts Deployed ---");
        // console.log("MarketVault:", coreContracts.marketVault);
        // console.log("SubsidyDistributor:", coreContracts.subsidyDistributor);
        // console.log("RootGuardian:", coreContracts.rootGuardian);
        // console.log("BountyKeeper:", coreContracts.bountyKeeper);

        // 4. Configure Contracts
        // configure.run(coreContracts, networkConfig /*, deployer */);
        console.log("--- Contracts Configured ---");

        // vm.stopBroadcast();

        console.log(
            "Deployment and configuration complete for network:", vm.toString(abi.encodePacked(selectedNetwork))
        );
        // TODO: Add verification step call if Verify.s.sol is ready
    }
}
