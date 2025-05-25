// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/LendingManager.sol";
import "../src/CollectionsVault.sol";
import "../src/RewardsController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import "../src/interfaces/IRewardsController.sol";

contract DeploySystem is Script {
    address EXISTING_MOCK_NFT_ADDRESS;
    address EXISTING_PROXY_ADMIN_ADDRESS;
    address ASSET_TOKEN_ADDRESS;
    address C_TOKEN_ADDRESS;
    address PRICE_ORACLE_ADDRESS;
    address AUTHORIZED_UPDATER_ADDRESS_FROM_ENV;
    IRewardsController.RewardBasis NFT_REWARD_BASIS;
    uint256 NFT_SHARE_PERCENTAGE_BPS;
    uint256 NFT_WEIGHT_PARAM_K;
    string COLLECTIONS_VAULT_NAME;
    string COLLECTIONS_VAULT_SYMBOL;
    address deployer;
    address finalAuthorizedUpdater;

    function loadConfig() internal {
        console.log("Loading configuration from .env file...");
        EXISTING_MOCK_NFT_ADDRESS = vm.envAddress("EXISTING_MOCK_NFT_ADDRESS");
        console.log("EXISTING_MOCK_NFT_ADDRESS:", EXISTING_MOCK_NFT_ADDRESS);
        EXISTING_PROXY_ADMIN_ADDRESS = vm.envAddress("EXISTING_PROXY_ADMIN_ADDRESS");
        console.log("EXISTING_PROXY_ADMIN_ADDRESS:", EXISTING_PROXY_ADMIN_ADDRESS);
        ASSET_TOKEN_ADDRESS = vm.envAddress("ASSET_TOKEN_ADDRESS");
        console.log("ASSET_TOKEN_ADDRESS:", ASSET_TOKEN_ADDRESS);
        C_TOKEN_ADDRESS = vm.envAddress("C_TOKEN_ADDRESS");
        console.log("C_TOKEN_ADDRESS:", C_TOKEN_ADDRESS);
        PRICE_ORACLE_ADDRESS = vm.envAddress("PRICE_ORACLE_ADDRESS");
        console.log("PRICE_ORACLE_ADDRESS:", PRICE_ORACLE_ADDRESS);
        AUTHORIZED_UPDATER_ADDRESS_FROM_ENV = vm.envAddress("AUTHORIZED_UPDATER_ADDRESS");
        console.log(
            "AUTHORIZED_UPDATER_ADDRESS (from .env, 0 means use deployer):", AUTHORIZED_UPDATER_ADDRESS_FROM_ENV
        );
        uint256 basisIndex = vm.envUint("NFT_REWARD_BASIS_ENUM_INDEX");
        if (basisIndex == 0) {
            NFT_REWARD_BASIS = IRewardsController.RewardBasis.DEPOSIT;
        } else if (basisIndex == 1) {
            NFT_REWARD_BASIS = IRewardsController.RewardBasis.BORROW;
        } else if (basisIndex == 2) {
            NFT_REWARD_BASIS = IRewardsController.RewardBasis.FIXED_POOL;
        } else {
            revert("Invalid NFT_REWARD_BASIS_ENUM_INDEX. Must be 0, 1, or 2.");
        }
        console.log("NFT_REWARD_BASIS_ENUM_INDEX:", basisIndex);
        console.log("NFT_REWARD_BASIS (parsed):", uint8(NFT_REWARD_BASIS));
        NFT_SHARE_PERCENTAGE_BPS = vm.envUint("NFT_SHARE_PERCENTAGE_BPS");
        console.log("NFT_SHARE_PERCENTAGE_BPS:", NFT_SHARE_PERCENTAGE_BPS);
        require(NFT_SHARE_PERCENTAGE_BPS <= 10000, "NFT_SHARE_PERCENTAGE_BPS must be <= 10000");
        NFT_WEIGHT_PARAM_K = vm.envUint("NFT_WEIGHT_PARAM_K");
        console.log("NFT_WEIGHT_PARAM_K:", NFT_WEIGHT_PARAM_K);
        COLLECTIONS_VAULT_NAME = vm.envString("COLLECTIONS_VAULT_NAME");
        console.log("COLLECTIONS_VAULT_NAME:", COLLECTIONS_VAULT_NAME);
        COLLECTIONS_VAULT_SYMBOL = vm.envString("COLLECTIONS_VAULT_SYMBOL");
        console.log("COLLECTIONS_VAULT_SYMBOL:", COLLECTIONS_VAULT_SYMBOL);
        console.log("Configuration loaded successfully.");
    }

    function run() external {
        loadConfig();
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPk);
        vm.startBroadcast(deployerPk);
        console.log("Deployer Address (from PRIVATE_KEY):", deployer);
        finalAuthorizedUpdater =
            (AUTHORIZED_UPDATER_ADDRESS_FROM_ENV == address(0)) ? deployer : AUTHORIZED_UPDATER_ADDRESS_FROM_ENV;
        console.log("Final AUTHORIZED_UPDATER_ADDRESS for RewardsController:", finalAuthorizedUpdater);
        console.log("Deploying CollectionsVault...");
        CollectionsVault newCollectionsVault = new CollectionsVault(
            IERC20(ASSET_TOKEN_ADDRESS), COLLECTIONS_VAULT_NAME, COLLECTIONS_VAULT_SYMBOL, deployer, address(0)
        );
        console.log("New CollectionsVault deployed at:", address(newCollectionsVault));
        console.log("Deploying RewardsController implementation...");
        RewardsController newRewardsControllerImpl = new RewardsController(PRICE_ORACLE_ADDRESS);
        console.log("New RewardsController implementation deployed at:", address(newRewardsControllerImpl));
        console.log("Deploying TransparentUpgradeableProxy for RewardsController...");
        // Initialize RewardsController
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            deployer, // initialOwner
            address(newCollectionsVault), // vaultAddress_
            finalAuthorizedUpdater // initialClaimSigner
        );

        TransparentUpgradeableProxy rewardsControllerProxy =
            new TransparentUpgradeableProxy(address(newRewardsControllerImpl), EXISTING_PROXY_ADMIN_ADDRESS, initData);
        IRewardsController newRewardsControllerProxy = IRewardsController(payable(address(rewardsControllerProxy)));
        console.log("New RewardsController Proxy deployed at:", address(newRewardsControllerProxy));
        console.log("RewardsController Proxy admin is:", EXISTING_PROXY_ADMIN_ADDRESS);
        console.log("Deploying LendingManager...");
        LendingManager newLendingManager = new LendingManager(
            deployer,
            address(newCollectionsVault),
            address(newRewardsControllerProxy),
            ASSET_TOKEN_ADDRESS,
            C_TOKEN_ADDRESS
        );
        console.log("New LendingManager deployed at:", address(newLendingManager));

        // Configure CollectionsVault with the new LendingManager
        console.log("Setting LendingManager on CollectionsVault...");
        newCollectionsVault.setLendingManager(address(newLendingManager));
        console.log("LendingManager set on CollectionsVault.");

        console.log("Linking contracts: Granting roles from LendingManager...");
        newLendingManager.grantVaultRole(address(newCollectionsVault));
        console.log("LendingManager granted VAULT_ROLE to CollectionsVault.");
        newLendingManager.grantRewardsControllerRole(address(newRewardsControllerProxy));
        console.log("LendingManager granted REWARDS_CONTROLLER_ROLE to RewardsController Proxy.");
        console.log("Configuring RewardsController for EXISTING_MOCK_NFT_ADDRESS...");
        newRewardsControllerProxy.whitelistCollection(
            EXISTING_MOCK_NFT_ADDRESS,
            IRewardsController.CollectionType.ERC721,
            NFT_REWARD_BASIS,
            uint16(NFT_SHARE_PERCENTAGE_BPS)
        );
        console.log("Whitelisted collection:", EXISTING_MOCK_NFT_ADDRESS);
        IRewardsController.WeightFunction memory nftWeightFn = IRewardsController.WeightFunction({
            fnType: IRewardsController.WeightFunctionType.LINEAR,
            p1: int256(NFT_WEIGHT_PARAM_K),
            p2: 0
        });
        newRewardsControllerProxy.setWeightFunction(EXISTING_MOCK_NFT_ADDRESS, nftWeightFn);
        console.log("Set weight function for collection:", EXISTING_MOCK_NFT_ADDRESS);
        vm.stopBroadcast();
        console.log("\n--- Deployment Summary ---");
        console.log("Deployer Address:", deployer);
        console.log("Asset Token (Mock DAI):", ASSET_TOKEN_ADDRESS);
        console.log("cToken (cMDAI):", C_TOKEN_ADDRESS);
        console.log("Existing MockNFT Address:", EXISTING_MOCK_NFT_ADDRESS);
        console.log("Existing ProxyAdmin Address:", EXISTING_PROXY_ADMIN_ADDRESS);
        console.log("New LendingManager Address:", address(newLendingManager));
        console.log("New CollectionsVault Address:", address(newCollectionsVault));
        console.log("New RewardsController Implementation Address:", address(newRewardsControllerImpl));
        console.log("New RewardsController Proxy Address:", address(newRewardsControllerProxy));
        console.log("RewardsController Authorized Updater:", finalAuthorizedUpdater);
        console.log("--- End of Summary ---");
    }
}
