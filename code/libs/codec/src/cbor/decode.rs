//! Exactly one data item read strictly: well formed by RFC 8949's Appendix C, valid by its 5.3,
//! and within [`DEPTH`]. Every head is read by minicbor's decoder; what it reads unchecked -- a
//! simple value below 32 in two bytes, a string chunk of another type, a repeated key -- is
//! refused here.

use std::collections::HashSet;
use std::error::Error as _;

use minicbor::Decoder;
use minicbor::decode::Error;

use super::encode;
use crate::{DEPTH, Refused, Value};

/// One data item from `bytes`. What is not well formed is refused as soon as it is met; what is
/// well formed yet not valid is refused only once the whole item is read well formed, and bytes
/// left after it are refused before that.
pub(crate) fn decode(bytes: &[u8]) -> Result<Value, Refused> {
	let mut reader = Reader { decoder: Decoder::new(bytes), invalid: false };
	let value = reader.item(0)?;
	if reader.decoder.position() < bytes.len() {
		Err(Refused::Trailing)
	} else if reader.invalid {
		Err(Refused::Invalid)
	} else {
		Ok(value)
	}
}

/// What minicbor's refusal is here: a head it does not read is a syntax error, and the rest the
/// input ending inside an item, a length longer than any input among them.
fn refusal(error: Error) -> Refused {
	if error.is_type_mismatch() { Refused::Syntax } else { Refused::Truncated }
}

struct Reader<'b> {
	decoder: Decoder<'b>,
	/// Whether an item read so far was well formed yet not valid.
	invalid: bool,
}

impl<'b> Reader<'b> {
	/// The byte the next head begins with, looked at and not taken.
	fn initial(&self) -> Result<u8, Refused> {
		self.decoder.input().get(self.decoder.position()).copied().ok_or(Refused::Truncated)
	}

	/// Takes a head of one byte, a break or an indefinite length, which minicbor reads only inside
	/// its own iterators.
	fn skip_byte(&mut self) {
		self.decoder.set_position(self.decoder.position().saturating_add(1));
	}

	/// Whether a break comes next, taken if it does.
	fn ended(&mut self) -> Result<bool, Refused> {
		let ended = self.initial()? == 0xff;
		if ended {
			self.skip_byte();
		}
		Ok(ended)
	}

	/// One item within `depth` arrays, maps and tags, where a break is out of place.
	fn item(&mut self, depth: usize) -> Result<Value, Refused> {
		if depth > DEPTH {
			return Err(Refused::TooDeep);
		}
		let initial = self.initial()?;
		let d = &mut self.decoder;
		Ok(match initial >> 5 {
			0 => Value::Integer(i128::from(d.u64().map_err(refusal)?)),
			1 => Value::Integer(i128::from(d.int().map_err(refusal)?)),
			2 => Value::Bytes(self.bytes(initial)?),
			3 => Value::Text(self.text(initial)?),
			4 => Value::Array(self.array(depth)?),
			5 => Value::Map(self.map(depth)?),
			6 => {
				let tag = d.tag().map_err(refusal)?;
				Value::Tag(tag.as_u64(), Box::new(self.item(depth.saturating_add(1))?))
			}
			// Major type 7, the last of three bits.
			_ => self.simple(initial)?,
		})
	}

	fn array(&mut self, depth: usize) -> Result<Vec<Value>, Refused> {
		let within = depth.saturating_add(1);
		let mut items = Vec::new();
		match self.decoder.array().map_err(refusal)? {
			Some(n) => {
				for _ in 0..n {
					items.push(self.item(within)?);
				}
			}
			None => {
				while !self.ended()? {
					items.push(self.item(within)?);
				}
			}
		}
		Ok(items)
	}

	fn map(&mut self, depth: usize) -> Result<Vec<(Value, Value)>, Refused> {
		let within = depth.saturating_add(1);
		let mut pairs = Vec::new();
		match self.decoder.map().map_err(refusal)? {
			Some(n) => {
				for _ in 0..n {
					pairs.push((self.item(within)?, self.item(within)?));
				}
			}
			None => {
				while !self.ended()? {
					pairs.push((self.item(within)?, self.item(within)?));
				}
			}
		}
		self.check_keys(&pairs);
		Ok(pairs)
	}

	/// Refuses a chunk of an indefinite string of `major` type that is not a definite string of
	/// that type, its 3.2.3, as soon as its first byte says so.
	fn chunk(&self, major: u8) -> Result<(), Refused> {
		let initial = self.initial()?;
		if initial >> 5 == major && initial & 0x1f != 31 { Ok(()) } else { Err(Refused::Syntax) }
	}

	/// A byte string's bytes, of one definite string or of its chunks.
	fn bytes(&mut self, initial: u8) -> Result<Vec<u8>, Refused> {
		if initial & 0x1f != 31 {
			return self.decoder.bytes().map(<[u8]>::to_vec).map_err(refusal);
		}
		self.skip_byte();
		let mut joined = Vec::new();
		while !self.ended()? {
			self.chunk(2)?;
			joined.extend_from_slice(self.decoder.bytes().map_err(refusal)?);
		}
		Ok(joined)
	}

	/// A text, of one definite string or of its chunks, each UTF-8 on its own.
	fn text(&mut self, initial: u8) -> Result<String, Refused> {
		if initial & 0x1f != 31 {
			return self.str().map(str::to_owned);
		}
		self.skip_byte();
		let mut joined = String::new();
		while !self.ended()? {
			self.chunk(3)?;
			joined.push_str(self.str()?);
		}
		Ok(joined)
	}

	/// A definite text. One that is not UTF-8 is not valid, its 5.3.1, and refused only once the
	/// whole item is read: minicbor has taken its bytes before checking them, so reading goes on.
	fn str(&mut self) -> Result<&'b str, Refused> {
		match self.decoder.str() {
			Ok(text) => Ok(text),
			Err(e) if e.source().is_some_and(|s| s.is::<std::str::Utf8Error>()) => {
				self.invalid = true;
				Ok("")
			}
			Err(e) => Err(refusal(e)),
		}
	}

	/// A map's keys each apart from the others, as their encodings are, its 5.6.
	fn check_keys(&mut self, pairs: &[(Value, Value)]) {
		let mut seen = HashSet::new();
		for (key, _) in pairs {
			// A key read well formed is always written; one that is not would be refused anyway.
			if !encode::encode(key).is_ok_and(|key| seen.insert(key)) {
				self.invalid = true;
			}
		}
	}

	/// What major type 7 holds: a simple value or a float; a break is out of place here.
	fn simple(&mut self, initial: u8) -> Result<Value, Refused> {
		let d = &mut self.decoder;
		Ok(match initial {
			0xe0..=0xf3 => Value::Simple(d.simple().map_err(refusal)?),
			0xf4 | 0xf5 => Value::Bool(d.bool().map_err(refusal)?),
			0xf6 => {
				d.null().map_err(refusal)?;
				Value::Null
			}
			0xf7 => {
				d.undefined().map_err(refusal)?;
				Value::Undefined
			}
			// minicbor reads the byte after f8 unchecked; one below 32 is a syntax error, its 3.3.
			0xf8 => match d.simple().map_err(refusal)? {
				n @ 32.. => Value::Simple(n),
				_ => return Err(Refused::Syntax),
			},
			0xf9..=0xfb => Value::Float(d.f64().map_err(refusal)?),
			// fc to fe are reserved, and ff a break out of place.
			_ => return Err(Refused::Syntax),
		})
	}
}
