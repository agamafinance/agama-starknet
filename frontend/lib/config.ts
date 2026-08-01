export const RPC_URL = "https://starknet-sepolia-rpc.publicnode.com";

// Deployed production stack on Starknet Sepolia.
// agUSD is the yield-bearing share token; the vault's NAV indexes on the four
// lending pools, each accruing yield at its own APR.
export const ADDRESSES = {
  usdc: "0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343",
  agusd: "0x04c0d175cab9fd3163958443830678c9828f52bbbfcd99c04cc52985302abd1f",
  vault: "0x059ed11c2b242e766818f3a957a1a9cfe22b0462b4eb7a60bbb71f5ecdb160b1",
  // STRK20 invoke anonymizer: the lending leg the native privacy pool calls to shield a deposit.
  shieldedAdapter: "0x075ed504a33de22a9e36e9de6232f51d7e3c6c31a123bb74cc7ab993e473b842",
};

// The four Agama lending pools behind agUSD. APR is read live on-chain; the sector
// labels are the product framing from the architecture.
export const POOLS = [
  { address: "0x07fd9db4d3377e6909555ea100b631784048de519e0100f32d5877180ebb55ad", label: "Pool A", sector: "Private credit" },
  { address: "0x018d17c95680bc634ffaa4211be8db4bfec2625ff614a2faf925422c44e3eb2d", label: "Pool B", sector: "Tokenized treasuries" },
  { address: "0x0438cd90d88358b574690ccdd8fd17370245929bed2d390f27bc984cbcf206e6", label: "Pool C", sector: "Bonds" },
  { address: "0x01ac07c1564032d8c3d02bdff1f9661783f3abc3b97ccdc6de318f70a171249f", label: "Pool D", sector: "Onchain RWA yield" },
];

export const EXPLORER = "https://sepolia.voyager.online";
