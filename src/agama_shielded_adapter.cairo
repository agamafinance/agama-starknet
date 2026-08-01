// STRK20 shielded adapter for the live agUSD product.
//
// The generic STRK20 lending-anonymizer (see `agama_anonymizer.cairo`) targets a Vesu-style
// vToken where the vault *is* the share ERC20. The Agama product splits that: the `AgamaVault`
// manages the reserve and the four lending pools, and mints a separate share token, `agUSD`.
// This adapter bridges that split so the native STRK20 privacy pool can shield a deposit
// straight into the yield-bearing agUSD product.
//
// Flow (identical shape to the official pattern, `privacy_invoke` driven by the privacy pool):
//   Deposit : privacy pool forwards a shielded user's USDC to this (stateless) adapter, then
//             calls privacy_invoke(Deposit, USDC, agUSD, amount). The adapter deposits the USDC
//             into the vault (minting agUSD at the current NAV price to itself), then approves
//             the privacy pool to pull the agUSD into an encrypted note. The user now holds
//             yield-bearing agUSD inside the shielded pool, unlinked from their address.
//   Withdraw: the reverse, redeem agUSD back to USDC and hand it back to be re-noted.
//
// Stateless: nothing is stranded. Final unlinkability is provided by the native STRK20 pool
// (client-side ZK note, Stwo); this adapter is the lending leg it invokes.
use starknet::ContractAddress;
use super::agama_anonymizer::{LendingOperation, OpenNoteDeposit};

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
    fn vault(self: @T) -> ContractAddress;
}

#[starknet::contract]
pub mod AgamaShieldedAdapter {
    use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
    use agama_starknet::vault::{IAgamaVaultDispatcher, IAgamaVaultDispatcherTrait};
    use core::num::traits::Zero;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::super::agama_anonymizer::{LendingOperation, OpenNoteDeposit, errors};
    use super::IAgamaShieldedAdapter;

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
            assert(in_token.is_non_zero(), errors::ZERO_IN_TOKEN);
            assert(out_token.is_non_zero(), errors::ZERO_OUT_TOKEN);
            assert(amount.is_non_zero(), errors::ZERO_AMOUNT);
            assert(in_token != out_token, errors::TOKENS_EQUAL);

            let self_addr = get_contract_address();
            let privacy_addr = get_caller_address();
            let vault = self.vault.read();
            let out_erc20 = IERC20Dispatcher { contract_address: out_token };

            let balance_before = out_erc20.balance_of(self_addr);

            match operation {
                LendingOperation::Deposit => {
                    // in_token = USDC (asset). Let the vault pull it, then mint agUSD to us.
                    IERC20Dispatcher { contract_address: in_token }.approve(vault, amount);
                    IAgamaVaultDispatcher { contract_address: vault }.deposit(amount);
                },
                LendingOperation::Withdraw => {
                    // in_token = agUSD (shares). Burn ours, receive USDC.
                    IAgamaVaultDispatcher { contract_address: vault }.redeem(amount);
                },
            };

            let balance_after = out_erc20.balance_of(self_addr);
            let out_amount: u128 = (balance_after - balance_before)
                .try_into()
                .expect(errors::RECEIVED_AMOUNT_OVERFLOW);
            assert(out_amount.is_non_zero(), errors::ZERO_OUT_AMOUNT);

            // Approve the privacy pool to pull the received token back into a shielded note.
            out_erc20.approve(privacy_addr, out_amount.into());

            array![OpenNoteDeposit { note_id, token: out_token, amount: out_amount }].span()
        }

        fn vault(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }
    }
}
