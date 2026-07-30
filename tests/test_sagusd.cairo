use agama_starknet::agusd::{IAgamaUSDDispatcher, IAgamaUSDDispatcherTrait};
use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
use agama_starknet::sagusd::{IStakedAgamaUSDDispatcher, IStakedAgamaUSDDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn minter() -> ContractAddress {
    0x11117.try_into().unwrap()
}
fn user1() -> ContractAddress {
    0xb0b1.try_into().unwrap()
}
fn user2() -> ContractAddress {
    0xb0b2.try_into().unwrap()
}
fn ysrc() -> ContractAddress {
    0x1e1d.try_into().unwrap()
}

fn deploy_agusd() -> ContractAddress {
    let c = declare("AgamaUSD").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    // set minter
    start_cheat_caller_address(a, owner());
    IAgamaUSDDispatcher { contract_address: a }.set_minter(minter());
    stop_cheat_caller_address(a);
    a
}

fn deploy_staking(agusd: ContractAddress) -> ContractAddress {
    let c = declare("StakedAgamaUSD").unwrap().contract_class();
    let mut cd = array![];
    agusd.serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn mint_agusd(agusd: ContractAddress, to: ContractAddress, amount: u256) {
    start_cheat_caller_address(agusd, minter());
    IAgamaUSDDispatcher { contract_address: agusd }.mint(to, amount);
    stop_cheat_caller_address(agusd);
}

fn approve(token: ContractAddress, from: ContractAddress, spender: ContractAddress, amount: u256) {
    start_cheat_caller_address(token, from);
    IERC20Dispatcher { contract_address: token }.approve(spender, amount);
    stop_cheat_caller_address(token);
}

fn stake(staking: ContractAddress, user: ContractAddress, amount: u256) {
    start_cheat_caller_address(staking, user);
    IStakedAgamaUSDDispatcher { contract_address: staking }.stake(amount);
    stop_cheat_caller_address(staking);
}

#[test]
fn test_first_stake_is_1_to_1() {
    let agusd = deploy_agusd();
    let staking = deploy_staking(agusd);
    mint_agusd(agusd, user1(), 1000000);
    approve(agusd, user1(), staking, 1000000);
    stake(staking, user1(), 1000000);

    let s = IStakedAgamaUSDDispatcher { contract_address: staking };
    assert(
        IERC20Dispatcher { contract_address: staking }.balance_of(user1()) == 1000000, 'sagUSD 1:1',
    );
    assert(s.total_assets() == 1000000, 'assets pooled');
}

#[test]
fn test_yield_raises_share_price() {
    let agusd = deploy_agusd();
    let staking = deploy_staking(agusd);
    mint_agusd(agusd, user1(), 1000000);
    approve(agusd, user1(), staking, 1000000);
    stake(staking, user1(), 1000000);

    // 200k agUSD of RWA yield lands in the pool
    mint_agusd(agusd, ysrc(), 200000);
    approve(agusd, ysrc(), staking, 200000);
    start_cheat_caller_address(staking, ysrc());
    IStakedAgamaUSDDispatcher { contract_address: staking }.distribute(200000);
    stop_cheat_caller_address(staking);

    // user1 unstakes all shares -> receives principal + yield
    start_cheat_caller_address(staking, user1());
    IStakedAgamaUSDDispatcher { contract_address: staking }.unstake(1000000);
    stop_cheat_caller_address(staking);

    assert(
        IERC20Dispatcher { contract_address: agusd }.balance_of(user1()) == 1200000,
        'principal + yield',
    );
}

#[test]
fn test_staker_after_yield_gets_fewer_shares() {
    let agusd = deploy_agusd();
    let staking = deploy_staking(agusd);
    mint_agusd(agusd, user1(), 1000000);
    approve(agusd, user1(), staking, 1000000);
    stake(staking, user1(), 1000000);

    mint_agusd(agusd, ysrc(), 200000);
    approve(agusd, ysrc(), staking, 200000);
    start_cheat_caller_address(staking, ysrc());
    IStakedAgamaUSDDispatcher { contract_address: staking }.distribute(200000);
    stop_cheat_caller_address(staking);

    // share price is now 1.2 -> 600k agUSD buys 500k sagUSD
    mint_agusd(agusd, user2(), 600000);
    approve(agusd, user2(), staking, 600000);
    stake(staking, user2(), 600000);

    assert(
        IERC20Dispatcher { contract_address: staking }.balance_of(user2()) == 500000,
        'fewer shares',
    );
}

#[test]
#[should_panic(expected: 'amount is zero')]
fn test_stake_zero_reverts() {
    let agusd = deploy_agusd();
    let staking = deploy_staking(agusd);
    start_cheat_caller_address(staking, user1());
    IStakedAgamaUSDDispatcher { contract_address: staking }.stake(0);
    stop_cheat_caller_address(staking);
}
