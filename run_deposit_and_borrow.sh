#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Set token decimals manually (MockERC20 uses 18 decimals)
# DECIMALS=18

# Calculate scaled amounts using cast parse-ether
SUPPLY2=$(cast parse-units 5000 18)
SUPPLY3=$(cast parse-units 10000 18)
BORROW2=$(cast parse-units 3000 18)
BORROW3=$(cast parse-units 5000 18)

echo "== USER2: Approve, Supply 5,000 mDAI, Enter Market, Borrow 3,000 mDAI =="
# Approve cToken contract to spend USER2's mDAI
cast send $ASSET_ADDRESS \
  "approve(address,uint256)" $CTOKEN_ADDRESS $SUPPLY2 \
  --from $USER2 --private-key $USER2_PRIVATE_KEY --rpc-url $RPC_URL  # success: approved

# Supply collateral: mint cMDAI
cast send $CTOKEN_ADDRESS \
  "mint(uint256)" $SUPPLY2 \
  --from $USER2 --private-key $USER2_PRIVATE_KEY --rpc-url $RPC_URL  # success: supplied collateral

# Enter market
cast send $COMPTROLLER_ADDRESS \
  'enterMarkets(address[])' '['"$CTOKEN_ADDRESS"']' \
  --silent --from $USER2 --private-key $USER2_PRIVATE_KEY --rpc-url $RPC_URL  # success: entered market

# Check if user is in the market
cast call $COMPTROLLER_ADDRESS "checkMembership(address,address)" $USER2 $CTOKEN_ADDRESS --rpc-url $RPC_URL

# Borrow 3,000 mDAI
cast send $CTOKEN_ADDRESS \
  "borrow(uint256)" $BORROW2 \
  --silent --from $USER2 --private-key $USER2_PRIVATE_KEY --rpc-url $RPC_URL  # success: borrowed


echo "== USER3: Approve, Supply 10,000 mDAI, Enter Market, Borrow 5,000 mDAI =="
# Approve cToken contract to spend USER3's mDAI
cast send $ASSET_ADDRESS \
  "approve(address,uint256)" $CTOKEN_ADDRESS $SUPPLY3 \
  --from $USER3 --private-key $USER3_PRIVATE_KEY --rpc-url $RPC_URL  # success: approved

# Supply collateral: mint cMDAI
cast send $CTOKEN_ADDRESS \
  "mint(uint256)" $SUPPLY3 \
  --from $USER3 --private-key $USER3_PRIVATE_KEY --rpc-url $RPC_URL  # success: supplied collateral

# Enter market
cast send $COMPTROLLER_ADDRESS \
  'enterMarkets(address[])' '['"$CTOKEN_ADDRESS"']' \
  --silent --from $USER3 --private-key $USER3_PRIVATE_KEY --rpc-url $RPC_URL  # success: entered market

# Check if user is in the market
cast call $COMPTROLLER_ADDRESS "checkMembership(address,address)" $USER3 $CTOKEN_ADDRESS --rpc-url $RPC_URL

# Borrow 5,000 mDAI
cast send $CTOKEN_ADDRESS \
  "borrow(uint256)" $BORROW3 \
  --silent --from $USER3 --private-key $USER3_PRIVATE_KEY --rpc-url $RPC_URL  # success: borrowed

 echo "All done!"
