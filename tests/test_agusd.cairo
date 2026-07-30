use agama_starknet::agusd::{IAgamaUSDDispatcher, IAgamaUSDDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

// Local view interface hitting AgamaUSD's ERC20 entrypoints (snake_case, exposed by
// the OpenZeppelin ERC20 mixin). Avoids depending on OZ's interface module layout.
#[starknet::interface]
pub trait IERC20View<T> {
    fn name(self: @T) -> ByteArray;
    fn symbol(self: @T) -> ByteArray;
    fn decimals(self: @T) -> u8;
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn total_supply(self: @T) -> u256;
}

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn vault() -> ContractAddress {
    0x0decaf.try_into().unwrap()
}
fn user() -> ContractAddress {
    0x0b0b.try_into().unwrap()
}

fn deploy() -> ContractAddress {
    let c = declare("AgamaUSD").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn with_minter() -> ContractAddress {
    let a = deploy();
    start_cheat_caller_address(a, owner());
    IAgamaUSDDispatcher { contract_address: a }.set_minter(vault());
    stop_cheat_caller_address(a);
    a
}

#[test]
fn test_metadata() {
    let m = IERC20ViewDispatcher { contract_address: deploy() };
    assert(m.name() == "Agama USD", 'name');
    assert(m.symbol() == "agUSD", 'symbol');
    assert(m.decimals() == 6, 'decimals == USDC');
}

#[test]
fn test_minter_can_mint() {
    let a = with_minter();
    start_cheat_caller_address(a, vault());
    IAgamaUSDDispatcher { contract_address: a }.mint(user(), 1000000);
    stop_cheat_caller_address(a);
    let m = IERC20ViewDispatcher { contract_address: a };
    assert(m.balance_of(user()) == 1000000, 'minted to user');
    assert(m.total_supply() == 1000000, 'supply increased');
}

#[test]
fn test_burn() {
    let a = with_minter();
    start_cheat_caller_address(a, vault());
    let ag = IAgamaUSDDispatcher { contract_address: a };
    ag.mint(user(), 1000000);
    ag.burn(user(), 400000);
    stop_cheat_caller_address(a);
    let m = IERC20ViewDispatcher { contract_address: a };
    assert(m.balance_of(user()) == 600000, 'burned');
    assert(m.total_supply() == 600000, 'supply reduced');
}

#[test]
#[should_panic(expected: 'agUSD: caller not minter')]
fn test_non_minter_cannot_mint() {
    let a = with_minter();
    start_cheat_caller_address(a, user());
    IAgamaUSDDispatcher { contract_address: a }.mint(user(), 1000000);
    stop_cheat_caller_address(a);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_only_owner_sets_minter() {
    let a = deploy();
    start_cheat_caller_address(a, user());
    IAgamaUSDDispatcher { contract_address: a }.set_minter(vault());
    stop_cheat_caller_address(a);
}
