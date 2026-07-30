use starknet::ContractAddress;

// ERC-4626 / SNIP-22 vault subset. This is the interface Starknet's STRK20 lending
// anonymizer calls on any lending vault (see starkware-libs/starknet-privacy,
// packages/vesu_lending_anonymizer). Exposing it makes an Agama pool composable
// with the native STRK20 shielded pool.
#[starknet::interface]
pub trait IVToken<T> {
    fn deposit(ref self: T, assets: u256, receiver: ContractAddress) -> u256;
    fn redeem(ref self: T, shares: u256, receiver: ContractAddress, owner: ContractAddress) -> u256;
}

// An Agama private-credit pool as an ERC-4626 vault: deposit underlying (USDC) ->
// mint pool shares 1:1; redeem shares -> return underlying. The share token is the
// vault itself (standard ERC-4626), so it also implements ERC20.
#[starknet::contract]
pub mod AgamaPoolVault {
    use agama_starknet::mock_usdc::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::IVToken;

    #[storage]
    struct Storage {
        underlying: ContractAddress,
        balances: Map<ContractAddress, u256>,
        allowances: Map<ContractAddress, Map<ContractAddress, u256>>,
        supply: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, underlying: ContractAddress) {
        self.underlying.write(underlying);
    }

    #[abi(embed_v0)]
    impl VToken of IVToken<ContractState> {
        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            // pull underlying from caller (the anonymizer, which approved us)
            IERC20Dispatcher { contract_address: self.underlying.read() }
                .transfer_from(get_caller_address(), get_contract_address(), assets);
            let shares = assets; // 1:1
            self.balances.entry(receiver).write(self.balances.entry(receiver).read() + shares);
            self.supply.write(self.supply.read() + shares);
            shares
        }
        fn redeem(
            ref self: ContractState,
            shares: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            let bal = self.balances.entry(owner).read();
            assert(bal >= shares, 'insufficient shares');
            self.balances.entry(owner).write(bal - shares);
            self.supply.write(self.supply.read() - shares);
            let assets = shares; // 1:1
            IERC20Dispatcher { contract_address: self.underlying.read() }
                .transfer(receiver, assets);
            assets
        }
    }

    // Pool shares as a standard ERC20 (so the anonymizer can measure balance and approve).
    #[abi(embed_v0)]
    impl Shares of IERC20<ContractState> {
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
            assert(allowed >= amount, 'shares: allowance');
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
            assert(bf >= amount, 'shares: balance');
            self.balances.entry(from).write(bf - amount);
            self.balances.entry(to).write(self.balances.entry(to).read() + amount);
        }
    }
}
