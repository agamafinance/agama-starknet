# Changelog

Recap of what Agama on Starknet is and what has been built. Everything below is live and
tested; see the linked docs for tx hashes and reproduction steps.

## Protocol (Cairo, live on Sepolia)

- **agUSD is the single yield-bearing token** (ERC-4626-style vault over USDC). Deposit USDC to
  mint agUSD shares at the current price; redeem to withdraw. No separate staking token.
- **Four lending pools** (`LendingPool`): Pool A private credit 12%, Pool B tokenized treasuries
  5%, Pool C bonds 7%, Pool D on-chain RWA yield 9%. Each accrues yield on its principal at its
  own APR, every block.
- **The vault NAV indexes on the pools**: `total_assets = idle + Σ pool.total_value()`, so the
  agUSD share price rises continuously as the pools earn. `total_assets` is an internal counter,
  which closes the classic ERC-4626 donation/inflation vector.
- Supporting contracts: NavOracle (3 checks + staleness), AllocationEngine (concentration caps),
  WithdrawalQueue (FIFO), pool adapters (Vesu ERC-4626 + originator/CCTP).
- Immutable, OpenZeppelin Cairo components. Deployed and exercised on Starknet Sepolia with real
  transactions (see `docs/e2e-sepolia.md`).

## STRK20 privacy integration

- **`agama_shielded_adapter.cairo`**: the STRK20 invoke anonymizer for the agUSD product. Bridges
  Agama's vault / share-token split so a shielded `privacy_invoke(Deposit, USDC, agUSD, amount)`
  lands directly as yield-bearing agUSD, approved for the privacy pool to seal into a note.
  Deployed on Sepolia and proven on-chain.
- **Verified against StarkWare's real code**: their `vesu_lending_anonymizer` (7/7) and `privacy`
  pool (303/303) suites pass in this environment, the Agama adapter passes against the real
  `privacy::objects` types (3/3), and a full shielded deposit into agUSD runs end-to-end on a
  local devnet with a mock prover. See `strk20-integration/`.
- Finding: the whole shielded flow is testable locally with no permission (open-source SDK +
  public prover image). Only a live public-chain private tx needs StarkWare's proving service.

## Frontend and demos

- **agama-starknet/frontend**: the LP dApp for the Sepolia agUSD vault. Wallet connect (direct
  injected wallet), deposit/redeem, and a live price-per-share chart in the Rocket Pool style
  (dashed y-grid, dated x-axis, range selector). Served locally on port 3009 via launchd.
- **strk20-integration/**: the reproducible STRK20 sources. `demo-shielded.ts` runs the shielded
  flow as a one-command demo; `shielded-server.ts` serves a clickable local web page (Shield /
  Lend to agUSD / Redeem) backed by the real privacy pool + mock prover on a local devnet. It runs
  persistently on port 3012 via launchd (KeepAlive, verified to respawn) and retries transient
  screening reverts (SCREENING_EXPIRED) so shielded ops are robust.

## Tests

- 48 `snforge` tests (unit + Sepolia fork + fuzz invariants), all passing.
- On-chain invariants verified live: `NAV == idle + Σ pool.value`, `vault USDC == realized`,
  pools hold no USDC (marking-only), `NAV >= realized`. Real deposit/redeem/allocate round-trips
  on Sepolia.
- STRK20: the real StarkWare suites pass here (vesu 7/7, privacy pool 303/303), the Agama adapter
  passes against the real `privacy` types (3/3), and the full shielded deposit into agUSD runs
  end-to-end on a local devnet (`agama-lending` e2e) and through the clickable web demo.
- Verified end-to-end across all layers: contracts, real StarkWare suites, devnet shielded e2e,
  the web demo under stress, on-chain invariants and round-trips, and both frontends.

## Live addresses (Starknet Sepolia)

| Contract | Address |
|---|---|
| AgamaUSD (agUSD) | `0x04c0d175cab9fd3163958443830678c9828f52bbbfcd99c04cc52985302abd1f` |
| AgamaVault | `0x059ed11c2b242e766818f3a957a1a9cfe22b0462b4eb7a60bbb71f5ecdb160b1` |
| AgamaShieldedAdapter (STRK20) | `0x075ed504a33de22a9e36e9de6232f51d7e3c6c31a123bb74cc7ab993e473b842` |

USDC (Circle native): `0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343`. Full
address list in the README.
