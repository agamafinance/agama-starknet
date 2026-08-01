use starknet::ContractAddress;

// Minimal ERC20 with open mint/burn (test only). Implements the standard snake_case selectors
// so the adapter's OZ IERC20 dispatcher works against it.
#[starknet::interface]
pub trait IMockErc20<T> {
    fn mint(ref self: T, to: ContractAddress, amount: u256);
    fn burn(ref self: T, from: ContractAddress, amount: u256);
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn total_supply(self: @T) -> u256;
    fn allowance(self: @T, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: T, to: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: T, from: ContractAddress, to: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: T, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::contract]
pub mod MockErc20 {
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use super::IMockErc20;

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<ContractAddress, Map<ContractAddress, u256>>,
        supply: u256,
    }

    #[abi(embed_v0)]
    impl Erc20 of IMockErc20<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.balances.entry(to).write(self.balances.entry(to).read() + amount);
            self.supply.write(self.supply.read() + amount);
        }
        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            let b = self.balances.entry(from).read();
            assert(b >= amount, 'burn exceeds balance');
            self.balances.entry(from).write(b - amount);
            self.supply.write(self.supply.read() - amount);
        }
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.entry(account).read()
        }
        fn total_supply(self: @ContractState) -> u256 {
            self.supply.read()
        }
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.entry(owner).entry(spender).read()
        }
        fn transfer(ref self: ContractState, to: ContractAddress, amount: u256) -> bool {
            self._transfer(get_caller_address(), to, amount);
            true
        }
        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) -> bool {
            let caller = get_caller_address();
            let allowed = self.allowances.entry(from).entry(caller).read();
            assert(allowed >= amount, 'ERC20: insufficient allowance');
            self.allowances.entry(from).entry(caller).write(allowed - amount);
            self._transfer(from, to, amount);
            true
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.allowances.entry(get_caller_address()).entry(spender).write(amount);
            true
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn _transfer(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) {
            let bf = self.balances.entry(from).read();
            assert(bf >= amount, 'ERC20: insufficient balance');
            self.balances.entry(from).write(bf - amount);
            self.balances.entry(to).write(self.balances.entry(to).read() + amount);
        }
    }
}

// Mock of the Agama vault / share-token split: deposit pulls USDC and mints agUSD (share) to the
// caller; redeem burns the caller's agUSD and returns USDC. 1:1 for the test (matches a fresh
// vault at price 1.0), which is all the adapter integration needs to exercise.
#[starknet::contract]
pub mod MockSplitVault {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::super::agama_shielded_adapter::IAgamaVault;
    use super::{IMockErc20Dispatcher, IMockErc20DispatcherTrait};

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
            IMockErc20Dispatcher { contract_address: self.usdc.read() }
                .transfer_from(user, get_contract_address(), assets);
            IMockErc20Dispatcher { contract_address: self.share.read() }.mint(user, assets);
            assets
        }
        fn redeem(ref self: ContractState, shares: u256) -> u256 {
            let user = get_caller_address();
            IMockErc20Dispatcher { contract_address: self.share.read() }.burn(user, shares);
            IMockErc20Dispatcher { contract_address: self.usdc.read() }.transfer(user, shares);
            shares
        }
    }
}
