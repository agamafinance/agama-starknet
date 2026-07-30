use starknet::ContractAddress;

// Faithful reproduction of Starknet's STRK20 lending-anonymizer pattern
// (starkware-libs/starknet-privacy, packages/vesu_lending_anonymizer), retargeted
// at an Agama pool. The native privacy pool calls `privacy_invoke` (via its
// INVOKE_SELECTOR) to run a deposit/withdraw on the lending vault on behalf of a
// shielded user, then pulls the received token back into an encrypted note. The
// anonymizer is stateless: nothing is stranded.

// Matches privacy::objects::OpenNoteDeposit { note_id, token, amount: u128 }.
#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct OpenNoteDeposit {
    pub note_id: felt252,
    pub token: ContractAddress,
    pub amount: u128,
}

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub enum LendingOperation {
    Deposit,
    Withdraw,
}

#[starknet::interface]
pub trait IAgamaLendingAnonymizer<T> {
    fn privacy_invoke(
        ref self: T,
        operation: LendingOperation,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        note_id: felt252,
    ) -> Span<OpenNoteDeposit>;
}

pub mod errors {
    pub const ZERO_IN_TOKEN: felt252 = 'ZERO_IN_TOKEN';
    pub const ZERO_OUT_TOKEN: felt252 = 'ZERO_OUT_TOKEN';
    pub const ZERO_AMOUNT: felt252 = 'ZERO_AMOUNT';
    pub const TOKENS_EQUAL: felt252 = 'TOKENS_EQUAL';
    pub const RECEIVED_AMOUNT_OVERFLOW: felt252 = 'RECEIVED_AMOUNT_OVERFLOW';
    pub const ZERO_OUT_AMOUNT: felt252 = 'ZERO_OUT_AMOUNT';
}

#[starknet::contract]
pub mod AgamaLendingAnonymizer {
    use agama_starknet::agama_pool_vault::{IVTokenDispatcher, IVTokenDispatcherTrait};
    use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::{IAgamaLendingAnonymizer, LendingOperation, OpenNoteDeposit, errors};

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    pub impl AnonymizerImpl of IAgamaLendingAnonymizer<ContractState> {
        fn privacy_invoke(
            ref self: ContractState,
            operation: LendingOperation,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            note_id: felt252,
        ) -> Span<OpenNoteDeposit> {
            assert(in_token.is_non_zero(), errors::ZERO_IN_TOKEN);
            assert(out_token.is_non_zero(), errors::ZERO_OUT_TOKEN);
            assert(amount.is_non_zero(), errors::ZERO_AMOUNT);
            assert(in_token != out_token, errors::TOKENS_EQUAL);

            let self_addr = get_contract_address();
            let privacy_addr = get_caller_address();
            let in_erc20 = IERC20Dispatcher { contract_address: in_token };
            let out_erc20 = IERC20Dispatcher { contract_address: out_token };

            let balance_before = out_erc20.balance_of(self_addr);

            let _shares = match operation {
                LendingOperation::Deposit => {
                    in_erc20.approve(out_token, amount);
                    IVTokenDispatcher { contract_address: out_token }.deposit(amount, self_addr)
                },
                LendingOperation::Withdraw => {
                    IVTokenDispatcher { contract_address: in_token }
                        .redeem(amount, self_addr, self_addr)
                },
            };

            let balance_after = out_erc20.balance_of(self_addr);
            let out_amount: u128 = (balance_after - balance_before)
                .try_into()
                .expect(errors::RECEIVED_AMOUNT_OVERFLOW);
            assert(out_amount.is_non_zero(), errors::ZERO_OUT_AMOUNT);

            // Approve the privacy pool to pull the received token back into a note.
            out_erc20.approve(privacy_addr, out_amount.into());

            array![OpenNoteDeposit { note_id, token: out_token, amount: out_amount }].span()
        }
    }
}
