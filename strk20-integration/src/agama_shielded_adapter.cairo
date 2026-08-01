// Agama STRK20 invoke anonymizer, built against the REAL StarkWare privacy package
// (returns `privacy::objects::OpenNoteDeposit`, the actual note type the pool applies).
// Bridges Agama's vault / share-token split so a shielded deposit lands as yield-bearing agUSD.
use privacy::objects::OpenNoteDeposit;
use starknet::ContractAddress;

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub enum LendingOperation {
    Deposit,
    Withdraw,
}

// The Agama vault: deposit USDC (mints agUSD shares to the caller), redeem shares back to USDC.
#[starknet::interface]
pub trait IAgamaVault<T> {
    fn deposit(ref self: T, assets: u256) -> u256;
    fn redeem(ref self: T, shares: u256) -> u256;
}

#[starknet::interface]
pub trait IAgamaShieldedAdapter<T> {
    fn privacy_invoke(
        ref self: T,
        operation: LendingOperation,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        note_id: felt252,
    ) -> Span<OpenNoteDeposit>;
}

#[starknet::contract]
pub mod AgamaShieldedAdapter {
    use core::num::traits::Zero;
    use openzeppelin::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use privacy::objects::OpenNoteDeposit;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::{
        IAgamaShieldedAdapter, IAgamaVaultDispatcher, IAgamaVaultDispatcherTrait, LendingOperation,
    };

    #[storage]
    struct Storage {
        vault: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, vault: ContractAddress) {
        self.vault.write(vault);
    }

    #[abi(embed_v0)]
    pub impl AdapterImpl of IAgamaShieldedAdapter<ContractState> {
        fn privacy_invoke(
            ref self: ContractState,
            operation: LendingOperation,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            note_id: felt252,
        ) -> Span<OpenNoteDeposit> {
            assert(in_token.is_non_zero(), 'ZERO_IN_TOKEN');
            assert(out_token.is_non_zero(), 'ZERO_OUT_TOKEN');
            assert(amount.is_non_zero(), 'ZERO_AMOUNT');
            assert(in_token != out_token, 'TOKENS_EQUAL');

            let self_addr = get_contract_address();
            let privacy_addr = get_caller_address();
            let vault = self.vault.read();
            let out_erc20 = IERC20Dispatcher { contract_address: out_token };
            let before = out_erc20.balance_of(self_addr);

            match operation {
                LendingOperation::Deposit => {
                    IERC20Dispatcher { contract_address: in_token }.approve(vault, amount);
                    IAgamaVaultDispatcher { contract_address: vault }.deposit(amount);
                },
                LendingOperation::Withdraw => {
                    IAgamaVaultDispatcher { contract_address: vault }.redeem(amount);
                },
            };

            let after = out_erc20.balance_of(self_addr);
            let out_amount: u128 = (after - before).try_into().expect('RECEIVED_AMOUNT_OVERFLOW');
            assert(out_amount.is_non_zero(), 'ZERO_OUT_AMOUNT');
            out_erc20.approve(privacy_addr, out_amount.into());

            array![OpenNoteDeposit { note_id, token: out_token, amount: out_amount }].span()
        }
    }
}
