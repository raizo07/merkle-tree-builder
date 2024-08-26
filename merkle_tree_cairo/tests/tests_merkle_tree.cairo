use core::clone::Clone;
use core::result::ResultTrait;
use starknet::{ContractAddress, contract_address_const};
use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, test_address, spy_events, EventSpy, start_cheat_caller_address,
    stop_cheat_caller_address, EventSpyAssertionsTrait
};

// Contracts
use merkle_tree_cairo::claimer::{Claimer, IClaimerDispatcher, IClaimerDispatcherTrait};

// Constants
use super::constants::{
    MERKLE_ROOT_FIRST_WAVE, MERKLE_ROOT_SECOND_WAVE, get_bob_first_wave_allocation,
    get_bob_second_wave_allocation, get_alice_second_wave_allocation, get_john_multiple_allocations
};

fn deploy_contract() -> ContractAddress {
    let contract = snf::declare("Claimer").expect('Contract declaration failed');

    let calldata: Array<felt252> = array![];
    let (contract_address, _) = contract.deploy(@calldata).expect('Contract deployment failed');

    contract_address
}

#[test]
fn test_set_merkle_root() {
    /// Test that the Merkle root can be set and retrieved correctly.
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract
        .set_merkle_root(
            803781063426407299979325390167664109772842041387232186868510660774343066272
        );
    let root = contract.get_merkle_root();
    assert_eq!(root, MERKLE_ROOT_FIRST_WAVE);
}

#[test]
fn test_bob_claims_single_allocation() {
    /// Test a simple claim scenario where Bob claims his allocation from the first wave.
    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    assert_eq!(contract.get_merkle_root(), root);

    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    start_cheat_caller_address(contract_address, bob_address);
    contract.claim(amount, timestamp, id, proof);

    assert!(contract.check_claimed(bob_address, timestamp, amount, id));
}

#[test]
#[should_panic(expected: 'Already claimed')]
fn test_bob_claims_twice() {
    /// Test that trying to claim the same allocation twice results in a panic.
    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    start_cheat_caller_address(contract_address, bob_address);
    contract.claim(amount, timestamp, id, proof.clone());
    assert!(contract.check_claimed(bob_address, timestamp, amount, id));

    contract.claim(amount, timestamp, id, proof);
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_address() {
    let (root, _, amount, timestamp, id, proof) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    let invalid_address = contract_address_const::<'DUMMY'>();
    assert!(!contract.check_claimed(invalid_address, timestamp, amount, id));

    start_cheat_caller_address(contract_address, invalid_address);
    contract.claim(amount, timestamp, id, proof);
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_amount() {
    let (root, bob_address, _, timestamp, id, proof) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    let invalid_amount = 0;
    assert!(!contract.check_claimed(bob_address, timestamp, invalid_amount, id));

    start_cheat_caller_address(contract_address, bob_address);
    contract.claim(invalid_amount, timestamp, id, proof);
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_timestamp() {
    let (root, bob_address, amount, _, id, proof) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    let invalid_timestamp = 0;
    assert!(!contract.check_claimed(bob_address, invalid_timestamp, amount, id));

    start_cheat_caller_address(contract_address, bob_address);
    contract.claim(amount, invalid_timestamp, id, proof);
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_proof() {
    let (root, bob_address, amount, timestamp, id, _) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    let invalid_proof: Array<felt252> = array![0x123, 0x1];
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    start_cheat_caller_address(contract_address, bob_address);
    contract.claim(amount, timestamp, id, invalid_proof);
}

#[test]
fn test_event_emission_on_claim() {
    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    let mut spy = spy_events();
    start_cheat_caller_address(contract_address, bob_address);
    contract.claim(amount, timestamp, id, proof);

    let expected_event = Claimer::Event::Claimed(
        Claimer::Claimed { claimee: bob_address, amount, timestamp }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);

    assert!(contract.check_claimed(bob_address, timestamp, amount, id));
}

#[test]
fn test_claim_after_root_update() {
    /// Test that an unclaimed allocation from the first wave can still be claimed after setting a new Merkle root.
    let (root, bob_address, amount, timestamp, id, _) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    let (new_root, _, _, _, _, new_proof) = get_bob_second_wave_allocation();
    contract.set_merkle_root(new_root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    start_cheat_caller_address(contract_address, bob_address);
    contract.claim(amount, timestamp, id, new_proof);
    assert!(contract.check_claimed(bob_address, timestamp, amount, id));
}

#[test]
fn test_alice_claims_in_second_wave() {
    /// Test that Bob can claim his allocation from the first wave and Alice can claim her allocation from the second wave.
    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();
    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    let mut spy = spy_events();
    start_cheat_caller_address(contract_address, bob_address);
    contract.claim(amount, timestamp, id, proof);

    let expected_event = Claimer::Event::Claimed(
        Claimer::Claimed { claimee: bob_address, amount, timestamp }
    );
    spy.assert_emitted(@array![(contract_address, expected_event)]);
    assert!(contract.check_claimed(bob_address, timestamp, amount, id));

    let (new_root, alice_address, amount, timestamp, id, proof) =
        get_alice_second_wave_allocation();
    contract.set_merkle_root(new_root);
    assert!(!contract.check_claimed(alice_address, timestamp, amount, id));

    start_cheat_caller_address(contract_address, alice_address);
    contract.claim(amount, timestamp, id, proof);
    assert!(contract.check_claimed(alice_address, timestamp, amount, id));
}

#[test]
fn test_john_claims_multiple_allocations() {
    /// Test that John can claim two of his three allocations from the first wave, and the remaining one from the second wave.
    let (
        root,
        new_root,
        john_address,
        amount1,
        timestamp1,
        id_1,
        amount2,
        timestamp2,
        id_2,
        amount3,
        timestamp3,
        id_3,
        amount4,
        timestamp4,
        id_4,
        proof1,
        proof2,
        _,
        proof4
    ) =
        get_john_multiple_allocations();

    let contract_address = deploy_contract();
    let contract = IClaimerDispatcher { contract_address };

    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(john_address, timestamp1, amount1, id_1));
    assert!(!contract.check_claimed(john_address, timestamp2, amount2, id_2));
    assert!(!contract.check_claimed(john_address, timestamp3, amount3, id_3));

    start_cheat_caller_address(contract_address, john_address);
    contract.claim(amount1, timestamp1, id_1, proof1);
    contract.claim(amount2, timestamp2, id_2, proof2);
    assert!(contract.check_claimed(john_address, timestamp1, amount1, id_1));
    assert!(contract.check_claimed(john_address, timestamp2, amount2, id_2));
    assert!(!contract.check_claimed(john_address, timestamp3, amount3, id_3));

    contract.set_merkle_root(new_root);
    contract.claim(amount4, timestamp4, id_4, proof4);
    assert!(contract.check_claimed(john_address, timestamp4, amount4, id_4));
    assert!(!contract.check_claimed(john_address, timestamp3, amount3, id_3));
}
