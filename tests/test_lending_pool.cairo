use agama_starknet::lending_pool::{ILendingPoolDispatcher, ILendingPoolDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp_global,
    start_cheat_caller_address, stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn vault() -> ContractAddress {
    0x0dead.try_into().unwrap()
}

const YEAR: u64 = 31536000;

fn deploy_pool(apr_bps: u32) -> ContractAddress {
    let c = declare("LendingPool").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    vault().serialize(ref cd);
    let nm: felt252 = 'Pool A';
    nm.serialize(ref cd);
    apr_bps.serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

#[test]
fn test_pool_accrues_apr_over_time() {
    start_cheat_block_timestamp_global(1000);
    let pool = deploy_pool(1200); // 12% APR
    let p = ILendingPoolDispatcher { contract_address: pool };

    start_cheat_caller_address(pool, vault());
    p.fund(100000000); // 100 USDC principal
    stop_cheat_caller_address(pool);
    assert(p.principal() == 100000000, 'principal set');
    assert(p.total_value() == 100000000, 'no yield yet');

    // one year later: +12%
    start_cheat_block_timestamp_global(1000 + YEAR);
    assert(p.pending() == 12000000, 'pending 12%');
    assert(p.total_value() == 112000000, 'value +12%');

    // accrue folds pending into stored accrued, value unchanged
    p.accrue();
    assert(p.accrued() == 12000000, 'accrued folded');
    assert(p.total_value() == 112000000, 'value stable');
    stop_cheat_block_timestamp_global();
}

#[test]
fn test_pool_half_year_is_half_yield() {
    start_cheat_block_timestamp_global(1000);
    let pool = deploy_pool(1000); // 10% APR
    let p = ILendingPoolDispatcher { contract_address: pool };
    start_cheat_caller_address(pool, vault());
    p.fund(100000000);
    stop_cheat_caller_address(pool);
    start_cheat_block_timestamp_global(1000 + YEAR / 2);
    assert(p.pending() == 5000000, 'half year = 5%');
    stop_cheat_block_timestamp_global();
}

#[test]
#[should_panic(expected: 'not vault')]
fn test_only_vault_can_fund() {
    let pool = deploy_pool(1200);
    start_cheat_caller_address(pool, owner()); // owner is admin, not the vault
    ILendingPoolDispatcher { contract_address: pool }.fund(1000000);
    stop_cheat_caller_address(pool);
}

#[test]
fn test_set_apr_locks_in_old_rate_first() {
    start_cheat_block_timestamp_global(1000);
    let pool = deploy_pool(1200);
    let p = ILendingPoolDispatcher { contract_address: pool };
    start_cheat_caller_address(pool, vault());
    p.fund(100000000);
    stop_cheat_caller_address(pool);
    // one year at 12%, then admin lowers APR to 6%
    start_cheat_block_timestamp_global(1000 + YEAR);
    start_cheat_caller_address(pool, owner());
    p.set_apr(600);
    stop_cheat_caller_address(pool);
    // the 12% year is banked; further accrual runs at 6%
    assert(p.accrued() == 12000000, 'old rate banked');
    assert(p.apr_bps() == 600, 'new rate set');
    stop_cheat_block_timestamp_global();
}
