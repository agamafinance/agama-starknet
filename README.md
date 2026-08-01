# Agama on Starknet

Cairo implementation of Agama's compliant private-credit lending protocol on Starknet,
built to run on the native **STRK20** privacy layer.

Lenders deposit USDC through Starknet's native **STRK20** privacy layer and receive `agUSD`,
Agama's single **yield-bearing** LP token. The vault reserve is auto-allocated by an on-chain
engine across lending pools (private credit, tokenized treasuries, bonds, on-chain RWA yield)
under concentration caps and marked by a NAV oracle, so the real-world yield accrues to `agUSD`
holders. Redeem `agUSD` at any time to withdraw USDC. Deposits are shielded through Starknet's
native STRK20 pool via the official lending-anonymizer pattern.

Contracts use OpenZeppelin's audited Cairo components and are **immutable** (no upgradeability).
Everything is tested with `snforge` (unit + fork tests) and exercised on Starknet Sepolia.

## Architecture

![Agama on Starknet architecture](docs/architecture.jpg)

An LP deposits USDC, shielded through the native STRK20 privacy pool, and mints `agUSD`. Behind
`agUSD` sit the four Agama lending pools: Pool A (private credit, 12%), Pool B (tokenized
treasuries, 5%), Pool C (bonds, 7%), Pool D (on-chain RWA yield, 9%). Each is a `LendingPool`
contract that accrues yield on its allocated principal at its own APR, every block. The vault's
**NAV is the sum of every pool's marked value plus the idle reserve**, and the `agUSD` share
price is `NAV / agUSD_supply`. So as the pools earn, the price rises continuously: 1 `agUSD` is
worth strictly more USDC each second, with no manual step. The single token is what LPs hold,
redeem, and earn on; the dApp reads the raw pool state and projects the price live to the
micro-USDC. Concentration caps, the NAV oracle mark, and realized-cash settlement (`distribute`)
back the model on the way to mainnet.

## Contracts (`src/`)

| Contract | Role |
|---|---|
| `agusd.cairo` | `AgamaUSD`: the yield-bearing LP **share token**. OZ ERC20, 6 decimals, mint/burn restricted to the vault (minter), owner-set minter. |
| `vault.cairo` | `AgamaVault`: the yield-bearing core. `deposit` mints `agUSD` shares at the current price; `redeem` burns shares for USDC; `allocate`/`deallocate` deploy the reserve into lending pools; `distribute` adds realized cash yield. **NAV = idle + Σ pool.total_value()**, so the `agUSD` price indexes on the aggregate pools. Donation-attack safe (idle only moves via deposit/redeem/allocate/distribute). |
| `lending_pool.cairo` | `LendingPool`: one Agama lending pool as a yield-bearing NAV position. Allocated `principal` accrues at the pool's `apr_bps` continuously (`total_value = principal + accrued + pending(now)`); Pool A/B/C/D run private-credit / treasuries / bonds / RWA rates. Vault-gated fund/defund, admin-set APR. |
| `nav_oracle.cairo` | `NavOracle`: pushes RWA NAV with three checks (authorized reporter, monotonic timestamp, ≤5% deviation else admin override) and a staleness gate that blocks allocations/withdrawals. |
| `allocation_engine.cairo` | `AllocationEngine`: admin pool registration (no self-listing), per-pool **concentration caps** enforced on-chain, allocations blocked while the oracle is stale. |
| `withdrawal_queue.cairo` | `WithdrawalQueue`: FIFO redemptions settled in order as USDC returns from settlement. |
| `pool_adapter.cairo` | `IPoolAdapter` + `VesuAdapter` (on-chain ERC-4626 / SNIP-22, e.g. Vesu) + `OriginatorAdapter` (off-chain private-credit originator via native USDC + CCTP). |
| `agama_pool_vault.cairo` | `AgamaPoolVault`: an Agama pool as an ERC-4626 / SNIP-22 vault, the interface the STRK20 anonymizer calls. |
| `agama_anonymizer.cairo` | `AgamaLendingAnonymizer`: the official STRK20 lending-anonymizer pattern (`privacy_invoke`): the native privacy pool runs deposit/withdraw on an Agama pool for a shielded user, then pulls the result into an encrypted note. |
| `agama_shielded_adapter.cairo` | `AgamaShieldedAdapter`: the STRK20 invoke anonymizer for the live agUSD product. Bridges the vault / share-token split so a shielded `privacy_invoke(Deposit, USDC, agUSD, amount)` lands directly as yield-bearing `agUSD`, approved for the privacy pool to seal into a note. |
| `mock_usdc.cairo` | Minimal ERC20 standing in for native USDC in tests. |

## STRK20 privacy integration

STRK20 is Starknet's native, note-based privacy standard (StarkWare,
[`starkware-libs/starknet-privacy`](https://github.com/starkware-libs/starknet-privacy)), live
on Starknet since June 2026 with USDC support. A protocol plugs in by providing an **invoke
anonymizer**: an on-chain contract the privacy pool calls (`privacy_invoke`) to run the lending
leg for a shielded user, then pulls the result into an encrypted note.

Agama provides exactly that, in two forms:

- `agama_anonymizer.cairo`: a faithful reproduction of the official Vesu pattern, for any
  ERC-4626 / SNIP-22 vToken (`agama_pool_vault.cairo` exposes that interface).
- `agama_shielded_adapter.cairo`: the invoke anonymizer for the **live agUSD product**. It
  bridges Agama's vault / share-token split so a shielded deposit lands directly as yield-bearing
  `agUSD`. Deployed on Sepolia and exercised on-chain: a stand-in privacy pool calls
  `privacy_invoke(Deposit, USDC, agUSD, amount)`, the adapter deposits into the vault, receives
  `agUSD` at the current NAV price, and approves the pool to seal it into a note (see
  [`docs/e2e-sepolia.md`](docs/e2e-sepolia.md) for the tx).

**Verified against StarkWare's real code.** The whole STRK20 stack is testable at the contract
level, and it passes in this environment. Running StarkWare's own suites: 7/7 for
`vesu_lending_anonymizer` and 303/303 for the `privacy` pool (the deposit/withdraw private flow,
viewing keys, notes, and an anonymizer driven through the real pool). And the Agama adapter,
compiled against the **real** `privacy::objects::OpenNoteDeposit` (not a copy), passes its own
shielded deposit/withdraw tests, see [`strk20-integration/`](strk20-integration/). So Agama is a
valid STRK20 invoke anonymizer against StarkWare's actual privacy package.

**The full shielded flow is testable locally, no permission required.** StarkWare's SDK is
open-source (in the `starknet-privacy` repo), and their own e2e runs the entire shielded lending
path on a local devnet with a **mock prover**: deposit into the privacy pool, withdraw to the
anonymizer, the anonymizer deposits into the lending vault, the received token lands in an
encrypted note. We reproduced this end-to-end locally (patched starknet-devnet + the SDK +
discovery service), and StarkWare's `vesu-lending` devnet test passes here. So development and
integration of the Agama lending leg need nothing from StarkWare.

**What needs the real prover.** Only a live public-chain private transaction needs StarkWare's
**operator-run proving service** (client-side ZK via Stwo), because the sequencer verifies a real
proof on chain (SNIP-36). The pool and anonymizer contract classes are already declared on public
Sepolia (verified on-chain), and the Agama adapter is deployed there. So mainnet is the only step
gated on proving-service access (a partnership unlock), not any Agama contract or test work.

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

The production stack deploys with `scripts/deploy_sepolia.sh` and is exercised end-to-end with
real transactions (see [`docs/e2e-sepolia.md`](docs/e2e-sepolia.md) for tx hashes): the
yield-bearing round-trip (deposit USDC → `distribute` RWA yield → the `agUSD` share price rises
→ redeem returns the appreciated USDC), the NAV oracle push at the deviation cap, and the
withdrawal-queue drain.

| Contract | Address |
|---|---|
| AgamaUSD (agUSD, yield-bearing share) | `0x04c0d175cab9fd3163958443830678c9828f52bbbfcd99c04cc52985302abd1f` |
| AgamaVault | `0x059ed11c2b242e766818f3a957a1a9cfe22b0462b4eb7a60bbb71f5ecdb160b1` |
| LendingPool A (private credit, 12%) | `0x07fd9db4d3377e6909555ea100b631784048de519e0100f32d5877180ebb55ad` |
| LendingPool B (tokenized treasuries, 5%) | `0x018d17c95680bc634ffaa4211be8db4bfec2625ff614a2faf925422c44e3eb2d` |
| LendingPool C (bonds, 7%) | `0x0438cd90d88358b574690ccdd8fd17370245929bed2d390f27bc984cbcf206e6` |
| LendingPool D (onchain RWA yield, 9%) | `0x01ac07c1564032d8c3d02bdff1f9661783f3abc3b97ccdc6de318f70a171249f` |
| NavOracle | `0x0524c9683f467d7c0ddc51b0b83352e33a2300bae006af90d9eb9ecad6349679` |
| WithdrawalQueue | `0x00a8f8cae024f97dd63c5fb90444d49ede807b23b25441d563b77450a8431493` |
| AllocationEngine | `0x013be6562483ab26ea3b1609580b8246eeb3542fbd57c7c583c036a46dc72bb9` |
| AgamaShieldedAdapter (STRK20) | `0x075ed504a33de22a9e36e9de6232f51d7e3c6c31a123bb74cc7ab993e473b842` |

USDC (Circle native): `0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343`.
The full stack is live. Explorer: https://sepolia.voyager.online

## Status

Not live on mainnet. Target: Starknet mainnet in 2 to 3 months, bringing LPs on-chain into
private-credit pools on the native STRK20 privacy layer. Contracts are immutable; a security
audit is planned before mainnet.
