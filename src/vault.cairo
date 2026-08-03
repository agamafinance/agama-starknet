use starknet::ContractAddress;

// The Agama vault is the yield-bearing core. LPs deposit USDC and receive `agUSD`
// *shares*; the vault's NAV is the idle reserve plus the marked value of every Agama
// lending pool it has allocated into. Each pool accrues yield at its own APR, so the
// vault's `total_assets` — and therefore the `agUSD` share price — rises continuously
// as the pools earn. `agUSD` is the single yield-bearing token, indexed on the
// aggregate of Pool A (private credit), B (tokenized treasuries), C (bonds), D
// (on-chain RWA yield).
//
//   deposit  : pull USDC into idle reserve, mint agUSD shares at the current price
//   allocate : deploy idle reserve into a lending pool (marks principal, starts yield)
//   redeem   : burn shares, return USDC at the current NAV price (pulls from idle,
//              defunding pools if needed)
//   distribute: push realized cash yield into the reserve, lifting the share price
//
// total_assets is the NAV: idle + Σ pool.total_value(). A bare token donation cannot
// skew it (idle only moves via deposit/redeem/allocate/distribute), closing the classic
// ERC-4626 inflation vector. Immutable, Ownable admin.
#[starknet::interface]
pub trait IAgamaVault<T> {
    fn deposit(ref self: T, assets: u256) -> u256;
    fn redeem(ref self: T, shares: u256) -> u256;
    fn distribute(ref self: T, amount: u256);
    fn register_pool(ref self: T, pool: ContractAddress);
    fn allocate(ref self: T, index: u32, amount: u256);
    fn deallocate(ref self: T, index: u32, amount: u256);
    fn total_assets(self: @T) -> u256;
    fn idle(self: @T) -> u256;
    fn pools_value(self: @T) -> u256;
    fn pool_count(self: @T) -> u32;
    fn pool_at(self: @T, index: u32) -> ContractAddress;
    fn convert_to_shares(self: @T, assets: u256) -> u256;
    fn convert_to_assets(self: @T, shares: u256) -> u256;
    fn reserve(self: @T) -> u256;
    fn usdc(self: @T) -> ContractAddress;
    fn agusd(self: @T) -> ContractAddress;
}

#[starknet::contract]
pub mod AgamaVault {
    use agama_starknet::agusd::{IAgamaUSDDispatcher, IAgamaUSDDispatcherTrait};
    use agama_starknet::lending_pool::{ILendingPoolDispatcher, ILendingPoolDispatcherTrait};
    use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry,
    };
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
        idle: u256,
        pool_count: u32,
        pools: Map<u32, ContractAddress>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Redeem: Redeem,
        Distribute: Distribute,
        Allocate: Allocate,
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
    #[derive(Drop, starknet::Event)]
    struct Allocate {
        index: u32,
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
        fn share_supply(self: @ContractState) -> u256 {
            IERC20Dispatcher { contract_address: self.agusd.read() }.total_supply()
        }

        // Realized USDC actually held by the vault = idle + Σ pool.principal. The pools'
        // *accrued* yield is marked, not cash, so redemptions are bounded by this.
        fn realized(self: @ContractState) -> u256 {
            let mut total = self.idle.read();
            let n = self.pool_count.read();
            let mut i = 0_u32;
            while i < n {
                total += ILendingPoolDispatcher { contract_address: self.pools.entry(i).read() }
                    .principal();
                i += 1;
            }
            total
        }

        // Spread a new deposit evenly across the registered pools so the capital lands in
        // the lending book in the same tx (the last pool absorbs the rounding remainder).
        fn auto_allocate(ref self: ContractState, amount: u256) {
            let n = self.pool_count.read();
            if n == 0 {
                return;
            }
            let per = amount / n.into();
            let mut allocated: u256 = 0;
            let mut i = 0_u32;
            while i < n {
                let part = if i == n - 1 {
                    amount - allocated
                } else {
                    per
                };
                if part > 0 {
                    self.idle.write(self.idle.read() - part);
                    ILendingPoolDispatcher { contract_address: self.pools.entry(i).read() }
                        .fund(part);
                    self.emit(Allocate { index: i, amount: part });
                    allocated += part;
                }
                i += 1;
            }
        }
    }

    #[abi(embed_v0)]
    impl VaultImpl of IAgamaVault<ContractState> {
        fn deposit(ref self: ContractState, assets: u256) -> u256 {
            assert(assets > 0, 'amount is zero');
            let user = get_caller_address();
            let shares = self.convert_to_shares(assets);
            IERC20Dispatcher { contract_address: self.usdc.read() }
                .transfer_from(user, get_contract_address(), assets);
            self.idle.write(self.idle.read() + assets);
            IAgamaUSDDispatcher { contract_address: self.agusd.read() }.mint(user, shares);
            // Deploy the deposit straight into the lending pools, in this same tx.
            self.auto_allocate(assets);
            self.emit(Deposit { user, assets, shares });
            shares
        }

        fn redeem(ref self: ContractState, shares: u256) -> u256 {
            assert(shares > 0, 'amount is zero');
            let user = get_caller_address();
            let assets = self.convert_to_assets(shares);
            assert(self.realized() >= assets, 'insufficient liquidity');
            IAgamaUSDDispatcher { contract_address: self.agusd.read() }.burn(user, shares);
            // Draw from idle first; defund pools in order for any remainder.
            let idle = self.idle.read();
            if idle >= assets {
                self.idle.write(idle - assets);
            } else {
                let mut rem = assets - idle;
                self.idle.write(0);
                let n = self.pool_count.read();
                let mut i = 0_u32;
                while rem > 0 && i < n {
                    let pool = ILendingPoolDispatcher {
                        contract_address: self.pools.entry(i).read(),
                    };
                    let p = pool.principal();
                    if p > 0 {
                        let take = if p >= rem {
                            rem
                        } else {
                            p
                        };
                        pool.defund(take);
                        rem -= take;
                    }
                    i += 1;
                }
            }
            IERC20Dispatcher { contract_address: self.usdc.read() }.transfer(user, assets);
            self.emit(Redeem { user, shares, assets });
            assets
        }

        // Push realized cash yield into the reserve: pulls USDC and grows idle, minting
        // no shares, so every agUSD's redemption value rises (fully backed).
        fn distribute(ref self: ContractState, amount: u256) {
            self.ownable.assert_only_owner();
            assert(amount > 0, 'amount is zero');
            IERC20Dispatcher { contract_address: self.usdc.read() }
                .transfer_from(get_caller_address(), get_contract_address(), amount);
            self.idle.write(self.idle.read() + amount);
            self.emit(Distribute { amount });
        }

        fn register_pool(ref self: ContractState, pool: ContractAddress) {
            self.ownable.assert_only_owner();
            let i = self.pool_count.read();
            self.pools.entry(i).write(pool);
            self.pool_count.write(i + 1);
        }

        // Deploy idle reserve into a pool: marks principal there so it starts earning.
        fn allocate(ref self: ContractState, index: u32, amount: u256) {
            self.ownable.assert_only_owner();
            assert(index < self.pool_count.read(), 'bad pool');
            assert(amount > 0, 'amount is zero');
            assert(self.idle.read() >= amount, 'over idle');
            self.idle.write(self.idle.read() - amount);
            ILendingPoolDispatcher { contract_address: self.pools.entry(index).read() }.fund(amount);
            self.emit(Allocate { index, amount });
        }

        fn deallocate(ref self: ContractState, index: u32, amount: u256) {
            self.ownable.assert_only_owner();
            assert(index < self.pool_count.read(), 'bad pool');
            assert(amount > 0, 'amount is zero');
            ILendingPoolDispatcher { contract_address: self.pools.entry(index).read() }
                .defund(amount);
            self.idle.write(self.idle.read() + amount);
        }

        fn total_assets(self: @ContractState) -> u256 {
            self.idle.read() + self.pools_value()
        }

        fn idle(self: @ContractState) -> u256 {
            self.idle.read()
        }

        fn pools_value(self: @ContractState) -> u256 {
            let mut total: u256 = 0;
            let n = self.pool_count.read();
            let mut i = 0_u32;
            while i < n {
                total += ILendingPoolDispatcher { contract_address: self.pools.entry(i).read() }
                    .total_value();
                i += 1;
            }
            total
        }

        fn pool_count(self: @ContractState) -> u32 {
            self.pool_count.read()
        }

        fn pool_at(self: @ContractState, index: u32) -> ContractAddress {
            self.pools.entry(index).read()
        }

        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            let supply = self.share_supply();
            let ta = self.total_assets();
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
                shares * self.total_assets() / supply
            }
        }

        fn reserve(self: @ContractState) -> u256 {
            self.total_assets()
        }
        fn usdc(self: @ContractState) -> ContractAddress {
            self.usdc.read()
        }
        fn agusd(self: @ContractState) -> ContractAddress {
            self.agusd.read()
        }
    }
}
