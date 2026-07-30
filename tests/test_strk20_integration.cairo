use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait, IMockUsdcDispatcher, IMockUsdcDispatcherTrait};
use agama_starknet::agama_anonymizer::{
    IAgamaLendingAnonymizerDispatcher, IAgamaLendingAnonymizerDispatcherTrait, LendingOperation,
};

// Stands in for the native STRK20 privacy pool that drives the anonymizer.
fn privacy_pool() -> ContractAddress {
    0x9111.try_into().unwrap()
}

fn deploy_usdc() -> ContractAddress {
    let c = declare("MockUsdc").unwrap().contract_class();
    let (a, _) = c.deploy(@array![]).unwrap();
    a
}

fn deploy_vault(underlying: ContractAddress) -> ContractAddress {
    let c = declare("AgamaPoolVault").unwrap().contract_class();
    let mut cd = array![];
    underlying.serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn deploy_anonymizer() -> ContractAddress {
    let c = declare("AgamaLendingAnonymizer").unwrap().contract_class();
    let (a, _) = c.deploy(@array![]).unwrap();
    a
}

// Full STRK20 lending-integration flow: a shielded user's USDC (held by the privacy
// pool) is deposited into an Agama pool through the anonymizer, and the pool shares
// are handed back to the privacy pool to be sealed into an encrypted note.
#[test]
fn test_strk20_shielded_deposit_into_agama_pool() {
    let usdc = deploy_usdc();
    let vault = deploy_vault(usdc);
    let anon = deploy_anonymizer();
    let amount: u256 = 1000;

    // Privacy pool has forwarded `amount` underlying USDC to the (stateless) anonymizer.
    IMockUsdcDispatcher { contract_address: usdc }.mint(anon, amount);

    // Privacy pool invokes the anonymizer to deposit into the Agama pool.
    start_cheat_caller_address(anon, privacy_pool());
    let notes = IAgamaLendingAnonymizerDispatcher { contract_address: anon }
        .privacy_invoke(LendingOperation::Deposit, usdc, vault, amount, 42);
    stop_cheat_caller_address(anon);

    let usdc_d = IERC20Dispatcher { contract_address: usdc };
    let shares_d = IERC20Dispatcher { contract_address: vault };

    // USDC moved into the Agama pool; none stranded in the anonymizer.
    assert(usdc_d.balance_of(vault) == amount, 'pool holds USDC');
    assert(usdc_d.balance_of(anon) == 0, 'anon USDC spent');
    // Anonymizer received pool shares and approved the privacy pool to pull them.
    assert(shares_d.balance_of(anon) == amount, 'anon holds shares');
    assert(shares_d.allowance(anon, privacy_pool()) == amount, 'privacy can pull shares');
    // Returned note deposit is correct for re-shielding.
    assert(notes.len() == 1, 'one note returned');
    let n = *notes.at(0);
    assert(n.note_id == 42, 'note id preserved');
    assert(n.token == vault, 'note token = pool shares');
    assert(n.amount == 1000, 'note amount = shares');
}

// The privacy pool can then unwind: redeem shares back to underlying through the anonymizer.
#[test]
fn test_strk20_shielded_withdraw_from_agama_pool() {
    let usdc = deploy_usdc();
    let vault = deploy_vault(usdc);
    let anon = deploy_anonymizer();
    let amount: u256 = 1000;

    // Seed: anonymizer deposits underlying to get shares (as in the deposit flow).
    IMockUsdcDispatcher { contract_address: usdc }.mint(anon, amount);
    start_cheat_caller_address(anon, privacy_pool());
    IAgamaLendingAnonymizerDispatcher { contract_address: anon }
        .privacy_invoke(LendingOperation::Deposit, usdc, vault, amount, 1);

    // Now withdraw: redeem the shares held by the anonymizer back to USDC.
    let notes = IAgamaLendingAnonymizerDispatcher { contract_address: anon }
        .privacy_invoke(LendingOperation::Withdraw, vault, usdc, amount, 2);
    stop_cheat_caller_address(anon);

    let usdc_d = IERC20Dispatcher { contract_address: usdc };
    assert(usdc_d.balance_of(anon) == amount, 'anon got USDC back');
    assert(usdc_d.balance_of(vault) == 0, 'pool released USDC');
    let n = *notes.at(0);
    assert(n.token == usdc, 'note token = USDC');
    assert(n.amount == 1000, 'note amount = underlying');
}

#[test]
#[should_panic(expected: 'TOKENS_EQUAL')]
fn test_anonymizer_rejects_equal_tokens() {
    let usdc = deploy_usdc();
    let anon = deploy_anonymizer();
    start_cheat_caller_address(anon, privacy_pool());
    IAgamaLendingAnonymizerDispatcher { contract_address: anon }
        .privacy_invoke(LendingOperation::Deposit, usdc, usdc, 1000, 7);
    stop_cheat_caller_address(anon);
}
