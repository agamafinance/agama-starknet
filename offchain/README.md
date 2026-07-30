# Agama off-chain services

Off-chain infrastructure for the Agama protocol on Starknet, using `starknet.js`.

- **NAV backend** (`nav`) — reconciles per-originator NAV reports into a single value and
  pushes it on-chain via `push_nav` on the `NavOracle` (requires an authorized reporter
  account). Enforced on-chain: reporter set, monotonic timestamp, ≤5% deviation.
- **Keeper** (`keeper`) — periodic loop that checks NAV oracle freshness and settles the
  FIFO withdrawal queue against the vault reserve.
- **Indexer** (`indexer`) — polls on-chain events (`Deposit`, `Redeem`, `NavUpdated`,
  `Allocated`), decodes them, and appends to `events.jsonl` (tracks last indexed block).

## Setup

```bash
cd offchain
pnpm install
cp .env.example .env      # fill in addresses + a reporter account for writes
```

## Run

```bash
pnpm run indexer -- --once     # index once (read-only, no account needed)
pnpm run indexer               # index continuously
pnpm run nav                   # reconcile + push NAV (needs REPORTER_*)
pnpm run keeper                # freshness + withdrawal-queue loop (needs REPORTER_*)
```

Config is env-driven (`.env`); defaults target Starknet Sepolia via PublicNode. The indexer
works read-only out of the box against the deployed vault; `nav`/`keeper` need a funded
reporter account authorized on the oracle.
