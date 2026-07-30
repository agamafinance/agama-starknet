use starknet::ContractAddress;

// AgamaVault mints agUSD 1:1 against deposited USDC and allocates the reserve
// across lending pools, enforcing a per-pool concentration cap on-chain (this is
// the "allocate() with cap checks" from Agama's Settlement & Trust model). agUSD
// is the synthetic dollar; its supply always equals total backing (reserve +
// deployed), which the tests assert as an invariant.
#[starknet::interface]
pub trait IAgamaVault<TContractState> {
    fn deposit(ref self: TContractState, amount: u256);
    fn redeem(ref self: TContractState, amount: u256);
    fn allocate(ref self: TContractState, pool_id: u32, amount: u256);
    fn deallocate(ref self: TContractState, pool_id: u32, amount: u256);
    fn reserve(self: @TContractState) -> u256;
    fn deployed(self: @TContractState, pool_id: u32) -> u256;
    fn total_deployed(self: @TContractState) -> u256;
    fn total_backing(self: @TContractState) -> u256;
    fn cap_bps(self: @TContractState) -> u256;
    fn agusd_balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn agusd_total_supply(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod AgamaVault {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use agama_starknet::mock_usdc::{IERC20Dispatcher, IERC20DispatcherTrait};
    use super::IAgamaVault;

    const BPS_DENOM: u256 = 10000;

    #[storage]
    struct Storage {
        admin: ContractAddress,
        usdc: ContractAddress,
        cap_bps: u256,
        reserve: u256,
        total_deployed: u256,
        deployed: Map<u32, u256>,
        agusd_balances: Map<ContractAddress, u256>,
        agusd_supply: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PrivateDeposit: PrivateDeposit,
        Allocated: Allocated,
    }

    #[derive(Drop, starknet::Event)]
    struct PrivateDeposit {
        user: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Allocated {
        pool_id: u32,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, admin: ContractAddress, usdc: ContractAddress, cap_bps: u256,
    ) {
        self.admin.write(admin);
        self.usdc.write(usdc);
        self.cap_bps.write(cap_bps);
    }

    #[abi(embed_v0)]
    impl Vault of IAgamaVault<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'amount is zero');
            let user = get_caller_address();
            // In production this USDC leg is shielded through the native STRK20 pool.
            IERC20Dispatcher { contract_address: self.usdc.read() }
                .transfer_from(user, get_contract_address(), amount);
            self.reserve.write(self.reserve.read() + amount);
            // mint agUSD 1:1
            self.agusd_balances.entry(user).write(self.agusd_balances.entry(user).read() + amount);
            self.agusd_supply.write(self.agusd_supply.read() + amount);
            self.emit(PrivateDeposit { user, amount });
        }

        fn redeem(ref self: ContractState, amount: u256) {
            let user = get_caller_address();
            let bal = self.agusd_balances.entry(user).read();
            assert(bal >= amount, 'insufficient agUSD');
            assert(self.reserve.read() >= amount, 'insufficient reserve');
            self.agusd_balances.entry(user).write(bal - amount);
            self.agusd_supply.write(self.agusd_supply.read() - amount);
            self.reserve.write(self.reserve.read() - amount);
            IERC20Dispatcher { contract_address: self.usdc.read() }.transfer(user, amount);
        }

        fn allocate(ref self: ContractState, pool_id: u32, amount: u256) {
            assert(get_caller_address() == self.admin.read(), 'not admin');
            assert(self.reserve.read() >= amount, 'insufficient reserve');
            let new_pool = self.deployed.entry(pool_id).read() + amount;
            // concentration cap: no single pool may exceed cap_bps of total backing
            let backing = self.reserve.read() + self.total_deployed.read();
            let cap = backing * self.cap_bps.read() / BPS_DENOM;
            assert(new_pool <= cap, 'cap breached');
            self.reserve.write(self.reserve.read() - amount);
            self.deployed.entry(pool_id).write(new_pool);
            self.total_deployed.write(self.total_deployed.read() + amount);
            self.emit(Allocated { pool_id, amount });
        }

        fn deallocate(ref self: ContractState, pool_id: u32, amount: u256) {
            assert(get_caller_address() == self.admin.read(), 'not admin');
            let dep = self.deployed.entry(pool_id).read();
            assert(dep >= amount, 'insufficient deployed');
            self.deployed.entry(pool_id).write(dep - amount);
            self.total_deployed.write(self.total_deployed.read() - amount);
            self.reserve.write(self.reserve.read() + amount);
        }

        fn reserve(self: @ContractState) -> u256 {
            self.reserve.read()
        }
        fn deployed(self: @ContractState, pool_id: u32) -> u256 {
            self.deployed.entry(pool_id).read()
        }
        fn total_deployed(self: @ContractState) -> u256 {
            self.total_deployed.read()
        }
        fn total_backing(self: @ContractState) -> u256 {
            self.reserve.read() + self.total_deployed.read()
        }
        fn cap_bps(self: @ContractState) -> u256 {
            self.cap_bps.read()
        }
        fn agusd_balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.agusd_balances.entry(account).read()
        }
        fn agusd_total_supply(self: @ContractState) -> u256 {
            self.agusd_supply.read()
        }
    }
}
