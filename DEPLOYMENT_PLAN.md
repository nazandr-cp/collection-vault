# Deployment Plan: `collection-vault/` Contracts

**Date:** 2025-05-22

**Objective:** Deploy the `collection-vault/` system, re-using specific existing contracts (`MockNFT`, `ProxyAdmin`) and Compound fork contract addresses, while deploying new instances of `LendingManager`, `CollectionsVault`, and `RewardsController` (with a new proxy). The script will be configurable via a `.env` file. Post-deployment, addresses will be documented and basic smoke tests run.

---

## Phase 1: Preparation & Configuration

### 1.1. Identify & Consolidate Configuration Parameters

The deployment script will require the following parameters, to be sourced primarily from a `.env` file and `deployed_testnet_addresses.md`.

*   **Re-used Contracts (from `deployed_testnet_addresses.md`):**
    *   `EXISTING_MOCK_NFT_ADDRESS`: `0xf97F713c919655636C0cE006f53a5Be03FA8815a`
    *   `EXISTING_PROXY_ADMIN_ADDRESS`: `0xbfc1C13D96F3e09Dce058aa0aA057b6f725E427a`
*   **Compound Fork Dependencies (from `deployed_testnet_addresses.md`):**
    *   `ASSET_TOKEN_ADDRESS` (Mock DAI): `0xf43EE9653ff96AB50C270eC3D9f0A8e015Df4065`
    *   `C_TOKEN_ADDRESS` (cMDAI): `0x663702880Ec335BB1fae3ca05915B2D24F2b6A48`
*   **Deployment Wallet & Roles:**
    *   `DEPLOYER_ADDRESS`: To be derived from `PRIVATE_KEY`.
    *   `PRIVATE_KEY`: For the deployer wallet (must be provided in `.env`).
    *   `AUTHORIZED_UPDATER_ADDRESS` for `RewardsController`: (e.g., `DEPLOYER_ADDRESS` or a specific admin address, configurable in `.env`).
*   **NFT Whitelisting & Weight Function Parameters for `EXISTING_MOCK_NFT_ADDRESS`:**
    *   `NFT_COLLECTION_TYPE`: `IRewardsController.CollectionType.ERC721` (Hardcoded in script)
    *   `NFT_REWARD_BASIS`: `IRewardsController.RewardBasis.BORROW` (Configurable via `NFT_REWARD_BASIS_ENUM_INDEX` in `.env`)
    *   `NFT_SHARE_PERCENTAGE_BPS`: `5000` (for 50.00%, configurable in `.env`)
    *   `NFT_WEIGHT_FUNCTION_TYPE`: `IRewardsController.WeightFunctionType.LINEAR` (Hardcoded in script)
    *   `NFT_WEIGHT_PARAM_K`: `1e17` (for 0.1, configurable in `.env`)
    *   `NFT_WEIGHT_PARAM_P2`: `0` (Hardcoded in script, as `p2` is not used for the chosen linear function)
*   **New Contract Parameters:**
    *   `COLLECTIONS_VAULT_NAME`: (e.g., "LendFam Collection Vault", configurable in `.env`)
    *   `COLLECTIONS_VAULT_SYMBOL`: (e.g., "lfCV", configurable in `.env`)
*   **Network Configuration:**
    *   `RPC_URL`: RPC endpoint for the target testnet (e.g., ApeChain Curtis, configurable in `.env`).

### 1.2. Create/Update `.env` File

*   **Location:** `collection-vault/.env`
*   **Content Template:**
    ```env
    PRIVATE_KEY=your_deployer_private_key
    RPC_URL=your_apechain_curtis_rpc_url

    # Re-used Contract Addresses
    EXISTING_MOCK_NFT_ADDRESS=0xf97F713c919655636C0cE006f53a5Be03FA8815a
    EXISTING_PROXY_ADMIN_ADDRESS=0xbfc1C13D96F3e09Dce058aa0aA057b6f725E427a

    # Compound Fork Dependencies
    ASSET_TOKEN_ADDRESS=0xf43EE9653ff96AB50C270eC3D9f0A8e015Df4065
    C_TOKEN_ADDRESS=0x663702880Ec335BB1fae3ca05915B2D24F2b6A48

    # Deployment Roles
    AUTHORIZED_UPDATER_ADDRESS= # Defaults to deployer if not set in script, or specify an address

    # NFT Configuration for EXISTING_MOCK_NFT_ADDRESS
    # IRewardsController.RewardBasis: 0:DEPOSIT, 1:BORROW, 2:FIXED_POOL
    NFT_REWARD_BASIS_ENUM_INDEX=1 
    NFT_SHARE_PERCENTAGE_BPS=5000 # 5000 = 50.00%
    NFT_WEIGHT_PARAM_K=100000000000000000 # 0.1 ether (1e17)

    # New Contract Parameters
    COLLECTIONS_VAULT_NAME="LendFam Collection Vault"
    COLLECTIONS_VAULT_SYMBOL="lfCV"
    ```

---

## Phase 2: Develop New Deployment Script

*   **Script Name:** `DeploySystem.s.sol`
*   **Location:** `collection-vault/script/DeploySystem.s.sol`

### 2.1. Script Structure & Imports
*   Standard Foundry `Script` contract.
*   Imports: `forge-std/Script.sol`, `forge-std/console.sol`, `@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol`, project contracts (`LendingManager.sol`, `CollectionsVault.sol`, `RewardsController.sol`), and interfaces (`IERC20.sol`, `CTokenInterface.sol`, `IRewardsController.sol`).

### 2.2. Configuration Variables & `loadConfig()` Function
*   Declare script variables for all parameters defined in Phase 1.1.
*   Implement `loadConfig()` to populate these variables using `vm.envAddress()`, `vm.envUint()`, `vm.envString()`, `vm.envOr()`.
*   Convert `NFT_REWARD_BASIS_ENUM_INDEX` from `.env` to the `IRewardsController.RewardBasis` enum type.
*   Log loaded configurations for verification during script execution.

### 2.3. Deployment Logic in `run()` Function

The `run()` function will perform the following steps sequentially:

1.  **Start Broadcast:** `vm.startBroadcast(vm.envString("PRIVATE_KEY"));`
2.  **Deploy `LendingManager` (New):**
    *   Constructor: `(address owner, address vault, address rewardsController, address asset, address cToken)`
    *   Initialize with `DEPLOYER_ADDRESS` as owner, `ASSET_TOKEN_ADDRESS`, `C_TOKEN_ADDRESS`.
    *   *Decision: Deploy dependencies (`CollectionsVault`, `RewardsController`) first and pass their addresses directly to the `LendingManager` constructor to avoid setter transactions.*
    *   Log the new `LendingManager` address.
3.  **Deploy `CollectionsVault` (New):**
    *   Constructor: `(IERC20 asset, string memory name, string memory symbol, address owner, address lendingManager)`
    *   Initialize with `ASSET_TOKEN_ADDRESS`, `COLLECTIONS_VAULT_NAME`, `COLLECTIONS_VAULT_SYMBOL`, `DEPLOYER_ADDRESS` as owner.
    *   *The `lendingManager` parameter will be the address of the newly deployed `LendingManager`.*
    *   Log the new `CollectionsVault` address.
4.  **Deploy `RewardsController` Implementation (New):**
    *   Deploy the `RewardsController` contract.
    *   Log the new `RewardsController` implementation address.
5.  **Deploy `TransparentUpgradeableProxy` for `RewardsController` (New Proxy):**
    *   `initialize` function selector: `RewardsController.initialize.selector`.
    *   `initData`: `abi.encodeWithSelector(RewardsController.initialize.selector, DEPLOYER_ADDRESS, newLendingManagerAddress, newCollectionsVaultAddress, AUTHORIZED_UPDATER_ADDRESS)`.
    *   Proxy constructor: `(address implementationAddress, address adminAddress, bytes memory data)`.
    *   Use the new `RewardsController` implementation address, the `EXISTING_PROXY_ADMIN_ADDRESS`, and the prepared `initData`.
    *   Log the new `RewardsController` proxy address.
6.  **Link Contracts (Finalize `LendingManager` Configuration):**
    *   Call `newLendingManager.grantVaultRole(newCollectionsVaultAddress)`.
    *   Call `newLendingManager.grantRewardsControllerRole(newRewardsControllerProxyAddress)`.
7.  **Configure `RewardsController` for `EXISTING_MOCK_NFT_ADDRESS`:**
    *   Call `newRewardsControllerProxy.whitelistCollection(EXISTING_MOCK_NFT_ADDRESS, IRewardsController.CollectionType.ERC721, NFT_REWARD_BASIS, uint16(NFT_SHARE_PERCENTAGE_BPS));`
    *   Prepare `WeightFunction` struct: `IRewardsController.WeightFunction memory nftWeightFn = IRewardsController.WeightFunction({ fnType: IRewardsController.WeightFunctionType.LINEAR, p1: int256(NFT_WEIGHT_PARAM_K), p2: 0 });`
    *   Call `newRewardsControllerProxy.setWeightFunction(EXISTING_MOCK_NFT_ADDRESS, nftWeightFn);`
8.  **Stop Broadcast:** `vm.stopBroadcast();`
9.  **Log Summary:** Output all key addresses: Deployer, Asset, cToken, Existing MockNFT, Existing ProxyAdmin, New LendingManager, New CollectionsVault, New RewardsController Impl, New RewardsController Proxy.

---

## Phase 3: Execution and Post-Deployment

### 3.1. Set Environment Variables
*   Ensure the `collection-vault/.env` file is correctly populated with the `PRIVATE_KEY`, `RPC_URL`, and all other configuration parameters as defined in Phase 1.2.

### 3.2. Run Deployment Script
*   Navigate to the `collection-vault/` directory.
*   Execute the script using Foundry:
    ```bash
    forge script script/DeploySystem.s.sol:DeploySystem --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
    ```
*   (Optional) For Etherscan verification, ensure `foundry.toml` is configured with an Etherscan API key and the target network is supported, then add the `--verify` flag.

### 3.3. Document New Addresses
*   From the script\'s log output, carefully record the newly deployed addresses for:
    *   `LendingManager`: `0xa6c21DEe7199DB105E5419eBD811CfF5CE857C4e` (New deployment on 2025-05-22)
    *   `CollectionsVault`: `0xCc7eadE99a0D2A0075ADA98b1b238d9f46DE2495` (New deployment on 2025-05-22)
    *   `RewardsController` (Implementation): `0x10Fb18c1391C28D990Fd43d021C8064Dd02b32ea` (New deployment on 2025-05-22)
    *   `RewardsController` (Proxy): `0xAc7d4e419DDC2E021a795d0598D9366bDD84323F` (New deployment on 2025-05-22)
*   Update the main `deployed_testnet_addresses.md` file in the project root:
    *   (Skipped as `deployed_testnet_addresses.md` not found in workspace)
    *   Under the "Collection Vault Contracts (`collection-vault/`)" section, replace the old addresses for `LendingManager`, `ERC4626Vault` (now `CollectionsVault`), `RewardsController (Implementation)`, and `RewardsController (Proxy)` with the newly deployed ones.
    *   Add a note like "(New deployment on YYYY-MM-DD)" next to each updated address.
    *   Ensure `MockNFT` and `ProxyAdmin` entries reflect their re-used status, e.g., "(Re-used on YYYY-MM-DD)".

### 3.4. Run Basic Smoke Tests
*   **Method:** Use `cast call` commands or a dedicated Foundry test file (`.t.sol`) that interacts with the deployed contracts on the live testnet.
*   **Test Cases:**
    *   **`LendingManager` (New Address - `<LM_ADDR>`):**
        *   `cast call <LM_ADDR> "owner()(address)"` -> Expected: `DEPLOYER_ADDRESS`.
        *   `cast call <LM_ADDR> "asset()(address)"` -> Expected: `ASSET_TOKEN_ADDRESS`.
        *   `cast call <LM_ADDR> "cToken()(address)"` -> Expected: `C_TOKEN_ADDRESS`.
        *   `cast call <LM_ADDR> "vault()(address)"` -> Expected: New `CollectionsVault` address.
        *   `cast call <LM_ADDR> "rewardsController()(address)"` -> Expected: New `RewardsController Proxy` address.
    *   **`CollectionsVault` (New Address - `<CV_ADDR>`):**
        *   `cast call <CV_ADDR> "owner()(address)"` -> Expected: `DEPLOYER_ADDRESS`.
        *   `cast call <CV_ADDR> "asset()(address)"` -> Expected: `ASSET_TOKEN_ADDRESS`.
        *   `cast call <CV_ADDR> "lendingManager()(address)"` -> Expected: New `LendingManager` address.
        *   `cast call <CV_ADDR> "name()(string)"` -> Expected: `COLLECTIONS_VAULT_NAME` from `.env`.
        *   `cast call <CV_ADDR> "symbol()(string)"` -> Expected: `COLLECTIONS_VAULT_SYMBOL` from `.env`.
    *   **`RewardsController Proxy` (New Address - `<RC_PROXY_ADDR>`):**
        *   `cast call <RC_PROXY_ADDR> "owner()(address)"` -> Expected: `DEPLOYER_ADDRESS`. (Note: Proxied calls, actual owner of proxy contract itself is ProxyAdmin).
        *   `cast call <RC_PROXY_ADDR> "lendingManager()(address)"` -> Expected: New `LendingManager` address.
        *   `cast call <RC_PROXY_ADDR> "vault()(address)"` -> Expected: New `CollectionsVault` address.
        *   `cast call <RC_PROXY_ADDR> "authorizedUpdater()(address)"` -> Expected: `AUTHORIZED_UPDATER_ADDRESS` from `.env`.
        *   `cast call <RC_PROXY_ADDR> "isCollectionWhitelisted(address)(bool)" -- "$EXISTING_MOCK_NFT_ADDRESS"` -> Expected: `true`.
        *   `cast call <RC_PROXY_ADDR> "collectionRewardBasis(address)(uint8)" -- "$EXISTING_MOCK_NFT_ADDRESS"` -> Expected: Value corresponding to `NFT_REWARD_BASIS_ENUM_INDEX`.
        *   (Verify `WeightFunction` parameters by calling relevant view functions if available, e.g., a getter for `collectionToWeightFunctionConfig` if it exists, or infer from behavior in more complex tests).

---

## Mermaid Diagram: Deployment Flow

```mermaid
graph TD
    subgraph "Phase 1: Preparation"
        A[Define .env: PK, RPC, Existing Addrs, New Params, NFT Config] --> B{Config Ready?};
    end

    subgraph "Phase 2: Script Execution (DeploySystem.s.sol)"
        B -- Yes --> C[Load Config from .env];
        C --> D[vm.startBroadcast()];
        D --> F[Deploy New CollectionsVault];
        F --> G[Deploy New RewardsController Impl];
        G --> H[Deploy New RewardsController Proxy (uses New Impl, Existing ProxyAdmin, initializes with DEPLOYER_ADDRESS, New CV, AuthUpdater)];
        H --> E[Deploy New LendingManager (initializes with DEPLOYER_ADDRESS, New CV, New RC_Proxy, Asset, cToken)];
        E --> I[Link Contracts: LM.grantVaultRole(CV), LM.grantRewardsControllerRole(RC_Proxy)];
        I --> J[Whitelist MockNFT in New RC_Proxy: whitelistCollection()];
        J --> J2[Set Weight Function for MockNFT in New RC_Proxy: setWeightFunction()];
        J2 --> K[vm.stopBroadcast()];
    end

    subgraph "Phase 3: Post-Deployment"
        K --> L[Log All New & Existing Addresses];
        L --> M[Update deployed_testnet_addresses.md];
        M --> N[Run Basic Smoke Tests (cast calls / test script)];
    end

    subgraph "Inputs/External"
        X1[deployed_testnet_addresses.md: MockNFT, ProxyAdmin, Compound Addrs] --> A;
        X2[User: Deployer PK, RPC URL, AuthUpdater, Vault Name/Symbol, NFT Reward/Share/Weight Params] --> A;
        X3[IRewardsController.sol: Enum definitions, Function Signatures] --> A;
    end

    classDef deployed fill:#c9ffc9,stroke:#333,stroke-width:2px;
    class E,F,G,H deployed;
    classDef reused fill:#lightblue,stroke:#333,stroke-width:2px;
    class X1 reused;
```

*(Note: Mermaid diagram slightly adjusted for constructor dependency flow where LM takes CV and RC_Proxy addresses).*