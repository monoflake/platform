//! An answer, `model/contracts.json`'s `answer`, a union by `status`, `success` code 1 with `data`
//! at key 1 and `error` code 2 with its fields beside.

use codec::Value as Cbor;
use serde_json::Value as Json;

use super::{
	Read, case_cbor, case_json, field_cbor, field_json, map_cbor, object_json, union_cbor,
	union_json, unknown_case,
};
use crate::contracts::Error;
use crate::{Answer, Encoded};

const STATUS: &str = "status";
const SUCCESS: (&str, i128) = ("success", 1);
const ERROR: (&str, i128) = ("error", 2);

impl<O: Encoded> Encoded for Answer<O> {
	fn to_json(&self) -> Json {
		match self {
			Self::Success(output) => union_json(STATUS, SUCCESS.0, [("data", Some(output.to_json()))]),
			Self::Error(error) => {
				let mut written = error.to_json();
				if let Json::Object(fields) = &mut written {
					fields.insert(STATUS.to_owned(), Json::from(ERROR.0));
				}
				written
			}
		}
	}

	fn from_json(json: &Json) -> Read<Self> {
		let object = object_json(json)?;
		match case_json(object, STATUS)? {
			"success" => field_json(object, "data", O::from_json).map(Self::Success),
			"error" => Error::from_json(json).map(Self::Error),
			_ => Err(unknown_case(STATUS, "one of success, error")),
		}
	}

	fn to_cbor(&self) -> Cbor {
		match self {
			Self::Success(output) => union_cbor(SUCCESS.1, [(1, Some(output.to_cbor()))]),
			Self::Error(error) => {
				let mut written = error.to_cbor();
				if let Cbor::Map(pairs) = &mut written {
					pairs.insert(0, (Cbor::Integer(0), Cbor::Integer(ERROR.1)));
				}
				written
			}
		}
	}

	fn from_cbor(cbor: &Cbor) -> Read<Self> {
		let map = map_cbor(cbor)?;
		match case_cbor(map, STATUS)? {
			1 => field_cbor(map, 1, "data", O::from_cbor).map(Self::Success),
			2 => Error::from_cbor(cbor).map(Self::Error),
			_ => Err(unknown_case(STATUS, "one of 1, 2")),
		}
	}
}
