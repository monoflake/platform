//! [`CoseSign1`] for [`Sign1`], RFC 9052's COSE_Sign1 and its structure alone.

use crate::{Cbor, CoseSign1, Sign1, Sign1Refused, Unwritable, Value};

/// COSE_Sign1's tag, RFC 9052's 2.
const TAG: u64 = 18;

impl CoseSign1 for Sign1 {
	fn to_be_signed(protected: &[u8], aad: &[u8], payload: &[u8]) -> Vec<u8> {
		// An empty map serialized is taken as no bytes, RFC 9052's 3.
		let protected = if protected == [0xa0] { &[] } else { protected };
		let structure = Value::Array(vec![
			Value::Text("Signature1".to_owned()),
			Value::Bytes(protected.to_vec()),
			Value::Bytes(aad.to_vec()),
			Value::Bytes(payload.to_vec()),
		]);
		// Byte strings and a text under an array of four are always written.
		structure.encode().unwrap_or_default()
	}

	fn encode(&self, tagged: bool) -> Result<Vec<u8>, Unwritable> {
		let fields = Value::Array(vec![
			Value::Bytes(self.protected.clone()),
			Value::Map(self.unprotected.clone()),
			self.payload.clone().map_or(Value::Null, Value::Bytes),
			Value::Bytes(self.signature.clone()),
		]);
		if tagged { Value::Tag(TAG, Box::new(fields)) } else { fields }.encode()
	}

	fn decode(bytes: &[u8]) -> Result<(Self, bool), Sign1Refused> {
		read(Value::decode(bytes).map_err(Sign1Refused::Cbor)?)
	}
}

/// A Sign1 from the one item it was read as, under tag 18 or under none, and whether it was tagged.
pub(crate) fn read(item: Value) -> Result<(Sign1, bool), Sign1Refused> {
	if let Value::Tag(TAG, fields) = item {
		shape(*fields).map(|sign1| (sign1, true))
	} else {
		shape(item).map(|sign1| (sign1, false))
	}
}

/// The four fields of an untagged Sign1, its protected bytes kept as written; a tag here is another
/// message's, not a Sign1.
fn shape(fields: Value) -> Result<Sign1, Sign1Refused> {
	let sign1 = fields_of(fields)?;
	if sign1.protected.is_empty() || matches!(Value::decode(&sign1.protected), Ok(Value::Map(_))) {
		Ok(sign1)
	} else {
		Err(Sign1Refused::Shape)
	}
}

/// The four fields, each of its type.
fn fields_of(fields: Value) -> Result<Sign1, Sign1Refused> {
	let Value::Array(fields) = fields else {
		return Err(Sign1Refused::Shape);
	};
	let Ok([protected, unprotected, payload, signature]) = <[Value; 4]>::try_from(fields) else {
		return Err(Sign1Refused::Shape);
	};
	match (protected, unprotected, payload, signature) {
		(
			Value::Bytes(protected),
			Value::Map(unprotected),
			Value::Bytes(payload),
			Value::Bytes(signature),
		) => Ok(Sign1 { protected, unprotected, payload: Some(payload), signature }),
		(Value::Bytes(protected), Value::Map(unprotected), Value::Null, Value::Bytes(signature)) => {
			Ok(Sign1 { protected, unprotected, payload: None, signature })
		}
		_ => Err(Sign1Refused::Shape),
	}
}
