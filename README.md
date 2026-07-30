# Agama on Starknet

Cairo proof of concept of Agama's private-credit lending product on Starknet, and its
integration with Starknet's native **STRK20** privacy layer.

It ports Agama's core mechanics (deposit → mint `agUSD` 1:1, an allocation engine with
on-chain concentration caps, redeem) to Cairo, and reproduces the official STRK20
**lending-anonymizer** pattern so a shielded user can deposit into an Agama pool privately.

Full lifecycle is tested (9/9 with `snforge`) and deployed + exercised with real
transactions on Starknet Sepolia using native Circle USDC.

## Contracts (`src/`)

| Contract | Role |
|---|---|
| `agama_vault.cairo` | `AgamaVault` — deposit USDC → mint `agUSD` 1:1; `allocate()` across pools with an on-chain **concentration cap**; `deallocate`; `redeem`. Invariant: `agUSD supply == reserve + deployed`. |
| `agama_pool_vault.cairo` | `AgamaPoolVault` — an Agama pool exposed as an **ERC-4626 / SNIP-22** vault (`deposit(assets, receiver)`, `redeem(shares, receiver, owner)`), the interface the STRK20 anonymizer calls. |
| `agama_anonymizer.cairo` | `AgamaLendingAnonymizer` — faithful reproduction of Starknet's STRK20 lending-anonymizer pattern (`privacy_invoke`). The native privacy pool calls it to run deposit/withdraw on the pool on behalf of a shielded user, then pulls the result into an encrypted note. Stateless. |
| `mock_usdc.cairo` | `MockUsdc` — minimal ERC20 standing in for native USDC in tests (`balance_of`, snake_case). |

Reference for the anonymizer pattern: [`starkware-libs/starknet-privacy`](https://github.com/starkware-libs/starknet-privacy), `packages/vesu_lending_anonymizer`. The anonymizer is protocol-agnostic: any ERC-4626/SNIP-22 vault plugs in.

## Tests (`tests/`)

```bash
snforge test
```

`test_vault.cairo`: deposit mints 1:1, redeem burns and returns USDC, allocate within cap,
allocate over cap reverts (`'cap breached'`), allocate requires admin, backing invariant.

`test_strk20_integration.cairo`: shielded deposit into an Agama pool through the anonymizer,
shielded withdraw (redeem) back out, and the anonymizer's equal-token guard.

## Deployed on Starknet Sepolia

Native Circle USDC used: `0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343` (6 decimals).

| Contract | Address |
|---|---|
| AgamaVault | `0x043b86c4822dcc4720c27b183beb5a3d1162c2f2b162e93d42a45e2671482e54` |
| AgamaPoolVault | `0x038ae973209be7daa4c13e6826316232c79c517ca2bc4b92d42c58a6587a4aaf` |
| AgamaLendingAnonymizer | `0x054a349aaefa2d71a18901290465ae057b36ff6577f9c81f9577321bd04a0790` |

Lifecycle exercised on-chain (real tx): deposit 15 USDC → `agUSD`, multi-pool allocate,
concentration-cap revert, deallocate, full redeem/withdraw, and STRK20 anonymizer
deposit + withdraw. Explorer: https://sepolia.voyager.online.

### What is proven vs. what is next

- **Proven on testnet:** the Agama product + the STRK20 contract-level integration (the
  anonymizer executing deposit/withdraw against the Agama ERC-4626 pool).
- **Next (needs Starknet Foundation):** the fully private end-to-end flow — client-side ZK
  proof (Stwo) via the [Privacy SDK](https://github.com/starkware-libs/starknet-privacy) and
  the deployed STRK20 privacy pool invoking the anonymizer via its `INVOKE_SELECTOR`. Fork a
  devnet against the deployed pool to test this locally (see below).

## Dev stack

- **scarb** 2.20, **starknet-foundry** 0.62 (`snforge` tests, `sncast` deploy/interact),
  **starknet-devnet** 0.9 for local dev.
- RPC: `sncast` expects JSON-RPC spec **0.10**. Use **PublicNode**
  (`https://starknet-sepolia-rpc.publicnode.com`) or a dedicated key (Alchemy). Do **not**
  use Blast (decommissioned). Profiles are in `snfoundry.toml`.

```bash
# tests
snforge test

# local devnet (instant, no rate limits, forkable)
starknet-devnet --seed 0
#   fork real Sepolia state to test against the deployed STRK20 pool:
#   starknet-devnet --fork-network sepolia --fork-block <n>

# Sepolia (uses snfoundry.toml default profile = PublicNode + your account)
sncast declare --contract-name AgamaVault
sncast deploy  --class-hash <hash> --constructor-calldata <admin> <usdc> <cap_bps> 0
sncast invoke  --contract-address <vault> --function deposit --calldata <amount> 0
sncast call    --contract-address <vault> --function reserve
```

## Status

Not live on mainnet. Target: Starknet mainnet in 2–3 months, bringing LPs on-chain into
private-credit pools, built on the native STRK20 privacy layer.
