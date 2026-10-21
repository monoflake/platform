//! [`Generate`] held to `model/contracts.json` as it stands, written the same for the same
//! contracts byte for byte, and to each way contracts may not be written in Rust, refused where
//! it is with what was expected there.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

use envelope_generator::{Contracts, Generate, Unread};
use serde_json::{Value, json};

const CONTRACTS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../model/contracts.json");

/// The least contracts that are written: a shell, the type `failure`, one record and one
/// interface.
fn least() -> Value {
	json!({
		"version": 1,
		"shell": [{ "name": "kind", "key": 1, "shape": { "prim": "string" } }],
		"call": {
			"fields": [
				{ "name": "interface", "key": 1, "shape": { "prim": "string" } },
				{ "name": "operation", "key": 2, "shape": { "prim": "string" } },
				{ "name": "input", "key": 3, "shape": { "input": "operation" } },
				{ "name": "capabilities", "key": 4, "shape": { "list": { "prim": "bytes" } }, "optional": true }
			],
			"typ": "monoflake:call:1"
		},
		"types": {
			"failure": { "enum": [{ "name": "rejected", "code": 1 }], "ordered": false },
			"thing": { "record": [{ "name": "type", "key": 1, "shape": { "prim": "bool" } }] }
		},
		"reasons": [{ "name": "denied", "failure": "rejected" }],
		"calling": [],
		"interfaces": {
			"things": {
				"version": 1,
				"operations": [{ "name": "get", "input": "thing", "output": "thing", "reasons": [] }]
			}
		}
	})
}

fn written(contracts: &Value) -> Result<String, Unread> {
	Contracts::read(&contracts.to_string()).and_then(|c| c.rust())
}

#[test]
fn the_contracts_are_written_the_same_byte_for_byte() {
	let text = std::fs::read_to_string(CONTRACTS).unwrap();
	let once = Contracts::read(&text).unwrap().rust().unwrap();
	let again = Contracts::read(&text).unwrap();
	assert_eq!(again.rust().unwrap(), once);
	assert_eq!(again.rust().unwrap(), once);
	for item in [
		"pub struct Bucket {",
		"pub r#type: BucketType,",
		"impl Encoded for BucketKind {",
		"pub enum Failure {",
		"pub struct Rights(",
		"pub const READ: u32 = 1;",
		"pub struct Shell {",
		"pub const REASONS: &[Reason]",
		"pub const CALLING: &[Reason]",
		"pub mod interface {",
		"pub mod object {",
		"impl Operation for Write {",
		"pub enum Call {",
		"Write(crate::contracts::ObjectWrite),",
		"impl Called for Call {",
		"pub fn call_json_to_cbor(",
		"pub fn call_cbor_to_json(",
		"pub fn json_to_cbor(",
		"pub fn cbor_to_json(",
	] {
		assert!(once.contains(item), "{item}: not written");
	}
}

#[test]
fn the_least_contracts_import_only_what_they_use() {
	let rust = written(&least()).unwrap();
	assert!(rust.contains("use crate::{Encoded, Envelope, Malformed, Reason, wire};"), "{rust}");
	assert!(!rust.contains("BTreeMap"), "{rust}");
	assert!(rust.contains("pub r#type: bool,"), "{rust}");
	assert!(rust.contains("pub mod things {"), "{rust}");
	assert!(rust.contains("impl Operation for Get {"), "{rust}");
}

#[test]
fn text_that_is_no_json_is_unread_at_the_top() {
	let unread = Contracts::read("{").unwrap_err();
	assert_eq!(unread.at, "");
	assert!(unread.expected.starts_with("JSON"), "{unread:?}");
}

/// The least contracts with `value` set at `pointer`, and where and what they are refused for.
fn refused(pointer: &str, value: Value) -> Unread {
	let mut contracts = least();
	*contracts
		.pointer_mut(pointer)
		.unwrap_or_else(|| panic!("{pointer}: not in the least contracts")) = value;
	written(&contracts).expect_err(pointer)
}

#[test]
fn each_way_contracts_cannot_be_written_is_refused_where_it_is() {
	let thing = json!({ "name": "type", "key": 1, "shape": { "prim": "bool" } });
	let cases = [
		(
			"/types/thing/record/0/shape",
			json!({ "type": "nothing" }),
			"types/thing/record/0/shape/type",
		),
		("/types/thing/record/0/shape", json!({ "prim": "int64" }), "types/thing/record/0/shape/prim"),
		("/types/thing/record/0/name", json!("Type"), "types/thing/record/0/name"),
		("/types/thing/record/0/name", json!("self"), "types/thing/record/0/name"),
		("/types/thing/record", json!([thing, thing]), "types/thing/record/1"),
		("/types/thing", json!({ "list": [] }), "types/thing"),
		("/types/failure", json!({ "record": [] }), "types/failure"),
		("/reasons/0/failure", json!("refused"), "reasons/0/failure"),
		("/call/fields/3/key", json!(5), "call/fields"),
		("/call/fields/2/shape", json!({ "type": "thing" }), "call/fields"),
		(
			"/interfaces/things/operations/0/input",
			json!("nothing"),
			"interfaces/things/operations/0/input",
		),
		("/interfaces/things/version", json!(-1), "interfaces/things/version"),
		(
			"/types/thing",
			json!({ "enum": [{ "name": "b", "code": 2 }, { "name": "a", "code": 1 }], "ordered": true }),
			"types/thing/enum",
		),
		("/types/thing", json!({ "flags": [{ "name": "a", "code": 3 }] }), "types/thing/flags/0/code"),
		(
			"/types/thing",
			json!({ "union": { "tag": "name", "cases": [{ "name": "a", "code": 1, "fields": [
				{ "name": "x", "key": 0, "shape": { "prim": "bool" } }
			] }] } }),
			"types/thing/union/cases/0/fields/0/key",
		),
		(
			"/types/thing",
			json!({ "union": { "tag": "name", "cases": [{ "name": "a", "code": 1, "fields": [
				{ "name": "name", "key": 1, "shape": { "prim": "bool" } }
			] }] } }),
			"types/thing/union/cases/0/fields/0/name",
		),
		("/interfaces/things/operations/0/name", json!("operation"), "interfaces/things"),
		("/interfaces/things/operations/0/name", json!("call"), "interfaces/things"),
	];
	for (pointer, value, at) in cases {
		let unread = refused(pointer, value.clone());
		assert_eq!(unread.at, at, "{pointer} = {value}: {unread:?}");
		assert!(!unread.expected.is_empty(), "{pointer} = {value}");
	}
}

#[test]
fn a_type_whose_rust_is_taken_is_refused() {
	let mut contracts = least();
	contracts["types"]["string"] = json!({ "record": [] });
	assert_eq!(written(&contracts).unwrap_err().at, "types/string");
	let mut contracts = least();
	contracts["types"]["a-1b"] = json!({ "record": [] });
	contracts["types"]["a1b"] = json!({ "record": [] });
	let unread = written(&contracts).unwrap_err();
	assert_eq!(unread.at, "types/a1b");
	assert!(unread.expected.contains("A1b"), "{unread:?}");
}
