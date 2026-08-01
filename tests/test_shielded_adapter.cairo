use agama_starknet::agama_anonymizer::LendingOperation;
use agama_starknet::agama_shielded_adapter::{
    IAgamaShieldedAdapterDispatcher, IAgamaShieldedAdapterDispatcherTrait,
};
use agama_starknet::agusd::{IAgamaUSDDispatcher, IAgamaUSDDispatcherTrait};
use agama_starknet::mock_usdc::{
    IERC20Dispatcher, IERC20DispatcherTrait, IMockUsdcDispatcher, IMockUsdcDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
// Stands in for the native STRK20 privacy pool that drives the adapter.
fn privacy_pool() -> ContractAddress {
    0x9111.try_into().unwrap()
}

fn deploy_usdc() -> ContractAddress {
    let (a, _) = declare("MockUsdc").unwrap().contract_class().deploy(@array![]).unwrap();
    a
}

// usdc + agUSD + vault (vault set as agUSD minter), then the shielded adapter over the vault.
fn stack() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
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
    let mut dc = array![];
    vault.serialize(ref dc);
    let (adapter, _) = declare("AgamaShieldedAdapter").unwrap().contract_class().deploy(@dc).unwrap();
    (usdc, agusd, vault, adapter)
}

// Shielded deposit straight into the yield-bearing agUSD product: the privacy pool forwards a
// shielded user's USDC to the (stateless) adapter, then invokes it. The adapter deposits into
// the vault, receives agUSD, and approves the privacy pool to seal it into an encrypted note.
#[test]
fn test_shielded_deposit_into_agusd() {
    let (usdc, agusd, vault, adapter) = stack();
    let amount: u256 = 1000000;

    IMockUsdcDispatcher { contract_address: usdc }.mint(adapter, amount);

    start_cheat_caller_address(adapter, privacy_pool());
    let notes = IAgamaShieldedAdapterDispatcher { contract_address: adapter }
        .privacy_invoke(LendingOperation::Deposit, usdc, agusd, amount, 42);
    stop_cheat_caller_address(adapter);

    let usdc_d = IERC20Dispatcher { contract_address: usdc };
    let ag_d = IERC20Dispatcher { contract_address: agusd };
    // USDC moved into the vault reserve; none stranded in the adapter.
    assert(usdc_d.balance_of(vault) == amount, 'vault holds USDC');
    assert(usdc_d.balance_of(adapter) == 0, 'adapter USDC spent');
    // Adapter received agUSD (first deposit is 1:1) and approved the privacy pool to pull it.
    assert(ag_d.balance_of(adapter) == amount, 'adapter holds agUSD');
    assert(ag_d.allowance(adapter, privacy_pool()) == amount, 'privacy can pull agUSD');
    // Note is correct for re-shielding.
    assert(notes.len() == 1, 'one note');
    let n = *notes.at(0);
    assert(n.note_id == 42, 'note id kept');
    assert(n.token == agusd, 'note token = agUSD');
    assert(n.amount == 1000000, 'note amount = shares');
}

// The privacy pool can unwind: redeem agUSD back to USDC through the adapter.
#[test]
fn test_shielded_withdraw_from_agusd() {
    let (usdc, agusd, vault, adapter) = stack();
    let amount: u256 = 1000000;

    IMockUsdcDispatcher { contract_address: usdc }.mint(adapter, amount);
    start_cheat_caller_address(adapter, privacy_pool());
    IAgamaShieldedAdapterDispatcher { contract_address: adapter }
        .privacy_invoke(LendingOperation::Deposit, usdc, agusd, amount, 1);
    // now withdraw the agUSD back to USDC
    let notes = IAgamaShieldedAdapterDispatcher { contract_address: adapter }
        .privacy_invoke(LendingOperation::Withdraw, agusd, usdc, amount, 2);
    stop_cheat_caller_address(adapter);

    let usdc_d = IERC20Dispatcher { contract_address: usdc };
    let ag_d = IERC20Dispatcher { contract_address: agusd };
    assert(usdc_d.balance_of(adapter) == amount, 'adapter got USDC back');
    assert(ag_d.balance_of(adapter) == 0, 'agUSD burned');
    assert(usdc_d.balance_of(vault) == 0, 'vault released USDC');
    let n = *notes.at(0);
    assert(n.token == usdc, 'note token = USDC');
    assert(n.amount == 1000000, 'note amount = underlying');
}

#[test]
#[should_panic(expected: 'TOKENS_EQUAL')]
fn test_adapter_rejects_equal_tokens() {
    let (usdc, _agusd, _vault, adapter) = stack();
    start_cheat_caller_address(adapter, privacy_pool());
    IAgamaShieldedAdapterDispatcher { contract_address: adapter }
        .privacy_invoke(LendingOperation::Deposit, usdc, usdc, 1000, 7);
    stop_cheat_caller_address(adapter);
}
