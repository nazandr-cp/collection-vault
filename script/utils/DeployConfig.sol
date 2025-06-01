// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

contract DeployConfig is Script {
    // --- Enums ---
    enum Network {
        LOCAL,
        TESTNET,
        MAINNET
    }

    // --- Structs ---
    struct NetworkConfig {
        Network networkType;
        address multiSig; // Mainnet multi-sig, testnet owner
        address timelock; // Optional timelock address
        address lendingManager; // Existing LendingManager address
        // Add other network-specific addresses like cTokens, oracles, etc.
        // Example: address cETH;
        // Example: address priceOracle;
        uint256 defaultGasLimit;
        uint256 deploymentTimeout;
    }

    struct CoreContractParams {
        // Parameters for MarketVault constructor
        address initialOwnerMV; // Will likely be RootGuardian or deployer initially
        address lendingManagerMV;
        // Parameters for SubsidyDistributor constructor
        address initialOwnerSD;
        address marketVaultSD;
        // Parameters for RootGuardian constructor
        address initialOwnerRG;
        address[] initialGuardiansRG;
        uint256 thresholdRG;
        // Parameters for BountyKeeper constructor
        address initialOwnerBK;
        address marketVaultBK;
        uint256 bountyRateBK; // e.g., in basis points
    }

    // --- State Variables ---
    // Mappings to store configurations per network
    mapping(Network => NetworkConfig) public networkConfigs;
    mapping(Network => CoreContractParams) public coreContractParams;

    constructor() {
        // --- LOCAL CONFIGURATION ---
        NetworkConfig memory localConfig = NetworkConfig({
            networkType: Network.LOCAL,
            multiSig: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil default deployer
            timelock: address(0), // No timelock for local
            lendingManager: address(0xcafE000000000000000000000000000000000001), // Placeholder
            defaultGasLimit: 3_000_000,
            deploymentTimeout: 600 // 10 minutes
        });
        networkConfigs[Network.LOCAL] = localConfig;

        CoreContractParams memory localParams = CoreContractParams({
            initialOwnerMV: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            lendingManagerMV: localConfig.lendingManager,
            initialOwnerSD: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            marketVaultSD: address(0), // Will be set post-deployment
            initialOwnerRG: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            initialGuardiansRG: new address[](0), // Add guardians if needed for local
            thresholdRG: 0,
            initialOwnerBK: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            marketVaultBK: address(0), // Will be set post-deployment
            bountyRateBK: 100 // 1%
        });
        coreContractParams[Network.LOCAL] = localParams;

        // --- TESTNET CONFIGURATION (Goerli/Sepolia etc.) ---
        // Load from .env or hardcode for simplicity in this example
        NetworkConfig memory testnetConfig = NetworkConfig({
            networkType: Network.TESTNET,
            multiSig: vm.envAddress("TESTNET_MULTISIG_ADDRESS"),
            timelock: vm.envAddress("TESTNET_TIMELOCK_ADDRESS"), // Optional
            lendingManager: vm.envAddress("TESTNET_LENDING_MANAGER_ADDRESS"),
            defaultGasLimit: 5_000_000,
            deploymentTimeout: 1200 // 20 minutes
        });
        networkConfigs[Network.TESTNET] = testnetConfig;

        CoreContractParams memory testnetParams = CoreContractParams({
            initialOwnerMV: testnetConfig.multiSig, // Or a deployer hot wallet first
            lendingManagerMV: testnetConfig.lendingManager,
            initialOwnerSD: testnetConfig.multiSig,
            marketVaultSD: address(0),
            initialOwnerRG: testnetConfig.multiSig,
            initialGuardiansRG: new address[](0), // Populate from env
            thresholdRG: 1, // Example: 1 for testnet
            initialOwnerBK: testnetConfig.multiSig,
            marketVaultBK: address(0),
            bountyRateBK: 50 // 0.5%
        });
        coreContractParams[Network.TESTNET] = testnetParams;

        // --- MAINNET CONFIGURATION ---
        NetworkConfig memory mainnetConfig = NetworkConfig({
            networkType: Network.MAINNET,
            multiSig: vm.envAddress("MAINNET_MULTISIG_ADDRESS"),
            timelock: vm.envAddress("MAINNET_TIMELOCK_ADDRESS"),
            lendingManager: vm.envAddress("MAINNET_LENDING_MANAGER_ADDRESS"),
            defaultGasLimit: 7_000_000,
            deploymentTimeout: 3600 // 1 hour
        });
        networkConfigs[Network.MAINNET] = mainnetConfig;

        CoreContractParams memory mainnetParams = CoreContractParams({
            initialOwnerMV: mainnetConfig.timelock, // Ownership through timelock
            lendingManagerMV: mainnetConfig.lendingManager,
            initialOwnerSD: mainnetConfig.timelock,
            marketVaultSD: address(0),
            initialOwnerRG: mainnetConfig.timelock,
            initialGuardiansRG: new address[](0), // Populate from env/secure source
            thresholdRG: 2, // Example: 2-of-3 guardians
            initialOwnerBK: mainnetConfig.timelock,
            marketVaultBK: address(0),
            bountyRateBK: 25 // 0.25%
        });
        coreContractParams[Network.MAINNET] = mainnetParams;
    }

    function getNetworkConfig(Network _network) public view returns (NetworkConfig memory) {
        return networkConfigs[_network];
    }

    function getCoreContractParams(Network _network) public view returns (CoreContractParams memory) {
        return coreContractParams[_network];
    }

    function selectNetwork() public view returns (Network) {
        uint256 chainId = block.chainid;
        if (chainId == 1) {
            return Network.MAINNET;
        } else if (chainId == 5 || chainId == 11155111) {
            // Goerli or Sepolia
            return Network.TESTNET;
        } else {
            // Localhost, Anvil, Hardhat Network etc.
            return Network.LOCAL;
        }
    }
}
