//! The module `contracts` held to what the samples of `tests/codec/` leave out: a field no reader
//! knows passed over, where a value is not as its type writes it and what was expected there, the
//! one text of bytes and of a hash, each shape's bounds, and the names an interface and the
//! reasons are written under.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

use std::collections::BTreeMap;

use codec::{Cbor, Value};
use envelope::contracts::{
	self, AppBindings, AppEnv, Availability, Content, DatabaseValue, Failure, FileEntry, ObjectRange,
	ObjectRead, ObjectWrite, Rights, Shell, interface,
};
use envelope::{Bounded, Called, Encoded, Envelope, Int53, Malformed, Operation, Step, Uint53};
use serde_json::json;

fn uint53(n: u64) -> Uint53 {
	Uint53::new(n).unwrap()
}

fn malformed(at: Vec<Step>, expected: &str) -> Malformed {
	Malformed { at, expected: expected.to_owned() }
}

fn field(name: &str) -> Step {
	Step::Field(name.to_owned())
}

/// A CBOR map of integer keys.
fn map(pairs: Vec<(i128, Value)>) -> Value {
	Value::Map(pairs.into_iter().map(|(k, v)| (Value::Integer(k), v)).collect())
}

#[test]
fn a_field_no_reader_knows_is_passed_over_in_either_form() {
	let range = ObjectRange { start: uint53(1), length: uint53(3) };
	let json = json!({ "start": 1, "length": 3, "end": 4, "also": { "nested": [] } });
	assert_eq!(ObjectRange::from_json(&json), Ok(range.clone()));
	let cbor =
		map(vec![(1, Value::Integer(1)), (2, Value::Integer(3)), (9, Value::Text("x".into()))]);
	assert_eq!(ObjectRange::from_cbor(&cbor), Ok(range.clone()));
	let Value::Map(mut pairs) = cbor else { unreachable!() };
	pairs.push((Value::Text("start".into()), Value::Bool(true)));
	assert_eq!(ObjectRange::from_cbor(&Value::Map(pairs)), Ok(range));
}

#[test]
fn a_field_absent_is_none_and_never_written() {
	let read = ObjectRead { name: "a".into(), range: None };
	assert_eq!(read.to_json(), json!({ "name": "a" }));
	assert_eq!(read.to_cbor().encode().unwrap(), [0xa1, 0x01, 0x61, b'a']);
	assert_eq!(ObjectRead::from_json(&json!({ "name": "a" })), Ok(read));
}

#[test]
fn a_field_missing_says_what_it_expected_there() {
	let write = ObjectWrite::from_json(&json!({ "name": "a" }));
	assert_eq!(write, Err(malformed(vec![field("content")], "present")));
	let write = ObjectWrite::from_cbor(&map(vec![(2, Value::Bytes(vec![]))]));
	assert_eq!(write, Err(malformed(vec![field("name")], "present")));
}

#[test]
fn null_is_no_value_of_any_shape_even_for_a_field_that_may_be_absent() {
	let read = ObjectRead::from_json(&json!({ "name": "a", "range": null }));
	assert_eq!(read, Err(malformed(vec![field("range")], "an object")));
	let read = ObjectRead::from_cbor(&map(vec![(1, Value::Text("a".into())), (2, Value::Null)]));
	assert_eq!(read, Err(malformed(vec![field("range")], "a map")));
}

#[test]
fn where_a_value_is_wrong_is_every_step_into_it() {
	let read = ObjectRead::from_json(&json!({ "name": "a", "range": { "start": -1, "length": 3 } }));
	assert_eq!(
		read,
		Err(malformed(vec![field("range"), field("start")], "an integer of 0 to 2^53 - 1"))
	);
	let zero = "0".repeat(64);
	let content = Content::from_json(&json!({ "hash": zero, "pieces": [zero, "00"] }));
	assert_eq!(
		content,
		Err(malformed(vec![field("pieces"), Step::Index(1)], "64 lowercase hex digits"))
	);
	let bindings = AppBindings::from_json(&json!({ "app": { "a": 1, "b": "2" } }));
	assert_eq!(
		bindings,
		Err(malformed(vec![field("app"), Step::Key("b".into())], "an integer of 0 to 2^32 - 1"))
	);
}

#[test]
fn bytes_are_base64url_unpadded_with_their_unused_bits_zero_and_nothing_else() {
	let cases: [(&[u8], &str); 6] = [
		(b"", ""),
		(b"\xff", "_w"),
		(b"\xfb\xff", "-_8"),
		(b"hel", "aGVs"),
		(b"hell", "aGVsbA"),
		(b"hello", "aGVsbG8"),
	];
	for (bytes, text) in cases {
		let write = ObjectWrite { name: "a".into(), content: bytes.to_vec() };
		assert_eq!(write.to_json(), json!({ "name": "a", "content": text }));
		assert_eq!(ObjectWrite::from_json(&json!({ "name": "a", "content": text })), Ok(write));
	}
	for text in
		["aGVsbG8=", "aGVsbA==", "aGVsbG9", "aGVsbB", "a", "aGV+bG8", "aGV/bG8", "aGVs bG8", "_x"]
	{
		let read = ObjectWrite::from_json(&json!({ "name": "a", "content": text }));
		assert_eq!(read, Err(malformed(vec![field("content")], "base64url, unpadded")), "{text}");
	}
	let read = ObjectWrite::from_cbor(&map(vec![
		(1, Value::Text("a".into())),
		(2, Value::Text("aGVsbG8".into())),
	]));
	assert_eq!(read, Err(malformed(vec![field("content")], "a byte string")));
}

#[test]
fn a_hash_is_64_lowercase_hex_digits_in_json_and_32_bytes_in_cbor() {
	let mut hash = [0; 32];
	hash[0] = 0xab;
	hash[31] = 0x01;
	let text = format!("ab{}01", "0".repeat(60));
	let content = Content { description: None, hash, pieces: vec![] };
	assert_eq!(content.to_json(), json!({ "hash": text, "pieces": [] }));
	assert_eq!(Content::from_json(&json!({ "hash": text, "pieces": [] })), Ok(content.clone()));
	assert_eq!(Content::from_cbor(&content.to_cbor()), Ok(content));
	for wrong in
		[text.to_uppercase(), text[..62].to_owned(), format!("{text}00"), format!("zz{}", &text[2..])]
	{
		let read = Content::from_json(&json!({ "hash": wrong, "pieces": [] }));
		assert_eq!(read, Err(malformed(vec![field("hash")], "64 lowercase hex digits")), "{wrong}");
	}
	let short = map(vec![(1, Value::Bytes(vec![0; 31])), (2, Value::Array(vec![]))]);
	assert_eq!(Content::from_cbor(&short), Err(malformed(vec![field("hash")], "32 bytes")));
}

#[test]
fn an_integer_is_read_by_its_value_within_its_bounds() {
	assert_eq!(Uint53::new((1 << 53) - 1).map(Uint53::get), Some((1 << 53) - 1));
	assert_eq!(Uint53::new(1 << 53), None);
	assert_eq!(Int53::new(-(1 << 53) + 1).map(Int53::get), Some(-(1 << 53) + 1));
	assert_eq!(Int53::new(1 << 53), None);
	assert_eq!(Int53::new(-(1 << 53)), None);
	let number = |text: &str| -> serde_json::Value { serde_json::from_str(text).unwrap() };
	for (text, value) in
		[("5.0", 5), ("1e2", 100), ("-0.0", 0), ("9007199254740991.0", (1 << 53) - 1)]
	{
		let read = ObjectRange::from_json(&json!({ "start": number(text), "length": 1 }));
		assert_eq!(read, Ok(ObjectRange { start: uint53(value), length: uint53(1) }), "{text}");
		assert_eq!(read.unwrap().to_json(), json!({ "start": value, "length": 1 }), "{text}");
	}
	let int53 =
		|text: &str| DatabaseValue::from_json(&json!({ "kind": "integer", "value": number(text) }));
	assert_eq!(int53("-1e2"), Ok(DatabaseValue::Integer { value: Int53::new(-100).unwrap() }));
	assert_eq!(
		int53("-9007199254740991.0"),
		Ok(DatabaseValue::Integer { value: Int53::new(-(1 << 53) + 1).unwrap() })
	);
	assert!(int53("-9007199254740992.0").is_err());
	assert!(int53("1e300").is_err());
	let wrong = ["5.5", "0.5", "-1.0", "9007199254740992.0", "9007199254740992", "1e16", "\"1\""];
	for wrong in wrong.map(number) {
		let read = ObjectRange::from_json(&json!({ "start": wrong, "length": 1 }));
		assert_eq!(
			read,
			Err(malformed(vec![field("start")], "an integer of 0 to 2^53 - 1")),
			"{wrong}"
		);
	}
	let float = map(vec![(1, Value::Float(1.0)), (2, Value::Integer(1))]);
	assert_eq!(
		ObjectRange::from_cbor(&float),
		Err(malformed(vec![field("start")], "an integer of 0 to 2^53 - 1"))
	);
	let beyond = map(vec![(1, Value::Integer(1 << 53)), (2, Value::Integer(1))]);
	assert!(ObjectRange::from_cbor(&beyond).is_err());
}

#[test]
fn a_float_is_a_float_in_cbor_and_any_number_in_json() {
	let real = DatabaseValue::Real { value: 1.5 };
	assert_eq!(real.to_cbor().encode().unwrap(), hex_of("a2000301f93e00"));
	assert_eq!(
		DatabaseValue::from_json(&json!({ "kind": "real", "value": 2 })),
		Ok(DatabaseValue::Real { value: 2.0 })
	);
	let integer = map(vec![(0, Value::Integer(3)), (1, Value::Integer(2))]);
	assert_eq!(
		DatabaseValue::from_cbor(&integer),
		Err(malformed(vec![field("value")], "a finite float"))
	);
	for wrong in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
		let real = map(vec![(0, Value::Integer(3)), (1, Value::Float(wrong))]);
		assert_eq!(
			DatabaseValue::from_cbor(&real),
			Err(malformed(vec![field("value")], "a finite float"))
		);
	}
}

fn hex_of(text: &str) -> Vec<u8> {
	(0..text.len()).step_by(2).map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap()).collect()
}

#[test]
fn a_union_is_its_case_at_its_tag_and_at_key_0() {
	let entry = FileEntry::Directory { name: "d".into(), size: uint53(0), count: uint53(2) };
	assert_eq!(entry.to_json(), json!({ "type": "directory", "name": "d", "size": 0, "count": 2 }));
	assert_eq!(FileEntry::from_cbor(&entry.to_cbor()), Ok(entry));
	let expected = "one of null, integer, real, text, bytes";
	assert_eq!(
		DatabaseValue::from_json(&json!({ "kind": "decimal" })),
		Err(malformed(vec![field("kind")], expected))
	);
	// The tag is read as any field is; only a name or a code no case has is "one of".
	let kind = |expected: &str| Err(malformed(vec![field("kind")], expected));
	assert_eq!(DatabaseValue::from_json(&json!({ "value": 1 })), kind("present"));
	assert_eq!(DatabaseValue::from_json(&json!({ "kind": 2 })), kind("a string"));
	let codes = "one of 1, 2, 3, 4, 5";
	assert_eq!(DatabaseValue::from_cbor(&map(vec![(0, Value::Integer(6))])), kind(codes));
	assert_eq!(DatabaseValue::from_cbor(&map(vec![])), kind("present"));
	let int32 = "an integer of -2^31 to 2^31 - 1";
	assert_eq!(DatabaseValue::from_cbor(&map(vec![(0, Value::Text("null".into()))])), kind(int32));
	assert_eq!(DatabaseValue::from_cbor(&map(vec![(0, Value::Integer(1 << 31))])), kind(int32));
	let secret = AppEnv::Secret { sealed: vec![1, 2] };
	assert_eq!(secret.to_json(), json!({ "name": "secret", "sealed": "AQI" }));
}

#[test]
fn an_enumeration_is_its_name_in_json_and_its_code_in_cbor() {
	assert_eq!(Availability::BestEffort.to_json(), json!("best_effort"));
	assert_eq!(Availability::BestEffort.to_cbor(), Value::Integer(2));
	assert_eq!(Availability::from_cbor(&Value::Integer(6)), Ok(Availability::Multiregion));
	assert!(Availability::from_json(&json!("BestEffort")).is_err());
	assert!(Availability::from_cbor(&Value::Integer(0)).is_err());
	assert!(Availability::Opportunistic < Availability::Multiregion);
}

#[test]
fn a_set_of_names_is_its_bits_in_cbor_and_no_bit_but_its_names() {
	let rights = Rights(Rights::READ | Rights::CALL);
	assert_eq!(rights.to_json(), json!(["read", "call"]));
	assert_eq!(Rights::from_json(&json!(["call", "read"])), Ok(rights));
	assert_eq!(Rights::from_cbor(&Value::Integer(33)), Ok(rights));
	let bits = Err(malformed(vec![], "an integer of the bits 1, 2, 4, 8, 16, 32"));
	assert_eq!(Rights::from_cbor(&Value::Integer(64)), bits);
	assert_eq!(Rights::from_cbor(&Value::Integer(-1)), bits);
	assert_eq!(Rights::from_cbor(&Value::Text("read".into())), bits);
	let names = "one of read, create, replace, delete, alter, call";
	assert_eq!(
		Rights::from_json(&json!(["read", "read"])),
		Err(malformed(vec![Step::Index(1)], names))
	);
	assert_eq!(Rights::from_json(&json!(["own"])), Err(malformed(vec![Step::Index(0)], names)));
	assert_eq!(Rights::from_json(&json!(3)), Err(malformed(vec![], "an array")));
}

#[test]
fn a_map_is_keyed_by_text() {
	let bindings =
		AppBindings { app: Some(BTreeMap::from([("a".to_owned(), 7)])), database: None, bucket: None };
	assert_eq!(bindings.to_json(), json!({ "app": { "a": 7 } }));
	assert_eq!(AppBindings::from_cbor(&bindings.to_cbor()), Ok(bindings));
	let keyed = map(vec![(1, Value::Map(vec![(Value::Integer(1), Value::Integer(7))]))]);
	assert_eq!(
		AppBindings::from_cbor(&keyed),
		Err(malformed(vec![field("app")], "a map keyed by text"))
	);
	let unmapped = map(vec![(1, Value::Array(vec![]))]);
	assert_eq!(AppBindings::from_cbor(&unmapped), Err(malformed(vec![field("app")], "a map")));
}

#[test]
fn the_shell_is_every_record_s_row() {
	let shell = Shell {
		kind: "bucket".into(),
		id: 1,
		generation: uint53(2),
		version: 1,
		content: Some(vec![0xa0]),
	};
	assert_eq!(
		shell.to_json(),
		json!({ "kind": "bucket", "id": 1, "generation": 2, "version": 1, "content": "oA" })
	);
	assert_eq!(Shell::from_json(&shell.to_json()), Ok(shell.clone()));
	assert_eq!(Shell::from_cbor(&shell.to_cbor()), Ok(shell));
}

/// An operation's input and output, by their names in `contracts`.
fn names<O: Operation>() -> (String, String) {
	let short = |t: &str| t.rsplit("::").next().unwrap().to_owned();
	(short(std::any::type_name::<O::Input>()), short(std::any::type_name::<O::Output>()))
}

#[test]
fn an_operation_is_named_as_its_interface_names_it() {
	assert_eq!(interface::object::VERSION, 1);
	assert_eq!(interface::object::Write::INTERFACE, "object");
	assert_eq!(interface::object::Write::VERSION, interface::object::VERSION);
	assert_eq!(interface::object::Write::NAME, "write");
	assert_eq!(
		names::<interface::object::Write>(),
		("ObjectWrite".to_owned(), "ObjectWritten".to_owned())
	);
	let reasons: Vec<_> =
		interface::object::Write::REASONS.iter().map(|r| (r.name, r.failure)).collect();
	assert_eq!(reasons, [("too_large", Failure::Rejected), ("storage_full", Failure::Unavailable)]);
	assert!(interface::object::Describe::REASONS.is_empty());
	assert_eq!(interface::storage::FileWrite::NAME, "file_write");
	assert_eq!(interface::database::Execute::VERSION, 3);
}

#[test]
fn the_reasons_every_operation_and_every_call_may_fail_for() {
	let every: Vec<_> = contracts::REASONS.iter().map(|r| (r.name, r.failure)).collect();
	assert_eq!(
		every,
		[
			("denied", Failure::Rejected),
			("malformed", Failure::Rejected),
			("overloaded", Failure::Unavailable),
			("rate_limited", Failure::Unavailable),
			("fault", Failure::Unknown)
		]
	);
	let calling: Vec<_> = contracts::CALLING.iter().map(|r| (r.name, r.failure)).collect();
	assert_eq!(calling, [("stopped", Failure::Unavailable)]);
}

#[test]
fn a_name_no_type_has_is_none() {
	assert_eq!(contracts::json_to_cbor("no-such-type", &json!({})), None);
	assert_eq!(contracts::cbor_to_json("no-such-type", &Value::Map(vec![])), None);
	assert_eq!(contracts::json_to_cbor("shell", &json!({})), None);
}

type ObjectCall = Envelope<interface::object::Call>;

fn write() -> interface::object::Call {
	interface::object::Call::Write(ObjectWrite { name: "a".into(), content: b"hello".to_vec() })
}

#[test]
fn a_call_is_its_operation_holding_its_input() {
	let call = write();
	assert_eq!(<interface::object::Call as Called>::INTERFACE, "object");
	assert_eq!(call.operation(), "write");
	assert_eq!(call.input_json(), json!({ "name": "a", "content": "aGVsbG8" }));
	let read = <interface::object::Call as Called>::from_json("write", &call.input_json());
	assert_eq!(read, Ok(call.clone()));
	assert_eq!(<interface::object::Call as Called>::from_cbor("write", &call.input_cbor()), Ok(call));
	let name = json!({ "name": "a" });
	let describe = <interface::object::Call as Called>::from_json("describe", &name);
	let delete = <interface::object::Call as Called>::from_json("delete", &name);
	assert!(matches!(describe, Ok(interface::object::Call::Describe(_))), "{describe:?}");
	assert!(matches!(delete, Ok(interface::object::Call::Delete(_))), "{delete:?}");
}

#[test]
fn a_call_carries_its_capabilities_absent_when_none() {
	let none = ObjectCall { call: write(), capabilities: vec![] };
	let json = json!({ "interface": "object", "operation": "write", "input": { "name": "a", "content": "aGVsbG8" } });
	assert_eq!(none.to_json(), json);
	assert_eq!(ObjectCall::from_cbor(&none.to_cbor()), Ok(none.clone()));
	let mut empty = json.clone();
	empty["capabilities"] = json!([]);
	assert_eq!(ObjectCall::from_json(&empty), Ok(none));
	let some = ObjectCall { call: write(), capabilities: vec![vec![1, 2, 3], vec![]] };
	assert_eq!(some.to_json()["capabilities"], json!(["AQID", ""]));
	assert_eq!(ObjectCall::from_json(&some.to_json()), Ok(some.clone()));
	assert_eq!(ObjectCall::from_cbor(&some.to_cbor()), Ok(some));
	let mut wrong = json;
	wrong["capabilities"] = json!(["AQID", "AQID="]);
	assert_eq!(
		ObjectCall::from_json(&wrong),
		Err(malformed(vec![field("capabilities"), Step::Index(1)], "base64url, unpadded"))
	);
}

#[test]
fn a_call_not_as_its_interface_writes_it_says_where() {
	let input = json!({ "name": "a", "content": "aGVsbG8" });
	let call =
		|interface: serde_json::Value, operation: serde_json::Value, input: serde_json::Value| {
			let mut call = json!({ "interface": interface, "operation": operation, "input": input });
			for key in ["interface", "operation", "input"] {
				if call[key].is_null() {
					call.as_object_mut().unwrap().remove(key);
				}
			}
			ObjectCall::from_json(&call)
		};
	let operations = "one of write, read, describe, delete, list";
	let cases = [
		(
			call(json!("database"), json!("write"), input.clone()),
			vec![field("interface")],
			"one of object",
		),
		(call(json!(null), json!("write"), input.clone()), vec![field("interface")], "present"),
		(call(json!(1), json!("write"), input.clone()), vec![field("interface")], "a string"),
		(call(json!("object"), json!("fly"), input.clone()), vec![field("operation")], operations),
		(call(json!("object"), json!(null), input.clone()), vec![field("operation")], "present"),
		(call(json!("object"), json!("write"), json!(null)), vec![field("input")], "present"),
		(call(json!("object"), json!("fly"), json!(null)), vec![field("operation")], operations),
		(
			call(json!("object"), json!("write"), json!({ "name": "a", "content": "aGVsbG8=" })),
			vec![field("input"), field("content")],
			"base64url, unpadded",
		),
	];
	for (read, at, expected) in cases {
		assert_eq!(read, Err(malformed(at, expected)));
	}
	let text = |s: &str| Value::Text(s.into());
	let input = write().input_cbor();
	let cbor = |pairs| ObjectCall::from_cbor(&map(pairs));
	assert_eq!(
		cbor(vec![(1, text("database")), (2, text("write")), (3, input.clone())]),
		Err(malformed(vec![field("interface")], "one of object"))
	);
	assert_eq!(
		cbor(vec![(1, Value::Integer(1)), (2, text("write")), (3, input.clone())]),
		Err(malformed(vec![field("interface")], "a text string"))
	);
	assert_eq!(
		cbor(vec![(1, text("object")), (2, Value::Integer(1)), (3, input.clone())]),
		Err(malformed(vec![field("operation")], "a text string"))
	);
	assert_eq!(
		cbor(vec![(1, text("object")), (2, text("fly")), (3, input.clone())]),
		Err(malformed(vec![field("operation")], operations))
	);
	assert_eq!(
		cbor(vec![(1, text("object")), (2, text("write"))]),
		Err(malformed(vec![field("input")], "present"))
	);
	assert_eq!(
		cbor(vec![(1, text("object")), (2, text("fly"))]),
		Err(malformed(vec![field("operation")], operations))
	);
	assert_eq!(
		cbor(vec![
			(1, text("object")),
			(2, text("write")),
			(3, input),
			(4, Value::Array(vec![text("x")]))
		]),
		Err(malformed(vec![field("capabilities"), Step::Index(0)], "a byte string"))
	);
}

#[test]
fn a_name_no_interface_has_is_none() {
	assert_eq!(contracts::call_json_to_cbor("no-such-interface", &json!({})), None);
	assert_eq!(contracts::call_cbor_to_json("no-such-interface", &Value::Map(vec![])), None);
	assert_eq!(contracts::call_json_to_cbor("object-write", &json!({})), None);
}
