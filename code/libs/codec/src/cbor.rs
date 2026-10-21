//! [`Cbor`] for [`Value`], written as RFC 8949's 4.2.1 writes it and read strictly through
//! minicbor.

mod decode;
mod encode;
mod float;

use crate::{Cbor, Refused, Unwritable, Value};

impl Cbor for Value {
	fn encode(&self) -> Result<Vec<u8>, Unwritable> {
		encode::encode(self)
	}

	fn decode(bytes: &[u8]) -> Result<Self, Refused> {
		decode::decode(bytes)
	}

	fn decode_deterministic(bytes: &[u8]) -> Result<Self, Refused> {
		let value = decode::decode(bytes)?;
		// A value read is always written, so what is written differs from what was read exactly where
		// what was read is not as 4.2.1 writes it.
		if encode::encode(&value).is_ok_and(|written| written == bytes) {
			Ok(value)
		} else {
			Err(Refused::Nondeterministic)
		}
	}
}
