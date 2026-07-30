# Agama LP dApp

Minimal Next.js front-end for the Agama vault on Starknet: connect a Ready/Braavos
wallet, deposit USDC to mint agUSD (the yield-bearing share token), and redeem back to
USDC. Points at the live Sepolia deployment (see `lib/config.ts`).

```bash
cd frontend
pnpm install
pnpm dev        # http://localhost:3000
pnpm build      # production build
```

Wallet connection talks directly to the injected Starknet Window Object (no wallet-kit
dependency); reads/writes use `starknet.js` against PublicNode (RPC spec 0.10, reads pinned to
the `latest` block). The balance card shows each agUSD holding alongside its live redeemable
USDC value (`convert_to_assets`), so accrued yield is visible. Shielded (STRK20) deposits are
wired in once the Foundation privacy pool address + Privacy SDK are available.
