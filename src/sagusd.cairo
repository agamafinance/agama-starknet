use starknet::ContractAddress;

// sagUSD: staked agUSD, an ERC-4626-style yield-bearing vault over agUSD.
// stake agUSD -> mint sagUSD shares; unstake -> burn shares and return agUSD.
// When RWA yield lands (agUSD sent to this contract via `distribute`), total assets
// grow while share supply does not, so each sagUSD becomes worth more agUSD.
// Share token is OpenZeppelin ERC20 (6 decimals). Immutable.
#[starknet::interface]
pub trait IStakedAgamaUSD<T> {
    fn stake(ref self: T, assets: u256) -> u256;
    fn unstake(ref self: T, shares: u256) -> u256;
    fn distribute(ref self: T, amount: u256);
    fn asset(self: @T) -> ContractAddress;
    fn total_assets(self: @T) -> u256;
    fn convert_to_shares(self: @T, assets: u256) -> u256;
    fn convert_to_assets(self: @T, shares: u256) -> u256;
}

#[starknet::contract]
pub mod StakedAgamaUSD {
    use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::IStakedAgamaUSD;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    impl ERC20ImmutableConfig of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 6;
    }

    #[storage]
    struct Storage {
        asset: ContractAddress,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Staked: Staked,
        Unstaked: Unstaked,
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Staked {
        user: ContractAddress,
        assets: u256,
        shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Unstaked {
        user: ContractAddress,
        shares: u256,
        assets: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, asset: ContractAddress) {
        self.erc20.initializer("Staked Agama USD", "sagUSD");
        self.asset.write(asset);
    }

    #[abi(embed_v0)]
    impl StakingImpl of IStakedAgamaUSD<ContractState> {
        fn stake(ref self: ContractState, assets: u256) -> u256 {
            assert(assets > 0, 'amount is zero');
            let user = get_caller_address();
            // share price is computed from state BEFORE pulling the new assets
            let shares = self.convert_to_shares(assets);
            IERC20Dispatcher { contract_address: self.asset.read() }
                .transfer_from(user, get_contract_address(), assets);
            self.erc20.mint(user, shares);
            self.emit(Staked { user, assets, shares });
            shares
        }

        fn unstake(ref self: ContractState, shares: u256) -> u256 {
            assert(shares > 0, 'amount is zero');
            let user = get_caller_address();
            let assets = self.convert_to_assets(shares);
            self.erc20.burn(user, shares);
            IERC20Dispatcher { contract_address: self.asset.read() }.transfer(user, assets);
            self.emit(Unstaked { user, shares, assets });
            assets
        }

        fn distribute(ref self: ContractState, amount: u256) {
            // Pull agUSD yield into the pool; grows share price, mints no shares.
            assert(amount > 0, 'amount is zero');
            IERC20Dispatcher { contract_address: self.asset.read() }
                .transfer_from(get_caller_address(), get_contract_address(), amount);
        }

        fn asset(self: @ContractState) -> ContractAddress {
            self.asset.read()
        }

        fn total_assets(self: @ContractState) -> u256 {
            IERC20Dispatcher { contract_address: self.asset.read() }
                .balance_of(get_contract_address())
        }

        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            let supply = self.erc20.ERC20_total_supply.read();
            let ta = self.total_assets();
            if supply == 0 || ta == 0 {
                assets
            } else {
                assets * supply / ta
            }
        }

        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            let supply = self.erc20.ERC20_total_supply.read();
            if supply == 0 {
                0
            } else {
                shares * self.total_assets() / supply
            }
        }
    }
}
