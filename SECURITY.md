# Security

This document is the threat model and audit scope for the Agama Starknet contracts. The
contracts are **immutable** (no upgradeability) and use OpenZeppelin Cairo components.

## Reporting

Report vulnerabilities privately to **security@agama.finance** (placeholder). Please do not
open public issues for security bugs.

## Audit scope (`src/`)

`agusd` · `vault` · `nav_oracle` · `allocation_engine` · `sagusd` · `withdrawal_queue` ·
`pool_adapter` (VesuAdapter, OriginatorAdapter) · `agama_pool_vault` · `agama_anonymizer`.
`mock_usdc` is test-only and out of scope.

## Trust model

- **Admin (Ownable `owner`)** — trusted, and must be a multisig in production. It can: set the
  agUSD minter, register pools and set concentration caps, add/remove oracle reporters, push a
  NAV beyond the deviation cap (`push_nav_admin`), and drive the withdrawal queue. Admin is
  not able to seize user funds directly, but controls allocation and oracle configuration.
- **NAV oracle (V1)** — a whitelisted reporter set pushes NAV. Centralization is bounded by:
  monotonic timestamps, a ≤5% per-update deviation cap (larger moves require the admin path),
  and a staleness gate that halts allocations/withdrawals if the feed goes quiet. V2 replaces
  the single reporter with a 2-of-3 quorum.
- **Off-chain (private credit)** — once USDC leaves for an originator, its return depends on the
  originator's operational integrity and borrower credit quality. On-chain concentration caps
  limit per-pool exposure; originators are permissioned (whitelist + legal agreement).
- **Immutability** — no upgrade path. Fixes require redeploying and migrating.

## Known considerations (for auditors)

- **sagUSD first-depositor / inflation attack.** `StakedAgamaUSD` is a plain ERC-4626-style
  vault; a first depositor can donate assets to inflate the share price and round later
  deposits to zero shares. Mitigation to add before mainnet: a dead-shares bootstrap (mint a
  small amount of shares to a burn address on first deposit) or virtual shares/assets offset.
- **Socialized loss (V1, no tranching).** A NAV write-down reduces backing pro-rata across all
  agUSD holders; there is no junior/senior split yet.
- **Reserve accounting vs. custody.** `AgamaVault.redeem` checks `reserve`; the allocation
  engine tracks deployed capital separately. Keepers must keep enough idle reserve (buffer) to
  serve redemptions, otherwise redemptions queue (see `WithdrawalQueue`).
- **agUSD burn authority.** Only the vault (minter) can burn agUSD; `redeem` burns the caller's
  own balance. A compromised vault owner could re-point the minter, hence the multisig
  requirement.
- **Rounding.** Share/asset conversions use integer division; auditors should confirm rounding
  always favors the protocol, not the withdrawer.

## Testing

39 `snforge` tests (unit + Sepolia fork) plus fuzz tests on core invariants
(`tests/test_invariants.cairo`): deposit/redeem round-trip, sagUSD stake/unstake round-trip
with no yield, and the allocation concentration-cap invariant.
