//! The module `contracts` held to the samples of `tests/codec/`, read as they stand: each sample's
//! JSON read as its type gives exactly its CBOR, as codec writes it, and that CBOR read back gives
//! exactly its JSON; each refused JSON is [`envelope::Malformed`].

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

use codec::Cbor;
use envelope::contracts;

const SAMPLES: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tests/codec");

/// Every file of the samples, by its path, in the order of their names.
fn files() -> Vec<std::path::PathBuf> {
	let mut files: Vec<_> = std::fs::read_dir(SAMPLES)
		.unwrap_or_else(|e| panic!("{SAMPLES}: {e}"))
		.map(|entry| entry.unwrap().path())
		.filter(|path| path.extension().is_some_and(|e| e == "json"))
		.collect();
	files.sort();
	assert!(!files.is_empty(), "{SAMPLES}: no samples");
	files
}

/// A file's list `part`, `samples` or `refused`, each with the file's name for what it reports.
fn part(part: &str) -> Vec<(String, serde_json::Value)> {
	files()
		.into_iter()
		.flat_map(|path| {
			let text =
				std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
			let file: serde_json::Value =
				serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
			let name = path.file_name().unwrap().to_string_lossy().into_owned();
			let items = file[part].as_array().unwrap_or_else(|| panic!("{name}: no {part}")).clone();
			items.into_iter().map(move |item| (name.clone(), item))
		})
		.collect()
}

/// The bytes a hex string spells.
fn hex(text: &str) -> Vec<u8> {
	assert!(text.len().is_multiple_of(2), "{text}: an odd number of digits");
	(0..text.len()).step_by(2).map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap()).collect()
}

#[test]
fn each_sample_is_its_cbor_from_its_json_and_its_json_from_its_cbor() {
	let samples = part("samples");
	assert!(!samples.is_empty());
	for (file, sample) in samples {
		let name = sample["type"].as_str().unwrap_or_else(|| panic!("{file}: {sample}: no type"));
		let json = &sample["json"];
		let bytes = hex(sample["cbor"].as_str().unwrap_or_else(|| panic!("{file}: {sample}: no cbor")));
		let cbor = contracts::json_to_cbor(name, json)
			.unwrap_or_else(|| panic!("{file}: {name}: no such type"))
			.unwrap_or_else(|m| panic!("{file}: {name} {json}: {m:?}"));
		assert_eq!(cbor.encode().unwrap(), bytes, "{file}: {name} {json}");
		let read = codec::Value::decode_deterministic(&bytes)
			.unwrap_or_else(|r| panic!("{file}: {name}: {r:?}"));
		let back = contracts::cbor_to_json(name, &read)
			.unwrap_or_else(|| panic!("{file}: {name}: no such type"))
			.unwrap_or_else(|m| panic!("{file}: {name} {}: {m:?}", sample["cbor"]));
		assert_eq!(&back, json, "{file}: {name} {}", sample["cbor"]);
	}
}

#[test]
fn each_refused_json_is_malformed() {
	let refused = part("refused");
	assert!(!refused.is_empty());
	for (file, sample) in refused {
		let name = sample["type"].as_str().unwrap_or_else(|| panic!("{file}: {sample}: no type"));
		assert_eq!(sample["reason"], "malformed", "{file}: {sample}: a reason this test does not know");
		let json = &sample["json"];
		let read =
			contracts::json_to_cbor(name, json).unwrap_or_else(|| panic!("{file}: {name}: no such type"));
		assert!(read.is_err(), "{file}: {name} {json}: read as {read:?}");
	}
}
