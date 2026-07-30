use starknet::ContractAddress;

// The Agama vault holds the USDC reserve and is the sole minter of agUSD.
// deposit: pull USDC (shielded via STRK20 in production) and mint agUSD 1:1.
// redeem: burn agUSD and return USDC from the reserve.
// Allocation across lending pools is handled by the Allocation Engine (separate
// contract); this vault owns deposit/redeem/reserve. Immutable, Ownable admin.
#[starknet::interface]
pub trait IAgamaVault<T> {
    fn deposit(ref self: T, amount: u256);
    fn redeem(ref self: T, amount: u256);
    fn reserve(self: @T) -> u256;
    fn usdc(self: @T) -> ContractAddress;
    fn agusd(self: @T) -> ContractAddress;
}

#[starknet::contract]
pub mod AgamaVault {
    use agama_starknet::agusd::{IAgamaUSDDispatcher, IAgamaUSDDispatcherTrait};
    use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::IAgamaVault;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        usdc: ContractAddress,
        agusd: ContractAddress,
        reserve: u256,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Redeem: Redeem,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        user: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Redeem {
        user: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        usdc: ContractAddress,
        agusd: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.usdc.write(usdc);
        self.agusd.write(agusd);
    }

    #[abi(embed_v0)]
    impl VaultImpl of IAgamaVault<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'amount is zero');
            let user = get_caller_address();
            // Pull USDC from the user (shielded through STRK20 in production).
            IERC20Dispatcher { contract_address: self.usdc.read() }
                .transfer_from(user, get_contract_address(), amount);
            self.reserve.write(self.reserve.read() + amount);
            // Mint agUSD 1:1.
            IAgamaUSDDispatcher { contract_address: self.agusd.read() }.mint(user, amount);
            self.emit(Deposit { user, amount });
        }

        fn redeem(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'amount is zero');
            let user = get_caller_address();
            assert(self.reserve.read() >= amount, 'insufficient reserve');
            // Burn the caller's agUSD, then return USDC.
            IAgamaUSDDispatcher { contract_address: self.agusd.read() }.burn(user, amount);
            self.reserve.write(self.reserve.read() - amount);
            IERC20Dispatcher { contract_address: self.usdc.read() }.transfer(user, amount);
            self.emit(Redeem { user, amount });
        }

        fn reserve(self: @ContractState) -> u256 {
            self.reserve.read()
        }
        fn usdc(self: @ContractState) -> ContractAddress {
            self.usdc.read()
        }
        fn agusd(self: @ContractState) -> ContractAddress {
            self.agusd.read()
        }
    }
}
