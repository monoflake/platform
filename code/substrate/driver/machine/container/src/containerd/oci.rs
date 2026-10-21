//! What an image's index, manifest and configuration say, as the OCI image specification writes
//! them. https://github.com/opencontainers/image-spec/blob/main/spec.md

use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::{Fault, ImageConfig};

const INDEXES: [&str; 2] = [
	"application/vnd.oci.image.index.v1+json",
	"application/vnd.docker.distribution.manifest.list.v2+json",
];
const MANIFESTS: [&str; 2] = [
	"application/vnd.oci.image.manifest.v1+json",
	"application/vnd.docker.distribution.manifest.v2+json",
];

/// The platform an image is chosen for, as OCI names it.
pub(super) struct Platform {
	pub(super) os: &'static str,
	pub(super) architecture: &'static str,
}

impl Platform {
	/// This machine's.
	pub(super) fn here() -> Self {
		let architecture = match std::env::consts::ARCH {
			"x86_64" => "amd64",
			"aarch64" => "arm64",
			other => other,
		};
		Self { os: "linux", architecture }
	}
}

/// What a blob is, by its media type.
pub(super) enum Kind {
	Index,
	Manifest,
}

pub(super) fn kind(media_type: &str) -> Option<Kind> {
	if INDEXES.contains(&media_type) {
		Some(Kind::Index)
	} else if MANIFESTS.contains(&media_type) {
		Some(Kind::Manifest)
	} else {
		None
	}
}

/// A descriptor's media type and digest.
pub(super) struct Descriptor {
	pub(super) media_type: String,
	pub(super) digest: String,
}

fn text<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
	value.get(key).and_then(Value::as_str)
}

fn descriptor(value: &Value) -> Option<Descriptor> {
	Some(Descriptor {
		media_type: text(value, "mediaType")?.to_owned(),
		digest: text(value, "digest")?.to_owned(),
	})
}

/// The manifest of an index the platform runs, one naming it or the one image an index holds
/// without a platform.
pub(super) fn chosen(index: &Value, platform: &Platform) -> Result<Descriptor, Fault> {
	let manifests =
		index.get("manifests").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();
	let named = manifests.iter().find(|m| {
		m.get("platform").is_some_and(|p| {
			text(p, "os") == Some(platform.os) && text(p, "architecture") == Some(platform.architecture)
		})
	});
	let attestation = |m: &&Value| {
		m.get("annotations").and_then(|a| text(a, "vnd.docker.reference.type"))
			== Some("attestation-manifest")
	};
	let unnamed =
		|| manifests.iter().filter(|m| m.get("platform").is_none()).find(|m| !attestation(m));
	named.or_else(unnamed).and_then(descriptor).ok_or_else(|| {
		Fault(format!("the image holds nothing for {}/{}", platform.os, platform.architecture))
	})
}

/// A manifest's configuration, by its descriptor.
pub(super) fn config_of(manifest: &Value) -> Result<Descriptor, Fault> {
	manifest
		.get("config")
		.and_then(descriptor)
		.ok_or_else(|| Fault("a manifest names no configuration".into()))
}

fn strings(value: Option<&Value>) -> Vec<String> {
	value
		.and_then(Value::as_array)
		.map_or_else(Vec::new, |a| a.iter().filter_map(Value::as_str).map(str::to_owned).collect())
}

/// What an image's configuration says it runs.
pub(super) fn image_config(config: &Value) -> ImageConfig {
	let runs = config.get("config");
	let field = |key: &str| runs.and_then(|r| r.get(key));
	let set =
		|key: &str| field(key).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_owned);
	ImageConfig {
		entrypoint: strings(field("Entrypoint")),
		cmd: strings(field("Cmd")),
		env: strings(field("Env")),
		working_dir: set("WorkingDir"),
		user: set("User"),
	}
}

/// The chain id of each layer bottom up from `rootfs.diff_ids`, each after the digest of the one
/// below.
/// https://github.com/opencontainers/image-spec/blob/main/config.md#layer-chainid
pub(super) fn chain_ids(config: &Value) -> Result<Vec<String>, Fault> {
	let diffs = strings(config.get("rootfs").and_then(|r| r.get("diff_ids")));
	if diffs.is_empty() {
		return Err(Fault("an image's configuration names no layers".into()));
	}
	let mut chain: Vec<String> = Vec::with_capacity(diffs.len());
	for diff in diffs {
		let next = match chain.last() {
			None => diff,
			Some(below) => {
				let digest = Sha256::digest(format!("{below} {diff}").as_bytes());
				let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
				format!("sha256:{hex}")
			}
		};
		chain.push(next);
	}
	Ok(chain)
}

/// `tests/images/` holds alpine 3.22.6's and prometheus v3.5.0's linux/amd64 configurations as
/// their registries serve them, formatted.
#[cfg(test)]
mod tests {
	use super::*;
	use serde_json::json;

	fn alpine() -> Value {
		serde_json::from_str(include_str!("../../tests/images/alpine.json")).unwrap()
	}

	#[test]
	fn a_real_configuration_is_read() {
		let config = image_config(&alpine());
		assert!(config.entrypoint.is_empty());
		assert_eq!(config.cmd, ["/bin/sh"]);
		assert!(config.env.iter().any(|e| e.starts_with("PATH=")));
		assert_eq!(config.working_dir.as_deref(), Some("/"));
		assert_eq!(config.user, None);
	}

	#[test]
	fn one_layer_is_its_own_chain() {
		let config = alpine();
		let chain = chain_ids(&config).unwrap();
		assert_eq!(chain.len(), 1);
		assert_eq!(Some(&json!(chain[0])), config["rootfs"]["diff_ids"].get(0));
	}

	#[test]
	fn a_configuration_naming_its_user_and_entrypoint_is_read() {
		let config: Value =
			serde_json::from_str(include_str!("../../tests/images/prometheus.json")).unwrap();
		let read = image_config(&config);
		assert_eq!(read.entrypoint, ["/bin/prometheus"]);
		assert_eq!(
			read.cmd,
			["--config.file=/etc/prometheus/prometheus.yml", "--storage.tsdb.path=/prometheus"]
		);
		assert_eq!(read.working_dir.as_deref(), Some("/prometheus"));
		assert_eq!(read.user.as_deref(), Some("nobody"));
		// Computed apart from this code, by Python's hashlib over the same diff ids.
		let top = "sha256:bf1e29ec4903804e5a792ce62d8f03bfc3791262eb4627d4e70bbabe08e00b2b";
		assert_eq!(chain_ids(&config).unwrap().last().map(String::as_str), Some(top));
	}

	#[test]
	fn layers_chain_by_their_digests() {
		// The image specification's own example.
		let config = json!({ "rootfs": { "diff_ids": ["sha256:a", "sha256:b", "sha256:c"] } });
		let chain = chain_ids(&config).unwrap();
		let hex = |text: &str| -> String {
			Sha256::digest(text.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
		};
		let two = format!("sha256:{}", hex("sha256:a sha256:b"));
		let three = format!("sha256:{}", hex(&format!("{two} sha256:c")));
		assert_eq!(chain, ["sha256:a".to_owned(), two, three]);
	}

	#[test]
	fn the_platform_named_is_chosen_and_an_attestation_never() {
		let here = Platform { os: "linux", architecture: "amd64" };
		let index = json!({ "manifests": [
			{ "mediaType": MANIFESTS[0], "digest": "sha256:arm", "platform": { "os": "linux", "architecture": "arm64" } },
			{ "mediaType": MANIFESTS[0], "digest": "sha256:amd", "platform": { "os": "linux", "architecture": "amd64" } },
		]});
		assert_eq!(chosen(&index, &here).unwrap().digest, "sha256:amd");
		let unnamed = json!({ "manifests": [
			{ "mediaType": MANIFESTS[0], "digest": "sha256:att",
				"annotations": { "vnd.docker.reference.type": "attestation-manifest" } },
			{ "mediaType": MANIFESTS[0], "digest": "sha256:one" },
		]});
		assert_eq!(chosen(&unnamed, &here).unwrap().digest, "sha256:one");
		assert!(chosen(&json!({ "manifests": [] }), &here).is_err());
	}
}
