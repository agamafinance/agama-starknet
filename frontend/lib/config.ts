export const RPC_URL = "https://starknet-sepolia-rpc.publicnode.com";

// Deployed production stack on Starknet Sepolia.
// agUSD is the yield-bearing share token; the vault's NAV indexes on the four
// lending pools, each accruing yield at its own APR.
export const ADDRESSES = {
  usdc: "0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343",
  agusd: "0x007b0c09db9f7f7666c62f6fb36c6a705fe65635ec23f40d6c87c0bca7e90872",
  vault: "0x025cd136281736bb4987fcf1714caed1e41a93796cf91678e88e92acbf7989df",
  // STRK20 invoke anonymizer: the lending leg the native privacy pool calls to shield a deposit.
  shieldedAdapter: "0x075ed504a33de22a9e36e9de6232f51d7e3c6c31a123bb74cc7ab993e473b842",
};

// The four Agama lending pools behind agUSD. APR is read live on-chain; the sector
// labels are the product framing from the architecture.
export const POOLS = [
  { address: "0x067de96fbe56ec9c71c23e40a2b6451a66ee92a2952ea0f0d09032219aa7ca1f", label: "Pool A", sector: "Private credit" },
  { address: "0x078aa4b27817470999c2bbbb44f155a932fc76bba584377a6a6c25c430449686", label: "Pool B", sector: "Tokenized treasuries" },
  { address: "0x00934b09f93593a725b1906404491fe2c227512f25d409fbb2148bf2eb57e9fd", label: "Pool C", sector: "Bonds" },
  { address: "0x020b2d4745ce863682c9bb6f7e8a84d436a2ced3f8c5de31374b7df610a16be3", label: "Pool D", sector: "Onchain RWA yield" },
];

export const EXPLORER = "https://sepolia.voyager.online";
