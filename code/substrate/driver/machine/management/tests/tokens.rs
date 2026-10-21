//! A binding's tokens taken from their files, checked as a call's header carries them, replaced and
//! forgotten, RFC 3d3nt.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

use driver_machine_management::{Binding, Denied, Hold, Tokens, Unread};
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// A directory of its own under the system's temporary one, removed when dropped.
struct Directory(PathBuf);

impl Directory {
	fn new(name: &str) -> Self {
		let nanos = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
		let path = std::env::temp_dir().join(format!("tokens-{name}-{}-{nanos}", std::process::id()));
		fs::create_dir_all(&path).unwrap();
		Self(path)
	}

	/// The file `name` in it, holding `text`.
	fn write(&self, name: &str, text: &str) -> PathBuf {
		let path = self.0.join(name);
		fs::write(&path, text).unwrap();
		path
	}
}

impl Drop for Directory {
	fn drop(&mut self) {
		let _ = fs::remove_dir_all(&self.0);
	}
}

/// Bytes in unpadded base64url.
fn base64url(bytes: &[u8]) -> String {
	let mut text = String::new();
	for chunk in bytes.chunks(3) {
		let word = chunk
			.iter()
			.enumerate()
			.fold(0u32, |word, (index, byte)| word | u32::from(*byte) << (16 - 8 * index));
		for index in 0..=chunk.len() {
			text.push(char::from(ALPHABET[usize::try_from(word >> (18 - 6 * index) & 63).unwrap()]));
		}
	}
	text
}

/// A secret of 32 bytes, each `seed`.
fn secret(seed: u8) -> [u8; 32] {
	[seed; 32]
}

/// The token of `binding` with that secret.
fn token(binding: Binding, seed: u8) -> String {
	format!("{binding}.{}", base64url(&secret(seed)))
}

/// The header a call carries that token in.
fn bearer(binding: Binding, seed: u8) -> String {
	format!("Bearer {}", token(binding, seed))
}

/// The hash a driver keeps of that secret.
fn hash(seed: u8) -> [u8; 32] {
	*blake3::hash(&secret(seed)).as_bytes()
}

/// Tokens taken from one file for each `(binding, seed)`, every file read whole.
fn held(directory: &Directory, tokens: &[(Binding, u8)]) -> (Tokens, Vec<PathBuf>) {
	let files: Vec<PathBuf> = tokens
		.iter()
		.map(|(binding, seed)| directory.write(&format!("{binding}-{seed}"), &token(*binding, *seed)))
		.collect();
	let mut held = Tokens::default();
	assert_eq!(held.reload(&files), vec![]);
	(held, files)
}

#[test]
fn the_encoding_here_is_base64url_unpadded() {
	let bytes: Vec<u8> = (0..32).collect();
	assert_eq!(base64url(&bytes), "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8");
	assert_eq!(base64url(&secret(0xff)), format!("{}8", "_".repeat(42)));
}

#[test]
fn a_call_with_a_token_held_is_for_its_binding() {
	let directory = Directory::new("good");
	let (tokens, _) = held(&directory, &[(7, 1), (1_000_000, 2)]);
	assert_eq!(tokens.check(Some(&bearer(7, 1))), Ok(7));
	assert_eq!(tokens.check(Some(&bearer(1_000_000, 2))), Ok(1_000_000));
	assert_eq!(tokens.check(Some(&format!("bearer {}", token(7, 1)))), Ok(7));
}

#[test]
fn a_token_absent_malformed_not_matching_or_of_no_binding_is_denied_alike() {
	let directory = Directory::new("denied");
	let (tokens, _) = held(&directory, &[(7, 1)]);
	let good = token(7, 1);
	let denied = [
		None,
		Some(String::new()),
		Some(good.clone()),
		Some("Bearer".to_owned()),
		Some("Bearer ".to_owned()),
		Some(format!("Basic {good}")),
		Some(format!("Bearer  {good}")),
		Some(format!("Bearer {good} ")),
		Some(format!("Bearer {good}\n")),
		Some(format!("Bearer {good}A")),
		Some(format!("Bearer {}", &good[..good.len() - 1])),
		Some(format!("Bearer 07.{}", base64url(&secret(1)))),
		Some(format!("Bearer +7.{}", base64url(&secret(1)))),
		Some(format!("Bearer .{}", base64url(&secret(1)))),
		Some(format!("Bearer 7{}", base64url(&secret(1)))),
		Some(format!("Bearer 7.{}=", base64url(&secret(1)))),
		Some(format!("Bearer 7.{}", base64url(&secret(1)).replace('B', "+"))),
		Some(format!("Bearer 4294967296.{}", base64url(&secret(1)))),
		// The last character's spare bits set, a second text of the same secret.
		Some(format!("Bearer 7.{}B", "A".repeat(42))),
		Some(bearer(7, 2)),
		Some(bearer(8, 1)),
	];
	for header in &denied {
		assert_eq!(tokens.check(header.as_deref()), Err(Denied), "{header:?}");
	}
}

#[test]
fn a_second_token_beside_the_first_works_with_it() {
	let directory = Directory::new("second");
	let (mut tokens, mut files) = held(&directory, &[(7, 1)]);
	files.push(directory.write("7-new", &token(7, 2)));
	assert_eq!(tokens.reload(&files), vec![]);
	assert_eq!(tokens.check(Some(&bearer(7, 1))), Ok(7));
	assert_eq!(tokens.check(Some(&bearer(7, 2))), Ok(7));
}

#[test]
fn an_apply_naming_only_the_new_hash_forgets_the_old_token() {
	let directory = Directory::new("replace");
	let (mut tokens, _) = held(&directory, &[(7, 1), (7, 2), (8, 3)]);
	tokens.apply(7, Some(&[hash(2)]));
	assert_eq!(tokens.check(Some(&bearer(7, 1))), Err(Denied));
	assert_eq!(tokens.check(Some(&bearer(7, 2))), Ok(7));
	assert_eq!(tokens.check(Some(&bearer(8, 3))), Ok(8));
}

#[test]
fn a_token_forgotten_stays_forgotten_though_its_file_stands() {
	let directory = Directory::new("forgotten");
	let (mut tokens, files) = held(&directory, &[(7, 1), (7, 2), (8, 3), (8, 4)]);
	tokens.apply(7, Some(&[hash(2)]));
	tokens.end(8);
	assert_eq!(tokens.reload(&files), vec![]);
	assert_eq!(tokens.check(Some(&bearer(7, 1))), Err(Denied));
	assert_eq!(tokens.check(Some(&bearer(8, 3))), Err(Denied));
	assert_eq!(tokens.check(Some(&bearer(8, 4))), Err(Denied));
	assert_eq!(tokens.check(Some(&bearer(7, 2))), Ok(7));
	// A token never seen still comes in beside them, as a binding's next one does.
	let next = directory.write("8-next", &token(8, 5));
	assert_eq!(tokens.reload(&[next]), vec![]);
	assert_eq!(tokens.check(Some(&bearer(8, 5))), Ok(8));
	// A forgotten hash is still held only where two bindings share a secret, and `check` refuses it.
	let (mut shared, _) = held(&directory, &[(10, 6), (11, 6)]);
	assert_eq!(shared.check(Some(&bearer(11, 6))), Ok(11));
	shared.end(10);
	assert_eq!(shared.check(Some(&bearer(10, 6))), Err(Denied));
	assert_eq!(shared.check(Some(&bearer(11, 6))), Err(Denied));
}

#[test]
fn an_apply_without_tokens_leaves_both() {
	let directory = Directory::new("unnamed");
	let (mut tokens, _) = held(&directory, &[(7, 1), (7, 2)]);
	let before = tokens.clone();
	tokens.apply(7, None);
	assert_eq!(tokens, before);
	assert_eq!(tokens.check(Some(&bearer(7, 1))), Ok(7));
	assert_eq!(tokens.check(Some(&bearer(7, 2))), Ok(7));
}

#[test]
fn a_file_removed_keeps_its_token_working() {
	let directory = Directory::new("removed");
	let (mut tokens, files) = held(&directory, &[(7, 1)]);
	fs::remove_file(&files[0]).unwrap();
	let unread = tokens.reload(&files);
	assert!(matches!(&unread[..], [Unread::Missing { file, .. }] if *file == files[0]));
	assert_eq!(tokens.reload(&[]), vec![]);
	assert_eq!(tokens.check(Some(&bearer(7, 1))), Ok(7));
}

#[test]
fn a_reload_takes_a_file_new_since() {
	let directory = Directory::new("reload");
	let (mut tokens, mut files) = held(&directory, &[(7, 1)]);
	assert_eq!(tokens.check(Some(&bearer(9, 3))), Err(Denied));
	files.push(directory.write("9", &format!("{}\n", token(9, 3))));
	assert_eq!(tokens.reload(&files), vec![]);
	assert_eq!(tokens.check(Some(&bearer(9, 3))), Ok(9));
	assert_eq!(tokens.check(Some(&bearer(7, 1))), Ok(7));
}

#[test]
fn a_file_not_read_or_not_a_token_is_answered_and_the_rest_taken() {
	let directory = Directory::new("unread");
	let missing = directory.0.join("absent");
	let spoiled = [
		directory.write("empty", ""),
		directory.write("two-newlines", &format!("{}\n\n", token(5, 1))),
		directory.write("crlf", &format!("{}\r\n", token(5, 2))),
		directory.write("two-tokens", &format!("{}\n{}\n", token(5, 3), token(5, 4))),
		directory.write("padded", &format!("{}=", token(5, 5))),
	];
	let good = directory.write("good", &token(6, 1));
	let mut files = vec![missing.clone()];
	files.extend(spoiled.iter().cloned());
	files.push(good);
	let mut tokens = Tokens::default();
	let unread = tokens.reload(&files);
	assert_eq!(unread.len(), 1 + spoiled.len());
	assert!(matches!(&unread[0], Unread::Missing { file, .. } if *file == missing));
	for (answer, path) in unread[1..].iter().zip(&spoiled) {
		match answer {
			Unread::Malformed { file, line, expected } => {
				assert_eq!(file, path);
				assert_eq!(*line, 1);
				assert!(expected.contains("<id>.<secret>"));
			}
			other => panic!("expected {} malformed, got {other:?}", path.display()),
		}
	}
	assert_eq!(tokens.check(Some(&bearer(6, 1))), Ok(6));
	for seed in 1..=5 {
		assert_eq!(tokens.check(Some(&bearer(5, seed))), Err(Denied));
	}
}

#[test]
fn a_token_read_twice_is_held_once() {
	let directory = Directory::new("twice");
	let (mut tokens, files) = held(&directory, &[(7, 1)]);
	let copy = directory.write("copy", &token(7, 1));
	let before = tokens.clone();
	assert_eq!(tokens.reload(&[files[0].clone(), copy]), vec![]);
	assert_eq!(tokens, before);
}

#[test]
fn an_end_forgets_every_token_of_its_binding_alone() {
	let directory = Directory::new("end");
	let (mut tokens, _) = held(&directory, &[(7, 1), (7, 2), (8, 3)]);
	tokens.end(7);
	assert_eq!(tokens.check(Some(&bearer(7, 1))), Err(Denied));
	assert_eq!(tokens.check(Some(&bearer(7, 2))), Err(Denied));
	assert_eq!(tokens.check(Some(&bearer(8, 3))), Ok(8));
}

#[test]
fn nothing_held_denies_every_call() {
	assert_eq!(Tokens::default().check(Some(&bearer(0, 0))), Err(Denied));
}
