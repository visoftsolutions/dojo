use array::{ArrayTrait, SpanTrait};
use traits::Into;
use option::OptionTrait;
use poseidon::poseidon_hash_span;
use serde::Serde;

use dojo::database::storage;

#[derive(Copy, Drop)]
struct WhereCondition {
    key: felt252,
    value: felt252,
}

fn create(address_domain: u32, table: felt252, id: felt252, value: felt252) {
    if exists(address_domain, table, id) {
        return ();
    }

    let index_len_key = build_index_len_key(table, value);
    let index_len = storage::get(address_domain, index_len_key);

    let data = array![index_len + 1, value].span(); // index and value of the created  entry
    storage::set_many(address_domain, build_index_item_key(table, id), 0, data, array![250,  252].span());
    storage::set(address_domain, index_len_key, index_len + 1);
    storage::set(address_domain, build_index_key(table, value, index_len), id);
}

/// Deletes an entry from the main index, as well as from each of the keys.
/// # Arguments
/// * address_domain - The address domain to write to.
/// * index - The index to write to.
/// * id - The id of the entry.
/// # Returns
fn delete(address_domain: u32, table: felt252, id: felt252) {
    if !exists(address_domain, table, id) {
        return ();
    }

    let index_item_key = build_index_item_key(table, id);
    let index_item_layout = array![250,  252].span();
    let delete_item = storage::get_many(address_domain, index_item_key, 0, 2, index_item_layout);
    let delete_item_idx = *delete_item.at(0) - 1;
    let value = *delete_item.at(1);
    

    let index_len_key = build_index_len_key(table, value);
    let replace_item_idx = storage::get(address_domain, index_len_key) - 1;

    storage::set(address_domain, index_item_key, 0);
    storage::set(address_domain, index_len_key, replace_item_idx);

    // Replace the deleted element with the last element.
    // NOTE: We leave the last element set as to not produce an unncessary state diff.
    let replace_item_value = storage::get(address_domain, build_index_key(table, value, replace_item_idx));
    storage::set(address_domain, build_index_key(table, value, delete_item_idx), replace_item_value);
}

fn exists(address_domain: u32, table: felt252, id: felt252) -> bool {
    storage::get(address_domain, build_index_item_key(table, id)) != 0
}

fn get(address_domain: u32, table: felt252, value: felt252) -> Span<felt252> {
    let mut res = ArrayTrait::new();
    let index_len_key = build_index_len_key(table, value);
    let index_len = storage::get(address_domain, index_len_key);
    let mut idx = 0;
    loop {
        if idx == index_len {
          break res.span();
        }

        let id = storage::get(address_domain, build_index_key(table, value, idx));
        res.append(id);
        idx += 1;
    }
}

fn build_index_len_key(table: felt252, value: felt252) -> Span<felt252> {
    array!['dojo_index_lens', table, value].span()
}

fn build_index_key(table: felt252, value: felt252, idx: felt252) -> Span<felt252> {
    array!['dojo_indexes', table, value, idx].span()
}

fn build_index_item_key(table: felt252, id: felt252) -> Span<felt252> {
    array!['dojo_index_ids', table, id].span()
}
