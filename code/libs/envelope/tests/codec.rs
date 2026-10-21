//! The module `contracts` held to the samples of `tests/codec/`, each JSON giving exactly its CBOR
//! and back, each refused one [`envelope::Malformed`].

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

/// What a sample is read as, a type or a call of an interface, by its name.
#[derive(Debug, Clone, Copy)]
enum As<'a> {
	Type(&'a str),
	Call(&'a str),
}

fn read_as<'a>(file: &str, sample: &'a serde_json::Value) -> As<'a> {
	match (sample["type"].as_str(), sample["interface"].as_str()) {
		(Some(name), None) => As::Type(name),
		(None, Some(name)) => As::Call(name),
		_ => panic!("{file}: {sample}: neither a type nor an interface, alone"),
	}
}

type Read<T> = Option<Result<T, envelope::Malformed>>;

fn json_to_cbor(read: As, json: &serde_json::Value) -> Read<codec::Value> {
	match read {
		As::Type(name) => contracts::json_to_cbor(name, json),
		As::Call(name) => contracts::call_json_to_cbor(name, json),
	}
}

fn cbor_to_json(read: As, cbor: &codec::Value) -> Read<serde_json::Value> {
	match read {
		As::Type(name) => contracts::cbor_to_json(name, cbor),
		As::Call(name) => contracts::call_cbor_to_json(name, cbor),
	}
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
		let name = read_as(&file, &sample);
		let json = &sample["json"];
		let bytes = hex(sample["cbor"].as_str().unwrap_or_else(|| panic!("{file}: {sample}: no cbor")));
		let cbor = json_to_cbor(name, json)
			.unwrap_or_else(|| panic!("{file}: {name:?}: none so named"))
			.unwrap_or_else(|m| panic!("{file}: {name:?} {json}: {m:?}"));
		assert_eq!(cbor.encode().unwrap(), bytes, "{file}: {name:?} {json}");
		let read = codec::Value::decode_deterministic(&bytes)
			.unwrap_or_else(|r| panic!("{file}: {name:?}: {r:?}"));
		let back = cbor_to_json(name, &read)
			.unwrap_or_else(|| panic!("{file}: {name:?}: none so named"))
			.unwrap_or_else(|m| panic!("{file}: {name:?} {}: {m:?}", sample["cbor"]));
		assert_eq!(&back, json, "{file}: {name:?} {}", sample["cbor"]);
	}
}

#[test]
fn each_refused_json_is_malformed() {
	let refused = part("refused");
	assert!(!refused.is_empty());
	for (file, sample) in refused {
		let name = read_as(&file, &sample);
		assert_eq!(sample["reason"], "malformed", "{file}: {sample}: a reason this test does not know");
		let json = &sample["json"];
		let read =
			json_to_cbor(name, json).unwrap_or_else(|| panic!("{file}: {name:?}: none so named"));
		assert!(read.is_err(), "{file}: {name:?} {json}: read as {read:?}");
	}
}
