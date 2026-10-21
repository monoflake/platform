//! The `deployments` interface for images, over containerd, the network, btrfs and the fetch.

mod labels;
mod marks;
mod secrets;
mod spec;

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use envelope::contracts::{
	Architecture, DeploymentDeleted, DeploymentDeploy, DeploymentDescribed, DeploymentForm,
	DeploymentIsolation, DeploymentOf, DeploymentRuns, DeploymentRuntime, DeploymentState,
};

use crate::{
	Binding, Chosen, Containerd, Containers, Deployments, Fault, Fetch, Image, Listed, Network,
	Quota, Refused, Runtimes, Spec, Task, Unfetched,
};
use labels::Kept;
use secrets::{KeyFile, Places};

/// How long a task is given to stop on its signal before it is killed, in milliseconds.
const GRACE: u64 = 10_000;

/// The isolation every container stands on.
const ISOLATION: DeploymentIsolation = DeploymentIsolation::Kernel;

impl Refused {
	fn new(reason: &'static str, message: impl Into<String>) -> Self {
		Self { reason, message: Some(message.into()) }
	}

	fn bare(reason: &'static str) -> Self {
		Self { reason, message: None }
	}
}

impl From<Fault> for Refused {
	fn from(fault: Fault) -> Self {
		Self::new("fault", fault.0)
	}
}

impl Chosen for Runtimes {
	fn binary(&self, named: Option<&DeploymentRuntime>) -> &Path {
		match named {
			Some(DeploymentRuntime::Crun) => &self.crun,
			Some(DeploymentRuntime::Youki) => &self.youki,
			Some(
				DeploymentRuntime::Runc
				| DeploymentRuntime::Workers
				| DeploymentRuntime::Workerd
				| DeploymentRuntime::Wasmtime,
			)
			| None => &self.runc,
		}
	}
}

/// The architecture this driver was built for, as OCI names it, or none where those names lack it.
fn own() -> Option<Architecture> {
	match std::env::consts::ARCH {
		"x86_64" => Some(Architecture::Amd64),
		"aarch64" => Some(Architecture::Arm64),
		_ => None,
	}
}

/// What a deploy asks, checked against what the host gives.
struct Wanted<'a> {
	runs: String,
	version: String,
	runtime: DeploymentRuntime,
	port: u16,
	capacity: &'a crate::Capacity,
	env: Vec<String>,
	secrets: &'a BTreeMap<String, Vec<u8>>,
}

impl<'a> Wanted<'a> {
	fn of(binding: &'a Binding, input: &'a DeploymentDeploy) -> Result<Self, Refused> {
		match input.form {
			DeploymentForm::Image => {}
			DeploymentForm::Modules | DeploymentForm::Component => {
				return Err(Refused::new("beyond_host", "a container runs an image alone"));
			}
		}
		// An artifact naming another architecture than the machine's is beyond the host, RFC ge55b.
		if let Some(named) = input.artifact.architecture
			&& own() != Some(named)
		{
			return Err(Refused::new(
				"beyond_host",
				"an image runs on the architecture it was built for",
			));
		}
		for isolation in &input.isolation {
			match isolation {
				DeploymentIsolation::Kernel => {}
				DeploymentIsolation::Isolate | DeploymentIsolation::Userspace | DeploymentIsolation::Vm => {
					return Err(Refused::new(
						"beyond_host",
						"a container stands on the kernel's isolation alone",
					));
				}
			}
		}
		let runtime = match input.runtime {
			None => DeploymentRuntime::Runc,
			Some(r @ (DeploymentRuntime::Runc | DeploymentRuntime::Crun | DeploymentRuntime::Youki)) => r,
			Some(
				DeploymentRuntime::Workers | DeploymentRuntime::Workerd | DeploymentRuntime::Wasmtime,
			) => {
				return Err(Refused::new("beyond_host", "a container runs on runc, crun or youki"));
			}
		};
		let port = input
			.port
			.ok_or_else(|| {
				Refused::new("malformed", "an image is deployed with the port it is called on")
			})
			.and_then(|p| {
				u16::try_from(p).map_err(|_| Refused::new("malformed", "a port is at most 65535"))
			})?;
		let into = input.into.ok_or_else(|| {
			Refused::new("malformed", "an image is deployed into a container of capacity")
		})?;
		let capacity = binding.capacities.get(&into).ok_or_else(|| {
			Refused::new("beyond_host", format!("the binding holds no capacity {into}"))
		})?;
		for name in input.secrets.keys() {
			secrets::named(name)?;
		}
		let env = vec![format!("MONOFLAKE_FOOTING={}", input.footing)];
		Ok(Self {
			runs: labels::runs(&input.runs),
			version: hex(&input.version),
			runtime,
			port,
			capacity,
			env,
			secrets: &input.secrets,
		})
	}
}

/// A hash in lowercase hex.
fn hex(hash: &[u8; 32]) -> String {
	hash.iter().map(|b| format!("{b:02x}")).collect()
}

/// The containerd id within the namespace of what runs as one container.
fn container_id(runs: &DeploymentRuns, version: &str) -> String {
	let of = match runs {
		DeploymentRuns::App { id } => format!("app-{id}"),
		DeploymentRuns::Component { component } => {
			let clean: String =
				component.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
			format!("component-{}", clean.trim_matches('-'))
		}
	};
	let short: String = version.chars().take(12).collect();
	format!("{of}-{short}")
}

/// A container's network, by a name unique on the machine, since containers of two bindings may
/// share an id.
fn network_id(namespace: &str, id: &str) -> String {
	format!("{namespace}-{id}")
}

/// The containers of one deployment, those in a namespace whose labels name what it runs.
fn of_runs(listed: Vec<Listed>, runs: &str) -> Vec<Listed> {
	listed.into_iter().filter(|l| l.labels.get(labels::RUNS).is_some_and(|r| r == runs)).collect()
}

/// The one container a deployment is answered by, a running one before any other.
fn chosen(mine: &[Listed]) -> Option<&Listed> {
	mine.iter().find(|l| l.task == Some(Task::Running)).or_else(|| mine.first())
}

/// A container's state, as its task and its labels say, and whether its stop was asked for.
fn state(listed: &Listed, asked: bool) -> DeploymentState {
	let ended = |message: String| match asked {
		true => DeploymentState::Stopped,
		false => DeploymentState::Failed { reason: "exited".into(), message: Some(message) },
	};
	match listed.task {
		Some(Task::Running) => match Kept::read(&listed.labels) {
			Ok(kept) => DeploymentState::Running {
				address: kept.address,
				runtime: kept.runtime,
				isolation: vec![ISOLATION],
			},
			Err(why) => DeploymentState::Failed { reason: "fault".into(), message: Some(why) },
		},
		Some(Task::Created | Task::Other) => DeploymentState::Making,
		Some(Task::Stopped(status)) => ended(format!("exit status {status}")),
		None => ended("its task is gone".into()),
	}
}

fn described(
	runs: &DeploymentRuns,
	listed: &Listed,
	asked: bool,
) -> Result<DeploymentDescribed, Refused> {
	let version = listed
		.labels
		.get(labels::VERSION)
		.and_then(|v| labels::unhex(v))
		.ok_or_else(|| Refused::new("fault", format!("{}: no version in its labels", listed.id)))?;
	Ok(DeploymentDescribed { runs: runs.clone(), version, state: state(listed, asked) })
}

impl<C, N, Q, F> Containers<C, N, Q, F>
where
	C: Containerd,
	N: Network,
	Q: Quota,
	F: Fetch,
{
	async fn mine(&self, binding: &Binding, runs: &DeploymentRuns) -> Result<Vec<Listed>, Refused> {
		let listed = self.containerd.list(&binding.namespace).await?;
		Ok(of_runs(listed, &labels::runs(runs)))
	}

	/// The deployment answered as containerd now holds it, `not_found` where nothing runs it.
	async fn answer(
		&self,
		binding: &Binding,
		runs: &DeploymentRuns,
	) -> Result<DeploymentDescribed, Refused> {
		let mine = self.mine(binding, runs).await?;
		let listed = chosen(&mine).ok_or_else(|| Refused::bare("not_found"))?;
		self.told(binding, runs, listed).await
	}

	/// A container described, its stop marks read.
	async fn told(
		&self,
		binding: &Binding,
		runs: &DeploymentRuns,
		listed: &Listed,
	) -> Result<DeploymentDescribed, Refused> {
		let asked = marks::is_set(&self.state, &binding.namespace, &listed.id).await;
		described(runs, listed, asked)
	}

	fn places(&self, namespace: &str, id: &str) -> Places {
		Places::of(&self.secrets, &self.state, namespace, id)
	}

	/// The artifact fetched and held to its hash, as a file to import.
	async fn fetched(&self, namespace: &str, input: &DeploymentDeploy) -> Result<PathBuf, Refused> {
		let directory = self.state.join("artifacts");
		tokio::fs::create_dir_all(&directory)
			.await
			.map_err(|e| Refused::new("fault", format!("{}: {e}", directory.display())))?;
		let file = directory.join(format!("{namespace}-{}.tar", hex(&input.artifact.hash)));
		match self.fetch.fetch(&input.artifact.address, &file, self.largest).await {
			Ok(hash) if hash == input.artifact.hash => Ok(file),
			Ok(_) => {
				forget(&file).await;
				Err(Refused::bare("hash_mismatch"))
			}
			Err(Unfetched::TooLarge) => {
				forget(&file).await;
				Err(Refused::new("too_large", format!("an artifact is at most {} bytes", self.largest)))
			}
			Err(Unfetched::Unfetchable(why)) => {
				forget(&file).await;
				Err(Refused::new("unfetchable", why))
			}
		}
	}

	/// The artifact fetched and imported into the binding's namespace.
	async fn imported(&self, namespace: &str, input: &DeploymentDeploy) -> Result<Image, Refused> {
		let archive = self.fetched(namespace, input).await?;
		let imported = self.containerd.import(namespace, &archive).await;
		forget(&archive).await;
		Ok(imported?)
	}

	/// A new container made and started on the image, its labels holding what it is.
	async fn made(
		&self,
		binding: &Binding,
		image: &Image,
		wanted: &Wanted<'_>,
		id: &str,
	) -> Result<(), Refused> {
		let namespace = binding.namespace.as_str();
		let mounts = self.containerd.prepare(namespace, id, image).await?;
		let rootfs = self.containerd.snapshot_path(namespace, id).await?;
		self.quota.assign(&rootfs, &binding.qgroup).await?;
		let attachment = self.network.attach(&network_id(namespace, id), wanted.port).await?;
		let user = spec::User::resolve(image.config.user.as_deref(), &rootfs).await?;
		let places = self.places(namespace, id);
		let bound = match wanted.secrets.is_empty() {
			true => None,
			false => {
				let seal = KeyFile::of(&self.state).await?;
				secrets::write(&places, wanted.secrets, &seal, user.uid, user.gid).await?;
				Some(places.open.as_path())
			}
		};
		let runtime_spec = spec::build(&spec::Asked {
			id,
			namespace,
			config: &image.config,
			user,
			env: &wanted.env,
			capacity: wanted.capacity,
			netns: &attachment.netns,
			secrets: bound,
		})?;
		let kept = Kept {
			runs: wanted.runs.clone(),
			version: wanted.version.clone(),
			runtime: wanted.runtime,
			address: attachment.address.to_string(),
			port: wanted.port,
			user: (user.uid, user.gid),
		};
		let spec = Spec {
			id: id.to_owned(),
			image: image.name.clone(),
			binary: self.runtimes.binary(Some(&wanted.runtime)).to_path_buf(),
			snapshot: id.to_owned(),
			runtime_spec,
			labels: kept.write(),
		};
		let output = self.state.join("output").join(namespace).join(format!("{id}.log"));
		self.containerd.create(namespace, &spec, &mounts, &output).await?;
		self.containerd.start(namespace, id).await?;
		Ok(())
	}

	/// Everything a container held removed, its network too.
	async fn removed(&self, namespace: &str, id: &str) -> Result<(), Refused> {
		self.containerd.remove(namespace, id).await?;
		self.network.detach(&network_id(namespace, id)).await?;
		secrets::remove(&self.places(namespace, id)).await?;
		marks::clear(&self.state, namespace, id).await
	}
}

/// A file removed, if it is there; what is left of a fetch is not worth failing for.
async fn forget(file: &Path) {
	// Nothing there is what is wanted, so a failure to remove it is no failure of the call.
	let _ = tokio::fs::remove_file(file).await;
}

impl<C, N, Q, F> Deployments for Containers<C, N, Q, F>
where
	C: Containerd,
	N: Network,
	Q: Quota,
	F: Fetch,
{
	async fn deploy(
		&self,
		binding: &Binding,
		input: DeploymentDeploy,
	) -> Result<DeploymentDescribed, Refused> {
		let wanted = Wanted::of(binding, &input)?;
		let mine = self.mine(binding, &input.runs).await?;
		if let Some(same) = mine.iter().find(|l| l.labels.get(labels::VERSION) == Some(&wanted.version))
		{
			return self.told(binding, &input.runs, same).await;
		}
		let id = container_id(&input.runs, &wanted.version);
		let image = self.imported(&binding.namespace, &input).await?;
		if let Err(refused) = self.made(binding, &image, &wanted, &id).await {
			// What was made of it before the failure goes with it; the failure is what is answered.
			let _ = self.removed(&binding.namespace, &id).await;
			return Err(refused);
		}
		for old in &mine {
			self.containerd.stop(&binding.namespace, &old.id, GRACE).await?;
			self.removed(&binding.namespace, &old.id).await?;
		}
		self.answer(binding, &input.runs).await
	}

	async fn stop(
		&self,
		binding: &Binding,
		input: DeploymentOf,
	) -> Result<DeploymentDescribed, Refused> {
		let mine = self.mine(binding, &input.runs).await?;
		if mine.is_empty() {
			return Err(Refused::bare("not_found"));
		}
		for listed in &mine {
			marks::set(&self.state, &binding.namespace, &listed.id).await?;
			self.containerd.stop(&binding.namespace, &listed.id, GRACE).await?;
		}
		self.answer(binding, &input.runs).await
	}

	async fn resume(
		&self,
		binding: &Binding,
		input: DeploymentOf,
	) -> Result<DeploymentDescribed, Refused> {
		let mine = self.mine(binding, &input.runs).await?;
		let listed = chosen(&mine).ok_or_else(|| Refused::bare("not_found"))?;
		let kept = Kept::read(&listed.labels).map_err(|why| Refused::new("fault", why))?;
		let places = self.places(&binding.namespace, &listed.id);
		if tokio::fs::try_exists(&places.sealed).await.unwrap_or(false) {
			let seal = KeyFile::of(&self.state).await?;
			secrets::restore(&places, &seal, kept.user.0, kept.user.1).await?;
		}
		// Its namespace is kept while stopped and made again where a restart lost it. A new address is
		// not yet written back to its label.
		self.network.attach(&network_id(&binding.namespace, &listed.id), kept.port).await?;
		self.containerd.start(&binding.namespace, &listed.id).await?;
		marks::clear(&self.state, &binding.namespace, &listed.id).await?;
		self.answer(binding, &input.runs).await
	}

	async fn describe(
		&self,
		binding: &Binding,
		input: DeploymentOf,
	) -> Result<DeploymentDescribed, Refused> {
		self.answer(binding, &input.runs).await
	}

	async fn delete(
		&self,
		binding: &Binding,
		input: DeploymentOf,
	) -> Result<DeploymentDeleted, Refused> {
		let mine = self.mine(binding, &input.runs).await?;
		let running = mine.iter().any(|l| match l.task {
			Some(Task::Running | Task::Created | Task::Other) => true,
			Some(Task::Stopped(_)) | None => false,
		});
		if running {
			return Err(Refused::bare("still_running"));
		}
		for listed in &mine {
			self.removed(&binding.namespace, &listed.id).await?;
		}
		Ok(DeploymentDeleted {})
	}
}
