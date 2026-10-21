//! A call, `model/contracts.json`'s `call`, `interface` at key 1, `operation` at 2, `input` at 3
//! and `capabilities` at 4, absent when none.

use codec::Value as Cbor;
use serde_json::Value as Json;

use super::{
	PRESENT, Read, bytes_from_cbor, bytes_from_json, bytes_to_cbor, bytes_to_json, field_cbor,
	field_json, list_from_cbor, list_from_json, list_to_cbor, list_to_json, map_cbor, object_json,
	optional_cbor, optional_json, record_cbor, record_json, string_from_cbor, string_from_json,
};
use crate::{Called, Encoded, Envelope, Malformed, Step};

/// What a call's `input` read as its operation's type answers, its own reason within `input`.
pub(crate) fn call_input<C>(read: Read<C>) -> Read<C> {
	read.map_err(|m| m.within(Step::Field("input".to_owned())))
}

/// An operation its interface has not, at `operation`, `expected` naming every one it has.
pub(crate) fn unknown_operation(expected: &str) -> Malformed {
	Malformed::expected(expected).within(Step::Field("operation".to_owned()))
}

/// The call's interface, a string, held to `C`'s.
fn interface<C: Called>(interface: &str) -> Read<()> {
	if interface == C::INTERFACE {
		Ok(())
	} else {
		let expected = format!("one of {}", C::INTERFACE);
		Err(Malformed::expected(expected).within(Step::Field("interface".to_owned())))
	}
}

/// What a call without an `input` answers, an unknown operation at `operation` and a known one at
/// `input`.
fn no_input<C>(looked_up: Read<C>) -> Malformed {
	match looked_up {
		Err(m) if m.at.first() == Some(&Step::Field("operation".to_owned())) => m,
		Ok(_) | Err(_) => Malformed::expected(PRESENT).within(Step::Field("input".to_owned())),
	}
}

impl<C: Called> Encoded for Envelope<C> {
	fn to_json(&self) -> Json {
		record_json([
			("interface", Some(Json::from(C::INTERFACE))),
			("operation", Some(Json::from(self.call.operation()))),
			("input", Some(self.call.input_json())),
			(
				"capabilities",
				(!self.capabilities.is_empty()).then(|| list_to_json(&self.capabilities, bytes_to_json)),
			),
		])
	}

	fn from_json(json: &Json) -> Read<Self> {
		let object = object_json(json)?;
		interface::<C>(&field_json(object, "interface", string_from_json)?)?;
		let operation = field_json(object, "operation", string_from_json)?;
		let call = match object.get("input") {
			Some(input) => C::from_json(&operation, input)?,
			None => return Err(no_input(C::from_json(&operation, &Json::Null))),
		};
		let capabilities =
			optional_json(object, "capabilities", |v| list_from_json(v, bytes_from_json))?;
		Ok(Self { call, capabilities: capabilities.unwrap_or_default() })
	}

	fn to_cbor(&self) -> Cbor {
		record_cbor([
			(1, Some(Cbor::Text(C::INTERFACE.to_owned()))),
			(2, Some(Cbor::Text(self.call.operation().to_owned()))),
			(3, Some(self.call.input_cbor())),
			(4, (!self.capabilities.is_empty()).then(|| list_to_cbor(&self.capabilities, bytes_to_cbor))),
		])
	}

	fn from_cbor(cbor: &Cbor) -> Read<Self> {
		let map = map_cbor(cbor)?;
		interface::<C>(&field_cbor(map, 1, "interface", string_from_cbor)?)?;
		let operation = field_cbor(map, 2, "operation", string_from_cbor)?;
		let call = match super::at(map, 3) {
			Some(input) => C::from_cbor(&operation, input)?,
			None => return Err(no_input(C::from_cbor(&operation, &Cbor::Null))),
		};
		let capabilities =
			optional_cbor(map, 4, "capabilities", |v| list_from_cbor(v, bytes_from_cbor))?;
		Ok(Self { call, capabilities: capabilities.unwrap_or_default() })
	}
}
