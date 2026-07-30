#!/usr/bin/env bash
# End-to-end exercise of the live Agama stack on Starknet Sepolia (real transactions).
#
# Uses sncast + the snfoundry.toml default profile (PublicNode + the deployer account).
# Set the deployed addresses as env vars, then run: scripts/e2e_sepolia.sh
#
#   USDC, AGUSD, VAULT     (required, already live)
#   ORACLE, QUEUE          (optional; the flow adapts to what is deployed)
set -uo pipefail

USDC="${USDC:?set USDC}"
AGUSD="${AGUSD:?set AGUSD}"
VAULT="${VAULT:?set VAULT}"
ORACLE="${ORACLE:-}"
QUEUE="${QUEUE:-}"
OWNER="${OWNER:?set OWNER (deployer address)}"

inv() { sncast --wait invoke --contract-address "$1" --function "$2" --calldata "${@:3}" 2>&1 \
          | grep -iE "Transaction Hash" | grep -oE "0x[0-9a-fA-F]+" | head -1; }
rd()  { sncast call --contract-address "$1" --function "$2" ${3:+--calldata $3} 2>&1 \
          | grep -iE "^Response:" | sed 's/Response:  *//'; }

# Yield-bearing round-trip: deposit 3 USDC -> mint 3 agUSD shares, distribute 2 USDC of
# yield (owner only) so the share price rises to ~1.667, then redeem the 3 shares for 5 USDC.
echo "## 1. yield-bearing round-trip (agUSD share price rises with distributed yield)"
echo "  agUSD balance before : $(rd "$AGUSD" balance_of "$OWNER")"
echo "  approve 3 USDC       : $(inv "$USDC" approve "$VAULT" 3000000 0)"
echo "  deposit 3 USDC       : $(inv "$VAULT" deposit 3000000 0)"
echo "  agUSD shares minted  : $(rd "$AGUSD" balance_of "$OWNER")"
echo "  approve 2 USDC yield : $(inv "$USDC" approve "$VAULT" 2000000 0)"
echo "  distribute 2 USDC    : $(inv "$VAULT" distribute 2000000 0)"
echo "  total_assets         : $(rd "$VAULT" total_assets)"
echo "  3 agUSD now worth    : $(rd "$VAULT" convert_to_assets 3000000) USDC"
echo "  redeem 3 agUSD       : $(inv "$VAULT" redeem 3000000 0)"
echo "  agUSD balance after  : $(rd "$AGUSD" balance_of "$OWNER")"

if [ -n "$ORACLE" ]; then
  echo "## 2. NAV oracle push"
  echo "  add reporter         : $(inv "$ORACLE" add_reporter "$OWNER")"
  TS=$(date +%s)
  echo "  push_nav(1050000)    : $(inv "$ORACLE" push_nav 1050000 0 "$TS")"
  echo "  nav / stale          : $(rd "$ORACLE" nav) / $(rd "$ORACLE" is_stale)"
fi

if [ -n "$QUEUE" ]; then
  echo "## 3. withdrawal queue"
  echo "  enqueue 1            : $(inv "$QUEUE" enqueue "$OWNER" 1000000 0)"
  echo "  process              : $(inv "$QUEUE" process 1000000 0)"
  echo "  pending              : $(rd "$QUEUE" pending)"
fi

echo "Done."
