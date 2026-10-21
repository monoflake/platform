//! [`Features`] held to `tests/compat/features.json`, read as it stands. `features_test.res` beside
//! it is the same in ReScript.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

mod sample;

use compat::{Featured, Features, Malformed, Missing};

const FEATURES: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tests/compat/features.json");

/// The names a JSON array holds.
fn names(value: &serde_json::Value) -> Vec<&str> {
	sample::items(value)
		.iter()
		.map(|n| n.as_str().unwrap_or_else(|| panic!("{n}: no name")))
		.collect()
}

/// A sample's `{has, needs}`, as features or why not.
fn features(value: &serde_json::Value) -> Result<Features, Malformed> {
	Features::new(&names(&value["has"]), &names(&value["needs"]))
}

/// The names a JSON array holds, owned.
fn owned(value: &serde_json::Value) -> Vec<String> {
	names(value).into_iter().map(str::to_owned).collect()
}

#[test]
fn every_side_is_made_sorted_once_as_its_sample_says() {
	for case in sample::items(&sample::read(FEATURES)["made"]) {
		let made = features(case).unwrap_or_else(|m| panic!("{case}: {m:?}"));
		assert_eq!(made.has(), owned(&case["made"]["has"]), "{case}");
		assert_eq!(made.needs(), owned(&case["made"]["needs"]), "{case}");
	}
}

#[test]
fn every_side_is_refused_by_its_first_name_as_its_sample_says() {
	for case in sample::items(&sample::read(FEATURES)["unmade"]) {
		let malformed = &case["malformed"];
		let expected = match (malformed.get("name"), malformed.get("unheld")) {
			(Some(name), None) => Malformed::Name(name.as_str().unwrap().to_owned()),
			(None, Some(name)) => Malformed::Unheld(name.as_str().unwrap().to_owned()),
			_ => panic!("{case}: neither name nor unheld"),
		};
		assert_eq!(features(case), Err(expected), "{case}");
	}
}

#[test]
fn every_two_sides_agree_or_miss_as_their_sample_says() {
	for case in sample::items(&sample::read(FEATURES)["agreed"]) {
		let first = features(&case["first"]).unwrap();
		let second = features(&case["second"]).unwrap();
		let expected = match (case.get("agreed"), case.get("missing")) {
			(Some(agreed), None) => Ok(owned(agreed)),
			(None, Some(missing)) => {
				Err(Missing { first: owned(&missing["first"]), second: owned(&missing["second"]) })
			}
			_ => panic!("{case}: neither agreed nor missing"),
		};
		assert_eq!(first.agreed(&second), expected, "{case}");
	}
}
