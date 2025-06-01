// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {DeployConfig} from "./utils/DeployConfig.sol";
// TODO: Import relevant interfaces (e.g., IProxy, IMarketVaultV2)
// TODO: Import new contract versions if deploying them (e.g., MarketVaultV2)
// import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol"; // If using OpenZeppelin UUPS

contract Upgrade is Script {
    DeployConfig deployConfig;

    // Example: Target contract to upgrade (assuming UUPS proxy)
    // address public marketVaultProxyAddress; // Set this via env or constructor

    constructor() {
        deployConfig = new DeployConfig();
        // marketVaultProxyAddress = vm.envAddress("MARKET_VAULT_PROXY_ADDRESS");
    }

    function run() external {
        // 1. Select Network and Load Configuration
        DeployConfig.Network selectedNetwork = deployConfig.selectNetwork();
        DeployConfig.NetworkConfig memory networkConfig = deployConfig.getNetworkConfig(selectedNetwork);
        console.log("Upgrading on network:", vm.toString(abi.encodePacked(selectedNetwork)));
        console.log("Using MultiSig/Owner for upgrade:", networkConfig.multiSig);

        // Get deployer/upgrader address (ensure it's the proxy admin or owner)
        address _upgrader = vm.envOr("UPGRADER_ADDRESS", msg.sender); // Should be proxy admin or owner
        // uint256 upgraderPrivateKey = vm.envUint("UPGRADER_PRIVATE_KEY");

        // vm.startBroadcast(upgraderPrivateKey); // Or vm.startBroadcast(upgrader);

        // --- Example: Upgrading MarketVault (UUPS) ---
        // This is a simplified example. Real UUPS upgrades involve deploying the new implementation
        // and then calling `upgradeTo` on the proxy, typically managed by a ProxyAdmin or directly by the owner.

        // 1. Deploy the new implementation contract (e.g., MarketVaultV2)
        // console.log("Deploying new MarketVaultV2 implementation...");
        // MarketVaultV2 newMarketVaultImpl = new MarketVaultV2();
        // console.log("MarketVaultV2 implementation deployed to:", address(newMarketVaultImpl));

        // 2. Call `upgradeTo` on the proxy contract
        // This must be called by the proxy's admin/owner.
        // If the proxy admin is a Timelock or MultiSig, this script might prepare the call data
        // for the Timelock/MultiSig to execute.

        // IProxy proxy = IProxy(marketVaultProxyAddress); // Generic proxy interface
        // UUPSUpgradeable proxyUUPS = UUPSUpgradeable(marketVaultProxyAddress); // If directly calling UUPS functions

        // Ensure `upgrader` is authorized to call upgradeTo.
        // For UUPS, the `proposeNewImplementation` and `approveNewImplementation` flow might be used,
        // or direct `upgradeTo` if allowed by the proxy's auth logic.

        // console.log("Attempting to upgrade MarketVault proxy at", marketVaultProxyAddress, "to new implementation", address(newMarketVaultImpl));
        // proxyUUPS.upgradeTo(address(newMarketVaultImpl)); // This might need to be `upgradeToAndCall` if initialization is needed

        // console.log("MarketVault proxy upgrade initiated to:", address(newMarketVaultImpl));

        // --- Post-Upgrade Steps ---
        // - Verify new implementation on block explorers
        // - Call any necessary initialization functions on the proxy (if `upgradeToAndCall` was used or needed separately)
        // - Perform health checks

        // vm.stopBroadcast();

        console.log("Upgrade script finished for network:", vm.toString(abi.encodePacked(selectedNetwork)));
        // Note: Actual upgrade execution might be via a MultiSig/Timelock for mainnet.
        // This script can help prepare calldata or execute on testnets.
    }

    // Helper interface for a generic proxy (could be Transparent or UUPS)
    // interface IProxy {
    //     function implementation() external view returns (address);
    //     // function upgradeTo(address newImplementation) external; // For Transparent Proxies, called by ProxyAdmin
    // }
}
