// Allocation engine: routes the vault's idle USDC across registered lending pools
// under on-chain risk controls.
//   - pools are admin-registered (no self-listing),
//   - every allocation is capped: a pool can never exceed its concentration cap
//     (a share of total managed capital), enforced on-chain,
//   - allocations are blocked while the NAV oracle is stale.
// Fund custody / real USDC movement to pool adapters is handled in the adapter
// layer; this contract owns registration, caps and allocation accounting.
// Immutable, Ownable admin.
#[starknet::interface]
pub trait IAllocationEngine<T> {
    fn register_pool(ref self: T, pool_id: u32, cap_bps: u256);
    fn set_cap(ref self: T, pool_id: u32, cap_bps: u256);
    fn fund(ref self: T, amount: u256);
    fn allocate(ref self: T, pool_id: u32, amount: u256);
    fn deallocate(ref self: T, pool_id: u32, amount: u256);
    fn idle(self: @T) -> u256;
    fn deployed(self: @T, pool_id: u32) -> u256;
    fn total_deployed(self: @T) -> u256;
    fn total_managed(self: @T) -> u256;
    fn cap_bps(self: @T, pool_id: u32) -> u256;
    fn is_registered(self: @T, pool_id: u32) -> bool;
}

#[starknet::contract]
pub mod AllocationEngine {
    use agama_starknet::nav_oracle::{INavOracleDispatcher, INavOracleDispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use super::IAllocationEngine;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    const BPS: u256 = 10000;

    #[storage]
    struct Storage {
        oracle: ContractAddress,
        registered: Map<u32, bool>,
        cap: Map<u32, u256>,
        deployed: Map<u32, u256>,
        total_deployed: u256,
        idle: u256,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PoolRegistered: PoolRegistered,
        Allocated: Allocated,
        Deallocated: Deallocated,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct PoolRegistered {
        pool_id: u32,
        cap_bps: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Allocated {
        pool_id: u32,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Deallocated {
        pool_id: u32,
        amount: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, oracle: ContractAddress) {
        self.ownable.initializer(owner);
        self.oracle.write(oracle);
    }

    #[abi(embed_v0)]
    impl EngineImpl of IAllocationEngine<ContractState> {
        fn register_pool(ref self: ContractState, pool_id: u32, cap_bps: u256) {
            self.ownable.assert_only_owner();
            assert(!self.registered.entry(pool_id).read(), 'pool already registered');
            assert(cap_bps <= BPS, 'cap over 100%');
            self.registered.entry(pool_id).write(true);
            self.cap.entry(pool_id).write(cap_bps);
            self.emit(PoolRegistered { pool_id, cap_bps });
        }

        fn set_cap(ref self: ContractState, pool_id: u32, cap_bps: u256) {
            self.ownable.assert_only_owner();
            assert(self.registered.entry(pool_id).read(), 'pool not registered');
            assert(cap_bps <= BPS, 'cap over 100%');
            self.cap.entry(pool_id).write(cap_bps);
        }

        fn fund(ref self: ContractState, amount: u256) {
            // In production the vault moves USDC here; tracked as idle managed capital.
            self.ownable.assert_only_owner();
            self.idle.write(self.idle.read() + amount);
        }

        fn allocate(ref self: ContractState, pool_id: u32, amount: u256) {
            self.ownable.assert_only_owner();
            assert(self.registered.entry(pool_id).read(), 'pool not registered');
            // block allocations while the RWA valuation is stale
            INavOracleDispatcher { contract_address: self.oracle.read() }.assert_fresh();
            assert(self.idle.read() >= amount, 'insufficient idle');
            let new_pool = self.deployed.entry(pool_id).read() + amount;
            // concentration cap: pool share of total managed capital
            let managed = self.idle.read() + self.total_deployed.read();
            let cap = managed * self.cap.entry(pool_id).read() / BPS;
            assert(new_pool <= cap, 'cap breached');
            self.idle.write(self.idle.read() - amount);
            self.deployed.entry(pool_id).write(new_pool);
            self.total_deployed.write(self.total_deployed.read() + amount);
            self.emit(Allocated { pool_id, amount });
        }

        fn deallocate(ref self: ContractState, pool_id: u32, amount: u256) {
            self.ownable.assert_only_owner();
            let dep = self.deployed.entry(pool_id).read();
            assert(dep >= amount, 'insufficient deployed');
            self.deployed.entry(pool_id).write(dep - amount);
            self.total_deployed.write(self.total_deployed.read() - amount);
            self.idle.write(self.idle.read() + amount);
            self.emit(Deallocated { pool_id, amount });
        }

        fn idle(self: @ContractState) -> u256 {
            self.idle.read()
        }
        fn deployed(self: @ContractState, pool_id: u32) -> u256 {
            self.deployed.entry(pool_id).read()
        }
        fn total_deployed(self: @ContractState) -> u256 {
            self.total_deployed.read()
        }
        fn total_managed(self: @ContractState) -> u256 {
            self.idle.read() + self.total_deployed.read()
        }
        fn cap_bps(self: @ContractState, pool_id: u32) -> u256 {
            self.cap.entry(pool_id).read()
        }
        fn is_registered(self: @ContractState, pool_id: u32) -> bool {
            self.registered.entry(pool_id).read()
        }
    }
}
