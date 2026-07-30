use agama_starknet::agusd::{IAgamaUSDDispatcher, IAgamaUSDDispatcherTrait};
use agama_starknet::allocation_engine::{
    IAllocationEngineDispatcher, IAllocationEngineDispatcherTrait,
};
use agama_starknet::mock_usdc::{
    IERC20Dispatcher, IERC20DispatcherTrait, IMockUsdcDispatcher, IMockUsdcDispatcherTrait,
};
use agama_starknet::nav_oracle::{INavOracleDispatcher, INavOracleDispatcherTrait};
use agama_starknet::vault::{IAgamaVaultDispatcher, IAgamaVaultDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp_global,
    start_cheat_caller_address, stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn user() -> ContractAddress {
    0xb0b.try_into().unwrap()
}

fn deploy_usdc() -> ContractAddress {
    let (a, _) = declare("MockUsdc").unwrap().contract_class().deploy(@array![]).unwrap();
    a
}

// usdc + agUSD + vault (vault set as agUSD minter)
fn stack() -> (ContractAddress, ContractAddress, ContractAddress) {
    let usdc = deploy_usdc();
    let mut ac = array![];
    owner().serialize(ref ac);
    let (agusd, _) = declare("AgamaUSD").unwrap().contract_class().deploy(@ac).unwrap();
    let mut vc = array![];
    owner().serialize(ref vc);
    usdc.serialize(ref vc);
    agusd.serialize(ref vc);
    let (vault, _) = declare("AgamaVault").unwrap().contract_class().deploy(@vc).unwrap();
    start_cheat_caller_address(agusd, owner());
    IAgamaUSDDispatcher { contract_address: agusd }.set_minter(vault);
    stop_cheat_caller_address(agusd);
    (usdc, agusd, vault)
}

// Invariant: depositing then redeeming the same amount returns all USDC and burns all agUSD.
#[test]
#[fuzzer(runs: 25)]
fn fuzz_deposit_redeem_roundtrip(raw: u64) {
    let amount: u256 = raw.into() + 1;
    let (usdc, agusd, vault) = stack();
    IMockUsdcDispatcher { contract_address: usdc }.mint(user(), amount);
    start_cheat_caller_address(usdc, user());
    IERC20Dispatcher { contract_address: usdc }.approve(vault, amount);
    stop_cheat_caller_address(usdc);

    let v = IAgamaVaultDispatcher { contract_address: vault };
    start_cheat_caller_address(vault, user());
    v.deposit(amount);
    v.redeem(amount);
    stop_cheat_caller_address(vault);

    assert(IERC20Dispatcher { contract_address: usdc }.balance_of(user()) == amount, 'usdc back');
    assert(IERC20Dispatcher { contract_address: agusd }.balance_of(user()) == 0, 'agUSD burned');
    assert(v.reserve() == 0, 'reserve empty');
}

// Invariant: the sole depositor captures 100% of distributed yield — redeeming all
// agUSD returns principal + all yield, and the reserve empties.
#[test]
#[fuzzer(runs: 25)]
fn fuzz_sole_depositor_captures_all_yield(raw: u64, raw_yield: u64) {
    let amount: u256 = raw.into() + 1;
    let yield_amt: u256 = raw_yield.into();
    let (usdc, agusd, vault) = stack();
    let v = IAgamaVaultDispatcher { contract_address: vault };

    IMockUsdcDispatcher { contract_address: usdc }.mint(user(), amount);
    start_cheat_caller_address(usdc, user());
    IERC20Dispatcher { contract_address: usdc }.approve(vault, amount);
    stop_cheat_caller_address(usdc);
    start_cheat_caller_address(vault, user());
    let shares = v.deposit(amount);
    stop_cheat_caller_address(vault);

    if yield_amt > 0 {
        IMockUsdcDispatcher { contract_address: usdc }.mint(owner(), yield_amt);
        start_cheat_caller_address(usdc, owner());
        IERC20Dispatcher { contract_address: usdc }.approve(vault, yield_amt);
        stop_cheat_caller_address(usdc);
        start_cheat_caller_address(vault, owner());
        v.distribute(yield_amt);
        stop_cheat_caller_address(vault);
    }

    start_cheat_caller_address(vault, user());
    let out = v.redeem(shares);
    stop_cheat_caller_address(vault);

    assert(out == amount + yield_amt, 'sole lp gets all yield');
    assert(
        IERC20Dispatcher { contract_address: usdc }.balance_of(user()) == amount + yield_amt,
        'usdc back + yield',
    );
    assert(v.reserve() == 0, 'reserve empty');
}

// Invariant: a pool's deployed balance never exceeds its concentration cap.
#[test]
#[fuzzer(runs: 25)]
fn fuzz_allocation_never_exceeds_cap(raw: u64) {
    let managed: u256 = 1000000;
    let amount: u256 = (raw % 1000000).into();
    // oracle
    let mut oc = array![];
    owner().serialize(ref oc);
    let nav0: u256 = 1000000;
    let dev: u256 = 500;
    nav0.serialize(ref oc);
    dev.serialize(ref oc);
    let stale: u64 = 604800;
    stale.serialize(ref oc);
    let (oracle, _) = declare("NavOracle").unwrap().contract_class().deploy(@oc).unwrap();
    start_cheat_caller_address(oracle, owner());
    INavOracleDispatcher { contract_address: oracle }.push_nav_admin(1000000, 1000);
    stop_cheat_caller_address(oracle);
    // engine
    let mut ec = array![];
    owner().serialize(ref ec);
    oracle.serialize(ref ec);
    let (engine, _) = declare("AllocationEngine").unwrap().contract_class().deploy(@ec).unwrap();
    let e = IAllocationEngineDispatcher { contract_address: engine };
    start_cheat_caller_address(engine, owner());
    e.register_pool(1, 4000); // 40% cap
    e.fund(managed);
    stop_cheat_caller_address(engine);

    let cap: u256 = managed * 4000 / 10000;
    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(engine, owner());
    if amount <= cap {
        e.allocate(1, amount);
        assert(e.deployed(1) <= cap, 'within cap holds');
    }
    stop_cheat_caller_address(engine);
    stop_cheat_block_timestamp_global();
}
