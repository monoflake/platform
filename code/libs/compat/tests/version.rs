//! [`Version`] and [`Range`] held to `tests/compat/versions.json` and `written.json`, read as they
//! stand. `version_test.res` beside it is the same in ReScript.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

mod sample;

use compat::{MAX, Range, Ranged, Refused, Unchosen, Version, Versioned};

const VERSIONS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tests/compat/versions.json");
const WRITTEN: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tests/compat/written.json");

/// A JSON number as a version, none where it is negative, fractional or above [`MAX`].
fn version(value: &serde_json::Value) -> Option<Version> {
	value.as_u64().and_then(Version::new)
}

/// A version that must be one.
fn made(value: &serde_json::Value) -> Version {
	version(value).unwrap_or_else(|| panic!("{value}: no version"))
}

/// A sample's `[lowest, highest]`, as a range or none.
fn range(value: &serde_json::Value) -> Option<Range> {
	let bounds = sample::items(value);
	assert_eq!(bounds.len(), 2, "{value}: no pair");
	Range::new(made(&bounds[0]), made(&bounds[1]))
}

#[test]
fn every_number_is_a_version_or_not_as_its_sample_says() {
	let versions = sample::read(VERSIONS);
	for number in sample::items(&versions["made"]) {
		assert_eq!(made(number).get(), number.as_u64().unwrap(), "{number}");
	}
	for number in sample::items(&versions["unmade"]) {
		assert_eq!(version(number), None, "{number}");
	}
	assert_eq!(Version::new(MAX).map(Version::get), Some(MAX));
	assert_eq!(Version::new(MAX + 1), None);
}

#[test]
fn every_range_is_made_or_not_as_its_sample_says() {
	let versions = sample::read(VERSIONS);
	for pair in sample::items(&versions["ranges"]["made"]) {
		let range = range(pair).unwrap_or_else(|| panic!("{pair}: unmade"));
		assert_eq!(range.lowest(), made(&pair[0]), "{pair}");
		assert_eq!(range.highest(), made(&pair[1]), "{pair}");
	}
	for pair in sample::items(&versions["ranges"]["unmade"]) {
		assert_eq!(range(pair), None, "{pair}");
	}
}

#[test]
fn every_read_is_read_or_refused_as_its_sample_says() {
	let versions = sample::read(VERSIONS);
	for case in sample::items(&versions["reads"]) {
		let range = range(&case["range"]).unwrap();
		let version = made(&case["version"]);
		let expected = match case.get("refused").map(|r| r.as_str().unwrap()) {
			None => Ok(()),
			Some("older") => Err(Refused::Older { version, range }),
			Some("newer") => Err(Refused::Newer { version, range }),
			Some(other) => panic!("{case}: refused as {other}"),
		};
		assert_eq!(range.reads(version), expected, "{case}");
	}
}

#[test]
fn every_case_writes_its_version_or_none_as_its_sample_says() {
	for case in sample::items(&sample::read(WRITTEN)["cases"]) {
		let what = &case["what"];
		let ranges: Vec<Range> =
			sample::items(&case["ranges"]).iter().map(|r| range(r).unwrap()).collect();
		let expected = match (case.get("written"), case.get("unchosen")) {
			(Some(written), None) => Ok(made(written)),
			(None, Some(unchosen)) if unchosen.as_str() == Some("empty") => Err(Unchosen::Empty),
			(None, Some(unchosen)) => Err(Unchosen::Apart {
				highest: made(&unchosen["highest"]),
				above: sample::items(&unchosen["above"])
					.iter()
					.map(|at| usize::try_from(at.as_u64().unwrap()).unwrap())
					.collect(),
			}),
			_ => panic!("{what}: neither written nor unchosen"),
		};
		assert_eq!(Range::written(&ranges), expected, "{what}");
	}
}
