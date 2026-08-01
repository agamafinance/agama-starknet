// Deployable mocks for the local devnet e2e: the agUSD share token and the Agama vault
// (split model). Used to drive a real shielded deposit through StarkWare's privacy pool
// into yield-bearing agUSD via our adapter.
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockShareToken<T> {
    fn mint(ref self: T, to: ContractAddress, amount: u256);
    fn burn(ref self: T, from: ContractAddress, amount: u256);
}

// agUSD share: a standard OZ ERC20 (18 decimals) with open mint/burn for the vault.
#[starknet::contract]
pub mod MockShareToken {
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;
    use super::IMockShareToken;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl ERC20ImmutableConfig of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 18;
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray) {
        self.erc20.initializer(name, symbol);
    }

    #[abi(embed_v0)]
    impl ShareControl of IMockShareToken<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.erc20.mint(to, amount);
        }
        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            self.erc20.burn(from, amount);
        }
    }
}

// Agama vault (split): deposit pulls USDC and mints agUSD to the caller; redeem burns the
// caller's agUSD and returns USDC. 1:1 for the test (a fresh vault at price 1.0).
#[starknet::interface]
pub trait IAgamaVault<T> {
    fn deposit(ref self: T, assets: u256) -> u256;
    fn redeem(ref self: T, shares: u256) -> u256;
}

#[starknet::contract]
pub mod MockAgamaVault {
    use openzeppelin::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::{IAgamaVault, IMockShareTokenDispatcher, IMockShareTokenDispatcherTrait};

    #[storage]
    struct Storage {
        usdc: ContractAddress,
        share: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, usdc: ContractAddress, share: ContractAddress) {
        self.usdc.write(usdc);
        self.share.write(share);
    }

    #[abi(embed_v0)]
    impl VaultImpl of IAgamaVault<ContractState> {
        fn deposit(ref self: ContractState, assets: u256) -> u256 {
            let user = get_caller_address();
            IERC20Dispatcher { contract_address: self.usdc.read() }
                .transfer_from(user, get_contract_address(), assets);
            IMockShareTokenDispatcher { contract_address: self.share.read() }.mint(user, assets);
            assets
        }
        fn redeem(ref self: ContractState, shares: u256) -> u256 {
            let user = get_caller_address();
            IMockShareTokenDispatcher { contract_address: self.share.read() }.burn(user, shares);
            IERC20Dispatcher { contract_address: self.usdc.read() }.transfer(user, shares);
            shares
        }
    }
}
