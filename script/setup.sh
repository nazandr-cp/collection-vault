#!/usr/bin/env bash
set -euo pipefail

# install dependencies if not present
if [ ! -d "dependencies" ]; then
  forge soldeer install
fi

forge build src

forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "${RPC_URL:-http://anvil:8545}" \
  --private-key "${PRIVATE_KEY}" \
  --broadcast -vvvv
