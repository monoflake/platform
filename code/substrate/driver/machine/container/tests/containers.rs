//! `Containers` driven through every operation of `deployments` for an image, and every reason it
//! answers, with containerd, the network, btrfs and the fetch faked; the real ones are run on a
//! machine apart from these tests.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use driver_machine_container::{
	Attachment, Binding, Capacity, Chosen, Containerd, Containers, Deployments, Fault, Fetch, Image,
	ImageConfig, Listed, Mount, Network, Quota, Refused, Runtimes, Spec, Task, Unfetched,
};
use envelope::contracts::{
	DeploymentArtifact, DeploymentDeploy, DeploymentDescribed, DeploymentForm, DeploymentIsolation,
	DeploymentNetwork, DeploymentOf, DeploymentRuns, DeploymentRuntime, DeploymentState,
};
use serde_json::Value;
use sha2::{Digest, Sha256};

/// What every fake did, in order.
type Log = Arc<Mutex<Vec<String>>>;

struct Held {
	labels: BTreeMap<String, String>,
	task: Option<Task>,
	spec: Spec,
}

struct Machine {
	log: Log,
	config: ImageConfig,
	rootfs: PathBuf,
	held: Mutex<BTreeMap<(String, String), Held>>,
}

impl Machine {
	fn note(&self, line: String) {
		self.log.lock().unwrap().push(line);
	}
}

impl Containerd for Machine {
	async fn import(&self, namespace: &str, archive: &Path) -> Result<Image, Fault> {
		let bytes = std::fs::read(archive).map_err(|e| Fault(e.to_string()))?;
		self.note(format!("import {namespace} {}", String::from_utf8_lossy(&bytes)));
		Ok(Image {
			name: "artifact/x".into(),
			chain: "sha256:top".into(),
			config: self.config.clone(),
			size: 100,
		})
	}

	async fn prepare(&self, namespace: &str, key: &str, image: &Image) -> Result<Vec<Mount>, Fault> {
		self.note(format!("prepare {namespace} {key} on {}", image.chain));
		Ok(vec![Mount {
			kind: "btrfs".into(),
			source: "/dev/fake".into(),
			options: vec!["subvolid=300".into()],
		}])
	}

	async fn snapshot_path(&self, _: &str, key: &str) -> Result<PathBuf, Fault> {
		self.note(format!("snapshot_path {key}"));
		Ok(self.rootfs.clone())
	}

	async fn create(
		&self,
		namespace: &str,
		spec: &Spec,
		rootfs: &[Mount],
		output: &Path,
	) -> Result<(), Fault> {
		self.note(format!(
			"create {namespace} {} with {} mounts to {}",
			spec.id,
			rootfs.len(),
			output.display()
		));
		let held = Held { labels: spec.labels.clone(), task: Some(Task::Created), spec: spec.clone() };
		self.held.lock().unwrap().insert((namespace.into(), spec.id.clone()), held);
		Ok(())
	}

	async fn start(&self, namespace: &str, id: &str) -> Result<u32, Fault> {
		self.note(format!("start {id}"));
		let mut held = self.held.lock().unwrap();
		let held =
			held.get_mut(&(namespace.into(), id.into())).ok_or_else(|| Fault("no container".into()))?;
		held.task = Some(Task::Running);
		Ok(42)
	}

	async fn stop(&self, namespace: &str, id: &str, grace: u64) -> Result<(), Fault> {
		self.note(format!("stop {id} within {grace}"));
		if let Some(held) = self.held.lock().unwrap().get_mut(&(namespace.into(), id.into())) {
			held.task = Some(Task::Stopped(143));
		}
		Ok(())
	}

	async fn remove(&self, namespace: &str, id: &str) -> Result<(), Fault> {
		self.note(format!("remove {id}"));
		self.held.lock().unwrap().remove(&(namespace.into(), id.into()));
		Ok(())
	}

	async fn list(&self, namespace: &str) -> Result<Vec<Listed>, Fault> {
		let held = self.held.lock().unwrap();
		Ok(
			held
				.iter()
				.filter(|((n, _), _)| n == namespace)
				.map(|((_, id), h)| Listed { id: id.clone(), labels: h.labels.clone(), task: h.task })
				.collect(),
		)
	}
}

struct Net {
	log: Log,
	given: Mutex<u8>,
}

impl Network for Net {
	async fn attach(&self, id: &str, port: u16) -> Result<Attachment, Fault> {
		self.log.lock().unwrap().push(format!("attach {id} {port}"));
		let mut given = self.given.lock().unwrap();
		*given += 1;
		let address: SocketAddr = format!("10.88.0.{}:{port}", *given + 1).parse().unwrap();
		Ok(Attachment { netns: PathBuf::from("/run/netns").join(id), address })
	}

	async fn detach(&self, id: &str) -> Result<(), Fault> {
		self.log.lock().unwrap().push(format!("detach {id}"));
		Ok(())
	}
}

struct Share {
	log: Log,
	refuse: bool,
}

impl Quota for Share {
	async fn assign(&self, subvolume: &Path, qgroup: &str) -> Result<(), Fault> {
		self.log.lock().unwrap().push(format!("assign {} {qgroup}", subvolume.display()));
		if self.refuse { Err(Fault("ERROR: quotas not enabled".into())) } else { Ok(()) }
	}

	async fn limit(&self, qgroup: &str, bytes: Option<u64>) -> Result<(), Fault> {
		self.log.lock().unwrap().push(format!("limit {qgroup} {bytes:?}"));
		Ok(())
	}
}

/// What an address serves.
#[derive(Clone)]
enum Served {
	Bytes(&'static [u8]),
	TooLarge,
	Nothing,
}

struct Artifacts {
	log: Log,
	served: BTreeMap<&'static str, Served>,
}

impl Fetch for Artifacts {
	async fn fetch(&self, address: &str, into: &Path, most: u64) -> Result<[u8; 32], Unfetched> {
		self.log.lock().unwrap().push(format!("fetch {address} at most {most}"));
		match self.served.get(address).cloned().unwrap_or(Served::Nothing) {
			Served::Bytes(bytes) => {
				std::fs::write(into, bytes).unwrap();
				Ok(Sha256::digest(bytes).into())
			}
			Served::TooLarge => Err(Unfetched::TooLarge),
			Served::Nothing => Err(Unfetched::Unfetchable(format!("{address}: nothing serves it"))),
		}
	}
}

const LARGEST: u64 = 1 << 30;
const ECHO: &[u8] = b"echo image";
const ECHO_TWO: &[u8] = b"echo image, two";

fn hash(bytes: &[u8]) -> [u8; 32] {
	Sha256::digest(bytes).into()
}

type Driver = Containers<Machine, Net, Share, Artifacts>;

/// A tree removed whole, its directories opened first, as a container's secrets are closed to
/// writing.
fn cleared(path: &Path) {
	use std::os::unix::fs::PermissionsExt;
	if path.is_dir() && !path.is_symlink() {
		let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700));
		for entry in std::fs::read_dir(path).unwrap() {
			cleared(&entry.unwrap().path());
		}
	}
}

/// A driver with nothing deployed, its state in a directory of the test's own.
fn driver(test: &str, config: ImageConfig, refuse: bool) -> (Driver, Log) {
	let log: Log = Arc::default();
	let state = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("containers").join(test);
	// What an earlier run left is not this run's.
	if state.exists() {
		cleared(&state);
		std::fs::remove_dir_all(&state).unwrap();
	}
	let rootfs = state.join("rootfs");
	std::fs::create_dir_all(rootfs.join("etc")).unwrap();
	std::fs::write(
		rootfs.join("etc/passwd"),
		"root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/:/sbin/nologin\n",
	)
	.unwrap();
	std::fs::write(rootfs.join("etc/group"), "root:x:0:\nnogroup:x:65533:\n").unwrap();
	let served = BTreeMap::from([
		("file:///echo.tar", Served::Bytes(ECHO)),
		("file:///echo-two.tar", Served::Bytes(ECHO_TWO)),
		("https://artifacts.invalid/large.tar", Served::TooLarge),
	]);
	let driver = Containers {
		containerd: Machine { log: log.clone(), config, rootfs, held: Mutex::default() },
		network: Net { log: log.clone(), given: Mutex::default() },
		quota: Share { log: log.clone(), refuse },
		fetch: Artifacts { log: log.clone(), served },
		runtimes: Runtimes {
			runc: "/bin/runc".into(),
			crun: "/bin/crun".into(),
			youki: "/bin/youki".into(),
		},
		secrets: state.join("tmpfs"),
		state,
		largest: LARGEST,
	};
	(driver, log)
}

fn shell() -> ImageConfig {
	ImageConfig {
		cmd: vec!["/bin/sh".into()],
		env: vec!["PATH=/usr/bin:/bin".into()],
		working_dir: Some("/".into()),
		..ImageConfig::default()
	}
}

fn binding() -> Binding {
	Binding {
		namespace: "b1".into(),
		qgroup: "1/7".into(),
		capacities: BTreeMap::from([(3, Capacity { millicores: 500, memory: 268_435_456 })]),
	}
}

fn app() -> DeploymentRuns {
	DeploymentRuns::App { id: 1 }
}

fn of() -> DeploymentOf {
	DeploymentOf { runs: app() }
}

/// The deployment of the image `forms.json` sends, as `tests/kinds/deployments/` has it.
fn deploy(address: &str, bytes: &[u8]) -> DeploymentDeploy {
	DeploymentDeploy {
		runs: app(),
		version: hash(bytes),
		form: DeploymentForm::Image,
		runtime: None,
		isolation: vec![DeploymentIsolation::Kernel],
		artifact: DeploymentArtifact { address: address.into(), hash: hash(bytes) },
		footing: "https://footing.invalid".into(),
		secrets: BTreeMap::from([("TOKEN".into(), b"hidden".to_vec())]),
		network: vec![DeploymentNetwork::Http],
		into: Some(3),
		port: Some(8080),
	}
}

fn echo() -> DeploymentDeploy {
	deploy("file:///echo.tar", ECHO)
}

fn running(address: &str) -> DeploymentState {
	DeploymentState::Running {
		address: address.into(),
		runtime: DeploymentRuntime::Runc,
		isolation: vec![DeploymentIsolation::Kernel],
	}
}

fn reason(refused: Refused) -> &'static str {
	refused.reason
}

fn lines(log: &Log) -> Vec<String> {
	log.lock().unwrap().clone()
}

fn spec_of(driver: &Driver) -> Spec {
	driver.containerd.held.lock().unwrap().values().next().unwrap().spec.clone()
}

#[tokio::test]
async fn an_image_deployed_runs_and_is_described_at_its_port() {
	let (driver, _) = driver("deployed", shell(), false);
	let deployed = driver.deploy(&binding(), echo()).await.unwrap();
	let expected =
		DeploymentDescribed { runs: app(), version: hash(ECHO), state: running("10.88.0.2:8080") };
	assert_eq!(deployed, expected);
	assert_eq!(driver.describe(&binding(), of()).await.unwrap(), expected);
}

#[tokio::test]
async fn its_layer_joins_the_qgroup_before_its_task_starts() {
	let (driver, log) = driver("ordered", shell(), false);
	driver.deploy(&binding(), echo()).await.unwrap();
	let id = "app-1-".to_owned() + &format!("{:x}", Sha256::digest(ECHO))[..12];
	let rootfs = driver.containerd.rootfs.display().to_string();
	let output = driver.state.join("output/b1").join(format!("{id}.log"));
	assert_eq!(
		lines(&log),
		[
			format!("fetch file:///echo.tar at most {LARGEST}"),
			"import b1 echo image".to_owned(),
			format!("prepare b1 {id} on sha256:top"),
			format!("snapshot_path {id}"),
			format!("assign {rootfs} 1/7"),
			format!("attach b1-{id} 8080"),
			format!("create b1 {id} with 1 mounts to {}", output.display()),
			format!("start {id}"),
		]
	);
	// The archive is not kept once containerd holds the image.
	assert_eq!(std::fs::read_dir(driver.state.join("artifacts")).unwrap().count(), 0);
}

#[tokio::test]
async fn its_spec_holds_its_capacity_its_network_and_what_it_is_given() {
	let (driver, _) = driver("spec", shell(), false);
	driver.deploy(&binding(), echo()).await.unwrap();
	let spec = spec_of(&driver);
	assert_eq!(spec.binary, PathBuf::from("/bin/runc"));
	assert_eq!(spec.snapshot, spec.id);
	assert_eq!(spec.image, "artifact/x");
	let s = &spec.runtime_spec;
	assert_eq!(s["process"]["args"], serde_json::json!(["/bin/sh"]));
	assert_eq!(
		s["process"]["env"],
		serde_json::json!(["PATH=/usr/bin:/bin", "MONOFLAKE_FOOTING=https://footing.invalid"])
	);
	assert_eq!(s["process"]["cwd"], "/");
	assert_eq!(s["process"]["user"], serde_json::json!({ "uid": 0, "gid": 0 }));
	assert_eq!(s["root"]["path"], "rootfs");
	assert_eq!(
		s["linux"]["resources"]["cpu"],
		serde_json::json!({ "period": 100_000, "quota": 50_000 })
	);
	assert_eq!(s["linux"]["resources"]["memory"]["limit"], 268_435_456);
	assert_eq!(s["linux"]["cgroupsPath"], format!("/b1/{}", spec.id));
	let network =
		s["linux"]["namespaces"].as_array().unwrap().iter().find(|n| n["type"] == "network").unwrap();
	assert_eq!(network["path"], format!("/run/netns/b1-{}", spec.id));
	// A secret is a file bound into the container: never in its spec, its labels or its sealed copy.
	let open = driver.secrets.join("b1").join(&spec.id);
	let bound = s["mounts"].as_array().unwrap().iter().find(|m| m["destination"] == "/run/secrets");
	assert_eq!(
		bound.unwrap(),
		&serde_json::json!({
			"destination": "/run/secrets",
			"type": "bind",
			"source": open,
			"options": ["rbind", "ro", "nosuid", "nodev", "noexec"],
		})
	);
	assert_eq!(std::fs::read(open.join("TOKEN")).unwrap(), b"hidden");
	let sealed = std::fs::read(driver.state.join("secrets/b1").join(&spec.id).join("TOKEN")).unwrap();
	assert!(!sealed.windows(6).any(|w| w == b"hidden"));
	assert!(!s.to_string().contains("hidden"));
	assert!(spec.labels.values().all(|v| !v.contains("hidden")));
}

#[tokio::test]
async fn a_deployment_without_secrets_binds_none() {
	let (driver, _) = driver("secretless", shell(), false);
	driver.deploy(&binding(), DeploymentDeploy { secrets: BTreeMap::new(), ..echo() }).await.unwrap();
	let s = spec_of(&driver).runtime_spec;
	assert!(s["mounts"].as_array().unwrap().iter().all(|m| m["destination"] != "/run/secrets"));
	assert!(!driver.state.join("secrets.key").exists());
}

#[tokio::test]
async fn secrets_lost_to_a_reboot_are_put_back_on_resuming() {
	let (driver, _) = driver("rebooted", shell(), false);
	driver.deploy(&binding(), echo()).await.unwrap();
	driver.stop(&binding(), of()).await.unwrap();
	let tmpfs = driver.secrets.clone();
	cleared(&tmpfs);
	std::fs::remove_dir_all(&tmpfs).unwrap();
	driver.resume(&binding(), of()).await.unwrap();
	let id = spec_of(&driver).id;
	assert_eq!(std::fs::read(tmpfs.join("b1").join(id).join("TOKEN")).unwrap(), b"hidden");
}

#[tokio::test]
async fn a_real_image_configuration_runs_as_its_user_in_its_directory() {
	let config: Value = serde_json::from_str(include_str!("images/prometheus.json")).unwrap();
	let strings =
		|v: &Value| v.as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_owned()).collect();
	let runs = &config["config"];
	let image = ImageConfig {
		entrypoint: strings(&runs["Entrypoint"]),
		cmd: strings(&runs["Cmd"]),
		env: strings(&runs["Env"]),
		working_dir: runs["WorkingDir"].as_str().map(str::to_owned),
		user: runs["User"].as_str().map(str::to_owned),
	};
	let (driver, _) = driver("prometheus", image, false);
	driver.deploy(&binding(), echo()).await.unwrap();
	let s = spec_of(&driver).runtime_spec;
	assert_eq!(
		s["process"]["args"],
		serde_json::json!([
			"/bin/prometheus",
			"--config.file=/etc/prometheus/prometheus.yml",
			"--storage.tsdb.path=/prometheus"
		])
	);
	assert_eq!(s["process"]["cwd"], "/prometheus");
	assert_eq!(s["process"]["user"], serde_json::json!({ "uid": 65534, "gid": 65534 }));
	assert_eq!(
		s["process"]["env"][0],
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	);
}

#[tokio::test]
async fn a_user_and_group_named_are_read_from_the_image() {
	let config = ImageConfig { user: Some("nobody:nogroup".into()), ..shell() };
	let (named, _) = driver("named", config, false);
	named.deploy(&binding(), echo()).await.unwrap();
	assert_eq!(
		spec_of(&named).runtime_spec["process"]["user"],
		serde_json::json!({ "uid": 65534, "gid": 65533 })
	);
	let config = ImageConfig { user: Some("nobody-at-all".into()), ..shell() };
	let (unnamed, _) = driver("unnamed", config, false);
	assert_eq!(reason(unnamed.deploy(&binding(), echo()).await.unwrap_err()), "malformed");
}

#[tokio::test]
async fn an_image_naming_nothing_to_run_is_refused_and_leaves_nothing() {
	let (driver, log) = driver("empty", ImageConfig::default(), false);
	assert_eq!(reason(driver.deploy(&binding(), echo()).await.unwrap_err()), "malformed");
	assert!(driver.containerd.held.lock().unwrap().is_empty());
	assert!(lines(&log).iter().any(|l| l.starts_with("remove ")));
	assert!(lines(&log).iter().any(|l| l.starts_with("detach ")));
}

#[tokio::test]
async fn deploying_the_same_again_is_the_one_deployment() {
	let (driver, log) = driver("again", shell(), false);
	let first = driver.deploy(&binding(), echo()).await.unwrap();
	let before = lines(&log).len();
	let second = driver.deploy(&binding(), echo()).await.unwrap();
	assert_eq!(first, second);
	assert_eq!(lines(&log).len(), before);
	assert_eq!(driver.containerd.held.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn a_new_version_replaces_the_one_before() {
	let (driver, log) = driver("replaced", shell(), false);
	driver.deploy(&binding(), echo()).await.unwrap();
	let two = driver.deploy(&binding(), deploy("file:///echo-two.tar", ECHO_TWO)).await.unwrap();
	assert_eq!(two.version, hash(ECHO_TWO));
	assert_eq!(two.state, running("10.88.0.3:8080"));
	let held = driver.containerd.held.lock().unwrap();
	assert_eq!(held.len(), 1);
	let old = "app-1-".to_owned() + &format!("{:x}", Sha256::digest(ECHO))[..12];
	let log = lines(&log);
	let start_two = log.iter().position(|l| l.starts_with("start ") && !l.ends_with(&old)).unwrap();
	let stop_one = log.iter().position(|l| *l == format!("stop {old} within 10000")).unwrap();
	assert!(start_two < stop_one, "the new runs before the old is stopped");
	assert!(log.contains(&format!("remove {old}")));
	assert!(log.contains(&format!("detach b1-{old}")));
}

#[tokio::test]
async fn what_the_host_cannot_give_is_beyond_it_and_nothing_is_fetched() {
	let (driver, log) = driver("beyond", shell(), false);
	let modules = DeploymentDeploy { form: DeploymentForm::Modules, ..echo() };
	let vm = DeploymentDeploy { isolation: vec![DeploymentIsolation::Vm], ..echo() };
	let isolate = DeploymentDeploy {
		isolation: vec![DeploymentIsolation::Kernel, DeploymentIsolation::Isolate],
		..echo()
	};
	let workerd = DeploymentDeploy { runtime: Some(DeploymentRuntime::Workerd), ..echo() };
	let elsewhere = DeploymentDeploy { into: Some(9), ..echo() };
	for input in [modules, vm, isolate, workerd, elsewhere] {
		assert_eq!(reason(driver.deploy(&binding(), input).await.unwrap_err()), "beyond_host");
	}
	assert!(lines(&log).is_empty());
}

#[tokio::test]
async fn an_image_without_its_port_or_its_container_is_malformed() {
	let (driver, log) = driver("unplaced", shell(), false);
	let portless = DeploymentDeploy { port: None, ..echo() };
	let wide = DeploymentDeploy { port: Some(70_000), ..echo() };
	let nowhere = DeploymentDeploy { into: None, ..echo() };
	let secret = |name: &str| DeploymentDeploy {
		secrets: BTreeMap::from([(name.to_owned(), b"x".to_vec())]),
		..echo()
	};
	let platform = secret("MONOFLAKE_FOOTING");
	let escaping = secret("../TOKEN");
	let hidden = secret(".TOKEN");
	for input in [portless, wide, nowhere, platform, escaping, hidden] {
		assert_eq!(reason(driver.deploy(&binding(), input).await.unwrap_err()), "malformed");
	}
	assert!(lines(&log).is_empty());
}

#[tokio::test]
async fn an_artifact_past_its_bound_is_too_large() {
	let (driver, log) = driver("large", shell(), false);
	let input = deploy("https://artifacts.invalid/large.tar", ECHO);
	assert_eq!(reason(driver.deploy(&binding(), input).await.unwrap_err()), "too_large");
	assert_eq!(lines(&log).len(), 1);
}

#[tokio::test]
async fn an_artifact_not_as_its_hash_says_is_refused_and_not_kept() {
	let (driver, log) = driver("mismatched", shell(), false);
	let input = DeploymentDeploy {
		artifact: DeploymentArtifact { address: "file:///echo.tar".into(), hash: hash(ECHO_TWO) },
		..echo()
	};
	assert_eq!(reason(driver.deploy(&binding(), input).await.unwrap_err()), "hash_mismatch");
	assert_eq!(lines(&log).len(), 1);
	assert_eq!(std::fs::read_dir(driver.state.join("artifacts")).unwrap().count(), 0);
}

#[tokio::test]
async fn an_artifact_nothing_serves_is_unfetchable() {
	let (driver, _) = driver("unfetchable", shell(), false);
	let refused =
		driver.deploy(&binding(), deploy("https://nothing.invalid/x.tar", ECHO)).await.unwrap_err();
	assert_eq!(refused.reason, "unfetchable");
	assert!(refused.message.unwrap().contains("nothing serves it"));
}

#[tokio::test]
async fn a_failure_of_the_machine_is_unknown_and_undoes_what_was_made() {
	let (driver, log) = driver("refused", shell(), true);
	let refused = driver.deploy(&binding(), echo()).await.unwrap_err();
	assert_eq!(refused.reason, "unknown");
	assert_eq!(refused.message.as_deref(), Some("ERROR: quotas not enabled"));
	let log = lines(&log);
	assert!(!log.iter().any(|l| l.starts_with("start ")));
	assert!(log.iter().any(|l| l.starts_with("remove ")));
}

#[tokio::test]
async fn what_was_never_deployed_is_not_found_and_deleting_it_succeeds() {
	let (driver, log) = driver("never", shell(), false);
	assert_eq!(reason(driver.describe(&binding(), of()).await.unwrap_err()), "not_found");
	assert_eq!(reason(driver.stop(&binding(), of()).await.unwrap_err()), "not_found");
	assert_eq!(reason(driver.resume(&binding(), of()).await.unwrap_err()), "not_found");
	driver.delete(&binding(), of()).await.unwrap();
	assert!(lines(&log).is_empty());
}

#[tokio::test]
async fn another_binding_sees_none_of_it() {
	let (driver, _) = driver("apart", shell(), false);
	driver.deploy(&binding(), echo()).await.unwrap();
	let other = Binding { namespace: "b2".into(), ..binding() };
	assert_eq!(reason(driver.describe(&other, of()).await.unwrap_err()), "not_found");
}

#[tokio::test]
async fn a_deployment_stopped_is_stopped_and_resumed_runs_again() {
	let (driver, log) = driver("lifecycle", shell(), false);
	driver.deploy(&binding(), echo()).await.unwrap();
	let stopped = driver.stop(&binding(), of()).await.unwrap();
	assert_eq!(stopped.state, DeploymentState::Stopped);
	assert_eq!(driver.describe(&binding(), of()).await.unwrap().state, DeploymentState::Stopped);
	let resumed = driver.resume(&binding(), of()).await.unwrap();
	assert_eq!(resumed.state, running("10.88.0.2:8080"));
	let log = lines(&log);
	assert_eq!(
		log.iter().filter(|l| l.starts_with("attach ")).count(),
		2,
		"resuming makes its network where it is gone"
	);
	assert_eq!(log.iter().filter(|l| l.starts_with("start ")).count(), 2);
}

#[tokio::test]
async fn a_deployment_is_deleted_only_once_stopped_and_is_then_not_found() {
	let (driver, log) = driver("deleted", shell(), false);
	driver.deploy(&binding(), echo()).await.unwrap();
	assert_eq!(reason(driver.delete(&binding(), of()).await.unwrap_err()), "still_running");
	driver.stop(&binding(), of()).await.unwrap();
	driver.delete(&binding(), of()).await.unwrap();
	assert_eq!(reason(driver.describe(&binding(), of()).await.unwrap_err()), "not_found");
	assert!(lines(&log).iter().any(|l| l.starts_with("detach b1-app-1-")));
	// Its secrets, both copies, and its stop's mark go with it.
	assert_eq!(std::fs::read_dir(driver.secrets.join("b1")).unwrap().count(), 0);
	assert_eq!(std::fs::read_dir(driver.state.join("secrets/b1")).unwrap().count(), 0);
	assert_eq!(std::fs::read_dir(driver.state.join("stopped/b1")).unwrap().count(), 0);
}

#[tokio::test]
async fn the_runtime_named_runs_it_and_runc_otherwise() {
	for (named, binary) in
		[(DeploymentRuntime::Crun, "/bin/crun"), (DeploymentRuntime::Youki, "/bin/youki")]
	{
		let (driver, _) = driver(&format!("runtime-{binary}").replace('/', "-"), shell(), false);
		let deployed =
			driver.deploy(&binding(), DeploymentDeploy { runtime: Some(named), ..echo() }).await.unwrap();
		assert_eq!(spec_of(&driver).binary, PathBuf::from(binary));
		let DeploymentState::Running { runtime, .. } = deployed.state else {
			panic!("not running: {deployed:?}")
		};
		assert_eq!(runtime, named);
	}
	let runtimes = Runtimes { runc: "/r".into(), crun: "/c".into(), youki: "/y".into() };
	assert_eq!(runtimes.binary(None), Path::new("/r"));
	assert_eq!(runtimes.binary(Some(&DeploymentRuntime::Runc)), Path::new("/r"));
	assert_eq!(runtimes.binary(Some(&DeploymentRuntime::Crun)), Path::new("/c"));
	assert_eq!(runtimes.binary(Some(&DeploymentRuntime::Youki)), Path::new("/y"));
}

#[tokio::test]
async fn a_container_ended_unasked_has_failed_and_one_made_is_making() {
	let (driver, _) = driver("exited", shell(), false);
	driver.deploy(&binding(), echo()).await.unwrap();
	let exited = |message: &str| DeploymentState::Failed {
		reason: "exited".into(),
		message: Some(message.into()),
	};
	for (task, state) in [
		(Some(Task::Stopped(1)), exited("exit status 1")),
		(None, exited("its task is gone")),
		(Some(Task::Created), DeploymentState::Making),
		(Some(Task::Other), DeploymentState::Making),
	] {
		driver.containerd.held.lock().unwrap().values_mut().for_each(|h| h.task = task);
		assert_eq!(driver.describe(&binding(), of()).await.unwrap().state, state);
	}
}
