//! [`Cwt`] for [`Claims`]: RFC 8392's claims set, carried as a Sign1's payload.

use crate::{Cbor, Claims, Cwt, CwtRefused, Sign1, Sign1Refused, Unwritable, Value, sign1};

/// CWT's tag, RFC 8392's 6, which stands outside the COSE message's own.
const TAG: u64 = 61;

impl Cwt for Claims {
	fn payload(&self) -> Result<Vec<u8>, Unwritable> {
		Value::Map(self.0.clone()).encode()
	}

	fn decode(bytes: &[u8]) -> Result<(Sign1, Self), CwtRefused> {
		let item = Value::decode(bytes).map_err(|r| CwtRefused::Sign1(Sign1Refused::Cbor(r)))?;
		let read = if let Value::Tag(TAG, message) = item {
			match sign1::read(*message) {
				Ok((sign1, true)) => Ok((sign1, true)),
				// Under tag 61 the Sign1 stands under its own tag 18 as well.
				Ok((_, false)) => Err(Sign1Refused::Shape),
				Err(refused) => Err(refused),
			}
		} else {
			sign1::read(item)
		};
		let (sign1, _) = read.map_err(CwtRefused::Sign1)?;
		let payload = sign1.payload.as_deref().ok_or(CwtRefused::Detached)?;
		match Value::decode(payload).map_err(CwtRefused::Payload)? {
			Value::Map(claims) => Ok((sign1, Claims(claims))),
			Value::Integer(_)
			| Value::Bytes(_)
			| Value::Text(_)
			| Value::Array(_)
			| Value::Tag(..)
			| Value::Bool(_)
			| Value::Null
			| Value::Undefined
			| Value::Simple(_)
			| Value::Float(_) => Err(CwtRefused::Unclaimed),
		}
	}
}
