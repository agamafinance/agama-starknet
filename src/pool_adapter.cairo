use starknet::ContractAddress;

// Pool adapters connect the allocation engine to a concrete yield source behind a
// uniform interface. `deploy` sends USDC out to the source; `withdraw` pulls it back.
//   - VesuAdapter: an on-chain ERC-4626 / SNIP-22 vault (e.g. Vesu). deploy mints
//     vTokens, withdraw redeems them.
//   - OriginatorAdapter: an off-chain private-credit originator. deploy sends USDC to
//     a permissioned originator (native USDC + CCTP in production); withdraw pulls the
//     settled USDC back once the originator repays.
#[starknet::interface]
pub trait IPoolAdapter<T> {
    fn deploy(ref self: T, amount: u256) -> u256;
    fn withdraw(ref self: T, amount: u256) -> u256;
    fn underlying(self: @T) -> ContractAddress;
    fn pool(self: @T) -> ContractAddress;
}

#[starknet::contract]
pub mod VesuAdapter {
    use agama_starknet::agama_pool_vault::{IVTokenDispatcher, IVTokenDispatcherTrait};
    use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use super::IPoolAdapter;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        underlying: ContractAddress,
        pool: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        underlying: ContractAddress,
        pool: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.underlying.write(underlying);
        self.pool.write(pool);
    }

    #[abi(embed_v0)]
    impl Adapter of IPoolAdapter<ContractState> {
        fn deploy(ref self: ContractState, amount: u256) -> u256 {
            self.ownable.assert_only_owner();
            let pool = self.pool.read();
            IERC20Dispatcher { contract_address: self.underlying.read() }.approve(pool, amount);
            IVTokenDispatcher { contract_address: pool }.deposit(amount, get_contract_address())
        }

        fn withdraw(ref self: ContractState, amount: u256) -> u256 {
            // `amount` is the vToken share count to redeem.
            self.ownable.assert_only_owner();
            let me = get_contract_address();
            IVTokenDispatcher { contract_address: self.pool.read() }.redeem(amount, me, me)
        }

        fn underlying(self: @ContractState) -> ContractAddress {
            self.underlying.read()
        }
        fn pool(self: @ContractState) -> ContractAddress {
            self.pool.read()
        }
    }
}

#[starknet::contract]
pub mod OriginatorAdapter {
    use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use super::IPoolAdapter;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        underlying: ContractAddress,
        originator: ContractAddress,
        deployed: u256,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        underlying: ContractAddress,
        originator: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.underlying.write(underlying);
        self.originator.write(originator);
    }

    #[abi(embed_v0)]
    impl Adapter of IPoolAdapter<ContractState> {
        fn deploy(ref self: ContractState, amount: u256) -> u256 {
            self.ownable.assert_only_owner();
            // In production this is a native-USDC CCTP transfer to the originator vault.
            IERC20Dispatcher { contract_address: self.underlying.read() }
                .transfer(self.originator.read(), amount);
            self.deployed.write(self.deployed.read() + amount);
            amount
        }

        fn withdraw(ref self: ContractState, amount: u256) -> u256 {
            // Originator repays: pull settled USDC back (originator has approved us).
            self.ownable.assert_only_owner();
            IERC20Dispatcher { contract_address: self.underlying.read() }
                .transfer_from(self.originator.read(), get_contract_address(), amount);
            self.deployed.write(self.deployed.read() - amount);
            amount
        }

        fn underlying(self: @ContractState) -> ContractAddress {
            self.underlying.read()
        }
        fn pool(self: @ContractState) -> ContractAddress {
            self.originator.read()
        }
    }
}
