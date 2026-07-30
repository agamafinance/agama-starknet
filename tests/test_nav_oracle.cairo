use agama_starknet::nav_oracle::{INavOracleDispatcher, INavOracleDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, stop_cheat_block_timestamp, stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn reporter() -> ContractAddress {
    0xbeef.try_into().unwrap()
}
fn stranger() -> ContractAddress {
    0xdead.try_into().unwrap()
}

const STALE: u64 = 604800; // 7 days

fn deploy() -> ContractAddress {
    let c = declare("NavOracle").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    let nav0: u256 = 1000000;
    let dev: u256 = 500; // 5%
    nav0.serialize(ref cd);
    dev.serialize(ref cd);
    STALE.serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn deploy_with_reporter() -> ContractAddress {
    let a = deploy();
    start_cheat_caller_address(a, owner());
    INavOracleDispatcher { contract_address: a }.add_reporter(reporter());
    stop_cheat_caller_address(a);
    a
}

#[test]
fn test_reporter_push_within_cap() {
    let a = deploy_with_reporter();
    let o = INavOracleDispatcher { contract_address: a };
    start_cheat_caller_address(a, reporter());
    o.push_nav(1040000, 100); // +4% <= 5%
    stop_cheat_caller_address(a);
    assert(o.nav() == 1040000, 'nav updated');
    assert(o.last_updated() == 100, 'ts updated');
}

#[test]
#[should_panic(expected: 'oracle: not reporter')]
fn test_non_reporter_reverts() {
    let a = deploy_with_reporter();
    start_cheat_caller_address(a, stranger());
    INavOracleDispatcher { contract_address: a }.push_nav(1010000, 100);
    stop_cheat_caller_address(a);
}

#[test]
#[should_panic(expected: 'oracle: stale timestamp')]
fn test_monotonic_timestamp() {
    let a = deploy_with_reporter();
    let o = INavOracleDispatcher { contract_address: a };
    start_cheat_caller_address(a, reporter());
    o.push_nav(1000000, 100);
    o.push_nav(1010000, 100); // ts not strictly greater
    stop_cheat_caller_address(a);
}

#[test]
#[should_panic(expected: 'oracle: deviation too large')]
fn test_deviation_cap() {
    let a = deploy_with_reporter();
    start_cheat_caller_address(a, reporter());
    INavOracleDispatcher { contract_address: a }.push_nav(1100000, 100); // +10% > 5%
    stop_cheat_caller_address(a);
}

#[test]
fn test_admin_override_large_move() {
    let a = deploy();
    let o = INavOracleDispatcher { contract_address: a };
    start_cheat_caller_address(a, owner());
    o.push_nav_admin(1500000, 100); // +50% allowed through admin path
    stop_cheat_caller_address(a);
    assert(o.nav() == 1500000, 'admin override applied');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_admin_path_owner_only() {
    let a = deploy();
    start_cheat_caller_address(a, stranger());
    INavOracleDispatcher { contract_address: a }.push_nav_admin(1500000, 100);
    stop_cheat_caller_address(a);
}

#[test]
fn test_staleness_window() {
    let a = deploy_with_reporter();
    let o = INavOracleDispatcher { contract_address: a };
    start_cheat_caller_address(a, reporter());
    o.push_nav(1000000, 100);
    stop_cheat_caller_address(a);

    start_cheat_block_timestamp(a, 100 + 1000);
    assert(!o.is_stale(), 'fresh inside window');
    stop_cheat_block_timestamp(a);

    start_cheat_block_timestamp(a, 100 + STALE + 1);
    assert(o.is_stale(), 'stale past window');
    stop_cheat_block_timestamp(a);
}

#[test]
#[should_panic(expected: 'oracle: stale')]
fn test_assert_fresh_reverts_when_stale() {
    let a = deploy_with_reporter();
    let o = INavOracleDispatcher { contract_address: a };
    start_cheat_caller_address(a, reporter());
    o.push_nav(1000000, 100);
    stop_cheat_caller_address(a);
    start_cheat_block_timestamp(a, 100 + STALE + 1);
    o.assert_fresh();
    stop_cheat_block_timestamp(a);
}
