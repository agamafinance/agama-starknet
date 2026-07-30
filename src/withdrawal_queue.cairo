use starknet::ContractAddress;

// FIFO withdrawal queue. When the vault reserve is short (capital is deployed to
// pools), redemptions are queued here and settled in order as USDC returns from
// settlement into idle reserves. Enqueue and process are owner-gated (the vault /
// keeper drives them). Immutable.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Request {
    pub user: ContractAddress,
    pub amount: u256,
    pub fulfilled: bool,
}

#[starknet::interface]
pub trait IWithdrawalQueue<T> {
    fn enqueue(ref self: T, user: ContractAddress, amount: u256) -> u64;
    fn process(ref self: T, liquidity: u256) -> u256;
    fn pending(self: @T) -> u64;
    fn head(self: @T) -> u64;
    fn tail(self: @T) -> u64;
    fn get_request(self: @T, id: u64) -> Request;
}

#[starknet::contract]
pub mod WithdrawalQueue {
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use super::{IWithdrawalQueue, Request};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        requests: Map<u64, Request>,
        head: u64,
        tail: u64,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Enqueued: Enqueued,
        Fulfilled: Fulfilled,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Enqueued {
        id: u64,
        user: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Fulfilled {
        id: u64,
        user: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl QueueImpl of IWithdrawalQueue<ContractState> {
        fn enqueue(ref self: ContractState, user: ContractAddress, amount: u256) -> u64 {
            self.ownable.assert_only_owner();
            assert(amount > 0, 'amount is zero');
            let id = self.tail.read();
            self.requests.entry(id).write(Request { user, amount, fulfilled: false });
            self.tail.write(id + 1);
            self.emit(Enqueued { id, user, amount });
            id
        }

        // Settle pending requests FIFO while `liquidity` covers the head request.
        // Returns the total amount marked fulfilled (the caller pays those users).
        fn process(ref self: ContractState, liquidity: u256) -> u256 {
            self.ownable.assert_only_owner();
            let t = self.tail.read();
            let mut h = self.head.read();
            let mut remaining = liquidity;
            let mut paid: u256 = 0;
            while h != t {
                let r = self.requests.entry(h).read();
                if r.amount > remaining {
                    break;
                }
                self
                    .requests
                    .entry(h)
                    .write(Request { user: r.user, amount: r.amount, fulfilled: true });
                remaining = remaining - r.amount;
                paid = paid + r.amount;
                self.emit(Fulfilled { id: h, user: r.user, amount: r.amount });
                h = h + 1;
            }
            self.head.write(h);
            paid
        }

        fn pending(self: @ContractState) -> u64 {
            self.tail.read() - self.head.read()
        }
        fn head(self: @ContractState) -> u64 {
            self.head.read()
        }
        fn tail(self: @ContractState) -> u64 {
            self.tail.read()
        }
        fn get_request(self: @ContractState, id: u64) -> Request {
            self.requests.entry(id).read()
        }
    }
}
