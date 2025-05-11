// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Project contracts
import {RewardsController} from "../src/RewardsController.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {ERC4626Vault} from "../src/ERC4626Vault.sol";
import {IRewardsController} from "../src/interfaces/IRewardsController.sol"; // For RewardBasis enum

// Mocks (if deploying them, otherwise use interfaces for existing ones)
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {MockCToken} from "../src/mocks/MockCToken.sol";
import {CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

contract DeployAll is Script {
    // Configuration Variables
    address DEPLOYER_ADDRESS;
    address AUTHORIZED_UPDATER_ADDRESS;
    address REWARD_TOKEN_ADDRESS;
    address C_TOKEN_ADDRESS;
    uint256 INITIAL_C_TOKEN_EXCHANGE_RATE = 2e28; // Default, can be overridden by env

    // Addresses for existing contracts, to be loaded from environment variables
    address EXISTING_MOCK_NFT_ADDRESS;
    address EXISTING_TOKEN_VAULT_ADDRESS;
    address EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS;

    struct NftConfig {
        address addr;
        string name;
        string symbol;
        uint256 beta;
        IRewardsController.RewardBasis rewardBasis;
        uint256 rewardSharePercentage;
    }

    NftConfig[] public nftConfigs;

    // Deployed contract instances
    ProxyAdmin public proxyAdmin;
    RewardsController public rewardsControllerImpl;
    RewardsController public rewardsControllerProxy;
    LendingManager public lendingManager;
    ERC4626Vault public tokenVault;
    IERC20 public rewardToken;
    CTokenInterface public cToken; // Use interface for flexibility

    function loadConfig() internal {
        DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
        if (DEPLOYER_ADDRESS == address(0)) {
            DEPLOYER_ADDRESS = msg.sender; // Default to broadcaster
        }
        console.log("Using DEPLOYER_ADDRESS: %s", DEPLOYER_ADDRESS);

        AUTHORIZED_UPDATER_ADDRESS = vm.envAddress("AUTHORIZED_UPDATER_ADDRESS");
        if (AUTHORIZED_UPDATER_ADDRESS == address(0)) {
            AUTHORIZED_UPDATER_ADDRESS = DEPLOYER_ADDRESS; // Default to deployer
        }
        console.log("Using AUTHORIZED_UPDATER_ADDRESS: %s", AUTHORIZED_UPDATER_ADDRESS);

        REWARD_TOKEN_ADDRESS = vm.envAddress("REWARD_TOKEN_ADDRESS");
        console.log("Env REWARD_TOKEN_ADDRESS: %s", REWARD_TOKEN_ADDRESS);

        C_TOKEN_ADDRESS = vm.envAddress("C_TOKEN_ADDRESS");
        console.log("Env C_TOKEN_ADDRESS: %s", C_TOKEN_ADDRESS);

        uint256 envExchangeRate = vm.envUint("INITIAL_C_TOKEN_EXCHANGE_RATE");
        if (envExchangeRate > 0) {
            INITIAL_C_TOKEN_EXCHANGE_RATE = envExchangeRate;
        }
        console.log("Using INITIAL_C_TOKEN_EXCHANGE_RATE: %s", INITIAL_C_TOKEN_EXCHANGE_RATE);

        EXISTING_MOCK_NFT_ADDRESS = vm.envAddress("EXISTING_MOCK_NFT_ADDRESS");
        console.log("Env EXISTING_MOCK_NFT_ADDRESS: %s", EXISTING_MOCK_NFT_ADDRESS);

        EXISTING_TOKEN_VAULT_ADDRESS = vm.envAddress("EXISTING_TOKEN_VAULT_ADDRESS");
        console.log("Env EXISTING_TOKEN_VAULT_ADDRESS: %s", EXISTING_TOKEN_VAULT_ADDRESS);

        EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS = vm.envAddress("EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS");
        console.log("Env EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS: %s", EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS);

        // Configure the primary (and only for this modified script) NFT collection
        if (EXISTING_MOCK_NFT_ADDRESS != address(0)) {
            nftConfigs.push(
                NftConfig({
                    addr: EXISTING_MOCK_NFT_ADDRESS,
                    name: "Existing MockNFT", // Name/Symbol for script's internal reference
                    symbol: "EMNFT", // Actual on-chain name/symbol might differ
                    beta: 0.1 ether, // ASSUMED parameter for the existing NFT
                    rewardBasis: IRewardsController.RewardBasis.BORROW, // ASSUMED parameter
                    rewardSharePercentage: 5000 // ASSUMED parameter (50%)
                })
            );
            console.log("Configured to use existing MockNFT at %s with assumed parameters.", EXISTING_MOCK_NFT_ADDRESS);
        } else {
            // Fallback to deploying a new "Mock NFT 1" if no existing address is provided
            // or use NFT_COLLECTION_1_ADDRESS if set in env.
            address nft1Addr = vm.envAddress("NFT_COLLECTION_1_ADDRESS");
            string memory nft1Name = "Mock NFT 1";
            string memory nft1Symbol = "MNFT1";
            if (nft1Addr != address(0)) {
                console.log("Configured to use NFT_COLLECTION_1_ADDRESS for NFT1: %s", nft1Addr);
            } else {
                console.log("Configured to deploy a new Mock NFT 1.");
            }
            nftConfigs.push(
                NftConfig({
                    addr: nft1Addr, // If address(0), deployMocksAndTokens will deploy it
                    name: nft1Name,
                    symbol: nft1Symbol,
                    beta: 0.1 ether,
                    rewardBasis: IRewardsController.RewardBasis.BORROW,
                    rewardSharePercentage: 5000
                })
            );
        }
        // Note: The second NFT collection ("Mock NFT 2") is no longer configured.
    }

    function deployMocksAndTokens() internal {
        if (REWARD_TOKEN_ADDRESS == address(0)) {
            console.log("Deploying Mock Reward Token (MDAI)...");
            MockERC20 mockDai = new MockERC20("Mock DAI", "MDAI", 18, 0); // Added initialSupply
            REWARD_TOKEN_ADDRESS = address(mockDai);
            mockDai.mint(DEPLOYER_ADDRESS, 1_000_000_000 ether); // Mint some for deployer
            console.log("Mock Reward Token (MDAI) deployed at: %s", REWARD_TOKEN_ADDRESS);
        }
        rewardToken = IERC20(REWARD_TOKEN_ADDRESS);
        console.log("Using Reward Token (Asset): %s", address(rewardToken));

        if (C_TOKEN_ADDRESS == address(0)) {
            console.log("Deploying Mock CToken for asset: %s", address(rewardToken));
            MockCToken mockCT = new MockCToken(address(rewardToken));
            mockCT.setExchangeRate(INITIAL_C_TOKEN_EXCHANGE_RATE);
            C_TOKEN_ADDRESS = address(mockCT);
            console.log("Mock CToken deployed at: %s", C_TOKEN_ADDRESS);
        }
        cToken = CTokenInterface(C_TOKEN_ADDRESS); // Use CTokenInterface
        console.log("Using CToken: %s", address(cToken));

        for (uint256 i = 0; i < nftConfigs.length; i++) {
            if (nftConfigs[i].addr == address(0)) {
                console.log("Deploying Mock NFT: %s (%s)...", nftConfigs[i].name, nftConfigs[i].symbol);
                MockERC721 newNft = new MockERC721(nftConfigs[i].name, nftConfigs[i].symbol);
                nftConfigs[i].addr = address(newNft);
                console.log("Deployed %s at %s", nftConfigs[i].name, address(newNft));
            } else {
                console.log("Using existing NFT %s at %s", nftConfigs[i].name, nftConfigs[i].addr);
            }
        }
    }

    function run() public {
        loadConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployMocksAndTokens();

        // 1. Deploy ProxyAdmin
        console.log("Deploying ProxyAdmin...");
        proxyAdmin = new ProxyAdmin(DEPLOYER_ADDRESS);
        console.log("ProxyAdmin deployed at: %s", address(proxyAdmin));

        // 2. Deploy LendingManager
        address temporaryVaultAddress = address(0x1); // Placeholder
        address temporaryRewardsControllerAddress = address(0x2); // Placeholder
        console.log("Deploying LendingManager...");
        lendingManager = new LendingManager(
            DEPLOYER_ADDRESS,
            temporaryVaultAddress,
            temporaryRewardsControllerAddress,
            address(rewardToken),
            address(cToken)
        );
        console.log("LendingManager deployed at: %s", address(lendingManager));

        // 3. Deploy or assign ERC4626Vault (TokenVault)
        if (EXISTING_TOKEN_VAULT_ADDRESS != address(0)) {
            console.log("Using existing ERC4626Vault (TokenVault) at: %s", EXISTING_TOKEN_VAULT_ADDRESS);
            tokenVault = ERC4626Vault(payable(EXISTING_TOKEN_VAULT_ADDRESS));
        } else {
            console.log("Deploying ERC4626Vault (TokenVault)...");
            string memory vaultNameKey = "VAULT_NAME";
            string memory defaultVaultName = "Vaulted Asset";
            string memory vaultSymbolKey = "VAULT_SYMBOL";
            string memory defaultVaultSymbol = "vAST";

            tokenVault = new ERC4626Vault(
                rewardToken,
                vm.envOr(vaultNameKey, defaultVaultName),
                vm.envOr(vaultSymbolKey, defaultVaultSymbol),
                DEPLOYER_ADDRESS,
                address(lendingManager)
            );
            console.log("TokenVault deployed at: %s", address(tokenVault));
        }

        // 4. Update LendingManager with actual TokenVault address
        console.log("Updating LendingManager vault role...");
        lendingManager.revokeVaultRole(temporaryVaultAddress);
        lendingManager.grantVaultRole(address(tokenVault));
        console.log("LendingManager vault role granted to: %s", address(tokenVault));

        // 5. Deploy or assign RewardsController
        if (EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS != address(0)) {
            console.log("Using existing RewardsController Proxy at: %s", EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS);
            rewardsControllerProxy = RewardsController(payable(EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS));
            // rewardsControllerImpl is not deployed as we are using an existing proxy.
            // ProxyAdmin was deployed earlier; it won't manage this existing proxy unless its admin is changed manually.
        } else {
            console.log("Deploying RewardsController implementation...");
            rewardsControllerImpl = new RewardsController();
            console.log("RewardsController implementation deployed at: %s", address(rewardsControllerImpl));

            // 6. Prepare RewardsController initialization data
            bytes memory initData = abi.encodeWithSelector(
                RewardsController.initialize.selector,
                DEPLOYER_ADDRESS,
                address(lendingManager),
                address(tokenVault),
                AUTHORIZED_UPDATER_ADDRESS
            );

            // 7. Deploy TransparentUpgradeableProxy for RewardsController
            console.log("Deploying TransparentUpgradeableProxy for RewardsController...");
            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(rewardsControllerImpl), address(proxyAdmin), initData);
            rewardsControllerProxy = RewardsController(payable(address(proxy)));
            console.log("RewardsController proxy deployed at: %s", address(rewardsControllerProxy));
        }

        // 8. Update LendingManager with actual RewardsController proxy address
        console.log("Updating LendingManager rewardsController role...");
        lendingManager.revokeRewardsControllerRole(temporaryRewardsControllerAddress);
        lendingManager.grantRewardsControllerRole(address(rewardsControllerProxy));
        console.log("LendingManager rewardsController role granted to: %s", address(rewardsControllerProxy));

        // 9. Whitelist NFT collections in RewardsController (only if deploying a new RewardsController)
        if (EXISTING_REWARDS_CONTROLLER_PROXY_ADDRESS == address(0)) {
            console.log("Whitelisting NFT collections in newly deployed RewardsController...");
            for (uint256 i = 0; i < nftConfigs.length; i++) {
                NftConfig memory config = nftConfigs[i];
                require(config.addr != address(0), "NFT Collection address not set for whitelisting");
                rewardsControllerProxy.addNFTCollection(
                    config.addr, config.beta, config.rewardBasis, config.rewardSharePercentage
                );
                string memory logMessage = string.concat(
                    "Whitelisted NFT Collection: ",
                    config.name,
                    " at ",
                    vm.toString(config.addr),
                    " with Beta: ",
                    vm.toString(config.beta),
                    ", Basis: ",
                    vm.toString(uint256(config.rewardBasis)),
                    ", Share: ",
                    vm.toString(config.rewardSharePercentage / 100),
                    "%%"
                );
                console.log(logMessage);
            }
        } else {
            console.log("Skipping NFT whitelisting as an existing RewardsController proxy is used.");
            // Optionally, you could add a check here to verify if the NFT is already whitelisted
            // in the existing RewardsController, but for now, we assume it is.
            for (uint256 i = 0; i < nftConfigs.length; i++) {
                NftConfig memory config = nftConfigs[i];
                if (config.addr != address(0)) {
                    // Log the NFT that would have been whitelisted
                    string memory logMessage = string.concat(
                        "Existing NFT Collection (assumed whitelisted): ", config.name, " at ", vm.toString(config.addr)
                    );
                    console.log(logMessage);
                }
            }
        }

        console.log("--- Deployment Summary ---");
        console.log("Deployer: %s", DEPLOYER_ADDRESS);
        console.log("Authorized Updater: %s", AUTHORIZED_UPDATER_ADDRESS);
        console.log("Reward Token (Asset): %s", address(rewardToken));
        console.log("CToken: %s", address(cToken));
        console.log("ProxyAdmin: %s", address(proxyAdmin));
        console.log("LendingManager: %s", address(lendingManager));
        console.log("TokenVault (ERC4626Vault): %s", address(tokenVault));
        console.log("RewardsController Implementation: %s", address(rewardsControllerImpl));
        console.log("RewardsController Proxy: %s", address(rewardsControllerProxy));
        for (uint256 i = 0; i < nftConfigs.length; i++) {
            console.log("NFT Collection '%s': %s", nftConfigs[i].name, nftConfigs[i].addr);
        }
        console.log("--- Deployment Complete ---");

        vm.stopBroadcast();
    }
}
