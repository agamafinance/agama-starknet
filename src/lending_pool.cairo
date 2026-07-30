// A single Agama lending pool as a yield-bearing NAV position. Capital allocated to
// the pool (`principal`) accrues yield continuously at the pool's APR — Pool A private
// credit, Pool B tokenized treasuries, Pool C bonds, Pool D on-chain RWA yield each run
// their own rate. `total_value()` = principal + accrued yield to the current block, so
// the mark grows every second. The Agama vault sums every pool's `total_value()` into
// its NAV, which is what the `agUSD` share price indexes on.
//
// This models the deployed position's marked value (as a private-credit fund reports
// NAV); realized cash settles into the vault reserve separately. Owner-driven fund /
// defund / set_apr; anyone can `accrue` to fold pending yield into storage. Immutable.
#[starknet::interface]
pub trait ILendingPool<T> {
    fn fund(ref self: T, amount: u256);
    fn defund(ref self: T, amount: u256);
    fn set_apr(ref self: T, apr_bps: u32);
    fn accrue(ref self: T);
    fn name(self: @T) -> felt252;
    fn apr_bps(self: @T) -> u32;
    fn principal(self: @T) -> u256;
    fn accrued(self: @T) -> u256;
    fn pending(self: @T) -> u256;
    fn total_value(self: @T) -> u256;
    fn last_accrual(self: @T) -> u64;
}

#[starknet::contract]
pub mod LendingPool {
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use super::ILendingPool;

    const BPS: u256 = 10000;
    const SECONDS_PER_YEAR: u256 = 31536000; // 365 days

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        name: felt252,
        vault: ContractAddress,
        apr_bps: u32,
        principal: u256,
        accrued: u256,
        last_ts: u64,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Funded: Funded,
        Defunded: Defunded,
        Accrued: Accrued,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Funded {
        amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct Defunded {
        amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct Accrued {
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        vault: ContractAddress,
        name: felt252,
        apr_bps: u32,
    ) {
        self.ownable.initializer(owner);
        self.vault.write(vault);
        self.name.write(name);
        self.apr_bps.write(apr_bps);
        self.last_ts.write(get_block_timestamp());
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        // Yield earned since the last accrual: principal * apr * dt / (BPS * year).
        fn pending_at(self: @ContractState, now: u64) -> u256 {
            let last = self.last_ts.read();
            if now <= last {
                return 0;
            }
            let dt: u256 = (now - last).into();
            let apr: u256 = self.apr_bps.read().into();
            self.principal.read() * apr * dt / (BPS * SECONDS_PER_YEAR)
        }

        // Fold pending yield into `accrued` and reset the clock.
        fn accrue_now(ref self: ContractState) {
            let now = get_block_timestamp();
            let p = self.pending_at(now);
            if p > 0 {
                self.accrued.write(self.accrued.read() + p);
                self.emit(Accrued { amount: p });
            }
            self.last_ts.write(now);
        }
    }

    #[abi(embed_v0)]
    impl LendingPoolImpl of ILendingPool<ContractState> {
        fn fund(ref self: ContractState, amount: u256) {
            assert(get_caller_address() == self.vault.read(), 'not vault');
            assert(amount > 0, 'amount is zero');
            self.accrue_now();
            self.principal.write(self.principal.read() + amount);
            self.emit(Funded { amount });
        }

        fn defund(ref self: ContractState, amount: u256) {
            assert(get_caller_address() == self.vault.read(), 'not vault');
            assert(amount > 0, 'amount is zero');
            self.accrue_now();
            assert(self.principal.read() >= amount, 'over principal');
            self.principal.write(self.principal.read() - amount);
            self.emit(Defunded { amount });
        }

        fn set_apr(ref self: ContractState, apr_bps: u32) {
            self.ownable.assert_only_owner();
            self.accrue_now(); // lock in yield at the old rate first
            self.apr_bps.write(apr_bps);
        }

        fn accrue(ref self: ContractState) {
            self.accrue_now();
        }

        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }
        fn apr_bps(self: @ContractState) -> u32 {
            self.apr_bps.read()
        }
        fn principal(self: @ContractState) -> u256 {
            self.principal.read()
        }
        fn accrued(self: @ContractState) -> u256 {
            self.accrued.read()
        }
        fn pending(self: @ContractState) -> u256 {
            self.pending_at(get_block_timestamp())
        }
        fn total_value(self: @ContractState) -> u256 {
            self.principal.read() + self.accrued.read() + self.pending_at(get_block_timestamp())
        }
        fn last_accrual(self: @ContractState) -> u64 {
            self.last_ts.read()
        }
    }
}
