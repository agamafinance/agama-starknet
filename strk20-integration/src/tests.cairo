use privacy::objects::OpenNoteDeposit;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use super::agama_shielded_adapter::{
    IAgamaShieldedAdapterDispatcher, IAgamaShieldedAdapterDispatcherTrait, LendingOperation,
};
use super::mocks::{IMockErc20Dispatcher, IMockErc20DispatcherTrait};

// Stands in for the native STRK20 privacy pool that drives the adapter.
fn privacy_pool() -> ContractAddress {
    0x9111.try_into().unwrap()
}

fn deploy_erc20() -> ContractAddress {
    let (a, _) = declare("MockErc20").unwrap().contract_class().deploy(@array![]).unwrap();
    a
}

fn deploy_vault(usdc: ContractAddress, share: ContractAddress) -> ContractAddress {
    let mut cd = array![];
    usdc.serialize(ref cd);
    share.serialize(ref cd);
    let (a, _) = declare("MockSplitVault").unwrap().contract_class().deploy(@cd).unwrap();
    a
}

fn deploy_adapter(vault: ContractAddress) -> ContractAddress {
    let mut cd = array![];
    vault.serialize(ref cd);
    let (a, _) = declare("AgamaShieldedAdapter").unwrap().contract_class().deploy(@cd).unwrap();
    a
}

// The real StarkWare privacy pool (stood in for here) shields a deposit straight into the
// yield-bearing agUSD product through the Agama adapter, receiving the REAL
// `privacy::objects::OpenNoteDeposit` note the pool applies.
#[test]
fn test_shielded_deposit_into_agusd() {
    let usdc = deploy_erc20();
    let agusd = deploy_erc20();
    let vault = deploy_vault(usdc, agusd);
    let adapter = deploy_adapter(vault);
    let amount: u256 = 1000000;

    // Privacy pool forwarded the shielded user's USDC to the (stateless) adapter.
    IMockErc20Dispatcher { contract_address: usdc }.mint(adapter, amount);

    start_cheat_caller_address(adapter, privacy_pool());
    let notes = IAgamaShieldedAdapterDispatcher { contract_address: adapter }
        .privacy_invoke(LendingOperation::Deposit, usdc, agusd, amount, 42);
    stop_cheat_caller_address(adapter);

    let usdc_d = IMockErc20Dispatcher { contract_address: usdc };
    let ag_d = IMockErc20Dispatcher { contract_address: agusd };
    assert(usdc_d.balance_of(vault) == amount, 'vault holds USDC');
    assert(usdc_d.balance_of(adapter) == 0, 'adapter USDC spent');
    assert(ag_d.balance_of(adapter) == amount, 'adapter holds agUSD');
    assert(ag_d.allowance(adapter, privacy_pool()) == amount, 'privacy can pull agUSD');

    // The returned note is the REAL privacy::objects::OpenNoteDeposit the pool applies.
    assert(notes.len() == 1, 'one note');
    let n: OpenNoteDeposit = *notes.at(0);
    assert(n.note_id == 42, 'note id kept');
    assert(n.token == agusd, 'note token = agUSD');
    assert(n.amount == 1000000, 'note amount = shares');
}

#[test]
fn test_shielded_withdraw_from_agusd() {
    let usdc = deploy_erc20();
    let agusd = deploy_erc20();
    let vault = deploy_vault(usdc, agusd);
    let adapter = deploy_adapter(vault);
    let amount: u256 = 1000000;

    IMockErc20Dispatcher { contract_address: usdc }.mint(adapter, amount);
    start_cheat_caller_address(adapter, privacy_pool());
    IAgamaShieldedAdapterDispatcher { contract_address: adapter }
        .privacy_invoke(LendingOperation::Deposit, usdc, agusd, amount, 1);
    let notes = IAgamaShieldedAdapterDispatcher { contract_address: adapter }
        .privacy_invoke(LendingOperation::Withdraw, agusd, usdc, amount, 2);
    stop_cheat_caller_address(adapter);

    let usdc_d = IMockErc20Dispatcher { contract_address: usdc };
    let ag_d = IMockErc20Dispatcher { contract_address: agusd };
    assert(usdc_d.balance_of(adapter) == amount, 'adapter got USDC back');
    assert(ag_d.balance_of(adapter) == 0, 'agUSD burned');
    assert(usdc_d.balance_of(vault) == 0, 'vault released USDC');
    let n: OpenNoteDeposit = *notes.at(0);
    assert(n.token == usdc, 'note token = USDC');
    assert(n.amount == 1000000, 'note amount = underlying');
}

#[test]
#[should_panic(expected: 'TOKENS_EQUAL')]
fn test_adapter_rejects_equal_tokens() {
    let usdc = deploy_erc20();
    let agusd = deploy_erc20();
    let vault = deploy_vault(usdc, agusd);
    let adapter = deploy_adapter(vault);
    start_cheat_caller_address(adapter, privacy_pool());
    IAgamaShieldedAdapterDispatcher { contract_address: adapter }
        .privacy_invoke(LendingOperation::Deposit, usdc, usdc, 1000, 7);
    stop_cheat_caller_address(adapter);
}
