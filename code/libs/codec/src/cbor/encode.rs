//! A value written as RFC 8949's 4.2.1 writes it. Every head is written by minicbor's encoder,
//! which writes each in its shortest form; what it leaves to its caller -- a float's width, the
//! order of a map's keys, a key repeated, the depth -- is decided here.

use std::convert::Infallible;

use minicbor::Encoder;
use minicbor::data::{Int, Tag};
use minicbor::encode::Error;

use super::float;
use crate::{DEPTH, Unwritable, Value};

/// The encoder everything here writes with, into bytes.
pub(super) type Writer = Encoder<Vec<u8>>;

/// `value` as 4.2.1 writes it.
pub(crate) fn encode(value: &Value) -> Result<Vec<u8>, Unwritable> {
	written(value, 0)
}

/// Takes what minicbor's encoder gives back: a `Vec` takes every byte, so a write to one never
/// fails, its error being `Infallible`'s.
pub(super) fn put(_: Result<&mut Writer, Error<Infallible>>) {}

/// `value` within `depth` arrays, maps and tags, written alone.
fn written(value: &Value, depth: usize) -> Result<Vec<u8>, Unwritable> {
	let mut e = Encoder::new(Vec::new());
	write(value, depth, &mut e)?;
	Ok(e.into_writer())
}

/// A length as a head's argument.
fn length(n: usize) -> Result<u64, Unwritable> {
	u64::try_from(n).map_err(|_| Unwritable::OutOfRange)
}

fn write(value: &Value, depth: usize, e: &mut Writer) -> Result<(), Unwritable> {
	if depth > DEPTH {
		return Err(Unwritable::TooDeep);
	}
	let within = depth.saturating_add(1);
	match value {
		Value::Integer(n) => put(e.int(Int::try_from(*n).map_err(|_| Unwritable::OutOfRange)?)),
		Value::Bytes(bytes) => put(e.bytes(bytes)),
		Value::Text(text) => put(e.str(text)),
		Value::Array(items) => {
			put(e.array(length(items.len())?));
			for item in items {
				write(item, within, e)?;
			}
		}
		Value::Map(pairs) => {
			// Each key is written alone first, so the pairs are put in the bytewise order of their
			// keys' encodings, where two keys written alike stand side by side.
			let mut written = pairs
				.iter()
				.map(|(key, value)| Ok((written(key, within)?, written(value, within)?)))
				.collect::<Result<Vec<_>, Unwritable>>()?;
			written.sort_by(|(a, _), (b, _)| a.cmp(b));
			if written.windows(2).any(|w| matches!(w, [(a, _), (b, _)] if a == b)) {
				return Err(Unwritable::RepeatedKey);
			}
			put(e.map(length(written.len())?));
			for (key, value) in written {
				e.writer_mut().extend_from_slice(&key);
				e.writer_mut().extend_from_slice(&value);
			}
		}
		Value::Tag(tag, content) => {
			put(e.tag(Tag::new(*tag)));
			write(content, within, e)?;
		}
		Value::Bool(b) => put(e.bool(*b)),
		Value::Null => put(e.null()),
		Value::Undefined => put(e.undefined()),
		// 20 to 23 are false, true, null and undefined, and 24 to 31 reserved, its 3.3.
		Value::Simple(20..=31) => return Err(Unwritable::OutOfRange),
		Value::Simple(n) => put(e.simple(*n)),
		Value::Float(x) => float::write(*x, e),
	}
	Ok(())
}
