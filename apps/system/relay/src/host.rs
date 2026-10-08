//! Reading this node's host: its events, its apps and the machine, with the read-only token. Each
//! answer is host's envelope, opened in `opened` alone. The shapes are infra's
//! `apps/deploy/host/src/store.rs` and `api.rs`.

use bytes::Bytes;
use http_body_util::{BodyExt, Empty};
use hyper::Request;
use hyper::header::AUTHORIZATION;
use hyper_util::client::legacy::Client;
use hyper_util::client::legacy::connect::HttpConnector;
use hyper_util::rt::TokioExecutor;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

/// The newest page of host's events, as many as its panel shows.
const EVENTS: &str = "/api/events?limit=50";
const APPS: &str = "/api/apps";
const MACHINE: &str = "/api/node/now";

/// Longer than any of the three takes on a node that is well, shorter than a round.
const PATIENCE: Duration = Duration::from_secs(5);

#[derive(Debug, thiserror::Error)]
pub enum ReadError {
	/// A token holding what a header cannot, such as a line break.
	#[error("the request to host could not be formed: {0}")]
	Unformed(#[from] hyper::http::Error),
	#[error("host did not answer: {0}")]
	Unreachable(#[from] hyper_util::client::legacy::Error),
	#[error("host's answer broke off: {0}")]
	Broken(#[from] hyper::Error),
	#[error("host did not answer within {0:?}")]
	Slow(Duration),
	#[error("host refused with `{code}`: {message}")]
	Refused { code: String, message: String },
	#[error("host answered what this relay cannot read: {0}")]
	Malformed(#[from] serde_json::Error),
}

/// One row of host's events, as the console needs it. A row's words -- `deploy`, `running`,
/// `loading` -- are host's to add to, so they pass on as words rather than as a closed set.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Event {
	pub id: i64,
	pub app: String,
	pub action: String,
	pub source: Source,
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub image: Option<String>,
	pub outcome: String,
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub stage: Option<String>,
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub detail: Option<String>,
	pub started_at: String,
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub finished_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Source {
	pub kind: String,
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub run: Option<u64>,
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub commit: Option<String>,
}

/// An app as it runs, without its declaration, which is long and changes only with a deploy.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(from = "Shown")]
pub struct App {
	pub name: String,
	pub image: String,
	pub deployed_at: String,
	pub running: bool,
	pub held: bool,
	/// How a new version takes its place, a word of host's: infra's spec/architecture/host.md, "An
	/// app chooses how it is rolled out, and keeping nothing earns a gapless one".
	pub rollout: String,
	/// The label its `[interface]` answers on under `.app`, its `domain` or else its name, when it
	/// has one: what `router` sends a public name to this node by. See infra's
	/// spec/architecture/host.md, "One name inside, and a domain label outside".
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub label: Option<String>,
}

/// An app as host's `/api/apps` lists it.
#[derive(Deserialize)]
struct Shown {
	manifest: Named,
	image: String,
	deployed_at: String,
	#[serde(default)]
	running: bool,
	#[serde(default)]
	held: bool,
	/// Absent from a host older than the field, whose every app is replaced.
	#[serde(default = "replaced")]
	rollout: String,
}

fn replaced() -> String {
	"replace".into()
}

#[derive(Deserialize)]
struct Named {
	name: String,
	#[serde(default)]
	interface: Option<Interface>,
}

#[derive(Deserialize)]
struct Interface {
	#[serde(default)]
	domain: Option<String>,
}

impl From<Shown> for App {
	fn from(shown: Shown) -> Self {
		let Shown { manifest, image, deployed_at, running, held, rollout } = shown;
		let label =
			manifest.interface.map(|interface| interface.domain.unwrap_or(manifest.name.clone()));
		Self { name: manifest.name, image, deployed_at, running, held, rollout, label }
	}
}

/// One round's three reads, each on its own: a meter that is not deployed fails the machine alone.
#[derive(Debug)]
pub struct Reading {
	pub events: Result<Vec<Event>, ReadError>,
	pub apps: Result<Vec<App>, ReadError>,
	/// The meter's `{ info, sample }`, passed on as it is.
	pub machine: Result<serde_json::Value, ReadError>,
}

/// What a round reads from; a fake one in the tests.
pub trait Reader: Send + Sync + 'static {
	fn read(&self) -> Pin<Box<dyn Future<Output = Reading> + Send + '_>>;
}

pub struct Host {
	client: Client<HttpConnector, Empty<Bytes>>,
	origin: String,
	token: String,
}

impl Host {
	pub fn new(origin: &str, token: String) -> Self {
		let client = Client::builder(TokioExecutor::new()).build(HttpConnector::new());
		Self { client, origin: origin.trim_end_matches('/').to_owned(), token }
	}

	async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T, ReadError> {
		let request = Request::get(format!("{}{path}", self.origin))
			.header(AUTHORIZATION, format!("Bearer {}", self.token))
			.body(Empty::new())?;
		let asked = async {
			let answer = self.client.request(request).await?;
			Ok::<_, ReadError>(answer.into_body().collect().await?.to_bytes())
		};
		let body =
			tokio::time::timeout(PATIENCE, asked).await.map_err(|_| ReadError::Slow(PATIENCE))??;
		opened(&body)
	}
}

impl Reader for Host {
	fn read(&self) -> Pin<Box<dyn Future<Output = Reading> + Send + '_>> {
		Box::pin(async {
			let (events, apps, machine) =
				tokio::join!(self.get(EVENTS), self.get(APPS), self.get(MACHINE));
			Reading { events, apps, machine }
		})
	}
}

/// What an answer carries, or the refusal it is. The status line is not read: the envelope says
/// the same, and says which code.
pub fn opened<T: DeserializeOwned>(body: &[u8]) -> Result<T, ReadError> {
	match serde_json::from_slice(body)? {
		response::Envelope::Success { data } => Ok(data),
		response::Envelope::Error { code, message } => Err(ReadError::Refused { code, message }),
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	/// Three rows as host writes them: a deploy still loading, a run skipped for its placements, and
	/// a restart from the panel.
	const EVENTS: &str = r#"{ "status": "success", "data": [
		{ "id": 42, "app": "geo", "action": "deploy",
			"source": { "kind": "run", "run": 18734, "commit": "9f1c2ab" },
			"image": "geo:9f1c2ab", "snapshot": "geo-20261006T120000Z", "outcome": "running",
			"stage": "loading", "started_at": "2026-10-06T12:00:00.123Z" },
		{ "id": 41, "app": "apt", "action": "deploy", "source": { "kind": "run", "run": 18734 },
			"outcome": "skipped", "stage": "admitting", "detail": "Placed on tyo, not here",
			"started_at": "2026-10-06T11:59:58Z", "finished_at": "2026-10-06T11:59:58Z" },
		{ "id": 40, "app": "cron", "action": "restart", "source": { "kind": "panel" },
			"outcome": "succeeded", "started_at": "2026-10-06T11:00:00Z",
			"finished_at": "2026-10-06T11:00:02Z" }
	] }"#;

	const APPS: &str = r#"{ "status": "success", "data": [
		{ "manifest": { "version": 1, "name": "geo", "placements": ["rdu"],
				"container": { "port": 23440, "health": "/health", "memory_mb": 768 },
				"interface": { "domain": "where", "lan": true } },
			"image": "geo:9f1c2ab",
			"previous": { "manifest": { "version": 1, "name": "geo", "placements": ["rdu"] },
				"image": "geo:1b2c3d4" },
			"deployed_at": "2026-10-05T08:00:00Z", "held": false, "running": true,
			"restorable": true, "platform": false, "driver": false, "rollout": "beside" },
		{ "manifest": { "version": 1, "name": "apt", "placements": ["rdu"] },
			"image": "apt:1b2c3d4", "previous": null, "deployed_at": "2026-10-01T08:00:00Z",
			"held": true, "running": false, "restorable": false, "platform": false, "driver": false }
	] }"#;

	#[test]
	fn reads_events_as_host_answers_them() {
		let events: Vec<Event> = opened(EVENTS.as_bytes()).unwrap();
		assert_eq!(events.len(), 3);
		let run = Source { kind: "run".into(), run: Some(18734), commit: Some("9f1c2ab".into()) };
		assert_eq!(events[0].source, run);
		assert_eq!(events[0].outcome, "running");
		assert_eq!(events[0].stage.as_deref(), Some("loading"));
		assert_eq!(events[0].finished_at, None);
		assert_eq!(events[1].detail.as_deref(), Some("Placed on tyo, not here"));
		assert_eq!(events[2].stage, None);

		// Passed on with what is absent left out, and the snapshot, which is host's own, dropped.
		let passed = serde_json::to_value(&events[2]).unwrap();
		assert_eq!(passed["source"], serde_json::json!({ "kind": "panel" }));
		assert!(passed.get("stage").is_none() && passed.get("image").is_none());
		assert!(serde_json::to_value(&events[0]).unwrap().get("snapshot").is_none());
	}

	/// geo's as host writes it, and apt's as a host older than `rollout` does, which is replaced.
	#[test]
	fn reads_each_app_without_its_declaration() {
		let apps: Vec<App> = opened(APPS.as_bytes()).unwrap();
		assert_eq!(
			apps,
			[
				App {
					name: "geo".into(),
					image: "geo:9f1c2ab".into(),
					deployed_at: "2026-10-05T08:00:00Z".into(),
					running: true,
					held: false,
					rollout: "beside".into(),
					label: Some("where".into()),
				},
				App {
					name: "apt".into(),
					image: "apt:1b2c3d4".into(),
					deployed_at: "2026-10-01T08:00:00Z".into(),
					running: false,
					held: true,
					rollout: "replace".into(),
					label: None,
				},
			]
		);
		// Passed on to the console as a word, and the label to `router`, absent where there is none.
		assert_eq!(serde_json::to_value(&apps[0]).unwrap()["rollout"], "beside");
		assert_eq!(serde_json::to_value(&apps[0]).unwrap()["label"], "where");
		assert!(serde_json::to_value(&apps[1]).unwrap().get("label").is_none());
		// An interface with no domain answers on the app's own name.
		let named = r#"{ "status": "success", "data": [{ "manifest": { "name": "qq",
			"interface": { "lan": false } }, "image": "qq:1", "deployed_at": "2026-10-08T00:00:00Z" }] }"#;
		let apps: Vec<App> = opened(named.as_bytes()).unwrap();
		assert_eq!(apps[0].label.as_deref(), Some("qq"));
	}

	#[test]
	fn the_machine_passes_on_whole() {
		let body =
			r#"{ "status": "success", "data": { "info": { "cores": 2 }, "sample": { "at": 104 } } }"#;
		let machine: serde_json::Value = opened(body.as_bytes()).unwrap();
		assert_eq!(machine["sample"]["at"], 104);
	}

	#[test]
	fn a_refusal_is_its_code() {
		let body = r#"{ "status": "error", "code": "meter_unavailable",
			"message": "No meter is deployed on this node" }"#;
		let refused = opened::<serde_json::Value>(body.as_bytes()).unwrap_err();
		assert!(matches!(refused, ReadError::Refused { code, .. } if code == "meter_unavailable"));
		assert!(matches!(opened::<Vec<Event>>(b"<html>"), Err(ReadError::Malformed(_))));
	}
}
