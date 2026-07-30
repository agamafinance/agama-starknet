# Agama on Starknet

Cairo implementation of Agama's compliant private-credit lending protocol on Starknet,
built to run on the native **STRK20** privacy layer.

Lenders deposit USDC through Starknet's native **STRK20** privacy layer and receive `agUSD`,
Agama's single **yield-bearing** LP token. The vault reserve is auto-allocated by an on-chain
engine across lending pools — private credit, tokenized treasuries, bonds, on-chain RWA yield —
under concentration caps and marked by a NAV oracle, so the real-world yield accrues to `agUSD`
holders. Redeem `agUSD` at any time to withdraw USDC. Deposits are shielded through Starknet's
native STRK20 pool via the official lending-anonymizer pattern.

Contracts use OpenZeppelin's audited Cairo components and are **immutable** (no upgradeability).
Everything is tested with `snforge` (unit + fork tests) and exercised on Starknet Sepolia.

## Architecture

![Agama on Starknet — architecture](docs/architecture.jpg)

An LP deposits USDC, shielded through the native STRK20 privacy pool, and mints `agUSD`. The
vault auto-allocates the reserve across the Agama lending pools; yield flows back to `agUSD`,
so the single token is what LPs hold, redeem, and earn on.

## Contracts (`src/`)

| Contract | Role |
|---|---|
| `agusd.cairo` | `AgamaUSD` — synthetic dollar. OZ ERC20, 6 decimals, mint/burn restricted to the vault (minter), owner-set minter. |
| `vault.cairo` | `AgamaVault` — deposit USDC → mint `agUSD` 1:1; redeem → burn `agUSD` and return USDC; holds the reserve. |
| `nav_oracle.cairo` | `NavOracle` — pushes RWA NAV with three checks (authorized reporter, monotonic timestamp, ≤5% deviation else admin override) and a staleness gate that blocks allocations/withdrawals. |
| `allocation_engine.cairo` | `AllocationEngine` — admin pool registration (no self-listing), per-pool **concentration caps** enforced on-chain, allocations blocked while the oracle is stale. |
| `withdrawal_queue.cairo` | `WithdrawalQueue` — FIFO redemptions settled in order as USDC returns from settlement. |
| `pool_adapter.cairo` | `IPoolAdapter` + `VesuAdapter` (on-chain ERC-4626 / SNIP-22, e.g. Vesu) + `OriginatorAdapter` (off-chain private-credit originator via native USDC + CCTP). |
| `agama_pool_vault.cairo` | `AgamaPoolVault` — an Agama pool as an ERC-4626 / SNIP-22 vault, the interface the STRK20 anonymizer calls. |
| `agama_anonymizer.cairo` | `AgamaLendingAnonymizer` — the official STRK20 lending-anonymizer pattern (`privacy_invoke`): the native privacy pool runs deposit/withdraw on an Agama pool for a shielded user, then pulls the result into an encrypted note. |
| `mock_usdc.cairo` | Minimal ERC20 standing in for native USDC in tests. |

## STRK20 privacy integration

The on-chain integration is the **anonymizer** (`agama_anonymizer.cairo`), a faithful
reproduction of Starknet's official pattern
([`starkware-libs/starknet-privacy`](https://github.com/starkware-libs/starknet-privacy),
`packages/vesu_lending_anonymizer`). It is protocol-agnostic: any ERC-4626 / SNIP-22 vault
plugs in, and `agama_pool_vault.cairo` exposes exactly that interface.

- **Built and tested:** the anonymizer's shielded deposit/withdraw against an Agama pool, at
  the contract level (unit tests + exercised on Sepolia).
- **Fork-ready:** `tests/test_fork.cairo` runs against real Sepolia state (validated today
  against Circle's native USDC). The same harness will test the anonymizer against the
  **deployed STRK20 privacy pool** once the Starknet Foundation shares its Sepolia address.
- **Then, end-to-end private:** client-side ZK proof (Stwo) via the Privacy SDK, with the
  deployed pool invoking the anonymizer through its `INVOKE_SELECTOR`.

## Tests

```bash
snforge test
```

Tests cover: agUSD mint/burn access control, vault deposit/redeem, NAV oracle (three
checks + admin override + staleness), allocation engine (caps + registration + oracle gate),
yield accrual, FIFO withdrawal queue, pool adapters (Vesu + originator), the STRK20 anonymizer
deposit/withdraw, and a Sepolia fork test against real Circle USDC.

## Dev stack

- **scarb** 2.20, **starknet-foundry** 0.62 (`snforge`, `sncast`), **starknet-devnet** 0.9.
- OpenZeppelin Cairo 3.0.
- RPC: `sncast` expects JSON-RPC spec **0.10**. Use **PublicNode**
  (`https://starknet-sepolia-rpc.publicnode.com`) or a dedicated key (Alchemy). Do **not**
  use Blast (decommissioned). Profiles live in `snfoundry.toml`.

```bash
snforge test                                   # unit + fork tests
starknet-devnet --seed 0                        # local node (instant, forkable)
sncast declare --contract-name AgamaVault       # Sepolia (default profile)
```

## Live on Sepolia

The production stack deploys with `scripts/deploy_sepolia.sh` and is exercised end-to-end
with `scripts/e2e_sepolia.sh` (see [`docs/e2e-sepolia.md`](docs/e2e-sepolia.md) for the run
with tx hashes: vault redeem/deposit round-trip, NAV oracle push at the deviation cap, and
withdrawal-queue drain — all real transactions).

| Contract | Address |
|---|---|
| AgamaUSD (agUSD) | `0x0143b8bf5144be0c0568410b6f8c3eb90629ddadfd0da9ac3a90cb35ec1b6006` |
| AgamaVault | `0x07909652ce28348eabfdce6b67a82228513798c70d5e06ec23fc2028abc261b5` |
| NavOracle | `0x0524c9683f467d7c0ddc51b0b83352e33a2300bae006af90d9eb9ecad6349679` |
| WithdrawalQueue | `0x00a8f8cae024f97dd63c5fb90444d49ede807b23b25441d563b77450a8431493` |
| AllocationEngine | `0x013be6562483ab26ea3b1609580b8246eeb3542fbd57c7c583c036a46dc72bb9` |

USDC (Circle native): `0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343`.
The full stack is live. Explorer: https://sepolia.voyager.online

## Status

Not live on mainnet. Target: Starknet mainnet in 2–3 months, bringing LPs on-chain into
private-credit pools on the native STRK20 privacy layer. Contracts are immutable; a security
audit is planned before mainnet.
