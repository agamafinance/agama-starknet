use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use agama_starknet::mock_usdc::{
    IERC20Dispatcher, IERC20DispatcherTrait, IMockUsdcDispatcher, IMockUsdcDispatcherTrait,
};
use agama_starknet::agama_vault::{IAgamaVaultDispatcher, IAgamaVaultDispatcherTrait};

fn admin() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn user() -> ContractAddress {
    0x0b0b.try_into().unwrap()
}

fn deploy_usdc() -> ContractAddress {
    let c = declare("MockUsdc").unwrap().contract_class();
    let (addr, _) = c.deploy(@array![]).unwrap();
    addr
}

fn deploy_vault(usdc: ContractAddress, cap_bps: u256) -> ContractAddress {
    let c = declare("AgamaVault").unwrap().contract_class();
    let mut calldata = array![];
    admin().serialize(ref calldata);
    usdc.serialize(ref calldata);
    cap_bps.serialize(ref calldata);
    let (addr, _) = c.deploy(@calldata).unwrap();
    addr
}

// deposit 1000 USDC from `user` into the vault (mints + approves first).
fn setup_with_deposit(cap_bps: u256, amount: u256) -> (ContractAddress, ContractAddress) {
    let usdc_addr = deploy_usdc();
    let vault_addr = deploy_vault(usdc_addr, cap_bps);
    let usdc = IERC20Dispatcher { contract_address: usdc_addr };
    let mint = IMockUsdcDispatcher { contract_address: usdc_addr };
    let vault = IAgamaVaultDispatcher { contract_address: vault_addr };

    mint.mint(user(), amount);

    start_cheat_caller_address(usdc_addr, user());
    usdc.approve(vault_addr, amount);
    stop_cheat_caller_address(usdc_addr);

    start_cheat_caller_address(vault_addr, user());
    vault.deposit(amount);
    stop_cheat_caller_address(vault_addr);

    (usdc_addr, vault_addr)
}

#[test]
fn test_deposit_mints_1_to_1() {
    let (usdc_addr, vault_addr) = setup_with_deposit(4000, 1000);
    let usdc = IERC20Dispatcher { contract_address: usdc_addr };
    let vault = IAgamaVaultDispatcher { contract_address: vault_addr };

    assert(vault.agusd_balance_of(user()) == 1000, 'agUSD minted 1:1');
    assert(vault.agusd_total_supply() == 1000, 'supply == deposit');
    assert(vault.reserve() == 1000, 'reserve holds USDC');
    assert(vault.total_backing() == 1000, 'backing == deposit');
    assert(usdc.balance_of(vault_addr) == 1000, 'vault holds USDC');
    assert(usdc.balance_of(user()) == 0, 'user USDC moved');
}

#[test]
fn test_redeem_burns_and_returns_usdc() {
    let (usdc_addr, vault_addr) = setup_with_deposit(4000, 1000);
    let usdc = IERC20Dispatcher { contract_address: usdc_addr };
    let vault = IAgamaVaultDispatcher { contract_address: vault_addr };

    start_cheat_caller_address(vault_addr, user());
    vault.redeem(400);
    stop_cheat_caller_address(vault_addr);

    assert(vault.agusd_balance_of(user()) == 600, 'agUSD burned');
    assert(vault.agusd_total_supply() == 600, 'supply reduced');
    assert(vault.reserve() == 600, 'reserve reduced');
    assert(usdc.balance_of(user()) == 400, 'user got USDC back');
}

#[test]
fn test_allocate_within_cap() {
    let (_usdc_addr, vault_addr) = setup_with_deposit(4000, 1000);
    let vault = IAgamaVaultDispatcher { contract_address: vault_addr };

    start_cheat_caller_address(vault_addr, admin());
    vault.allocate(1, 400); // 40% of 1000, exactly the cap
    stop_cheat_caller_address(vault_addr);

    assert(vault.deployed(1) == 400, 'pool 1 deployed');
    assert(vault.reserve() == 600, 'reserve reduced');
    assert(vault.total_deployed() == 400, 'total deployed');
    assert(vault.total_backing() == 1000, 'backing unchanged');
}

#[test]
#[should_panic(expected: 'cap breached')]
fn test_allocate_exceeds_cap_reverts() {
    let (_usdc_addr, vault_addr) = setup_with_deposit(4000, 1000);
    let vault = IAgamaVaultDispatcher { contract_address: vault_addr };

    start_cheat_caller_address(vault_addr, admin());
    vault.allocate(1, 500); // 50% > 40% cap -> reverts on-chain
    stop_cheat_caller_address(vault_addr);
}

#[test]
#[should_panic(expected: 'not admin')]
fn test_allocate_requires_admin() {
    let (_usdc_addr, vault_addr) = setup_with_deposit(4000, 1000);
    let vault = IAgamaVaultDispatcher { contract_address: vault_addr };

    start_cheat_caller_address(vault_addr, user());
    vault.allocate(1, 100);
    stop_cheat_caller_address(vault_addr);
}

#[test]
fn test_backing_invariant_holds() {
    let (_usdc_addr, vault_addr) = setup_with_deposit(5000, 1000);
    let vault = IAgamaVaultDispatcher { contract_address: vault_addr };

    // allocate across two pools, then partially deallocate
    start_cheat_caller_address(vault_addr, admin());
    vault.allocate(1, 300);
    vault.allocate(2, 500);
    vault.deallocate(1, 100);
    stop_cheat_caller_address(vault_addr);

    // agUSD supply must always equal reserve + deployed
    assert(vault.agusd_total_supply() == vault.total_backing(), 'supply == backing');
    assert(vault.total_backing() == 1000, 'backing conserved');
    assert(vault.deployed(1) == 200, 'pool1 after dealloc');
    assert(vault.deployed(2) == 500, 'pool2 deployed');
    assert(vault.reserve() == 300, 'reserve remainder');
}
