//! The tokens a binding calls management by, read from one file each and held by the BLAKE3 of each
//! secret, RFC 3d3nt.

use crate::{Binding, Denied, Hold, Tokens, Unread};
use std::fs;
use std::path::PathBuf;

/// What a token file holds, as a file that does not is answered.
const TOKEN: &str = "one token, `<id>.<secret>`, the id a binding's integer in decimal and the \
	secret 32 bytes in unpadded base64url, one newline allowed after it";

/// The characters of a 32 byte secret in unpadded base64url.
const SECRET: usize = 43;

/// The value of one base64url character, none for any other.
fn sextet(character: u8) -> Option<u32> {
	let value = match character {
		b'A'..=b'Z' => character - b'A',
		b'a'..=b'z' => character - b'a' + 26,
		b'0'..=b'9' => character - b'0' + 52,
		b'-' => 62,
		b'_' => 63,
		_ => return None,
	};
	Some(u32::from(value))
}

/// The 32 bytes a secret writes, none where it is not their one unpadded base64url text.
fn secret(text: &str) -> Option<[u8; 32]> {
	if text.len() != SECRET {
		return None;
	}
	let mut bytes = [0u8; 32];
	let mut written = 0usize;
	let mut bits = 0u32;
	let mut count = 0u32;
	for character in text.bytes() {
		bits = (bits << 6) | sextet(character)?;
		count += 6;
		if count >= 8 {
			count -= 8;
			*bytes.get_mut(written)? = u8::try_from((bits >> count) & 0xff).ok()?;
			written += 1;
			bits &= (1 << count) - 1;
		}
	}
	// The last character's two bits past the 32nd byte are zero, so each secret has one text.
	(written == 32 && bits == 0).then_some(bytes)
}

/// A binding's id, decimal digits with no leading zero.
fn id(text: &str) -> Option<Binding> {
	let digits = !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit());
	if !digits || (text.len() > 1 && text.starts_with('0')) {
		return None;
	}
	text.parse().ok()
}

/// A token's binding and the hash of its secret.
fn token(text: &str) -> Option<(Binding, [u8; 32])> {
	let (binding, rest) = text.split_once('.')?;
	Some((id(binding)?, *blake3::hash(&secret(rest)?).as_bytes()))
}

/// What a file holds, one token and at most one newline after it.
fn file(text: &str) -> Option<(Binding, [u8; 32])> {
	token(text.strip_suffix('\n').unwrap_or(text))
}

impl Hold for Tokens {
	fn reload(&mut self, files: &[PathBuf]) -> Vec<Unread> {
		let mut unread = Vec::new();
		for path in files {
			let text = match fs::read_to_string(path) {
				Ok(text) => text,
				Err(error) => {
					unread.push(Unread::Missing { file: path.clone(), error: error.to_string() });
					continue;
				}
			};
			let Some((binding, hash)) = file(&text) else {
				unread.push(Unread::Malformed { file: path.clone(), line: 1, expected: TOKEN.to_owned() });
				continue;
			};
			if self.forgotten.contains(&hash) {
				continue;
			}
			let held = self.held.entry(binding).or_default();
			if !held.contains(&hash) {
				held.push(hash);
			}
		}
		unread
	}

	fn check(&self, authorization: Option<&str>) -> Result<Binding, Denied> {
		let header = authorization.ok_or(Denied)?;
		let (scheme, text) = header.split_once(' ').ok_or(Denied)?;
		if !scheme.eq_ignore_ascii_case("Bearer") {
			return Err(Denied);
		}
		let (binding, bytes) = token(text).ok_or(Denied)?;
		let hash = blake3::Hash::from_bytes(bytes);
		// Every hash is compared, each in constant time by `blake3::Hash`, so the time names no match.
		let found = self
			.held
			.get(&binding)
			.is_some_and(|held| held.iter().fold(false, |found, other| found | (hash == *other)));
		// A hash forgotten is refused though one were held, a second guard beside `reload`'s.
		(found & !self.forgotten.contains(&bytes)).then_some(binding).ok_or(Denied)
	}

	fn apply(&mut self, binding: Binding, tokens: Option<&[[u8; 32]]>) {
		let Some(tokens) = tokens else { return };
		if let Some(held) = self.held.get_mut(&binding) {
			let (kept, forgotten): (Vec<_>, Vec<_>) =
				held.drain(..).partition(|hash| tokens.contains(hash));
			*held = kept;
			self.forgotten.extend(forgotten);
		}
	}

	fn end(&mut self, binding: Binding) {
		if let Some(held) = self.held.remove(&binding) {
			self.forgotten.extend(held);
		}
	}
}
