# Collection Vault System

Collection Vault is a set of Solidity contracts that coordinate NFT collection deposits with a yield strategy based on Compound-like lending markets. The repository contains multiple modules that can be deployed separately or combined into a single system.

## Repository Structure

- **src/** – Core contract implementations.
  - `CollectionsVault.sol` – ERC4626 compliant vault that tracks deposits per NFT collection and accrues yield.
  - `LendingManager.sol` – Adapter for depositing assets into a Compound V2 fork and pulling yield back to the vault.
  - `EpochManager.sol` – Utility contract for rolling epochs used to allocate yield over time.
  - `DebtSubsidizer.sol` – Upgradeable contract used for distributing protocol incentives.
    - Includes `claimAllSubsidies` for batching subsidy claims across multiple vaults.
  - `AccessControlBase.sol` – Base contract providing standardized access control and security features.
  - `CrossContractSecurity.sol` – Advanced security utilities including circuit breakers and rate limiting.
  - `Roles.sol` – Centralized role definitions for the entire system.
  - `mocks/` – Simplified token and cToken mocks used for development.
- **script/** – (planned) deployment and management scripts.
- **foundry.toml** – Foundry configuration file.

## Access Control & Security

The Collection Vault system implements a comprehensive 5-role access control hierarchy with advanced security features:

### Role Hierarchy

| Role | Description | Managed By | Key Responsibilities |
|------|-------------|------------|---------------------|
| **OWNER_ROLE** | Ultimate system control and governance | DEFAULT_ADMIN_ROLE | • Grant/revoke all other roles<br>• Critical system changes<br>• Emergency governance decisions |
| **ADMIN_ROLE** | Day-to-day administrative operations | OWNER_ROLE | • Contract configuration<br>• Non-critical updates<br>• Standard admin functions<br>• Manage operational roles |
| **OPERATOR_ROLE** | Cross-contract operational calls and automation | ADMIN_ROLE | • Automated system calls<br>• Cross-contract interactions<br>• Vault operations<br>• Epoch management |
| **COLLECTION_MANAGER_ROLE** | Collection-specific operations and management | ADMIN_ROLE | • Collection registration<br>• Yield share management<br>• Vault-collection associations |
| **GUARDIAN_ROLE** | Emergency controls and security functions | OWNER_ROLE | • Pause/unpause contracts<br>• Emergency actions<br>• Circuit breaker overrides<br>• Security responses |

### Security Features

- **🔒 Circuit Breakers**: Automatic protection against external contract failures
- **⏱️ Rate Limiting**: Prevents abuse of automated system functions  
- **🛡️ Contract Validation**: Ensures external dependencies remain secure
- **💰 Transfer Protection**: Large amount controls with cooldowns
- **🚨 Emergency Controls**: Guardian-level pause and override capabilities
- **📊 Security Monitoring**: Comprehensive event logging for all role changes

### Role Assignment Guidelines

1. **OWNER_ROLE**: Should be a multisig wallet or DAO governance contract
2. **ADMIN_ROLE**: Trusted administrators for daily operations
3. **OPERATOR_ROLE**: Automated systems, trusted vaults, and operational contracts
4. **COLLECTION_MANAGER_ROLE**: Collection managers and registry operators
5. **GUARDIAN_ROLE**: Security team members and emergency response systems

### Contract-Specific Permissions

| Contract | Additional Access Controls |
|----------|---------------------------|
| **CollectionsVault** | Collection-specific operators for deposit/withdraw operations |
| **LendingManager** | Vault-specific roles for lending protocol interactions |
| **DebtSubsidizer** | Merkle root updates and subsidy pool management |
| **EpochManager** | Epoch lifecycle management and automation |
| **CollectionRegistry** | Collection registration and configuration |

## Getting Started

1. **Install Foundry** if it is not already available:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   source ~/.bashrc
   foundryup
   ```
2. **Install dependencies** (only required once):
   ```bash
   forge soldeer install
   ```
3. **Build the contracts**:
   ```bash
   forge build src
   ```

## Environment Variables

Deployment scripts and tests expect the following environment variables:

- `PRIVATE_KEY` – Deployer key for broadcasting transactions.
- `RPC_URL` – RPC endpoint for the target network.
- Optional variables such as `AUTHORIZED_UPDATER_ADDRESS`, `COLLECTIONS_VAULT_NAME`, `COLLECTIONS_VAULT_SYMBOL` can further customize deployment.

Create a `.env` file in the project root and export these values before running scripts.

## Development Workflow

 - `forge build src` – Compile the core contracts.
- `forge test` – Run the test suite (none are included yet).
- `forge fmt` – Format all Solidity files using Foundry's style.
- `anvil` – Launch a local testnet for manual interaction.
- `forge script` – Execute deployment or utility scripts. Example:
  ```bash
  forge script script/DeploySystem.s.sol:DeploySystem --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
  ```

## License

This project is released under the terms of the MIT License. See [LICENSE](LICENSE) for details.


## Docker Local Setup

A Docker configuration is provided for quickly deploying the entire system on a local Anvil network. To start the environment run:

```bash
docker compose up deployer
```

The compose file builds a container with Foundry, launches an Anvil instance, and runs `script/setup.sh`. The script installs dependencies, compiles only the contracts in `src/`, and deploys:

- Mock ERC20 and ERC721 tokens
- Minimal Compound contracts (`Comptroller` and `WhitePaperInterestRateModel`)
- `SimpleMockCToken`, `LendingManager`, `CollectionsVault`, `EpochManager` and `DebtSubsidizer`

The script requires a `PRIVATE_KEY` environment variable, which should match one of the funded Anvil accounts (the default is fine). The deployed addresses will be printed to the console.
