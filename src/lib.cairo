// Agama on Starknet — integration proof of concept.
//
// Mirrors the core of Agama's live Soroban logic (deposit USDC -> mint agUSD
// shares, yield accrues to agUSD via the vault, allocation engine with on-chain
// concentration caps, redeem) in Cairo, so the flow can be tested on Starknet. In
// production the USDC deposit leg is shielded through Starknet's native STRK20 pool.
//
// STRK20 integration: `agama_pool_vault` exposes the ERC-4626 / SNIP-22 interface
// and `agama_anonymizer` reproduces Starknet's official lending-anonymizer pattern
// (starkware-libs/starknet-privacy), which is how a lending protocol composes with
// the native shielded pool.
pub mod agama_anonymizer;
pub mod agama_pool_vault;
pub mod agama_shielded_adapter;
pub mod agusd;
pub mod allocation_engine;
pub mod lending_pool;
pub mod mock_usdc;
pub mod nav_oracle;
pub mod pool_adapter;
pub mod vault;
pub mod withdrawal_queue;
