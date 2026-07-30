use agama_starknet::mock_usdc::{
    IERC20Dispatcher, IERC20DispatcherTrait, IMockUsdcDispatcher, IMockUsdcDispatcherTrait,
};
use agama_starknet::pool_adapter::{IPoolAdapterDispatcher, IPoolAdapterDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn originator() -> ContractAddress {
    0x061613.try_into().unwrap()
}
fn stranger() -> ContractAddress {
    0xdead.try_into().unwrap()
}

fn deploy_usdc() -> ContractAddress {
    let c = declare("MockUsdc").unwrap().contract_class();
    let (a, _) = c.deploy(@array![]).unwrap();
    a
}

fn deploy_pool(usdc: ContractAddress) -> ContractAddress {
    let c = declare("AgamaPoolVault").unwrap().contract_class();
    let mut cd = array![];
    usdc.serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn deploy_vesu_adapter(usdc: ContractAddress, pool: ContractAddress) -> ContractAddress {
    let c = declare("VesuAdapter").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    usdc.serialize(ref cd);
    pool.serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn deploy_orig_adapter(usdc: ContractAddress) -> ContractAddress {
    let c = declare("OriginatorAdapter").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    usdc.serialize(ref cd);
    originator().serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn mint(usdc: ContractAddress, to: ContractAddress, amount: u256) {
    IMockUsdcDispatcher { contract_address: usdc }.mint(to, amount);
}

#[test]
fn test_vesu_adapter_deploy_and_withdraw() {
    let usdc = deploy_usdc();
    let pool = deploy_pool(usdc);
    let ad = deploy_vesu_adapter(usdc, pool);
    mint(usdc, ad, 1000000);
    let a = IPoolAdapterDispatcher { contract_address: ad };

    start_cheat_caller_address(ad, owner());
    let shares = a.deploy(1000000);
    stop_cheat_caller_address(ad);
    assert(shares == 1000000, 'shares 1:1');
    assert(
        IERC20Dispatcher { contract_address: usdc }.balance_of(pool) == 1000000, 'pool has USDC',
    );
    assert(
        IERC20Dispatcher { contract_address: pool }.balance_of(ad) == 1000000, 'adapter has shares',
    );
    assert(IERC20Dispatcher { contract_address: usdc }.balance_of(ad) == 0, 'adapter USDC spent');

    start_cheat_caller_address(ad, owner());
    let got = a.withdraw(1000000);
    stop_cheat_caller_address(ad);
    assert(got == 1000000, 'redeemed underlying');
    assert(IERC20Dispatcher { contract_address: usdc }.balance_of(ad) == 1000000, 'USDC back');
    assert(IERC20Dispatcher { contract_address: usdc }.balance_of(pool) == 0, 'pool emptied');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_vesu_adapter_deploy_only_owner() {
    let usdc = deploy_usdc();
    let pool = deploy_pool(usdc);
    let ad = deploy_vesu_adapter(usdc, pool);
    mint(usdc, ad, 1000000);
    start_cheat_caller_address(ad, stranger());
    IPoolAdapterDispatcher { contract_address: ad }.deploy(1000000);
    stop_cheat_caller_address(ad);
}

#[test]
fn test_originator_adapter_deploy_and_settle() {
    let usdc = deploy_usdc();
    let ad = deploy_orig_adapter(usdc);
    mint(usdc, ad, 1000000);
    let a = IPoolAdapterDispatcher { contract_address: ad };

    start_cheat_caller_address(ad, owner());
    a.deploy(1000000); // deploy to originator (CCTP)
    stop_cheat_caller_address(ad);
    assert(
        IERC20Dispatcher { contract_address: usdc }.balance_of(originator()) == 1000000,
        'originator funded',
    );
    assert(IERC20Dispatcher { contract_address: usdc }.balance_of(ad) == 0, 'adapter emptied');

    // originator repays: approves the adapter, then withdraw settles back
    start_cheat_caller_address(usdc, originator());
    IERC20Dispatcher { contract_address: usdc }.approve(ad, 1000000);
    stop_cheat_caller_address(usdc);
    start_cheat_caller_address(ad, owner());
    a.withdraw(1000000);
    stop_cheat_caller_address(ad);
    assert(IERC20Dispatcher { contract_address: usdc }.balance_of(ad) == 1000000, 'settled back');
}
