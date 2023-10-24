use core::result::ResultTrait;
use array::ArrayTrait;
use array::SpanTrait;
use debug::PrintTrait;
use option::OptionTrait;
use poseidon::poseidon_hash_span;
use starknet::SyscallResultTrait;
use starknet::{contract_address_const, ContractAddress, ClassHash, get_caller_address};

use dojo::database;
use dojo::database::{storage, index};
use dojo::packing::{shl, shr};
use dojo::model::Model;
use dojo::world_test::Foo;

const GAS_OFFSET: felt252 = 0x1_000000_000000_000000_000000_000000; // 15 bajtów


fn end(start: u128, name: felt252) {
    let gas_after = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let mut name: u256 = name.into();

    // overwriting zeros with spaces
    let mut char = 0;
    loop {
        if char == 15 {
            break;
        }
        // if given byte is zero
        if shl(0xff, 8 * char) & name == 0 {
            name = name | shl(0x20, 8 * char); // set space
        }
        char += 1;
    };

    let name: felt252 = (name % GAS_OFFSET.into()).try_into().unwrap();
    let used_gas = (start - gas_after - 1770).into() * GAS_OFFSET;
    (used_gas + name).print();
}


#[test]
#[available_gas(1000000000)]
fn bench_reference_offset() {
    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    end(gas, 'bench empty');
}

#[test]
#[available_gas(1000000000)]
fn bench_storage_single() {
    let keys = array!['database_test', '42'].span();

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    storage::set(0, keys, 420);
    end(gas, 'storage set');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let res = storage::get(0, keys);
    end(gas, 'storage get');

    assert(res == 420, 'values differ');
}

#[test]
#[available_gas(1000000000)]
fn bench_storage_many() {
    let keys = array![0x1337].span();
    let values = array![1, 2].span();
    let layout = array![251, 251].span();

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    storage::set_many(0, keys, 0, values, layout);
    end(gas, 'storage set mny');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let res = storage::get_many(0, keys, 0, 2, layout);
    end(gas, 'storage get mny');

    assert(res.len() == 2, 'wrong number of values');
    assert(*res.at(0) == *values.at(0), 'value not set');
    assert(*res.at(1) == *values.at(1), 'value not set');
}

#[test]
#[available_gas(1000000000)]
fn bench_native_storage() {
    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let keys = array![0x1337].span();
    let base = starknet::storage_base_address_from_felt252(poseidon_hash_span(keys));
    let address = starknet::storage_address_from_base(base);
    end(gas, 'native prep');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    starknet::storage_write_syscall(0, address, 42);
    end(gas, 'native write');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let value = starknet::storage_read_syscall(0, address).unwrap_syscall();
    end(gas, 'native read');

    assert(value == 42, 'read invalid');
}

#[test]
#[available_gas(1000000000)]
fn bench_native_storage_offset() {
    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let keys = array![0x1337].span();
    let base = starknet::storage_base_address_from_felt252(poseidon_hash_span(keys));
    let address = starknet::storage_address_from_base_and_offset(base, 42);
    end(gas, 'native prep of');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    starknet::storage_write_syscall(0, address, 42);
    end(gas, 'native writ of');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let value = starknet::storage_read_syscall(0, address).unwrap_syscall();
    end(gas, 'native read of');

    assert(value == 42, 'read invalid');
}

#[test]
#[available_gas(1000000000)]
fn bench_index() {
    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let no_query = index::query(0, 69, Option::None(()));
    end(gas, 'idx empty');
    assert(no_query.len() == 0, 'entity indexed');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    index::create(0, 69, 420);
    end(gas, 'idx create 1st');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let query = index::query(0, 69, Option::None(()));
    end(gas, 'idx query one');
    assert(query.len() == 1, 'entity not indexed');
    assert(*query.at(0) == 420, 'entity value incorrect');
    
    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    index::create(0, 69, 1337);
    end(gas, 'idx query 2nd');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let two_query = index::query(0, 69, Option::None(()));
    end(gas, 'idx query two');
    assert(two_query.len() == 2, 'index should have two query');
    assert(*two_query.at(1) == 1337, 'entity value incorrect');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    index::exists(0, 69, 420);
    end(gas, 'idx exists chk');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    index::delete(0, 69, 420);
    end(gas, 'idx dlt !last');

    assert(!index::exists(0, 69, 420), 'entity should not exist');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    index::delete(0, 69, 1337);
    end(gas, 'idx dlt last');

    assert(!index::exists(0, 69, 1337), 'entity should not exist');
}

#[test]
#[available_gas(1000000000)]
fn bench_database_array() {
    let value = array![1, 2, 3, 4, 5, 6, 7, 8, 9, 10].span();
    let layout = array![251, 251, 251, 251, 251, 251, 251, 251, 251, 251].span();
    let half_layout = array![251, 251, 251, 251, 251].span();
    let len = value.len();

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    database::set('table', 'key', 0, value, layout);
    end(gas, 'db set arr');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let res = database::get('table', 'key', 0, len, layout);
    end(gas, 'db get arr');

    assert(res.len() == len, 'wrong number of values');
    assert(*res.at(0) == *value.at(0), 'value not set');
    assert(*res.at(1) == *value.at(1), 'value not set');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let second_res = database::get('table', 'key', 3, 8, array![251, 251, 251, 251, 251].span());
    end(gas, 'db get half arr');

    assert(second_res.len() == 5, 'wrong number of values');
    assert(*second_res.at(0) == *value.at(3), 'value not set');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    database::del('table', 'key');
    end(gas, 'db del arr');
}

#[test]
#[available_gas(1000000000)]
fn bench_indexed_database_array() {
    let even = array![2, 4].span();
    let odd = array![1, 3].span();
    let layout = array![251, 251].span();

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    database::set_with_index('table', 'even', 0, even, layout);
    end(gas, 'dbi set arr 1st');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (keys, values) = database::scan('table', Option::None(()), 2, layout);
    end(gas, 'dbi scan arr 1');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    database::set_with_index('table', 'odd', 0, odd, layout);
    end(gas, 'dbi set arr 2nd');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (keys, values) = database::scan('table', Option::None(()), 2, layout);
    end(gas, 'dbi scan arr 2');

    assert(keys.len() == 2, 'Wrong number of keys!');
    assert(values.len() == 2, 'Wrong number of values!');
    assert(*keys.at(0) == 'even', 'Wrong key at index 0!');
    assert(*(*values.at(0)).at(0) == 2, 'Wrong value at index 0!');
    assert(*(*values.at(0)).at(1) == 4, 'Wrong value at index 1!');
}


#[test]
#[available_gas(1000000000)]
fn bench_simple_struct() {
    let caller = starknet::contract_address_const::<0x42>();

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let mut foo = Foo {
        caller,
        a: 0x123456789abcdef,
        b: 0x123456789abcdef,
    };
    end(gas, 'foo init');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let mut serialized = ArrayTrait::new();
    serde::Serde::serialize(@foo.a, ref serialized);
    serde::Serde::serialize(@foo.b, ref serialized);
    let serialized = array::ArrayTrait::span(@serialized);
    end(gas, 'foo serialize');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let values: Span<felt252> = foo.values();
    end(gas, 'foo values');

    assert(serialized.len() == 2, 'serialized wrong length');
    assert(values.len() == 2, 'value wrong length');
    assert(serialized.at(0) == values.at(0), 'serialized differ at 0');
    assert(serialized.at(1) == values.at(1), 'serialized differ at 1');
}


#[derive(Introspect, Copy, Drop, Serde)]
struct Sword {
    swordsmith: ContractAddress,
    damage: u32,
}

#[derive(Model, Copy, Drop, Serde)]
struct Case {
    #[key]
    owner: ContractAddress,
    sword: Sword,
}

#[test]
#[available_gas(1000000000)]
fn bench_nested_struct() {
    let caller = starknet::contract_address_const::<0x42>();
    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();

    let mut case = Case {
        owner: caller,
        sword: Sword {
            swordsmith: caller,
            damage: 0x12345678,
        },
    };
    end(gas, 'case init');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let mut serialized = ArrayTrait::new();
    serde::Serde::serialize(@case.sword.swordsmith, ref serialized);
    serde::Serde::serialize(@case.sword.damage, ref serialized);
    let serialized = array::ArrayTrait::span(@serialized);
    end(gas, 'case serialize');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let values: Span<felt252> = case.values();
    end(gas, 'case values');

    assert(serialized.len() == values.len(), 'serialized not equal');
    let mut idx = 0;
    loop {
        if idx == serialized.len() {
            break;
        }
        assert(serialized.at(idx) == values.at(idx), 'serialized differ');
        idx += 1;
    };

    assert(case.layout().len() == values.len(), 'layout inconsintent with values');
}


#[derive(Model, Copy, Drop, Serde)]
struct Character {
    #[key]
    caller: ContractAddress,
    heigth: felt252,
    abilities: Abilities,
    stats: Stats,
    weapon: Sword,
    gold: u32,
}

#[derive(Introspect, Copy, Drop, Serde)]
struct Abilities {
    strength: u8,
    dexterity: u8,
    constitution: u8,
    intelligence: u8,
    wisdom: u8,
    charisma: u8,
}

#[derive(Introspect, Copy, Drop, Serde)]
struct Stats {
    kills: u128,
    deaths: u16,
    rests: u32,
    hits: u64,
    blocks: u32,
    walked: felt252,
    runned: felt252,
    finished: bool,
    romances: u16,
}



#[test]
#[available_gas(1000000000)]
fn bench_complex_struct() {
    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();

    let char = Character {
        caller: starknet::contract_address_const::<0x42>(),
        heigth: 0x123456789abcdef,
        abilities: Abilities {
            strength: 0x12,
            dexterity: 0x34,
            constitution: 0x56,
            intelligence: 0x78,
            wisdom: 0x9a,
            charisma: 0xbc,
        },
        stats: Stats {
            kills: 0x123456789abcdef,
            deaths: 0x1234,
            rests: 0x12345678,
            hits: 0x123456789abcdef,
            blocks: 0x12345678,
            walked: 0x123456789abcdef,
            runned: 0x123456789abcdef,
            finished: true,
            romances: 0x1234,
        },
        weapon: Sword {
            swordsmith: starknet::contract_address_const::<0x69>(),
            damage: 0x12345678,
        },
        gold: 0x12345678,
    };
    end(gas, 'chars init');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let mut serialized = ArrayTrait::new();
    serde::Serde::serialize(@char.heigth, ref serialized);
    serde::Serde::serialize(@char.abilities, ref serialized);
    serde::Serde::serialize(@char.stats, ref serialized);
    serde::Serde::serialize(@char.weapon, ref serialized);
    serde::Serde::serialize(@char.gold, ref serialized);
    let serialized = array::ArrayTrait::span(@serialized);
    end(gas, 'chars serialize');

    let gas = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let values: Span<felt252> = char.values();
    end(gas, 'chars values');


    serialized.len().print();
    values.len().print();
    assert(serialized.len() == values.len(), 'serialized not equal');

    let mut idx = 0;
    loop {
        if idx == serialized.len() {
            break;
        }
        assert(serialized.at(idx) == values.at(idx), 'serialized differ');
        idx += 1;
    };
}