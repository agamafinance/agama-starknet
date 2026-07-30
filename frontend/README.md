# Agama LP dApp

Minimal Next.js front-end for the Agama vault on Starknet: connect an Argent/Braavos
wallet, deposit USDC to mint agUSD, and stake into sagUSD. Points at the live Sepolia
deployment (see `lib/config.ts`).

```bash
cd frontend
pnpm install
pnpm dev        # http://localhost:3000
pnpm build      # production build
```

Wallet connection uses `starknetkit`; reads/writes use `starknet.js` against PublicNode
(RPC spec 0.10). Set `ADDRESSES.sagusd` in `lib/config.ts` once `StakedAgamaUSD` is deployed
to enable staking. Shielded (STRK20) deposits are wired in once the Foundation privacy pool
address + Privacy SDK are available (see the contracts repo).
