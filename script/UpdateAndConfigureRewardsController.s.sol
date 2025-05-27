// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/interfaces/IRewardsController.sol";
import "src/RewardsController.sol"; // To access enums if not fully defined in interface
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol"; // Added for proxy deployment

// Minimal interface for ProxyAdmin focusing on the upgrade function
interface IMinimalProxyAdmin {
    function upgrade(address proxy, address implementation) external;
    // If other ProxyAdmin functions were needed by this script, they'd be added here.
}

contract UpdateAndConfigureRewardsControllerScript is Script {
    // Default values for whitelistCollection - adjust if needed
    IRewardsController.CollectionType constant NFT_COLLECTION_TYPE = IRewardsController.CollectionType.ERC721;
    // Based on RewardsController.sol, for NFTs, nValue is calculated directly from balance.
    // RewardBasis.DEPOSIT is used here as a convention for the parameter.
    IRewardsController.RewardBasis constant NFT_REWARD_BASIS = IRewardsController.RewardBasis.DEPOSIT;
    uint16 constant NFT_SHARE_PERCENTAGE_BPS = 9000; // 90%

    function run() external {
        // Load addresses from environment variables
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        // address newRewardsControllerImplAddress = vm.envAddress("NEW_REWARDS_CONTROLLER_IMPL_ADDRESS"); // No longer needed from env
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address lendingManagerAddress = vm.envAddress("LENDING_MANAGER_ADDRESS");
        address mockNftAddress = vm.envAddress("MOCK_NFT_ADDRESS");
        // address rewardsControllerProxyAddress = vm.envAddress("REWARDS_CONTROLLER_PROXY_ADDRESS"); // Keep for upgrade, or remove if deploying new
        address authorizedUpdaterAddress = vm.envAddress("AUTHORIZED_UPDATER_ADDRESS"); // For new proxy initialization

        // Ensure critical addresses are valid
        // if (rewardsControllerProxyAddress == address(0)) {
        //     console.log("ERROR: REWARDS_CONTROLLER_PROXY_ADDRESS environment variable is not set or is address(0).");
        //     return;
        // }
        if (proxyAdminAddress == address(0)) {
            console.log("ERROR: PROXY_ADMIN_ADDRESS environment variable is not set or is address(0).");
            return;
        }
        // if (newRewardsControllerImplAddress == address(0)) { // No longer needed from env
        //     console.log("ERROR: NEW_REWARDS_CONTROLLER_IMPL_ADDRESS environment variable is not set or is address(0).");
        //     return;
        // }
        if (vaultAddress == address(0)) {
            console.log("ERROR: VAULT_ADDRESS environment variable is not set or is address(0).");
            return;
        }
        if (lendingManagerAddress == address(0)) {
            console.log("ERROR: LENDING_MANAGER_ADDRESS environment variable is not set or is address(0).");
            return;
        }
        if (mockNftAddress == address(0)) {
            console.log("ERROR: MOCK_NFT_ADDRESS environment variable is not set or is address(0).");
            return;
        }
        if (authorizedUpdaterAddress == address(0)) {
            console.log("ERROR: AUTHORIZED_UPDATER_ADDRESS environment variable is not set or is address(0).");
            return;
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Option A: Upgrade existing proxy (current script logic)
        // address rewardsControllerProxyAddress = vm.envAddress("REWARDS_CONTROLLER_PROXY_ADDRESS");
        // IMinimalProxyAdmin proxyAdmin = IMinimalProxyAdmin(proxyAdminAddress);
        // console.log(
        //     "Upgrading RewardsController proxy (%s) to new implementation (%s) via ProxyAdmin (%s)...",
        //     rewardsControllerProxyAddress,
        //     newRewardsControllerImplAddress,
        //     proxyAdminAddress
        // );
        // proxyAdmin.upgrade(rewardsControllerProxyAddress, newRewardsControllerImplAddress);
        // console.log("RewardsController implementation upgraded successfully.");
        // IRewardsController rewardsController = IRewardsController(rewardsControllerProxyAddress);

        // Option B: Deploy a new RewardsController Proxy
        console.log("Deploying new RewardsController implementation...");
        RewardsController newRewardsControllerImpl = new RewardsController();
        address newRewardsControllerImplAddress = address(newRewardsControllerImpl);
        console.log("New RewardsController implementation deployed at:", newRewardsControllerImplAddress);

        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            deployer, // initialOwner
            authorizedUpdaterAddress // initialClaimSigner
        );

        TransparentUpgradeableProxy newRewardsControllerProxy =
            new TransparentUpgradeableProxy(newRewardsControllerImplAddress, proxyAdminAddress, initData);
        console.log("New RewardsController Proxy deployed at:", address(newRewardsControllerProxy));
        IRewardsController rewardsController = IRewardsController(address(newRewardsControllerProxy));
        address rewardsControllerProxyAddress = address(newRewardsControllerProxy); // Use this for subsequent calls


        // 2. Re-add Vault
        console.log(
            "Adding/Re-adding Vault (%s) with LendingManager (%s) to RewardsController (%s)...",
            vaultAddress,
            lendingManagerAddress,
            rewardsControllerProxyAddress
        );
        rewardsController.addVault(vaultAddress, lendingManagerAddress);
        console.log("Vault added/re-added to RewardsController successfully.");

        // 3. Re-add Collection (Whitelist Collection)
        console.log(
            "Whitelisting/Re-adding Collection (%s) to Vault (%s) in RewardsController...", mockNftAddress, vaultAddress
        );
        rewardsController.whitelistCollection(
            vaultAddress, mockNftAddress, NFT_COLLECTION_TYPE, NFT_REWARD_BASIS, NFT_SHARE_PERCENTAGE_BPS
        );
        console.log(
            "Collection whitelisted/re-added successfully: Type=%s, Basis=%s, ShareBPS=%s",
            uint8(NFT_COLLECTION_TYPE),
            uint8(NFT_REWARD_BASIS),
            NFT_SHARE_PERCENTAGE_BPS
        );

        vm.stopBroadcast();
        console.log("Script execution finished.");
    }
}
