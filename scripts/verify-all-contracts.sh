#!/bin/bash

# Contract verification script for Blockscout
# This script verifies all deployed contracts on the Curtis explorer

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Contract addresses from .env file
# Use the latest deployment addresses
LENDING_MANAGER_ADDRESS="${LENDING_MANAGER_ADDRESS}"
COLLECTION_REGISTRY_ADDRESS="${COLLECTION_REGISTRY_ADDRESS}"
COLLECTIONS_VAULT_ADDRESS="${VAULT_ADDRESS}"
EPOCH_MANAGER_ADDRESS="${EPOCH_MANAGER_ADDRESS}"
DEBT_SUBSIDIZER_ADDRESS="${DEBT_SUBSIDIZER_PROXY_ADDRESS}"  # Use proxy address for verification

# Verification settings
# Use RPC_URL from .env file
VERIFIER="blockscout"
VERIFIER_URL="https://curtis.explorer.caldera.xyz/api/"

echo -e "${BLUE}🔍 Starting contract verification on Curtis Blockscout...${NC}\n"

# Function to verify a contract with error handling
verify_contract() {
    local address=$1
    local contract_path=$2
    local contract_name=$3
    local description=$4
    
    echo -e "${YELLOW}Verifying $description...${NC}"
    echo -e "Address: ${BLUE}$address${NC}"
    echo -e "Contract: ${BLUE}$contract_path:$contract_name${NC}"
    
    if forge verify-contract \
        --rpc-url "${RPC_URL}" \
        --verifier "$VERIFIER" \
        --verifier-url "$VERIFIER_URL" \
        "$address" \
        "$contract_path:$contract_name" 2>&1; then
        echo -e "${GREEN}✅ $description verified successfully${NC}"
        echo -e "Explorer: ${BLUE}https://curtis.explorer.caldera.xyz/address/$address${NC}\n"
    else
        echo -e "${RED}❌ Failed to verify $description${NC}"
        echo -e "Address: $address${NC}\n"
    fi
}

# Verify all contracts
echo -e "${BLUE}=== Core Protocol Contracts ===${NC}\n"

verify_contract \
    "$COLLECTION_REGISTRY_ADDRESS" \
    "src/CollectionRegistry.sol" \
    "CollectionRegistry" \
    "Collection Registry"

verify_contract \
    "$COLLECTIONS_VAULT_ADDRESS" \
    "src/CollectionsVault.sol" \
    "CollectionsVault" \
    "Collections Vault"

verify_contract \
    "$LENDING_MANAGER_ADDRESS" \
    "src/LendingManager.sol" \
    "LendingManager" \
    "Lending Manager"

verify_contract \
    "$EPOCH_MANAGER_ADDRESS" \
    "src/EpochManager.sol" \
    "EpochManager" \
    "Epoch Manager"

verify_contract \
    "$DEBT_SUBSIDIZER_ADDRESS" \
    "src/DebtSubsidizer.sol" \
    "DebtSubsidizer" \
    "Debt Subsidizer"

echo -e "${BLUE}=== Mock/Test Contracts ===${NC}\n"

verify_contract \
    "${ASSET_ADDRESS}" \
    "src/mocks/MockERC20.sol" \
    "MockERC20" \
    "Mock ERC20 (USDC)"

verify_contract \
    "${NFT_ADDRESS}" \
    "src/mocks/MockERC721.sol" \
    "MockERC721" \
    "Mock NFT Collection"

echo -e "${BLUE}=== External Contracts (Compound) ===${NC}\n"

# Note: Compound contracts might be already verified or use different source paths
echo -e "${YELLOW}Note: Compound contracts (cToken, Comptroller) may already be verified${NC}"
echo -e "cToken Address: ${BLUE}${CTOKEN_ADDRESS}${NC}"
echo -e "Comptroller Address: ${BLUE}${COMPTROLLER_ADDRESS}${NC}\n"

# Summary
echo -e "${GREEN}🎉 Contract verification process completed!${NC}\n"

echo -e "${BLUE}=== Verification Summary ===${NC}"
echo -e "Collection Registry:  https://curtis.explorer.caldera.xyz/address/${COLLECTION_REGISTRY_ADDRESS}"
echo -e "Collections Vault:    https://curtis.explorer.caldera.xyz/address/${COLLECTIONS_VAULT_ADDRESS}"
echo -e "Lending Manager:      https://curtis.explorer.caldera.xyz/address/${LENDING_MANAGER_ADDRESS}"
echo -e "Epoch Manager:        https://curtis.explorer.caldera.xyz/address/${EPOCH_MANAGER_ADDRESS}"
echo -e "Debt Subsidizer:      https://curtis.explorer.caldera.xyz/address/${DEBT_SUBSIDIZER_ADDRESS}"
echo -e "Mock USDC:            https://curtis.explorer.caldera.xyz/address/${ASSET_ADDRESS}"
echo -e "Mock NFT:             https://curtis.explorer.caldera.xyz/address/${NFT_ADDRESS}"

echo -e "\n${GREEN}All contracts submitted for verification!${NC}"
echo -e "${YELLOW}Note: Verification may take a few minutes to complete on the explorer.${NC}"