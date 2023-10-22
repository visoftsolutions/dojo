use debug::PrintTrait;

trait Model<T> {
    fn name(self: @T) -> felt252;
    fn keys(self: @T) -> Span<felt252>;
    fn values(self: @T) -> Span<felt252>;
    fn layout(self: @T) -> Span<u8>;
    fn packed_size(self: @T) -> usize;
}

#[starknet::interface]
trait IModel<T> {
    fn name(self: @T) -> felt252;
    fn layout(self: @T) -> Span<felt252>;
    fn schema(self: @T) -> Span<dojo::database::schema::Member>;
}


#[derive(Model, Copy, Drop, Serde)]
struct Outer {
    #[key]
    key: felt252,
    inner: Inner,
}

#[derive(Model, Copy, Drop, Serde)]
struct Inner {
    #[key]
    key: felt252,
    value: felt252,
}

#[test]
#[available_gas(1500000)]
fn test_model_packing() {
    let outer = Outer {
        key: 0,
        inner: Inner {
            key: 1,
            value: 2,
        },
    };

    let values = outer.values();
    let mut idx = 0;
    'values:'.print();
    loop {
        if idx == values.len() {
            break;
        }

        (*values.at(idx)).print();
        idx += 1;
    };

    let layout = outer.layout();
    'layout:'.print();
    let mut idx = 0;
    loop {
        if idx == layout.len() {
            break;
        }

        (*layout.at(idx)).print();
        idx += 1;
    };

    assert(layout.len() == values.len(), 'different lengths'); // failing
}