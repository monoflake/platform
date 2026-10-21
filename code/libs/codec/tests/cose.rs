//! [`CoseSign1`] and [`Cwt`] held to cose-wg's examples, their structure alone, as `cose_test.res`
//! is in ReScript.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

mod sample;

use codec::{Cbor, Claims, CoseSign1, Cwt, CwtRefused, Refused, Sign1, Sign1Refused, Value};

const SIGN1_TESTS: &str =
	concat!(env!("CARGO_MANIFEST_DIR"), "/../../../vendor/cose-examples/sign1-tests");
const EDDSA_01: &str = concat!(
	env!("CARGO_MANIFEST_DIR"),
	"/../../../vendor/cose-examples/eddsa-examples/eddsa-sig-01.json"
);
const EDDSA_02: &str = concat!(
	env!("CARGO_MANIFEST_DIR"),
	"/../../../vendor/cose-examples/eddsa-examples/eddsa-sig-02.json"
);
const CWT_A_3: &str =
	concat!(env!("CARGO_MANIFEST_DIR"), "/../../../vendor/cose-examples/CWT/A_3.json");

/// Every Sign1 case by its file's name, each of `sign1-tests/` and the two EdDSA ones.
fn cases() -> Vec<(String, serde_json::Value)> {
	let mut paths: Vec<_> =
		std::fs::read_dir(SIGN1_TESTS).unwrap().map(|e| e.unwrap().path()).collect();
	paths.sort();
	paths.push(EDDSA_01.into());
	paths.push(EDDSA_02.into());
	paths
		.into_iter()
		.map(|p| (p.file_name().unwrap().to_string_lossy().into_owned(), sample::read(&p)))
		.collect()
}

/// Whether a case's upstream changed its output after signing it by `failure`.
fn failed_by(case: &serde_json::Value, failure: &str) -> bool {
	case["input"]["failures"].get(failure).is_some()
}

/// The bytes a case's signature covers, as built from what was decoded of it.
fn to_be_signed(case: &serde_json::Value, sign1: &Sign1) -> Vec<u8> {
	let aad = case["input"]["sign0"].get("external").map(sample::hex_at).unwrap_or_default();
	Sign1::to_be_signed(&sign1.protected, &aad, sign1.payload.as_deref().unwrap())
}

#[test]
fn every_sign1_case_is_read_written_back_and_its_signed_bytes_built() {
	for (name, case) in cases() {
		let bytes = sample::hex_at(&case["output"]["cbor"]);
		if failed_by(&case, "ChangeCBORTag") {
			// sign-fail-01 has a tag other than 18, so it is another message and not a Sign1.
			assert_eq!(Sign1::decode(&bytes), Err(Sign1Refused::Shape), "{name}");
			continue;
		}
		let (sign1, tagged) = Sign1::decode(&bytes).unwrap_or_else(|r| panic!("{name}: {r:?}"));
		assert_eq!(tagged, !failed_by(&case, "RemoveCBORTag"), "{name}");
		assert_eq!(sign1.encode(tagged).unwrap(), bytes, "{name}: written back");
		let expected = sample::hex_at(&case["intermediates"]["ToBeSign_hex"]);
		if case["fail"].as_bool() == Some(true) {
			// sign-fail-02, -03, -04, -06 and -07 change what is signed after signing, so the structure
			// stands and only a signature check catches them.
			assert_ne!(to_be_signed(&case, &sign1), expected, "{name}");
		} else {
			assert_eq!(to_be_signed(&case, &sign1), expected, "{name}");
		}
	}
}

#[test]
fn an_empty_protected_map_is_kept_as_written_and_signed_over_as_no_bytes() {
	// sign-pass-01 carries its protected header as h'a0', and gives what is signed as holding h''.
	let (name, case) = cases().into_iter().find(|(name, _)| name == "sign-pass-01.json").unwrap();
	let (sign1, _) = Sign1::decode(&sample::hex_at(&case["output"]["cbor"])).unwrap();
	assert_eq!(sign1.protected, [0xa0], "{name}");
	assert_eq!(
		to_be_signed(&case, &sign1),
		sample::hex_at(&case["intermediates"]["ToBeSign_hex"]),
		"{name}"
	);
	assert_eq!(Sign1::to_be_signed(&[0xa0], &[], &[]), Sign1::to_be_signed(&[], &[], &[]));
	// Any other map is signed over as written.
	assert_ne!(Sign1::to_be_signed(&[0xbf, 0xff], &[], &[]), Sign1::to_be_signed(&[], &[], &[]));
}

#[test]
fn a_sign1_holds_a_detached_payload_and_empty_protected_bytes() {
	let sign1 =
		Sign1 { protected: Vec::new(), unprotected: Vec::new(), payload: None, signature: vec![1, 2] };
	let written = sign1.encode(false).unwrap();
	assert_eq!(written, [0x84, 0x40, 0xa0, 0xf6, 0x42, 0x01, 0x02]);
	assert_eq!(Sign1::decode(&written), Ok((sign1.clone(), false)));
	let tagged = sign1.encode(true).unwrap();
	assert_eq!(tagged.first(), Some(&0xd2));
	assert_eq!(Sign1::decode(&tagged), Ok((sign1, true)));
	assert_eq!(
		Sign1::to_be_signed(&[], &[], &[]),
		[0x84, 0x6a, b'S', b'i', b'g', b'n', b'a', b't', b'u', b'r', b'e', b'1', 0x40, 0x40, 0x40]
	);
}

#[test]
fn what_is_no_sign1_is_refused() {
	// Three fields; a text where the signature stands; a map's bytes where the map stands.
	assert_eq!(Sign1::decode(&[0x83, 0x40, 0xa0, 0xf6]), Err(Sign1Refused::Shape));
	assert_eq!(Sign1::decode(&[0x84, 0x40, 0xa0, 0xf6, 0x60]), Err(Sign1Refused::Shape));
	assert_eq!(Sign1::decode(&[0x84, 0x40, 0x41, 0xa0, 0xf6, 0x40]), Err(Sign1Refused::Shape));
	assert_eq!(Sign1::decode(&[0x84, 0x40]), Err(Sign1Refused::Cbor(Refused::Truncated)));
	// Protected bytes that are no map, a map and more, a map cut short, and a map not valid.
	for protected in [&[0x00][..], &[0xa0, 0x00], &[0xa1, 0x01], &[0xa2, 0x01, 0x00, 0x01, 0x00]] {
		let sign1 = Sign1 {
			protected: protected.to_vec(),
			unprotected: Vec::new(),
			payload: None,
			signature: Vec::new(),
		};
		assert_eq!(Sign1::decode(&sign1.encode(true).unwrap()), Err(Sign1Refused::Shape));
	}
	// A map written as 4.2.1 would not write it is still a map.
	let sign1 = Sign1 {
		protected: vec![0xbf, 0x01, 0x00, 0xff],
		unprotected: Vec::new(),
		payload: None,
		signature: Vec::new(),
	};
	assert_eq!(Sign1::decode(&sign1.encode(false).unwrap()), Ok((sign1, false)));
}

#[test]
fn a_cwt_is_read_with_its_claims_under_tags_61_and_18_or_18_alone() {
	let case = sample::read(CWT_A_3);
	let bytes = sample::hex_at(&case["output"]["cbor"]);
	let Value::Map(expected) =
		Value::decode(&sample::hex_at(&case["input"]["plaintext_hex"])).unwrap()
	else {
		panic!("A_3's plaintext is no map");
	};
	let (sign1, claims) = Claims::decode(&bytes).unwrap();
	assert_eq!(claims, Claims(expected));
	assert_eq!(claims.payload().unwrap(), sign1.payload.clone().unwrap());
	assert_eq!(
		Sign1::to_be_signed(&sign1.protected, &[], &claims.payload().unwrap()),
		sample::hex_at(&case["intermediates"]["ToBeSign_hex"])
	);
	let under_61 = [&[0xd8, 0x3d][..], &bytes].concat();
	assert_eq!(Claims::decode(&under_61), Ok((sign1, claims)));
	// Tag 61 over a Sign1 that is not under its own tag 18.
	let untagged = bytes.get(1..).unwrap();
	assert_eq!(
		Claims::decode(&[&[0xd8, 0x3d][..], untagged].concat()),
		Err(CwtRefused::Sign1(Sign1Refused::Shape))
	);
}

#[test]
fn what_carries_no_claims_is_refused() {
	let sign = |payload: Option<Vec<u8>>| {
		Sign1 { protected: Vec::new(), unprotected: Vec::new(), payload, signature: Vec::new() }
			.encode(true)
			.unwrap()
	};
	assert_eq!(Claims::decode(&sign(None)), Err(CwtRefused::Detached));
	assert_eq!(Claims::decode(&sign(Some(vec![0x01]))), Err(CwtRefused::Unclaimed));
	assert_eq!(Claims::decode(&sign(Some(vec![0x18]))), Err(CwtRefused::Payload(Refused::Truncated)));
	assert_eq!(
		Claims::decode(&sign(Some(vec![0xa0]))).map(|(_, claims)| claims),
		Ok(Claims(Vec::new()))
	);
	assert_eq!(Claims::decode(&[0xd8, 0x3d, 0x00]), Err(CwtRefused::Sign1(Sign1Refused::Shape)));
}
