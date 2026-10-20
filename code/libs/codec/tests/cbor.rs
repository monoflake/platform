//! [`Cbor`] held to RFC 8949's own examples in `tests/cbor/`, read as they stand, and to what they
//! leave out: what 4.2.1 writes, what is refused, and in which order. `cbor_test.res` beside it is
//! the same in ReScript.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

mod sample;

use codec::{Cbor, Refused, Unwritable, Value};

const WELL_FORMED: &str =
	concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tests/cbor/well-formed.json");
const NOT_WELL_FORMED: &str =
	concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tests/cbor/not-well-formed.json");
const SORTED_KEYS: &str =
	concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tests/cbor/sorted-keys.json");

/// A sample's `items`.
fn items(path: &str) -> Vec<serde_json::Value> {
	sample::read(path)["items"].as_array().unwrap_or_else(|| panic!("{path}: no items")).clone()
}

#[test]
fn appendix_a_is_read_and_its_deterministic_items_written_back_byte_for_byte() {
	for item in items(WELL_FORMED) {
		let bytes = sample::hex_at(&item["hex"]);
		let value = Value::decode(&bytes).unwrap_or_else(|r| panic!("{}: {r:?}", item["hex"]));
		let strict = Value::decode_deterministic(&bytes);
		if item["deterministic"].as_bool().unwrap() {
			assert!(strict.is_ok(), "{}: {strict:?}", item["hex"]);
			assert_eq!(value.encode().unwrap(), bytes, "{}", item["hex"]);
		} else {
			assert_eq!(strict, Err(Refused::Nondeterministic), "{}", item["hex"]);
		}
	}
}

/// The refusal each of Appendix F.1's kinds implies: the first five are its "too little data", the
/// rest its syntax errors.
fn refusal(kind: &str) -> Refused {
	match kind {
		"end of input in a head"
		| "definite-length strings with short data"
		| "definite-length maps and arrays not closed with enough items"
		| "tag number not followed by tag content"
		| "indefinite-length strings not closed by a \"break\" stop code"
		| "indefinite-length maps and arrays not closed by a \"break\" stop code" => Refused::Truncated,
		"reserved additional information values"
		| "reserved two-byte encodings of simple values"
		| "indefinite-length string chunks not of the correct type"
		| "indefinite-length string chunks not definite length"
		| "break occurring on its own outside of an indefinite-length item"
		| "break occurring in a definite-length array or map or a tag"
		| "break in an indefinite-length map that would lead to an odd number of items (break in a value position)"
		| "major type 0, 1, 6 with additional information 31" => Refused::Syntax,
		_ => panic!("{kind}: a kind of Appendix F.1 this test does not know"),
	}
}

#[test]
fn appendix_f_is_refused_each_by_its_kind() {
	for item in items(NOT_WELL_FORMED) {
		let bytes = sample::hex_at(&item["hex"]);
		let expected = refusal(item["kind"].as_str().unwrap());
		assert_eq!(Value::decode(&bytes), Err(expected), "{}", item["hex"]);
		assert_eq!(Value::decode_deterministic(&bytes), Err(expected), "{}", item["hex"]);
	}
}

#[test]
fn a_map_is_written_in_the_bytewise_order_of_its_keys_however_it_was_given() {
	let keys: Vec<Vec<u8>> = items(SORTED_KEYS).iter().map(|k| sample::hex_at(&k["hex"])).collect();
	let mut expected = vec![0xa0 | u8::try_from(keys.len()).unwrap()];
	for key in &keys {
		expected.extend_from_slice(key);
		expected.push(0xf6);
	}
	let mut given: Vec<Value> =
		keys.iter().map(|k| Value::decode_deterministic(k).unwrap()).collect();
	given.reverse();
	for _ in 0..given.len() {
		let map = Value::Map(given.iter().map(|k| (k.clone(), Value::Null)).collect());
		assert_eq!(map.encode().unwrap(), expected);
		assert_eq!(Value::decode_deterministic(&expected).unwrap().encode().unwrap(), expected);
		given.rotate_left(1);
	}
}

#[test]
fn a_map_keeps_its_pairs_in_the_order_read() {
	let read = Value::decode(&[0xa2, 0x02, 0x00, 0x01, 0x00]).unwrap();
	assert_eq!(
		read,
		Value::Map(vec![
			(Value::Integer(2), Value::Integer(0)),
			(Value::Integer(1), Value::Integer(0))
		])
	);
	assert_eq!(read.encode().unwrap(), [0xa2, 0x01, 0x00, 0x02, 0x00]);
	assert_eq!(
		Value::decode_deterministic(&[0xa2, 0x02, 0x00, 0x01, 0x00]),
		Err(Refused::Nondeterministic)
	);
}

#[test]
fn integers_and_floats_are_kept_apart() {
	assert_eq!(Value::decode(&[0x01]), Ok(Value::Integer(1)));
	assert_eq!(Value::decode(&[0xf9, 0x3c, 0x00]), Ok(Value::Float(1.0)));
	assert_eq!(Value::Float(1.0).encode().unwrap(), [0xf9, 0x3c, 0x00]);
	assert_eq!(Value::Integer(1).encode().unwrap(), [0x01]);
}

#[test]
fn a_float_is_written_at_the_narrowest_width_that_keeps_it() {
	let cases: [(f64, &[u8]); 9] = [
		(0.0, &[0xf9, 0x00, 0x00]),
		(-0.0, &[0xf9, 0x80, 0x00]),
		(65504.0, &[0xf9, 0x7b, 0xff]),
		(65505.0, &[0xfa, 0x47, 0x7f, 0xe1, 0x00]),
		(f64::from(f32::MIN_POSITIVE) / 2.0, &[0xfa, 0x00, 0x40, 0x00, 0x00]),
		(f64::from(f32::from_bits(1)), &[0xfa, 0x00, 0x00, 0x00, 0x01]),
		(f64::from(f32::from_bits(1)) / 2.0, &[0xfb, 0x36, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
		(f64::from_bits(1), &[0xfb, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]),
		(f64::from_bits(0x7ff8_0000_0000_0001), &[0xf9, 0x7e, 0x00]),
	];
	for (x, bytes) in cases {
		assert_eq!(Value::Float(x).encode().unwrap(), bytes, "{x:e}");
		if !x.is_nan() {
			let read = Value::decode(bytes).unwrap();
			assert!(matches!(read, Value::Float(y) if y.to_bits() == x.to_bits()), "{x:e}: {read:?}");
		}
	}
	// A half's subnormal: 2^-24 and 3 * 2^-15.
	assert_eq!(Value::Float(2f64.powi(-24)).encode().unwrap(), [0xf9, 0x00, 0x01]);
	assert_eq!(Value::Float(3.0 * 2f64.powi(-16)).encode().unwrap(), [0xf9, 0x03, 0x00]);
	// A NaN but f97e00 is read, and refused as written longer than it need be.
	assert!(matches!(Value::decode(&[0xf9, 0x7e, 0x01]), Ok(Value::Float(x)) if x.is_nan()));
	assert_eq!(Value::decode_deterministic(&[0xf9, 0x7e, 0x01]), Err(Refused::Nondeterministic));
}

#[test]
fn what_cbor_cannot_write_is_out_of_range() {
	let least = -(1i128 << 64);
	assert_eq!(
		Value::Integer(least).encode().unwrap(),
		[0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]
	);
	assert_eq!(Value::Integer(least - 1).encode(), Err(Unwritable::OutOfRange));
	assert_eq!(Value::Integer(1i128 << 64).encode(), Err(Unwritable::OutOfRange));
	for n in 20..=31 {
		assert_eq!(Value::Simple(n).encode(), Err(Unwritable::OutOfRange), "simple({n})");
	}
	assert_eq!(Value::Simple(19).encode().unwrap(), [0xf3]);
	assert_eq!(Value::Simple(32).encode().unwrap(), [0xf8, 0x20]);
	let nested = Value::Array(vec![Value::Map(vec![(Value::Simple(24), Value::Null)])]);
	assert_eq!(nested.encode(), Err(Unwritable::OutOfRange));
}

#[test]
fn a_map_holding_one_key_twice_is_never_written() {
	let twice = |key: Value| Value::Map(vec![(key.clone(), Value::Null), (key, Value::Integer(1))]);
	assert_eq!(twice(Value::Integer(1)).encode(), Err(Unwritable::RepeatedKey));
	assert_eq!(twice(Value::Text("a".to_owned())).encode(), Err(Unwritable::RepeatedKey));
	// Two NaNs are both written f97e00, so are one key.
	let nans = Value::Map(vec![
		(Value::Float(f64::NAN), Value::Null),
		(Value::Float(f64::from_bits(0x7ff8_0000_0000_0001)), Value::Null),
	]);
	assert_eq!(nans.encode(), Err(Unwritable::RepeatedKey));
	assert_eq!(Value::Array(vec![twice(Value::Null)]).encode(), Err(Unwritable::RepeatedKey));
	// Zero and its negative are two floats; an integer and a float are two keys.
	let apart = Value::Map(vec![
		(Value::Float(0.0), Value::Null),
		(Value::Float(-0.0), Value::Null),
		(Value::Integer(0), Value::Null),
	]);
	assert_eq!(
		apart.encode().unwrap(),
		[0xa3, 0x00, 0xf6, 0xf9, 0x00, 0x00, 0xf6, 0xf9, 0x80, 0x00, 0xf6]
	);
}

/// `inner` within `n` arrays, maps and tags in turn, and its bytes: `[x]`, `{0: x}` and `0(x)`.
fn nested(n: usize, inner: Value) -> (Value, Vec<u8>) {
	let (mut value, mut bytes) = (inner.clone(), inner.encode().unwrap());
	for at in 0..n {
		let (wrapped, head): (Value, &[u8]) = match at % 3 {
			0 => (Value::Array(vec![value]), &[0x81]),
			1 => (Value::Map(vec![(Value::Integer(0), value)]), &[0xa1, 0x00]),
			_ => (Value::Tag(0, Box::new(value)), &[0xc0]),
		};
		value = wrapped;
		bytes = [head, &bytes].concat();
	}
	(value, bytes)
}

#[test]
fn an_item_within_128_arrays_maps_and_tags_is_read_and_written_and_within_129_refused() {
	assert_eq!(codec::DEPTH, 128);
	for inner in [Value::Integer(0), Value::Array(Vec::new()), Value::Map(Vec::new())] {
		let (within, bytes) = nested(codec::DEPTH, inner.clone());
		assert_eq!(within.encode().unwrap(), bytes);
		assert_eq!(Value::decode_deterministic(&bytes), Ok(within));
	}
	let (deeper, bytes) = nested(codec::DEPTH + 1, Value::Integer(0));
	assert_eq!(deeper.encode(), Err(Unwritable::TooDeep));
	assert_eq!(Value::decode(&bytes), Err(Refused::TooDeep));
	// A key is within its map as a value is.
	let (key, mut bytes) = nested(codec::DEPTH, Value::Integer(0));
	let keyed = Value::Map(vec![(key, Value::Null)]);
	bytes = [&[0xa1][..], &bytes, &[0xf6]].concat();
	assert_eq!(keyed.encode(), Err(Unwritable::TooDeep));
	assert_eq!(Value::decode(&bytes), Err(Refused::TooDeep));
}

#[test]
fn too_deep_is_refused_as_soon_as_it_is_met() {
	// Before the input ends, before bytes trail, and before what is not valid.
	assert_eq!(Value::decode(&[0x81; 200]), Err(Refused::TooDeep));
	assert_eq!(
		Value::decode(&[[0x81; 129].as_slice(), &[0x00, 0x00]].concat()),
		Err(Refused::TooDeep)
	);
	let invalid = [&[0x82, 0x61, 0xff][..], &[0x81; 129], &[0x00]].concat();
	assert_eq!(Value::decode(&invalid), Err(Refused::TooDeep));
	// Within 128, the input ending is what is refused.
	assert_eq!(Value::decode(&[0x81; 128]), Err(Refused::Truncated));
	// The 129th indefinite array stands within 128, and holds nothing deeper.
	let indefinite = [[0x9f; 129], [0xff; 129]].concat();
	assert!(Value::decode(&indefinite).is_ok());
	assert_eq!(Value::decode_deterministic(&indefinite), Err(Refused::Nondeterministic));
}

#[test]
fn what_is_well_formed_yet_not_valid_is_invalid() {
	// A text not UTF-8, whole or split across two chunks each not UTF-8 alone.
	assert_eq!(Value::decode(&[0x61, 0xff]), Err(Refused::Invalid));
	assert_eq!(Value::decode(&[0x7f, 0x61, 0xc3, 0x61, 0xbc, 0xff]), Err(Refused::Invalid));
	assert_eq!(Value::decode(&[0x7f, 0x62, 0xc3, 0xbc, 0xff]), Ok(Value::Text("\u{fc}".to_owned())));
	// Reading goes on past a text not UTF-8, so what follows it is read as it stands.
	assert_eq!(Value::decode(&[0x82, 0x61, 0xff, 0x00]), Err(Refused::Invalid));
	assert_eq!(Value::decode(&[0x82, 0x61, 0xff, 0x00, 0x00]), Err(Refused::Trailing));
	assert_eq!(Value::decode(&[0x82, 0x61, 0xff]), Err(Refused::Truncated));
	// A key repeated, as written or as two encodings of one value.
	assert_eq!(Value::decode(&[0xa2, 0x01, 0x00, 0x01, 0x00]), Err(Refused::Invalid));
	assert_eq!(Value::decode(&[0xa2, 0x01, 0x00, 0x18, 0x01, 0x00]), Err(Refused::Invalid));
	// An integer and a float are no repeated key.
	assert!(Value::decode(&[0xa2, 0x01, 0x00, 0xf9, 0x3c, 0x00, 0x00]).is_ok());
}

#[test]
fn not_well_formed_and_trailing_come_before_invalid() {
	// A repeated key and then the end of input inside the array holding it.
	assert_eq!(Value::decode(&[0x82, 0xa2, 0x01, 0x00, 0x01, 0x00]), Err(Refused::Truncated));
	assert_eq!(Value::decode(&[0x82, 0xa2, 0x01, 0x00, 0x01, 0x00, 0x1c]), Err(Refused::Syntax));
	assert_eq!(Value::decode(&[0xa2, 0x01, 0x00, 0x01, 0x00, 0x00]), Err(Refused::Trailing));
	assert_eq!(Value::decode(&[0x00, 0x00]), Err(Refused::Trailing));
	assert_eq!(Value::decode(&[]), Err(Refused::Truncated));
}

#[test]
fn a_head_longer_than_it_need_be_is_refused_only_strictly() {
	for bytes in
		[&[0x18, 0x17][..], &[0x19, 0x00, 0xff][..], &[0x5f, 0xff][..], &[0xd8, 0x01, 0x00][..]]
	{
		assert!(Value::decode(bytes).is_ok(), "{bytes:02x?}");
		assert_eq!(Value::decode_deterministic(bytes), Err(Refused::Nondeterministic), "{bytes:02x?}");
	}
	// A float written wider than it need be.
	assert_eq!(
		Value::decode_deterministic(&[0xfa, 0x3f, 0x80, 0x00, 0x00]),
		Err(Refused::Nondeterministic)
	);
}

#[test]
fn tags_and_simple_values_are_kept_as_written() {
	// A bignum is a tag of a byte string, whatever it holds.
	let bignum = [0xc2, 0x43, 0x00, 0x00, 0x01];
	let read = Value::decode_deterministic(&bignum).unwrap();
	assert_eq!(read, Value::Tag(2, Box::new(Value::Bytes(vec![0, 0, 1]))));
	assert_eq!(read.encode().unwrap(), bignum);
	assert_eq!(Value::decode(&[0xf8, 0xff]), Ok(Value::Simple(255)));
	assert_eq!(Value::decode(&[0xe0]), Ok(Value::Simple(0)));
	assert_eq!(Value::decode(&[0xf8, 0x20]), Ok(Value::Simple(32)));
}

#[test]
fn a_chunk_of_another_type_is_refused_by_its_first_byte() {
	// Its head cut short, or whole, the chunk's type is already wrong.
	for bytes in [&[0x5f, 0x38][..], &[0x5f, 0x3b, 0x00], &[0x7f, 0x81], &[0x5f, 0x7f]] {
		assert_eq!(Value::decode(bytes), Err(Refused::Syntax), "{bytes:02x?}");
	}
	assert_eq!(Value::decode(&[0x5f, 0x41]), Err(Refused::Truncated));
	assert_eq!(Value::decode(&[0x5f, 0x5c]), Err(Refused::Syntax));
}
