use starknet::ContractAddress;

// On-chain NAV oracle for Agama's off-chain RWA book. A whitelisted reporter pushes
// the net asset value; the contract enforces three checks on every update:
//   1. caller is in the authorized reporter set,
//   2. timestamp is strictly more recent than the last accepted one,
//   3. deviation from the previous NAV is within `max_deviation_bps` (else it must
//      go through the admin path `push_nav_admin`, i.e. the admin multisig).
// If no valid update lands within `staleness` seconds the oracle is stale, and
// `assert_fresh` (called by the vault/allocation engine) blocks withdrawals and
// allocations until the feed refreshes. Immutable, Ownable admin.
#[starknet::interface]
pub trait INavOracle<T> {
    fn push_nav(ref self: T, nav: u256, timestamp: u64);
    fn push_nav_admin(ref self: T, nav: u256, timestamp: u64);
    fn add_reporter(ref self: T, reporter: ContractAddress);
    fn remove_reporter(ref self: T, reporter: ContractAddress);
    fn nav(self: @T) -> u256;
    fn last_updated(self: @T) -> u64;
    fn is_reporter(self: @T, who: ContractAddress) -> bool;
    fn is_stale(self: @T) -> bool;
    fn assert_fresh(self: @T);
}

#[starknet::contract]
pub mod NavOracle {
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use super::INavOracle;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    const BPS: u256 = 10000;

    #[storage]
    struct Storage {
        reporters: Map<ContractAddress, bool>,
        nav: u256,
        last_ts: u64,
        max_deviation_bps: u256,
        staleness: u64,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        NavUpdated: NavUpdated,
        ReporterSet: ReporterSet,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct NavUpdated {
        nav: u256,
        timestamp: u64,
        by_admin: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct ReporterSet {
        reporter: ContractAddress,
        allowed: bool,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        initial_nav: u256,
        max_deviation_bps: u256,
        staleness: u64,
    ) {
        self.ownable.initializer(owner);
        self.nav.write(initial_nav);
        self.max_deviation_bps.write(max_deviation_bps);
        self.staleness.write(staleness);
    }

    #[abi(embed_v0)]
    impl OracleImpl of INavOracle<ContractState> {
        fn push_nav(ref self: ContractState, nav: u256, timestamp: u64) {
            assert(self.reporters.entry(get_caller_address()).read(), 'oracle: not reporter');
            assert(timestamp > self.last_ts.read(), 'oracle: stale timestamp');
            // deviation check (skipped on the very first real value)
            let old = self.nav.read();
            if old != 0 {
                let diff = if nav > old {
                    nav - old
                } else {
                    old - nav
                };
                assert(
                    diff * BPS <= old * self.max_deviation_bps.read(),
                    'oracle: deviation too large',
                );
            }
            self.nav.write(nav);
            self.last_ts.write(timestamp);
            self.emit(NavUpdated { nav, timestamp, by_admin: false });
        }

        fn push_nav_admin(ref self: ContractState, nav: u256, timestamp: u64) {
            self.ownable.assert_only_owner();
            assert(timestamp > self.last_ts.read(), 'oracle: stale timestamp');
            self.nav.write(nav);
            self.last_ts.write(timestamp);
            self.emit(NavUpdated { nav, timestamp, by_admin: true });
        }

        fn add_reporter(ref self: ContractState, reporter: ContractAddress) {
            self.ownable.assert_only_owner();
            self.reporters.entry(reporter).write(true);
            self.emit(ReporterSet { reporter, allowed: true });
        }

        fn remove_reporter(ref self: ContractState, reporter: ContractAddress) {
            self.ownable.assert_only_owner();
            self.reporters.entry(reporter).write(false);
            self.emit(ReporterSet { reporter, allowed: false });
        }

        fn nav(self: @ContractState) -> u256 {
            self.nav.read()
        }
        fn last_updated(self: @ContractState) -> u64 {
            self.last_ts.read()
        }
        fn is_reporter(self: @ContractState, who: ContractAddress) -> bool {
            self.reporters.entry(who).read()
        }
        fn is_stale(self: @ContractState) -> bool {
            let last = self.last_ts.read();
            if last == 0 {
                return true;
            }
            get_block_timestamp() > last + self.staleness.read()
        }
        fn assert_fresh(self: @ContractState) {
            assert(!self.is_stale(), 'oracle: stale');
        }
    }
}
