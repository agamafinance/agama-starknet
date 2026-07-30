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
fn test_deposit_mints_agusd_1_to_1() {
    let (usdc, agusd, vault) = setup(1000000);
    start_cheat_caller_address(vault, user());
    IAgamaVaultDispatcher { contract_address: vault }.deposit(1000000);
    stop_cheat_caller_address(vault);

    assert(IERC20Dispatcher { contract_address: agusd }.balance_of(user()) == 1000000, 'agUSD 1:1');
    assert(IAgamaVaultDispatcher { contract_address: vault }.reserve() == 1000000, 'reserve holds');
    assert(
        IERC20Dispatcher { contract_address: usdc }.balance_of(vault) == 1000000, 'vault has USDC',
    );
    assert(IERC20Dispatcher { contract_address: usdc }.balance_of(user()) == 0, 'user USDC moved');
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
