//! What the module `contracts` is written with, RFC fhg6w's subset: a record's and a union's fields,
//! an enumeration's names and codes, a set of names' bits, a list, a map and each primitive, in
//! JSON and in CBOR, each reader saying what it expected and where. A record's or a union's field
//! no reader knows is passed over, in either form; anything else not as its type writes it is
//! [`Malformed`].

mod call;
mod number;
mod text;

use std::collections::BTreeMap;

use codec::Value as Cbor;
use serde_json::{Map, Value as Json};

pub(crate) use call::{call_input, unknown_operation};
pub(crate) use number::{
	float_from_cbor, float_from_json, float_to_cbor, float_to_json, int32_from_cbor, int53_from_cbor,
	int53_from_json, int53_to_cbor, int53_to_json, uint32_from_cbor, uint32_from_json,
	uint32_to_cbor, uint32_to_json, uint53_from_cbor, uint53_from_json, uint53_to_cbor,
	uint53_to_json,
};
#[allow(
	unused_imports,
	reason = "the subset holds a signed 32-bit integer no contract has yet"
)]
pub(crate) use number::{int32_from_json, int32_to_cbor, int32_to_json};
pub(crate) use text::{
	bytes_from_cbor, bytes_from_json, bytes_to_cbor, bytes_to_json, hash_from_cbor, hash_from_json,
	hash_to_cbor, hash_to_json,
};

use crate::{Encoded, Malformed, Step};

type Read<T> = Result<T, Malformed>;

/// A CBOR map's pairs, as a record or a union is read from them.
type Pairs = [(Cbor, Cbor)];

/// The JSON read as `T` and written as its CBOR.
pub(crate) fn json_to_cbor<T: Encoded>(json: &Json) -> Read<Cbor> {
	T::from_json(json).map(|value| value.to_cbor())
}

/// The CBOR read as `T` and written as its JSON.
pub(crate) fn cbor_to_json<T: Encoded>(cbor: &Cbor) -> Read<Json> {
	T::from_cbor(cbor).map(|value| value.to_json())
}

/// What a field that is absent expects.
pub(super) const PRESENT: &str = "present";

// A record, and a union's fields beside its case.

/// A record's or a union's JSON, an object.
pub(crate) fn object_json(json: &Json) -> Read<&Map<String, Json>> {
	json.as_object().ok_or_else(|| Malformed::expected("an object"))
}

/// A record's or a union's CBOR, a map.
pub(crate) fn map_cbor(cbor: &Cbor) -> Read<&Pairs> {
	if let Cbor::Map(pairs) = cbor { Ok(pairs) } else { Err(Malformed::expected("a map")) }
}

/// The field `name`, there and as `read` reads it.
pub(crate) fn field_json<T>(
	object: &Map<String, Json>,
	name: &str,
	read: impl Fn(&Json) -> Read<T>,
) -> Read<T> {
	match object.get(name) {
		Some(value) => read(value),
		None => Err(Malformed::expected(PRESENT)),
	}
	.map_err(|m| m.within(Step::Field(name.to_owned())))
}

/// The field `name` as `read` reads it, or none where it is absent.
pub(crate) fn optional_json<T>(
	object: &Map<String, Json>,
	name: &str,
	read: impl Fn(&Json) -> Read<T>,
) -> Read<Option<T>> {
	object
		.get(name)
		.map(|value| read(value).map_err(|m| m.within(Step::Field(name.to_owned()))))
		.transpose()
}

/// The value at the integer `key`, if there is one.
pub(super) fn at(map: &Pairs, key: i128) -> Option<&Cbor> {
	map.iter().find(|(k, _)| matches!(k, Cbor::Integer(n) if *n == key)).map(|(_, value)| value)
}

/// The field `name`, at `key`, there and as `read` reads it.
pub(crate) fn field_cbor<T>(
	map: &Pairs,
	key: i128,
	name: &str,
	read: impl Fn(&Cbor) -> Read<T>,
) -> Read<T> {
	match at(map, key) {
		Some(value) => read(value),
		None => Err(Malformed::expected(PRESENT)),
	}
	.map_err(|m| m.within(Step::Field(name.to_owned())))
}

/// The field `name`, at `key`, as `read` reads it, or none where it is absent.
pub(crate) fn optional_cbor<T>(
	map: &Pairs,
	key: i128,
	name: &str,
	read: impl Fn(&Cbor) -> Read<T>,
) -> Read<Option<T>> {
	at(map, key)
		.map(|value| read(value).map_err(|m| m.within(Step::Field(name.to_owned()))))
		.transpose()
}

/// A record's JSON, each field by its name, one with nothing to say left out.
pub(crate) fn record_json(fields: impl IntoIterator<Item = (&'static str, Option<Json>)>) -> Json {
	Json::Object(
		fields.into_iter().filter_map(|(name, value)| value.map(|v| (name.to_owned(), v))).collect(),
	)
}

/// A record's CBOR, each field at its key, one with nothing to say left out.
pub(crate) fn record_cbor(fields: impl IntoIterator<Item = (i128, Option<Cbor>)>) -> Cbor {
	Cbor::Map(
		fields.into_iter().filter_map(|(key, value)| value.map(|v| (Cbor::Integer(key), v))).collect(),
	)
}

/// A union's JSON: its case's name in the field `tag`, beside the case's fields.
pub(crate) fn union_json(
	tag: &'static str,
	case: &'static str,
	fields: impl IntoIterator<Item = (&'static str, Option<Json>)>,
) -> Json {
	record_json(std::iter::once((tag, Some(Json::from(case)))).chain(fields))
}

/// A union's CBOR: its case's code at key 0, beside the case's fields.
pub(crate) fn union_cbor(
	code: i128,
	fields: impl IntoIterator<Item = (i128, Option<Cbor>)>,
) -> Cbor {
	record_cbor(std::iter::once((0, Some(Cbor::Integer(code)))).chain(fields))
}

/// A union's case, its name in the field `tag`, read as any field is: a name no case has is the
/// caller's to refuse, by [`unknown_case`].
pub(crate) fn case_json<'a>(object: &'a Map<String, Json>, tag: &str) -> Read<&'a str> {
	match object.get(tag) {
		Some(value) => value.as_str().ok_or_else(|| Malformed::expected("a string")),
		None => Err(Malformed::expected(PRESENT)),
	}
	.map_err(|m| m.within(Step::Field(tag.to_owned())))
}

/// A union's case, its code at key 0, read as a signed 32-bit integer.
pub(crate) fn case_cbor(map: &Pairs, tag: &str) -> Read<i128> {
	field_cbor(map, 0, tag, int32_from_cbor).map(i128::from)
}

/// A union's case that is none of its cases, at its field `tag`.
pub(crate) fn unknown_case(tag: &str, expected: &str) -> Malformed {
	Malformed::expected(expected).within(Step::Field(tag.to_owned()))
}

// An enumeration, and a set of names.

/// An enumeration's JSON, its choice's name.
pub(crate) fn name_to_json(name: &'static str) -> Json {
	Json::from(name)
}

/// An enumeration's name, `expected` naming every choice.
pub(crate) fn name_from_json<'a>(json: &'a Json, expected: &str) -> Read<&'a str> {
	json.as_str().ok_or_else(|| unexpected(expected))
}

/// An enumeration's CBOR, its choice's code.
pub(crate) fn code_to_cbor(code: i128) -> Cbor {
	Cbor::Integer(code)
}

/// An enumeration's code, `expected` naming every code.
pub(crate) fn code_from_cbor(cbor: &Cbor, expected: &str) -> Read<i128> {
	if let Cbor::Integer(code) = cbor { Ok(*code) } else { Err(unexpected(expected)) }
}

/// A choice that is none of its enumeration's.
pub(crate) fn unexpected(expected: &str) -> Malformed {
	Malformed::expected(expected)
}

/// A set of names' bits, as its CBOR's reader expects them.
fn bits_expected(names: &[(&str, u32)]) -> String {
	let bits: Vec<String> = names.iter().map(|(_, bit)| bit.to_string()).collect();
	format!("an integer of the bits {}", bits.join(", "))
}

/// A set of names' JSON, the names of its bits set, in the order of their bits.
pub(crate) fn flags_to_json(bits: u32, names: &[(&str, u32)]) -> Json {
	Json::Array(
		names.iter().filter(|(_, bit)| bits & bit != 0).map(|(name, _)| Json::from(*name)).collect(),
	)
}

/// A set of names' bits, from the names set, each once.
pub(crate) fn flags_from_json(json: &Json, names: &[(&str, u32)]) -> Read<u32> {
	let all: Vec<&str> = names.iter().map(|(name, _)| *name).collect();
	let expected = || format!("one of {}", all.join(", "));
	let items = json.as_array().ok_or_else(|| Malformed::expected("an array"))?;
	items.iter().enumerate().try_fold(0, |bits, (i, item)| {
		item
			.as_str()
			.and_then(|name| names.iter().find(|(n, _)| *n == name))
			.map(|(_, bit)| *bit)
			.filter(|bit| bits & bit == 0)
			.map(|bit| bits | bit)
			.ok_or_else(|| Malformed::expected(expected()).within(Step::Index(i)))
	})
}

/// A set of names' bits, from the integer of them, no bit but its names' set.
pub(crate) fn flags_from_cbor(cbor: &Cbor, names: &[(&str, u32)]) -> Read<u32> {
	let all = names.iter().fold(0, |all, (_, bit)| all | bit);
	match cbor {
		Cbor::Integer(n) => u32::try_from(*n).ok().filter(|bits| bits & !all == 0),
		Cbor::Bytes(_)
		| Cbor::Text(_)
		| Cbor::Array(_)
		| Cbor::Map(_)
		| Cbor::Tag(..)
		| Cbor::Bool(_)
		| Cbor::Null
		| Cbor::Undefined
		| Cbor::Simple(_)
		| Cbor::Float(_) => None,
	}
	.ok_or_else(|| Malformed::expected(bits_expected(names)))
}

// A list and a map.

/// A list's JSON, an array.
pub(crate) fn list_to_json<T>(items: &[T], write: impl Fn(&T) -> Json) -> Json {
	Json::Array(items.iter().map(write).collect())
}

/// A list, each item as `read` reads it.
pub(crate) fn list_from_json<T>(json: &Json, read: impl Fn(&Json) -> Read<T>) -> Read<Vec<T>> {
	let items = json.as_array().ok_or_else(|| Malformed::expected("an array"))?;
	items
		.iter()
		.enumerate()
		.map(|(i, item)| read(item).map_err(|m| m.within(Step::Index(i))))
		.collect()
}

/// A list's CBOR, an array.
pub(crate) fn list_to_cbor<T>(items: &[T], write: impl Fn(&T) -> Cbor) -> Cbor {
	Cbor::Array(items.iter().map(write).collect())
}

/// A list, each item as `read` reads it.
pub(crate) fn list_from_cbor<T>(cbor: &Cbor, read: impl Fn(&Cbor) -> Read<T>) -> Read<Vec<T>> {
	let Cbor::Array(items) = cbor else {
		return Err(Malformed::expected("an array"));
	};
	items
		.iter()
		.enumerate()
		.map(|(i, item)| read(item).map_err(|m| m.within(Step::Index(i))))
		.collect()
}

/// A map's JSON, an object.
pub(crate) fn map_to_json<T>(entries: &BTreeMap<String, T>, write: impl Fn(&T) -> Json) -> Json {
	Json::Object(entries.iter().map(|(key, value)| (key.clone(), write(value))).collect())
}

/// A map, each entry as `read` reads it.
pub(crate) fn map_from_json<T>(
	json: &Json,
	read: impl Fn(&Json) -> Read<T>,
) -> Read<BTreeMap<String, T>> {
	let entries = json.as_object().ok_or_else(|| Malformed::expected("an object"))?;
	entries
		.iter()
		.map(|(key, value)| {
			Ok((key.clone(), read(value).map_err(|m| m.within(Step::Key(key.clone())))?))
		})
		.collect()
}

/// A map's CBOR, keyed by text.
pub(crate) fn map_to_cbor<T>(entries: &BTreeMap<String, T>, write: impl Fn(&T) -> Cbor) -> Cbor {
	Cbor::Map(entries.iter().map(|(key, value)| (Cbor::Text(key.clone()), write(value))).collect())
}

/// A map keyed by text, each entry as `read` reads it.
pub(crate) fn map_from_cbor<T>(
	cbor: &Cbor,
	read: impl Fn(&Cbor) -> Read<T>,
) -> Read<BTreeMap<String, T>> {
	let Cbor::Map(pairs) = cbor else {
		return Err(Malformed::expected("a map"));
	};
	pairs
		.iter()
		.map(|(key, value)| {
			let Cbor::Text(key) = key else {
				return Err(Malformed::expected("a map keyed by text"));
			};
			Ok((key.clone(), read(value).map_err(|m| m.within(Step::Key(key.clone())))?))
		})
		.collect()
}

// A boolean and a string.

/// A boolean's JSON.
pub(crate) fn bool_to_json(value: &bool) -> Json {
	Json::Bool(*value)
}

/// A boolean.
pub(crate) fn bool_from_json(json: &Json) -> Read<bool> {
	json.as_bool().ok_or_else(|| Malformed::expected("a boolean"))
}

/// A boolean's CBOR.
pub(crate) fn bool_to_cbor(value: &bool) -> Cbor {
	Cbor::Bool(*value)
}

/// A boolean.
pub(crate) fn bool_from_cbor(cbor: &Cbor) -> Read<bool> {
	if let Cbor::Bool(value) = cbor { Ok(*value) } else { Err(Malformed::expected("a boolean")) }
}

/// A string's JSON.
pub(crate) fn string_to_json(value: &impl AsRef<str>) -> Json {
	Json::from(value.as_ref())
}

/// A string.
pub(crate) fn string_from_json(json: &Json) -> Read<String> {
	json.as_str().map(str::to_owned).ok_or_else(|| Malformed::expected("a string"))
}

/// A string's CBOR, a text string.
pub(crate) fn string_to_cbor(value: &impl AsRef<str>) -> Cbor {
	Cbor::Text(value.as_ref().to_owned())
}

/// A string, from a text string.
pub(crate) fn string_from_cbor(cbor: &Cbor) -> Read<String> {
	if let Cbor::Text(value) = cbor {
		Ok(value.clone())
	} else {
		Err(Malformed::expected("a text string"))
	}
}
