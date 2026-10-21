//! [`Answer`] held to `model/contracts.json`'s `answer`, RFC ge55b, in JSON and CBOR, with its
//! refusals and every reason's message.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

use codec::{Cbor, Value};
use envelope::contracts::{self, Error, Failure, ObjectName, interface};
use envelope::{Answer, Encoded, Malformed, Operation, Reason, Step};
use serde_json::json;

type Named = Answer<ObjectName>;

fn malformed(at: Vec<Step>, expected: &str) -> Malformed {
	Malformed { at, expected: expected.to_owned() }
}

fn field(name: &str) -> Step {
	Step::Field(name.to_owned())
}

fn hex_of(text: &str) -> Vec<u8> {
	(0..text.len()).step_by(2).map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap()).collect()
}

fn decoded(text: &str) -> Value {
	Value::decode_deterministic(&hex_of(text)).unwrap()
}

fn gone() -> Named {
	Answer::Error(Error {
		failure: Failure::Rejected,
		reason: "not_found".into(),
		message: "gone".into(),
	})
}

#[test]
fn a_success_holds_the_output_as_data() {
	let answer = Named::Success(ObjectName { name: "a".into() });
	let json = json!({ "status": "success", "data": { "name": "a" } });
	assert_eq!(answer.to_json(), json);
	assert_eq!(Named::from_json(&json), Ok(answer.clone()));
	// `{0: 1, 1: {1: "a"}}`
	assert_eq!(answer.to_cbor().encode().unwrap(), hex_of("a2000101a1016161"));
	assert_eq!(Named::from_cbor(&decoded("a2000101a1016161")), Ok(answer));
}

#[test]
fn an_error_holds_its_fields_beside_the_status() {
	let json =
		json!({ "status": "error", "failure": "rejected", "reason": "not_found", "message": "gone" });
	assert_eq!(gone().to_json(), json);
	assert_eq!(Named::from_json(&json), Ok(gone()));
	// `{0: 2, 1: 1, 2: "not_found", 3: "gone"}`
	let cbor = "a40002010102696e6f745f666f756e640364676f6e65";
	assert_eq!(gone().to_cbor().encode().unwrap(), hex_of(cbor));
	assert_eq!(Named::from_cbor(&decoded(cbor)), Ok(gone()));
}

#[test]
fn a_field_no_reader_knows_is_passed_over() {
	let json = json!({ "status": "success", "data": { "name": "a" }, "message": 1 });
	assert_eq!(Named::from_json(&json), Ok(Named::Success(ObjectName { name: "a".into() })));
	let json = json!({ "status": "error", "failure": "rejected", "reason": "not_found", "message": "gone", "data": {} });
	assert_eq!(Named::from_json(&json), Ok(gone()));
	// `{0: 2, 1: 1, 2: "not_found", 3: "gone", 9: true}`
	assert_eq!(
		Named::from_cbor(&decoded("a50002010102696e6f745f666f756e640364676f6e6509f5")),
		Ok(gone())
	);
}

#[test]
fn a_status_neither_case_names_is_refused_at_status() {
	let status = |expected: &str| Err(malformed(vec![field("status")], expected));
	assert_eq!(
		Named::from_json(&json!({ "status": "done", "data": {} })),
		status("one of success, error")
	);
	assert_eq!(Named::from_json(&json!({ "data": { "name": "a" } })), status("present"));
	assert_eq!(Named::from_json(&json!({ "status": 1 })), status("a string"));
	// `{0: 3}`
	assert_eq!(Named::from_cbor(&decoded("a10003")), status("one of 1, 2"));
	assert_eq!(Named::from_cbor(&decoded("a0")), status("present"));
	assert_eq!(Named::from_json(&json!([])), Err(malformed(vec![], "an object")));
}

#[test]
fn what_a_case_holds_is_read_as_its_type() {
	assert_eq!(
		Named::from_json(&json!({ "status": "success", "data": { "name": 1 } })),
		Err(malformed(vec![field("data"), field("name")], "a string"))
	);
	assert_eq!(
		Named::from_json(&json!({ "status": "success" })),
		Err(malformed(vec![field("data")], "present"))
	);
	assert_eq!(
		Named::from_json(
			&json!({ "status": "error", "failure": "lost", "reason": "x", "message": "y" })
		),
		Err(malformed(vec![field("failure")], "one of rejected, unavailable, unknown"))
	);
}

#[test]
fn an_error_without_its_message_is_refused() {
	let json = json!({ "status": "error", "failure": "rejected", "reason": "not_found" });
	assert_eq!(Named::from_json(&json), Err(malformed(vec![field("message")], "present")));
	// `{0: 2, 1: 1, 2: "not_found"}`
	let cbor = Value::Map(vec![
		(Value::Integer(0), Value::Integer(2)),
		(Value::Integer(1), Value::Integer(1)),
		(Value::Integer(2), Value::Text("not_found".into())),
	]);
	assert_eq!(Named::from_cbor(&cbor), Err(malformed(vec![field("message")], "present")));
	let alone = json!({ "failure": "rejected", "reason": "not_found" });
	assert_eq!(Error::from_json(&alone), Err(malformed(vec![field("message")], "present")));
}

/// `model/contracts.json`'s `messages`, as it stands.
fn messages() -> serde_json::Map<String, serde_json::Value> {
	let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../model/contracts.json");
	let text = std::fs::read_to_string(path).unwrap();
	let contracts: serde_json::Value = serde_json::from_str(&text).unwrap();
	contracts["messages"].as_object().unwrap().clone()
}

fn carried(reasons: &[Reason]) {
	assert!(!reasons.is_empty());
	let messages = messages();
	for reason in reasons {
		assert_eq!(messages[reason.name], reason.message, "{}", reason.name);
		assert_eq!(contracts::message(reason.name), Some(reason.message), "{}", reason.name);
	}
}

#[test]
fn every_reason_carries_the_message_messages_gives_it() {
	carried(contracts::REASONS);
	carried(contracts::CALLING);
	carried(interface::object::Write::REASONS);
	carried(interface::object::Read::REASONS);
	carried(interface::database::Execute::REASONS);
	for (name, message) in messages() {
		assert_eq!(contracts::message(&name), message.as_str(), "{name}");
	}
	assert_eq!(contracts::message("not_found"), Some("Nothing of that name or id exists"));
	assert_eq!(contracts::message("no_such_reason"), None);
}
