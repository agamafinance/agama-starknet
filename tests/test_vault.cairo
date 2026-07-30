use agama_starknet::agusd::{IAgamaUSDDispatcher, IAgamaUSDDispatcherTrait};
use agama_starknet::mock_usdc::{
    IERC20Dispatcher, IERC20DispatcherTrait, IMockUsdcDispatcher, IMockUsdcDispatcherTrait,
};
use agama_starknet::vault::{IAgamaVaultDispatcher, IAgamaVaultDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn user() -> ContractAddress {
    0x0b0b.try_into().unwrap()
}

fn deploy_usdc() -> ContractAddress {
    let c = declare("MockUsdc").unwrap().contract_class();
    let (a, _) = c.deploy(@array![]).unwrap();
    a
}

fn deploy_agusd() -> ContractAddress {
    let c = declare("AgamaUSD").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn deploy_vault(usdc: ContractAddress, agusd: ContractAddress) -> ContractAddress {
    let c = declare("AgamaVault").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    usdc.serialize(ref cd);
    agusd.serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

// Deploy the stack, make the vault the agUSD minter, fund + approve `user` for `amount`.
fn setup(amount: u256) -> (ContractAddress, ContractAddress, ContractAddress) {
    let usdc = deploy_usdc();
    let agusd = deploy_agusd();
    let vault = deploy_vault(usdc, agusd);

    start_cheat_caller_address(agusd, owner());
    IAgamaUSDDispatcher { contract_address: agusd }.set_minter(vault);
    stop_cheat_caller_address(agusd);

    IMockUsdcDispatcher { contract_address: usdc }.mint(user(), amount);
    start_cheat_caller_address(usdc, user());
    IERC20Dispatcher { contract_address: usdc }.approve(vault, amount);
    stop_cheat_caller_address(usdc);

    (usdc, agusd, vault)
}

#[test]
fn test_first_deposit_mints_shares_1_to_1() {
    let (usdc, agusd, vault) = setup(1000000);
    start_cheat_caller_address(vault, user());
    IAgamaVaultDispatcher { contract_address: vault }.deposit(1000000);
    stop_cheat_caller_address(vault);

    // First depositor: share price is 1.0, so 1 USDC -> 1 agUSD share.
    assert(IERC20Dispatcher { contract_address: agusd }.balance_of(user()) == 1000000, 'agUSD 1:1');
    assert(IAgamaVaultDispatcher { contract_address: vault }.reserve() == 1000000, 'reserve holds');
    assert(
        IERC20Dispatcher { contract_address: usdc }.balance_of(vault) == 1000000, 'vault has USDC',
    );
    assert(IERC20Dispatcher { contract_address: usdc }.balance_of(user()) == 0, 'user USDC moved');
}

// Yield lands via `distribute`: total assets grow, share supply doesn't, so each
// agUSD becomes worth more USDC and redeeming returns the appreciated amount.
#[test]
fn test_yield_accrues_to_agusd() {
    // user deposits 1_000_000; owner distributes 200_000 of yield -> price 1.2.
    let usdc = deploy_usdc();
    let agusd = deploy_agusd();
    let vault = deploy_vault(usdc, agusd);
    let v = IAgamaVaultDispatcher { contract_address: vault };

    start_cheat_caller_address(agusd, owner());
    IAgamaUSDDispatcher { contract_address: agusd }.set_minter(vault);
    stop_cheat_caller_address(agusd);

    // fund + deposit as user
    IMockUsdcDispatcher { contract_address: usdc }.mint(user(), 1000000);
    start_cheat_caller_address(usdc, user());
    IERC20Dispatcher { contract_address: usdc }.approve(vault, 1000000);
    stop_cheat_caller_address(usdc);
    start_cheat_caller_address(vault, user());
    let shares = v.deposit(1000000);
    stop_cheat_caller_address(vault);
    assert(shares == 1000000, 'shares 1:1');

    // owner distributes 200_000 USDC of yield
    IMockUsdcDispatcher { contract_address: usdc }.mint(owner(), 200000);
    start_cheat_caller_address(usdc, owner());
    IERC20Dispatcher { contract_address: usdc }.approve(vault, 200000);
    stop_cheat_caller_address(usdc);
    start_cheat_caller_address(vault, owner());
    v.distribute(200000);
    stop_cheat_caller_address(vault);

    // share price is now 1.2: the user's 1_000_000 shares are worth 1_200_000 USDC.
    assert(v.total_assets() == 1200000, 'assets grew');
    assert(v.convert_to_assets(1000000) == 1200000, 'price up 1.2x');

    // redeeming all shares returns the appreciated USDC.
    start_cheat_caller_address(vault, user());
    let out = v.redeem(shares);
    stop_cheat_caller_address(vault);
    assert(out == 1200000, 'redeem returns yield');
    assert(
        IERC20Dispatcher { contract_address: usdc }.balance_of(user()) == 1200000, 'user got yield',
    );
    assert(IERC20Dispatcher { contract_address: agusd }.balance_of(user()) == 0, 'shares burned');
}

// Two depositors share yield pro-rata by shares held.
#[test]
fn test_two_depositors_split_yield_pro_rata() {
    let usdc = deploy_usdc();
    let agusd = deploy_agusd();
    let vault = deploy_vault(usdc, agusd);
    let v = IAgamaVaultDispatcher { contract_address: vault };
    let bob: ContractAddress = 0x0c0c.try_into().unwrap();

    start_cheat_caller_address(agusd, owner());
    IAgamaUSDDispatcher { contract_address: agusd }.set_minter(vault);
    stop_cheat_caller_address(agusd);

    // user deposits 1_000_000 (price 1.0 -> 1_000_000 shares)
    IMockUsdcDispatcher { contract_address: usdc }.mint(user(), 1000000);
    start_cheat_caller_address(usdc, user());
    IERC20Dispatcher { contract_address: usdc }.approve(vault, 1000000);
    stop_cheat_caller_address(usdc);
    start_cheat_caller_address(vault, user());
    let s_user = v.deposit(1000000);
    stop_cheat_caller_address(vault);

    // owner distributes 1_000_000 yield -> price 2.0
    IMockUsdcDispatcher { contract_address: usdc }.mint(owner(), 1000000);
    start_cheat_caller_address(usdc, owner());
    IERC20Dispatcher { contract_address: usdc }.approve(vault, 1000000);
    stop_cheat_caller_address(usdc);
    start_cheat_caller_address(vault, owner());
    v.distribute(1000000);
    stop_cheat_caller_address(vault);

    // bob now deposits 1_000_000 at price 2.0 -> gets 500_000 shares
    IMockUsdcDispatcher { contract_address: usdc }.mint(bob, 1000000);
    start_cheat_caller_address(usdc, bob);
    IERC20Dispatcher { contract_address: usdc }.approve(vault, 1000000);
    stop_cheat_caller_address(usdc);
    start_cheat_caller_address(vault, bob);
    let s_bob = v.deposit(1000000);
    stop_cheat_caller_address(vault);
    assert(s_user == 1000000, 'user 1e6 shares');
    assert(s_bob == 500000, 'bob 0.5e6 shares at 2x');
    // total assets 3_000_000 across 1_500_000 shares -> price still 2.0
    assert(v.convert_to_assets(1000000) == 2000000, 'user worth 2e6');
    assert(v.convert_to_assets(500000) == 1000000, 'bob worth his deposit');
}

#[test]
fn test_redeem_burns_and_returns_usdc() {
    let (usdc, agusd, vault) = setup(1000000);
    let v = IAgamaVaultDispatcher { contract_address: vault };
    start_cheat_caller_address(vault, user());
    v.deposit(1000000);
    v.redeem(400000);
    stop_cheat_caller_address(vault);

    assert(
        IERC20Dispatcher { contract_address: agusd }.balance_of(user()) == 600000, 'agUSD burned',
    );
    assert(v.reserve() == 600000, 'reserve reduced');
    assert(
        IERC20Dispatcher { contract_address: usdc }.balance_of(user()) == 400000, 'USDC returned',
    );
}

#[test]
#[should_panic(expected: 'amount is zero')]
fn test_deposit_zero_reverts() {
    let (_usdc, _agusd, vault) = setup(1000000);
    start_cheat_caller_address(vault, user());
    IAgamaVaultDispatcher { contract_address: vault }.deposit(0);
    stop_cheat_caller_address(vault);
}

#[test]
#[should_panic(expected: 'insufficient reserve')]
fn test_redeem_over_reserve_reverts() {
    let (_usdc, _agusd, vault) = setup(1000000);
    let v = IAgamaVaultDispatcher { contract_address: vault };
    start_cheat_caller_address(vault, user());
    v.deposit(1000000);
    v.redeem(1000001);
    stop_cheat_caller_address(vault);
}
