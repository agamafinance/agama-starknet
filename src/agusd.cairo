use starknet::ContractAddress;

// agUSD control surface: mint/burn are restricted to `minter` (the Agama vault);
// the owner sets the minter. Everything else is standard ERC20 (OpenZeppelin).
#[starknet::interface]
pub trait IAgamaUSD<TState> {
    fn mint(ref self: TState, to: ContractAddress, amount: u256);
    fn burn(ref self: TState, from: ContractAddress, amount: u256);
    fn set_minter(ref self: TState, minter: ContractAddress);
    fn minter(self: @TState) -> ContractAddress;
}

// Agama USD (agUSD) — the synthetic dollar, minted 1:1 against deposited USDC by the
// Agama vault. Built on OpenZeppelin's audited ERC20 + Ownable components, 6 decimals
// to match USDC. Immutable (no upgradeability).
#[starknet::contract]
pub mod AgamaUSD {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use super::IAgamaUSD;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    impl ERC20ImmutableConfig of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 6;
    }

    #[storage]
    struct Storage {
        minter: ContractAddress,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.erc20.initializer("Agama USD", "agUSD");
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl AgamaUSDImpl of IAgamaUSD<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            assert(get_caller_address() == self.minter.read(), 'agUSD: caller not minter');
            self.erc20.mint(to, amount);
        }
        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            assert(get_caller_address() == self.minter.read(), 'agUSD: caller not minter');
            self.erc20.burn(from, amount);
        }
        fn set_minter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            self.minter.write(minter);
        }
        fn minter(self: @ContractState) -> ContractAddress {
            self.minter.read()
        }
    }
}
