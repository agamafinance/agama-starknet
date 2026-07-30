use starknet::ContractAddress;

// The Agama vault is the yield-bearing core. LPs deposit USDC and receive `agUSD`
// *shares*; the vault tracks total assets (USDC under management) and agUSD's total
// supply is the share supply. When real-world yield lands via `distribute` (USDC
// pulled in without minting shares), total assets grow while supply does not, so each
// agUSD becomes worth more USDC — agUSD is itself the yield-bearing token, with no
// separate staking layer. Redeem burns shares and returns USDC at the current price.
//
// total_assets is an internal counter (moved only by deposit / redeem / distribute),
// not the raw USDC balance, so a bare token donation cannot skew the share price —
// this closes the classic ERC-4626 first-depositor inflation vector. Immutable,
// Ownable admin; only the owner can distribute yield.
#[starknet::interface]
pub trait IAgamaVault<T> {
    fn deposit(ref self: T, assets: u256) -> u256;
    fn redeem(ref self: T, shares: u256) -> u256;
    fn distribute(ref self: T, amount: u256);
    fn total_assets(self: @T) -> u256;
    fn convert_to_shares(self: @T, assets: u256) -> u256;
    fn convert_to_assets(self: @T, shares: u256) -> u256;
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
        total_assets: u256,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Redeem: Redeem,
        Distribute: Distribute,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        user: ContractAddress,
        assets: u256,
        shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Redeem {
        user: ContractAddress,
        shares: u256,
        assets: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Distribute {
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

    #[generate_trait]
    impl Internal of InternalTrait {
        // Share supply == agUSD total supply (the vault is agUSD's sole minter).
        fn share_supply(self: @ContractState) -> u256 {
            IERC20Dispatcher { contract_address: self.agusd.read() }.total_supply()
        }
    }

    #[abi(embed_v0)]
    impl VaultImpl of IAgamaVault<ContractState> {
        fn deposit(ref self: ContractState, assets: u256) -> u256 {
            assert(assets > 0, 'amount is zero');
            let user = get_caller_address();
            // Price from state BEFORE the new assets land, then pull and mint.
            let shares = self.convert_to_shares(assets);
            IERC20Dispatcher { contract_address: self.usdc.read() }
                .transfer_from(user, get_contract_address(), assets);
            self.total_assets.write(self.total_assets.read() + assets);
            IAgamaUSDDispatcher { contract_address: self.agusd.read() }.mint(user, shares);
            self.emit(Deposit { user, assets, shares });
            shares
        }

        fn redeem(ref self: ContractState, shares: u256) -> u256 {
            assert(shares > 0, 'amount is zero');
            let user = get_caller_address();
            let assets = self.convert_to_assets(shares);
            assert(self.total_assets.read() >= assets, 'insufficient reserve');
            // Burn the caller's shares, then return USDC at the current price.
            IAgamaUSDDispatcher { contract_address: self.agusd.read() }.burn(user, shares);
            self.total_assets.write(self.total_assets.read() - assets);
            IERC20Dispatcher { contract_address: self.usdc.read() }.transfer(user, assets);
            self.emit(Redeem { user, shares, assets });
            assets
        }

        // Push real-world yield in: pull USDC and grow total assets, minting no shares,
        // so every agUSD's redemption value rises. Owner-only (keeper / allocation).
        fn distribute(ref self: ContractState, amount: u256) {
            self.ownable.assert_only_owner();
            assert(amount > 0, 'amount is zero');
            IERC20Dispatcher { contract_address: self.usdc.read() }
                .transfer_from(get_caller_address(), get_contract_address(), amount);
            self.total_assets.write(self.total_assets.read() + amount);
            self.emit(Distribute { amount });
        }

        fn total_assets(self: @ContractState) -> u256 {
            self.total_assets.read()
        }

        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            let supply = self.share_supply();
            let ta = self.total_assets.read();
            if supply == 0 || ta == 0 {
                assets
            } else {
                assets * supply / ta
            }
        }

        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            let supply = self.share_supply();
            if supply == 0 {
                0
            } else {
                shares * self.total_assets.read() / supply
            }
        }

        // Compatibility alias: assets under management (== USDC reserve).
        fn reserve(self: @ContractState) -> u256 {
            self.total_assets.read()
        }
        fn usdc(self: @ContractState) -> ContractAddress {
            self.usdc.read()
        }
        fn agusd(self: @ContractState) -> ContractAddress {
            self.agusd.read()
        }
    }
}
