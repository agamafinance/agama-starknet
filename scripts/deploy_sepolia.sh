#!/usr/bin/env bash
# Deploy the Agama production stack to Starknet Sepolia.
#
# Prereqs: scarb + starknet-foundry on PATH, an `agama_deployer` account funded with
# STRK, and snfoundry.toml's default profile pointing at a working RPC (PublicNode).
# Declaring the larger contracts (AllocationEngine) needs a few tens of STRK of
# headroom because sncast sets a high max fee bound; top up via
# https://starknet-faucet.vercel.app if a declare fails with "resources exceed balance".
#
# Usage: scripts/deploy_sepolia.sh
set -euo pipefail

# Circle native USDC on Sepolia (6 decimals). Swap for mainnet USDC on mainnet.
USDC="${USDC:-0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343}"
# Deployer = owner/admin of the stack. Defaults to the account's own address.
OWNER="${OWNER:?set OWNER to the deployer/admin address}"

declare_class() { sncast --wait declare --contract-name "$1" | grep -oE '0x[0-9a-fA-F]{60,}' | head -1; }
deploy() { sncast --wait deploy --class-hash "$1" --constructor-calldata "${@:2}" | grep -A1 'Contract Address' | grep -oE '0x[0-9a-fA-F]+' | head -1; }
invoke() { sncast --wait invoke --contract-address "$1" --function "$2" --calldata "${@:3}" >/dev/null; }

echo "Declaring classes..."
AGUSD_CH=$(declare_class AgamaUSD)
VAULT_CH=$(declare_class AgamaVault)
ORACLE_CH=$(declare_class NavOracle)
ALLOC_CH=$(declare_class AllocationEngine)
QUEUE_CH=$(declare_class WithdrawalQueue)

echo "Deploying instances..."
AGUSD=$(deploy "$AGUSD_CH" "$OWNER")
VAULT=$(deploy "$VAULT_CH" "$OWNER" "$USDC" "$AGUSD")
# initial NAV=1_000_000 (u256), 5% deviation cap (500 bps), 7-day staleness (604800s)
ORACLE=$(deploy "$ORACLE_CH" "$OWNER" 1000000 0 500 0 604800)
ALLOC=$(deploy "$ALLOC_CH" "$OWNER" "$ORACLE")
QUEUE=$(deploy "$QUEUE_CH" "$OWNER")

echo "Wiring..."
invoke "$AGUSD" set_minter "$VAULT"   # only the vault can mint/burn agUSD (shares)

cat <<EOF

Agama production stack (Sepolia)
  USDC             $USDC
  AgamaUSD         $AGUSD   (yield-bearing share token)
  AgamaVault       $VAULT
  NavOracle        $ORACLE
  AllocationEngine $ALLOC
  WithdrawalQueue  $QUEUE
EOF
