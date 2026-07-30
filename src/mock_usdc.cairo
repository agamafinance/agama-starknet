use starknet::ContractAddress;

// Minimal ERC20 used to stand in for native USDC in tests. In production this is
// Circle's native USDC on Starknet; here we keep a self-contained mock so the
// integration test needs no external dependency.
#[starknet::interface]
pub trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn total_supply(self: @TContractState) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, to: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, amount: u256,
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
pub trait IMockUsdc<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod MockUsdc {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use super::{IERC20, IMockUsdc};

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<ContractAddress, Map<ContractAddress, u256>>,
        supply: u256,
    }

    #[abi(embed_v0)]
    impl Erc20 of IERC20<ContractState> {
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

    #[abi(embed_v0)]
    impl Mint of IMockUsdc<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.balances.entry(to).write(self.balances.entry(to).read() + amount);
            self.supply.write(self.supply.read() + amount);
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
