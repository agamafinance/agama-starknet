#!/usr/bin/env bash
# End-to-end exercise of the live Agama stack on Starknet Sepolia (real transactions).
#
# Uses sncast + the snfoundry.toml default profile (PublicNode + the deployer account).
# Set the deployed addresses as env vars, then run: scripts/e2e_sepolia.sh
#
#   USDC, AGUSD, VAULT     (required, already live)
#   ORACLE, QUEUE, SAGUSD  (optional; the flow adapts to what is deployed)
set -uo pipefail

USDC="${USDC:?set USDC}"
AGUSD="${AGUSD:?set AGUSD}"
VAULT="${VAULT:?set VAULT}"
ORACLE="${ORACLE:-}"
QUEUE="${QUEUE:-}"
SAGUSD="${SAGUSD:-}"
OWNER="${OWNER:?set OWNER (deployer address)}"

inv() { sncast --wait invoke --contract-address "$1" --function "$2" --calldata "${@:3}" 2>&1 \
          | grep -iE "Transaction Hash" | grep -oE "0x[0-9a-fA-F]+" | head -1; }
rd()  { sncast call --contract-address "$1" --function "$2" ${3:+--calldata $3} 2>&1 \
          | grep -iE "^Response:" | sed 's/Response:  *//'; }

echo "## 1. vault redeem/deposit round-trip (production agUSD)"
echo "  agUSD balance before : $(rd "$AGUSD" balance_of "$OWNER")"
echo "  vault reserve        : $(rd "$VAULT" reserve)"
echo "  redeem 5 agUSD       : $(inv "$VAULT" redeem 5000000 0)"
echo "  approve 5 USDC       : $(inv "$USDC" approve "$VAULT" 5000000 0)"
echo "  deposit 5 USDC       : $(inv "$VAULT" deposit 5000000 0)"
echo "  agUSD balance after  : $(rd "$AGUSD" balance_of "$OWNER")"

if [ -n "$ORACLE" ]; then
  echo "## 2. NAV oracle push"
  echo "  add reporter         : $(inv "$ORACLE" add_reporter "$OWNER")"
  TS=$(date +%s)
  echo "  push_nav(1050000)    : $(inv "$ORACLE" push_nav 1050000 0 "$TS")"
  echo "  nav / stale          : $(rd "$ORACLE" nav) / $(rd "$ORACLE" is_stale)"
fi

if [ -n "$SAGUSD" ]; then
  echo "## 3. sagUSD stake"
  echo "  approve agUSD        : $(inv "$AGUSD" approve "$SAGUSD" 5000000 0)"
  echo "  stake 5 agUSD        : $(inv "$SAGUSD" stake 5000000 0)"
  echo "  sagUSD balance       : $(rd "$SAGUSD" balance_of "$OWNER")"
fi

if [ -n "$QUEUE" ]; then
  echo "## 4. withdrawal queue"
  echo "  enqueue 1            : $(inv "$QUEUE" enqueue "$OWNER" 1000000 0)"
  echo "  process              : $(inv "$QUEUE" process 1000000 0)"
  echo "  pending              : $(rd "$QUEUE" pending)"
fi

echo "Done."
