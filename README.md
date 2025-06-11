# Collection Vault System

Collection Vault is a set of Solidity contracts that coordinate NFT collection deposits with a yield strategy based on Compound-like lending markets. The repository contains multiple modules that can be deployed separately or combined into a single system.

## Repository Structure

- **src/** – Core contract implementations.
  - `CollectionsVault.sol` – ERC4626 compliant vault that tracks deposits per NFT collection and accrues yield.
  - `LendingManager.sol` – Adapter for depositing assets into a Compound V2 fork and pulling yield back to the vault.
  - `EpochManager.sol` – Utility contract for rolling epochs used to allocate yield over time.
  - `DebtSubsidizer.sol` – Upgradeable contract used for distributing protocol incentives.
  - `mocks/` – Simplified token and cToken mocks used for development.
- **script/** – (planned) deployment and management scripts.
- **foundry.toml** – Foundry configuration file.

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
   forge build
   ```

## Environment Variables

Deployment scripts and tests expect the following environment variables:

- `PRIVATE_KEY` – Deployer key for broadcasting transactions.
- `RPC_URL` – RPC endpoint for the target network.
- Optional variables such as `AUTHORIZED_UPDATER_ADDRESS`, `COLLECTIONS_VAULT_NAME`, `COLLECTIONS_VAULT_SYMBOL` can further customize deployment.

Create a `.env` file in the project root and export these values before running scripts.

## Development Workflow

- `forge build` – Compile the entire project.
- `forge test` – Run the test suite (none are included yet).
- `forge fmt` – Format all Solidity files using Foundry's style.
- `anvil` – Launch a local testnet for manual interaction.
- `forge script` – Execute deployment or utility scripts. Example:
  ```bash
  forge script script/DeploySystem.s.sol:DeploySystem --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
  ```

## License

This project is released under the terms of the MIT License. See [LICENSE](LICENSE) for details.

