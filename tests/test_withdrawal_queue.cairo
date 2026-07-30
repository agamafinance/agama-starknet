use agama_starknet::withdrawal_queue::{IWithdrawalQueueDispatcher, IWithdrawalQueueDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}
fn stranger() -> ContractAddress {
    0xdead.try_into().unwrap()
}
fn u1() -> ContractAddress {
    0xb0b1.try_into().unwrap()
}
fn u2() -> ContractAddress {
    0xb0b2.try_into().unwrap()
}
fn u3() -> ContractAddress {
    0xb0b3.try_into().unwrap()
}

fn deploy() -> ContractAddress {
    let c = declare("WithdrawalQueue").unwrap().contract_class();
    let mut cd = array![];
    owner().serialize(ref cd);
    let (a, _) = c.deploy(@cd).unwrap();
    a
}

fn seed() -> ContractAddress {
    let q = deploy();
    start_cheat_caller_address(q, owner());
    let d = IWithdrawalQueueDispatcher { contract_address: q };
    d.enqueue(u1(), 100);
    d.enqueue(u2(), 200);
    d.enqueue(u3(), 500);
    stop_cheat_caller_address(q);
    q
}

#[test]
fn test_enqueue_sets_fifo() {
    let d = IWithdrawalQueueDispatcher { contract_address: seed() };
    assert(d.pending() == 3, 'pending 3');
    assert(d.head() == 0, 'head 0');
    assert(d.tail() == 3, 'tail 3');
    assert(d.get_request(0).amount == 100, 'req0 amount');
    assert(d.get_request(2).user == u3(), 'req2 user');
}

#[test]
fn test_process_partial_liquidity_fifo() {
    let q = seed();
    let d = IWithdrawalQueueDispatcher { contract_address: q };
    start_cheat_caller_address(q, owner());
    let paid = d.process(300); // covers req0(100)+req1(200), not req2(500)
    stop_cheat_caller_address(q);
    assert(paid == 300, 'paid 300');
    assert(d.head() == 2, 'head advanced');
    assert(d.pending() == 1, 'one left');
    assert(d.get_request(0).fulfilled, 'req0 done');
    assert(d.get_request(1).fulfilled, 'req1 done');
    assert(!d.get_request(2).fulfilled, 'req2 pending');
}

#[test]
fn test_process_rest_then_empty() {
    let q = seed();
    let d = IWithdrawalQueueDispatcher { contract_address: q };
    start_cheat_caller_address(q, owner());
    d.process(300);
    let paid2 = d.process(1000); // covers req2(500)
    let paid3 = d.process(1000); // nothing left
    stop_cheat_caller_address(q);
    assert(paid2 == 500, 'paid the rest');
    assert(paid3 == 0, 'nothing left');
    assert(d.pending() == 0, 'queue empty');
    assert(d.head() == 3, 'head at tail');
}

#[test]
fn test_process_insufficient_for_head() {
    let q = seed();
    let d = IWithdrawalQueueDispatcher { contract_address: q };
    start_cheat_caller_address(q, owner());
    let paid = d.process(50); // < req0(100)
    stop_cheat_caller_address(q);
    assert(paid == 0, 'nothing paid');
    assert(d.head() == 0, 'head unchanged');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_enqueue_only_owner() {
    let q = deploy();
    start_cheat_caller_address(q, stranger());
    IWithdrawalQueueDispatcher { contract_address: q }.enqueue(u1(), 100);
    stop_cheat_caller_address(q);
}
