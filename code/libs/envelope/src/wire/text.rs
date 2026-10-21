//! Bytes in unpadded base64url, RFC 4648's 5, and a hash in 64 lowercase hex digits, b8f35, each a
//! byte string in CBOR.

use codec::Value as Cbor;
use serde_json::Value as Json;

use super::Read;
use crate::Malformed;

const BASE64URL: &str = "base64url, unpadded";
const HEX: &str = "64 lowercase hex digits";
const BYTES: &str = "a byte string";
const HASH: &str = "32 bytes";

/// RFC 4648's table 2, the URL and filename safe alphabet.
const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// The letter of a sextet, the low six bits of `sextet`.
fn letter(sextet: u32) -> Option<char> {
	usize::try_from(sextet & 0x3f).ok().and_then(|i| ALPHABET.get(i)).map(|b| char::from(*b))
}

/// The sextet a letter spells, if it is one of the alphabet's.
fn sextet(letter: u8) -> Option<u32> {
	ALPHABET.iter().position(|b| *b == letter).and_then(|i| u32::try_from(i).ok())
}

/// `bytes` in base64url, unpadded.
fn encode(bytes: &[u8]) -> String {
	let mut text = String::new();
	for chunk in bytes.chunks(3) {
		let (group, letters) = match *chunk {
			[a] => (u32::from_be_bytes([0, a, 0, 0]), 2),
			[a, b] => (u32::from_be_bytes([0, a, b, 0]), 3),
			[a, b, c] => (u32::from_be_bytes([0, a, b, c]), 4),
			_ => (0, 0),
		};
		text.extend([18, 12, 6, 0].iter().take(letters).filter_map(|shift| letter(group >> shift)));
	}
	text
}

/// The bytes base64url spells, unpadded and with its unused bits zero, or none.
fn decode(text: &str) -> Option<Vec<u8>> {
	let sextets = text.bytes().map(sextet).collect::<Option<Vec<u32>>>()?;
	let mut bytes = Vec::new();
	for chunk in sextets.chunks(4) {
		let group =
			chunk.iter().zip([18, 12, 6, 0]).fold(0, |group, (sextet, shift)| group | sextet << shift);
		let [_, a, b, c] = group.to_be_bytes();
		match *chunk {
			[_, _, _, _] => bytes.extend([a, b, c]),
			[_, _, _] if c == 0 => bytes.extend([a, b]),
			[_, _] if b == 0 && c == 0 => bytes.push(a),
			_ => return None,
		}
	}
	Some(bytes)
}

/// Bytes' JSON, base64url.
pub(crate) fn bytes_to_json(value: &impl AsRef<[u8]>) -> Json {
	Json::String(encode(value.as_ref()))
}

/// Bytes, from base64url alone.
pub(crate) fn bytes_from_json(json: &Json) -> Read<Vec<u8>> {
	json.as_str().and_then(decode).ok_or_else(|| Malformed::expected(BASE64URL))
}

/// Bytes' CBOR, a byte string.
pub(crate) fn bytes_to_cbor(value: &impl AsRef<[u8]>) -> Cbor {
	Cbor::Bytes(value.as_ref().to_vec())
}

/// Bytes, from a byte string.
pub(crate) fn bytes_from_cbor(cbor: &Cbor) -> Read<Vec<u8>> {
	if let Cbor::Bytes(value) = cbor { Ok(value.clone()) } else { Err(Malformed::expected(BYTES)) }
}

/// A hex digit's value, if it is one of the lowercase sixteen.
fn digit(letter: u8) -> Option<u8> {
	match letter {
		b'0'..=b'9' => Some(letter - b'0'),
		b'a'..=b'f' => Some(letter - b'a' + 10),
		_ => None,
	}
}

/// A hash's JSON, its 64 lowercase hex digits.
pub(crate) fn hash_to_json(value: &[u8; 32]) -> Json {
	let digits = value
		.iter()
		.flat_map(|b| [b >> 4, b & 0xf])
		.filter_map(|d| char::from_digit(u32::from(d), 16))
		.collect::<String>();
	Json::String(digits)
}

/// A hash, from its 64 lowercase hex digits alone.
pub(crate) fn hash_from_json(json: &Json) -> Read<[u8; 32]> {
	let hash = json.as_str().filter(|text| text.len() == 64).and_then(|text| {
		let mut hash = [0; 32];
		for (byte, pair) in hash.iter_mut().zip(text.as_bytes().chunks(2)) {
			let [high, low] = *pair else {
				return None;
			};
			*byte = digit(high)? << 4 | digit(low)?;
		}
		Some(hash)
	});
	hash.ok_or_else(|| Malformed::expected(HEX))
}

/// A hash's CBOR, a byte string of 32 bytes.
pub(crate) fn hash_to_cbor(value: &[u8; 32]) -> Cbor {
	Cbor::Bytes(value.to_vec())
}

/// A hash, from a byte string of 32 bytes.
pub(crate) fn hash_from_cbor(cbor: &Cbor) -> Read<[u8; 32]> {
	let hash =
		if let Cbor::Bytes(value) = cbor { <[u8; 32]>::try_from(value.as_slice()).ok() } else { None };
	hash.ok_or_else(|| Malformed::expected(HASH))
}
