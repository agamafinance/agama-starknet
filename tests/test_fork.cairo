use starknet::ContractAddress;

// Fork test: runs against real Starknet Sepolia state, proving our code interacts
// with actually-deployed contracts (here, Circle's native USDC). The same harness is
// how we will test the STRK20 lending anonymizer against the deployed privacy pool
// once the Starknet Foundation shares its Sepolia address (see agama_anonymizer).
#[starknet::interface]
pub trait IUsdcMeta<T> {
    fn decimals(self: @T) -> u8;
    fn symbol(self: @T) -> ByteArray;
}

// Circle native USDC on Starknet Sepolia (6 decimals).
const USDC: felt252 = 0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343;

#[test]
#[fork("SEPOLIA")]
fn test_fork_reads_real_circle_usdc() {
    let usdc: ContractAddress = USDC.try_into().unwrap();
    let m = IUsdcMetaDispatcher { contract_address: usdc };
    assert(m.decimals() == 6, 'real USDC has 6 decimals');
    assert(m.symbol() == "USDC", 'real USDC symbol is USDC');
}
