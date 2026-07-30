#!/usr/bin/env bash
# Full acceptance run against the live Agama stack on Starknet Sepolia — real
# transactions, with state assertions and on-chain guard (revert) checks.
#
# Requires the deployed addresses as env vars (USDC, AGUSD, VAULT, ORACLE, ALLOC,
# SAGUSD, QUEUE, OWNER) and the snfoundry.toml default profile. Reads use two RPCs to
# ride out public-endpoint rate limits.
set -uo pipefail

: "${USDC:?}"; : "${AGUSD:?}"; : "${VAULT:?}"; : "${ORACLE:?}"
: "${ALLOC:?}"; : "${SAGUSD:?}"; : "${QUEUE:?}"; : "${OWNER:?}"
D="$OWNER"
PUB="https://starknet-sepolia-rpc.publicnode.com"
CART="https://api.cartridge.gg/x/starknet/sepolia"

getv() { for u in $PUB $CART $PUB $CART $PUB $CART; do
  R=$(sncast call --url "$u" --contract-address "$1" --function "$2" ${3:+--calldata $3} 2>&1 \
        | grep -iE "^Response:" | sed 's/Response:  *//; s/_u[0-9]*//'); [ -n "$R" ] && { echo "$R"; return; }; sleep 2
  done; echo "ERR"; }
send() { sncast --wait invoke --contract-address "$1" --function "$2" --calldata "${@:3}" 2>&1 \
           | grep -i "Transaction Hash" | grep -oE "0x[0-9a-fA-F]+" | head -1; }
rv() { local exp="$1"; shift; local out
  out=$(sncast --wait invoke --contract-address "$1" --function "$2" --calldata "${@:3}" 2>&1)
  echo "$out" | grep -qi "$exp" && echo "PASS reverted ($exp)" || echo "FAIL no-revert"; }

P=0; F=0
chk() { if [ "$1" = "$2" ]; then echo "  ✓ $3 = $1"; P=$((P+1)); else echo "  ✗ $3: got $1 want $2"; F=$((F+1)); fi; }
TS=$(date +%s)

echo "### T1 deposit 5 USDC -> mint agUSD"
R0=$(getv "$VAULT" reserve); send "$USDC" approve "$VAULT" 5000000 0 >/dev/null; send "$VAULT" deposit 5000000 0 >/dev/null
chk "$(getv "$VAULT" reserve)" "$((R0 + 5000000))" "reserve after deposit"

echo "### T2 NAV oracle: fresh push + deviation guard"
send "$ORACLE" push_nav 1050000 0 "$TS" >/dev/null
chk "$(getv "$ORACLE" nav)" "1050000" "nav"; chk "$(getv "$ORACLE" is_stale)" "false" "fresh"
echo "  guard(+25%): $(rv 'deviation too large' "$ORACLE" push_nav 1300000 0 $((TS + 1)))"

echo "### T3 allocation: within-cap + cap guard + deallocate"
TD0=$(getv "$ALLOC" total_deployed); send "$ALLOC" allocate 1 1000000 0 >/dev/null
chk "$(getv "$ALLOC" total_deployed)" "$((TD0 + 1000000))" "deployed after allocate"
echo "  guard(cap): $(rv 'cap breached' "$ALLOC" allocate 1 1000000 0)"
send "$ALLOC" deallocate 1 1000000 0 >/dev/null
chk "$(getv "$ALLOC" total_deployed)" "$TD0" "deployed after deallocate"

echo "### T4 staking stake/distribute/unstake (yield)"
send "$AGUSD" approve "$SAGUSD" 10000000 0 >/dev/null
send "$SAGUSD" stake 5000000 0 >/dev/null; send "$SAGUSD" distribute 2000000 0 >/dev/null
send "$SAGUSD" unstake 5000000 0 >/dev/null
chk "$(getv "$SAGUSD" total_assets)" "0" "staking drained after unstake"

echo "### T5 redeem 5 agUSD -> USDC"
R1=$(getv "$VAULT" reserve); send "$VAULT" redeem 5000000 0 >/dev/null
chk "$(getv "$VAULT" reserve)" "$((R1 - 5000000))" "reserve after redeem"

echo "### T6 withdrawal queue enqueue + process"
send "$QUEUE" enqueue "$D" 1000000 0 >/dev/null; send "$QUEUE" process 1000000 0 >/dev/null
chk "$(getv "$QUEUE" pending)" "0" "queue drained"

echo ""; echo "RESULT: $P checks passed, $F failed"
[ "$F" -eq 0 ]
