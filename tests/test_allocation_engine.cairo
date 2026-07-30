use agama_starknet::allocation_engine::{
    IAllocationEngineDispatcher, IAllocationEngineDispatcherTrait,
};
use agama_starknet::nav_oracle::{INavOracleDispatcher, INavOracleDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp_global,
    start_cheat_caller_address, stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn stranger() -> ContractAddress {
    0xdead.try_into().unwrap()
}

const NAV_TS: u64 = 1000;
const STALE: u64 = 604800;

// Deploy a fresh NAV oracle (NAV seeded at NAV_TS) + an allocation engine wired to it,
// with pool 1 registered at a 40% cap and 1_000_000 idle funded.
fn setup() -> (ContractAddress, ContractAddress) {
    let oc = declare("NavOracle").unwrap().contract_class();
    let mut ocd = array![];
    owner().serialize(ref ocd);
    let nav0: u256 = 1000000;
    let dev: u256 = 500;
    nav0.serialize(ref ocd);
    dev.serialize(ref ocd);
    STALE.serialize(ref ocd);
    let (oracle, _) = oc.deploy(@ocd).unwrap();

    start_cheat_caller_address(oracle, owner());
    INavOracleDispatcher { contract_address: oracle }.push_nav_admin(1000000, NAV_TS);
    stop_cheat_caller_address(oracle);

    let ec = declare("AllocationEngine").unwrap().contract_class();
    let mut ecd = array![];
    owner().serialize(ref ecd);
    oracle.serialize(ref ecd);
    let (engine, _) = ec.deploy(@ecd).unwrap();

    start_cheat_caller_address(engine, owner());
    let e = IAllocationEngineDispatcher { contract_address: engine };
    e.register_pool(1, 4000);
    e.fund(1000000);
    stop_cheat_caller_address(engine);

    (oracle, engine)
}

#[test]
fn test_allocate_within_cap() {
    let (_oracle, engine) = setup();
    let e = IAllocationEngineDispatcher { contract_address: engine };
    start_cheat_block_timestamp_global(NAV_TS);
    start_cheat_caller_address(engine, owner());
    e.allocate(1, 400000); // 40% of 1_000_000, exactly the cap
    stop_cheat_caller_address(engine);
    stop_cheat_block_timestamp_global();

    assert(e.deployed(1) == 400000, 'deployed');
    assert(e.idle() == 600000, 'idle');
    assert(e.total_deployed() == 400000, 'total deployed');
    assert(e.total_managed() == 1000000, 'managed conserved');
}

#[test]
#[should_panic(expected: 'cap breached')]
fn test_allocate_exceeds_cap() {
    let (_oracle, engine) = setup();
    start_cheat_block_timestamp_global(NAV_TS);
    start_cheat_caller_address(engine, owner());
    IAllocationEngineDispatcher { contract_address: engine }.allocate(1, 500000); // 50% > 40%
    stop_cheat_caller_address(engine);
    stop_cheat_block_timestamp_global();
}

#[test]
#[should_panic(expected: 'pool not registered')]
fn test_allocate_unregistered_pool() {
    let (_oracle, engine) = setup();
    start_cheat_block_timestamp_global(NAV_TS);
    start_cheat_caller_address(engine, owner());
    IAllocationEngineDispatcher { contract_address: engine }.allocate(2, 100);
    stop_cheat_caller_address(engine);
    stop_cheat_block_timestamp_global();
}

#[test]
#[should_panic(expected: 'oracle: stale')]
fn test_allocate_blocked_when_oracle_stale() {
    let (_oracle, engine) = setup();
    start_cheat_block_timestamp_global(NAV_TS + STALE + 1);
    start_cheat_caller_address(engine, owner());
    IAllocationEngineDispatcher { contract_address: engine }.allocate(1, 100);
    stop_cheat_caller_address(engine);
    stop_cheat_block_timestamp_global();
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_register_only_owner() {
    let (_oracle, engine) = setup();
    start_cheat_caller_address(engine, stranger());
    IAllocationEngineDispatcher { contract_address: engine }.register_pool(2, 4000);
    stop_cheat_caller_address(engine);
}

#[test]
fn test_deallocate_returns_to_idle() {
    let (_oracle, engine) = setup();
    let e = IAllocationEngineDispatcher { contract_address: engine };
    start_cheat_block_timestamp_global(NAV_TS);
    start_cheat_caller_address(engine, owner());
    e.allocate(1, 300000);
    e.deallocate(1, 100000);
    stop_cheat_caller_address(engine);
    stop_cheat_block_timestamp_global();

    assert(e.deployed(1) == 200000, 'deployed after dealloc');
    assert(e.idle() == 800000, 'idle restored');
    assert(e.total_deployed() == 200000, 'total deployed');
}
