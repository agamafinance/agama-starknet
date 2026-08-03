export const RPC_URL = "https://starknet-sepolia-rpc.publicnode.com";

// Deployed production stack on Starknet Sepolia.
// agUSD is the yield-bearing share token; the vault's NAV indexes on the four
// lending pools, each accruing yield at its own APR.
export const ADDRESSES = {
  usdc: "0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343",
  agusd: "0x02c25931fa0fd76a872db10b9aa88a749e5f96201d343e60967747c5289d0445",
  vault: "0x07d4a616c1ad04e2895477a21ad1d93c65ff47a3083df95183a7c101433f89ea",
  // STRK20 invoke anonymizer: the lending leg the native privacy pool calls to shield a deposit.
  shieldedAdapter: "0x075ed504a33de22a9e36e9de6232f51d7e3c6c31a123bb74cc7ab993e473b842",
};

// The four Agama lending pools behind agUSD. APR is read live on-chain; the sector
// labels are the product framing from the architecture.
export const POOLS = [
  { address: "0x00939a9b9fa4c385a577492c9a7fd9e3b809c9a2c489f51f634b4902f901a42c", label: "Pool A", sector: "Private credit" },
  { address: "0x03615e597ea27956be21b55d7383f39353cd30ea00e0d1f7232c21a8bad9fc6b", label: "Pool B", sector: "Tokenized treasuries" },
  { address: "0x066c3b0a50fed66924c1decd5756eaad1396a7778f50343c1562325b6022fb00", label: "Pool C", sector: "Bonds" },
  { address: "0x015c1866da69849a7feac67e590a69586864bcae9660c85b25253302beb3081f", label: "Pool D", sector: "Onchain RWA yield" },
];

export const EXPLORER = "https://sepolia.voyager.online";
