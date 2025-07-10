# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important
- ALL instructions within this document MUST BE FOLLOWED, these are not optional unless explicitly stated.
- ASK FOR CLARIFICATION If you are uncertain of any of thing within the document.
- DO NOT edit more code than you have to.
- DO NOT WASTE TOKENS, be succinct and concise.


## Architecture Overview

Collection Vault is a Solidity smart contract system implementing NFT collection-backed lending using an ERC4626 vault architecture. The system coordinates deposits per NFT collection with yield strategies through Compound V2 fork integration.

### Core Components

- **CollectionsVault**: ERC4626-compliant vault tracking deposits per NFT collection with yield accrual
- **LendingManager**: Adapter for Compound V2 fork integration, handles asset deposits and yield extraction
- **EpochManager**: Time-based yield allocation system with configurable epochs
- **DebtSubsidizer**: Upgradeable contract for protocol incentive distribution with Merkle proof claims
- **CollectionRegistry**: NFT collection registration with yield share configuration
- **RolesBase/RolesBaseUpgradeable**: Unified access control system with 5-role hierarchy

### Security Architecture

5-role access control hierarchy:
- **OWNER_ROLE**: Ultimate system control and governance
- **ADMIN_ROLE**: Day-to-day administrative operations  
- **OPERATOR_ROLE**: Cross-contract operational calls and automation
- **COLLECTION_MANAGER_ROLE**: Collection-specific operations and management
- **GUARDIAN_ROLE**: Emergency controls and security functions

Advanced security features include circuit breakers, rate limiting, contract validation, and emergency controls.

## Development Commands

### Build and Testing
```bash
# Install dependencies
forge soldeer install

# Build contracts (only src/ directory)
forge build src

# Run tests
forge test

# Format code
forge fmt

# Run specific test
forge test --match-contract CollectionRegistryTest
```

### Fuzzing and Security Testing
```bash
# Run Echidna fuzzing tests
./echidna/run-echidna-tests.sh

# Run specific Echidna test
echidna echidna/EchidnaBasicVault.sol --contract EchidnaBasicVault --test-limit 5000
```

### Deployment
```bash
# Deploy full system (requires .env file)
forge script script/DeployWithExistingNFT.s.sol:DeployWithExistingNFT --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv

# Deploy individual scripts
forge script script/DepositToVault.s.sol:DepositToVault --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
```

### Contract Verification
```bash
# Verify all contracts on block explorer
./scripts/verify-all-contracts.sh
```

### Docker Development
```bash
# Start local Anvil network and deploy contracts
docker compose up deployer
```

## Key Development Patterns

### Library Usage
- `CollectionYieldLib`: Yield calculation and distribution logic
- `CollectionCoreLib`: Core operations and validation

### Access Control Integration
- Standardized role definitions via `Roles.sol`
- `onlyRoleOrGuardian` pattern for emergency overrides
- Unified security features across all contracts

### External Dependencies
- **OpenZeppelin**: ERC4626, AccessControl, upgradeable contracts
- **Compound Protocol**: CToken and Comptroller interfaces for yield generation
- **Forge-std**: Testing framework and utilities

## Environment Configuration

Required environment variables:
- `PRIVATE_KEY`: Deployer private key
- `RPC_URL`: Ethereum RPC endpoint

Optional deployment configuration:
- `AUTHORIZED_UPDATER_ADDRESS`: Address for contract updates
- `COLLECTIONS_VAULT_NAME`: Vault token name
- `COLLECTIONS_VAULT_SYMBOL`: Vault token symbol

## Testing Strategy

### Unit Tests
- Located in `test/` directory
- Use `TestSetup.sol` for consistent test environment
- Mock contracts in `test/mocks/` for isolated testing

### Integration Tests
- Located in `test/integration/` directory
- Test full protocol flows and cross-contract interactions

### Fuzzing Tests
- Located in `echidna/` directory
- Property-based testing with multiple test configurations
- Focus on mathematical invariants and security properties

### Security Analysis
- Slither static analysis integration
- Echidna fuzzing for property verification
- Comprehensive security documentation in `SECURITY_ANALYSIS.md`

## Contract Upgrade Patterns

Upgradeable contracts use OpenZeppelin's proxy pattern:
- `DebtSubsidizer`: Upgradeable for protocol incentive evolution
- `RolesBaseUpgradeable`: Upgradeable base for role management
- Non-upgradeable core contracts for immutability guarantees

## File Structure Conventions

- `src/`: Core contract implementations
- `src/interfaces/`: Contract interfaces
- `src/libraries/`: Reusable library code
- `src/mocks/`: Development and testing mocks
- `script/`: Deployment and management scripts
- `test/`: Test contracts and utilities
- `echidna/`: Fuzzing test contracts and configurations

## Development Notes

- **Forge Script Environment**: Use source env for forge script running