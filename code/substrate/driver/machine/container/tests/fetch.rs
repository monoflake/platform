//! `Https` fetching a `file:` address, copied, hashed and bounded, only a regular file in the named
//! directory through no link.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

use std::path::{Path, PathBuf};

use driver_machine_container::{Fetch, Https, Unfetched};
use sha2::{Digest, Sha256};

/// A directory of the test's own, holding `served/`, the one `file:` addresses may name.
fn place(test: &str) -> (PathBuf, Https) {
	let place = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("fetch").join(test);
	// What an earlier run left is not this run's.
	let _ = std::fs::remove_dir_all(&place);
	std::fs::create_dir_all(place.join("served/deep")).unwrap();
	let https = Https { local: Some(place.join("served")) };
	(place, https)
}

fn address(path: &Path) -> String {
	format!("file://{}", path.display())
}

/// Refused as the interface has it, unfetchable with a message naming no path.
fn refused(fetched: Result<[u8; 32], Unfetched>, place: &Path) {
	match fetched {
		Err(Unfetched::Unfetchable(why)) => {
			assert!(!why.contains(&*place.to_string_lossy()), "a path told back: {why}");
			assert!(!why.contains("No such file"), "a system error told back: {why}");
		}
		other => panic!("expected unfetchable, got {other:?}"),
	}
}

#[tokio::test]
async fn a_file_is_fetched_whole_and_hashed() {
	let (place, https) = place("whole");
	let bytes: Vec<u8> = (0..200_000u32).map(|n| n.to_le_bytes()[0]).collect();
	let served = place.join("served/deep/image.tar");
	std::fs::write(&served, &bytes).unwrap();
	let into = place.join("kept/fetched.tar");
	for address in [address(&served), format!("file:{}", served.display())] {
		let hash = https.fetch(&address, &into, 1 << 20).await.unwrap();
		assert_eq!(hash, <[u8; 32]>::from(Sha256::digest(&bytes)));
		assert_eq!(std::fs::read(&into).unwrap(), bytes);
	}
}

#[tokio::test]
async fn a_file_past_the_bound_is_too_large() {
	let (place, https) = place("large");
	let served = place.join("served/image.tar");
	std::fs::write(&served, [7u8; 1025]).unwrap();
	let into = place.join("fetched.tar");
	assert_eq!(https.fetch(&address(&served), &into, 1024).await, Err(Unfetched::TooLarge));
	assert!(https.fetch(&address(&served), &into, 1025).await.is_ok());
}

#[tokio::test]
async fn nothing_outside_the_directory_is_fetched() {
	let (place, https) = place("outside");
	let outside = place.join("secret.tar");
	std::fs::write(&outside, b"not to be read").unwrap();
	std::os::unix::fs::symlink(&outside, place.join("served/link.tar")).unwrap();
	std::os::unix::fs::symlink(&place, place.join("served/up")).unwrap();
	let into = place.join("fetched.tar");
	for named in [
		outside.clone(),
		place.join("served/../secret.tar"),
		place.join("served/link.tar"),
		place.join("served/up/secret.tar"),
		place.join("served/deep"),
		place.join("served/missing.tar"),
	] {
		refused(https.fetch(&address(&named), &into, 1024).await, &place);
	}
	assert!(!into.exists());
}

#[tokio::test]
async fn a_file_address_is_refused_where_no_directory_is_named() {
	let (place, _) = place("unnamed");
	let served = place.join("served/image.tar");
	std::fs::write(&served, b"image").unwrap();
	let https = Https { local: None };
	refused(https.fetch(&address(&served), &place.join("fetched.tar"), 1024).await, &place);
}

#[tokio::test]
async fn an_address_of_another_scheme_is_unfetchable() {
	let (place, https) = place("scheme");
	for address in ["ftp://artifacts.invalid/x.tar", "http://localhost:9/x.tar"] {
		refused(https.fetch(address, &place.join("fetched.tar"), 1024).await, &place);
	}
}
