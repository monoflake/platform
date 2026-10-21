//! `driver(machine)`'s container, `model/ground/drivers.res`, and this file its interface, the
//! model's, `docs/code.md`. Whoever implements it implements each trait here for the types it
//! names, each in a private module beside this file, and never edits this file.
//!
//! An image deployed as a container on the machine, by the `deployments` interface, RFC vr5lw:
//! each binding a containerd namespace of its own; its image imported and unpacked onto the btrfs
//! snapshotter; its container's layer assigned to the binding's qgroup between preparing it and
//! starting it; its runtime runc unless the deployment names crun or youki, each through
//! containerd's `io.containerd.runc.v2` shim by its binary; its network a namespace of its own on a
//! bridge, made by the CNI plugins the machine holds, its address reached within the machine; its
//! processor and memory held to the capacity it is deployed into. What leaves it is not checked
//! yet, `?egress`. An artifact is an OCI image layout archive fetched from its address, its hash the
//! SHA-256 of its bytes, RFC ge55b; how one reaches the driver is open. Everything the driver holds
//! of a container is written on it, as labels, so the driver comes back from a restart by reading
//! containerd.

use std::collections::BTreeMap;
use std::future::Future;
use std::net::SocketAddr;
use std::path::PathBuf;

use envelope::contracts::{
	DeploymentDeleted, DeploymentDeploy, DeploymentDescribed, DeploymentOf, DeploymentRuntime,
};

mod containerd;
mod containers;
mod fetch;
mod network;
mod quota;

/// A failure an operation answers, by its reason as the `deployments` interface declares it, or one
/// every operation may fail for; its message a person reads, none for the reason's own.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Refused {
	/// The reason.
	pub reason: &'static str,
	/// A message more exact than the reason's own.
	pub message: Option<String>,
}

/// What a machine could not do, at a moment, of containerd, the network, btrfs or the fetch:
/// answered `fault`, RFC ge55b, unless the step that met it says otherwise.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fault(pub String);

/// A container's capacity, as `management-capacity`'s `container` case holds it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Capacity {
	/// Cores, in thousandths.
	pub millicores: u32,
	/// Memory, in bytes.
	pub memory: u64,
}

/// A binding, as the management holds it, RFC vr5lw: its containerd namespace, its qgroup, and the
/// containers of capacity it asked for, by their ids.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Binding {
	/// Its containerd namespace.
	pub namespace: String,
	/// Its qgroup above every subvolume it holds, `1/<n>`.
	pub qgroup: String,
	/// Each container of capacity, by its `capacity` id.
	pub capacities: BTreeMap<u32, Capacity>,
}

/// The `deployments` interface for images, RFC vr5lw; implemented for [`Containers`]. Deploying is
/// idempotent, the same version sent again leaving what runs; what was never deployed is
/// `not_found` but to `delete`, which succeeds; `delete` of a running one is `still_running`. A form
/// but `image`, an isolation but `kernel`, or a runtime but runc, crun or youki is `beyond_host`.
pub trait Deployments {
	/// Deploys, and answers at once, `making` until it runs.
	fn deploy(
		&self,
		binding: &Binding,
		input: DeploymentDeploy,
	) -> impl Future<Output = Result<DeploymentDescribed, Refused>> + Send;
	/// Stops it, its container kept.
	fn stop(
		&self,
		binding: &Binding,
		input: DeploymentOf,
	) -> impl Future<Output = Result<DeploymentDescribed, Refused>> + Send;
	/// Starts it again as it was.
	fn resume(
		&self,
		binding: &Binding,
		input: DeploymentOf,
	) -> impl Future<Output = Result<DeploymentDescribed, Refused>> + Send;
	/// What runs, and its state.
	fn describe(
		&self,
		binding: &Binding,
		input: DeploymentOf,
	) -> impl Future<Output = Result<DeploymentDescribed, Refused>> + Send;
	/// Removes it and everything it held, once stopped.
	fn delete(
		&self,
		binding: &Binding,
		input: DeploymentOf,
	) -> impl Future<Output = Result<DeploymentDeleted, Refused>> + Send;
}

/// An image's configuration, as its OCI config gives it.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ImageConfig {
	/// `Entrypoint`.
	pub entrypoint: Vec<String>,
	/// `Cmd`.
	pub cmd: Vec<String>,
	/// `Env`, each `NAME=value`.
	pub env: Vec<String>,
	/// `WorkingDir`.
	pub working_dir: Option<String>,
	/// `User`.
	pub user: Option<String>,
}

/// An image imported into a namespace and unpacked onto the btrfs snapshotter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Image {
	/// Its name in the namespace.
	pub name: String,
	/// The chain id of its top layer, the parent its container's snapshot is prepared on.
	pub chain: String,
	/// Its configuration.
	pub config: ImageConfig,
	/// Its layers' size unpacked, in bytes, counted once, at unpacking.
	pub size: u64,
}

/// A mount, as containerd's snapshots give it and a task's rootfs takes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Mount {
	/// Its type, `btrfs`.
	pub kind: String,
	/// Its source.
	pub source: String,
	/// Its options.
	pub options: Vec<String>,
}

/// A container to create: its id, its image, its runtime's binary, its snapshot, its OCI runtime
/// spec in JSON, and its labels, which hold all the driver keeps of it.
#[derive(Debug, Clone, PartialEq)]
pub struct Spec {
	/// Its id within the namespace.
	pub id: String,
	/// Its image's name.
	pub image: String,
	/// The runtime binary the runc v2 shim runs, by its path.
	pub binary: PathBuf,
	/// Its snapshot's key.
	pub snapshot: String,
	/// Its OCI runtime spec.
	pub runtime_spec: serde_json::Value,
	/// Its labels.
	pub labels: BTreeMap<String, String>,
}

/// A task's state, as containerd's tasks give it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Task {
	/// Created, not started.
	Created,
	/// Running.
	Running,
	/// Stopped, with its exit status.
	Stopped(u32),
	/// Paused or anything else containerd says.
	Other,
}

/// A container as containerd lists it: its id, its labels, its task's state, none where it has no
/// task.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Listed {
	/// Its id.
	pub id: String,
	/// Its labels.
	pub labels: BTreeMap<String, String>,
	/// Its task.
	pub task: Option<Task>,
}

/// What the driver asks of containerd, over its gRPC API by `containerd-client`; implemented for
/// [`Socket`]. Every call is within a namespace.
pub trait Containerd: Send + Sync {
	/// An OCI image layout archive imported and unpacked onto the btrfs snapshotter.
	fn import(
		&self,
		namespace: &str,
		archive: &std::path::Path,
	) -> impl Future<Output = Result<Image, Fault>> + Send;
	/// A writable snapshot prepared on the image's top layer, and its mounts.
	fn prepare(
		&self,
		namespace: &str,
		key: &str,
		image: &Image,
	) -> impl Future<Output = Result<Vec<Mount>, Fault>> + Send;
	/// The snapshot's directory on the host, which the qgroup is assigned by.
	fn snapshot_path(
		&self,
		namespace: &str,
		key: &str,
	) -> impl Future<Output = Result<PathBuf, Fault>> + Send;
	/// The container created, and its task, on the mounts, its output to the files named.
	fn create(
		&self,
		namespace: &str,
		spec: &Spec,
		rootfs: &[Mount],
		output: &std::path::Path,
	) -> impl Future<Output = Result<(), Fault>> + Send;
	/// Its task started; its process's id.
	fn start(&self, namespace: &str, id: &str) -> impl Future<Output = Result<u32, Fault>> + Send;
	/// Its task signalled, and waited on up to so many milliseconds, then killed.
	fn stop(
		&self,
		namespace: &str,
		id: &str,
		grace: u64,
	) -> impl Future<Output = Result<(), Fault>> + Send;
	/// Its task, the container and its snapshot removed.
	fn remove(&self, namespace: &str, id: &str) -> impl Future<Output = Result<(), Fault>> + Send;
	/// Every container of the namespace.
	fn list(&self, namespace: &str) -> impl Future<Output = Result<Vec<Listed>, Fault>> + Send;
}

/// containerd at its socket.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Socket {
	/// Its path, `/run/containerd/containerd.sock`.
	pub path: PathBuf,
}

/// A container's network: its namespace and its address on the bridge.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Attachment {
	/// Its network namespace, by path, which its spec joins.
	pub netns: PathBuf,
	/// Its address, at the port the image is called on.
	pub address: SocketAddr,
}

/// A container's network made and unmade; implemented for [`Bridge`]. What making it answered is
/// kept, so unmaking it after a restart undoes the same.
pub trait Network: Send + Sync {
	/// A namespace for the container, joined to the bridge.
	fn attach(&self, id: &str, port: u16) -> impl Future<Output = Result<Attachment, Fault>> + Send;
	/// Its namespace removed and its address given back; none to remove is no failure.
	fn detach(&self, id: &str) -> impl Future<Output = Result<(), Fault>> + Send;
}

/// A bridge, made by the CNI plugins `bridge`, `host-local` and `loopback`, run by their binaries
/// as the CNI specification has a runtime run them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bridge {
	/// The directory the plugins are in.
	pub plugins: PathBuf,
	/// The bridge's name.
	pub name: String,
	/// The subnet addresses are given from, `10.88.0.0/16`.
	pub subnet: String,
	/// Where what each plugin answered is kept, and the namespaces made.
	pub state: PathBuf,
}

/// A binding's share of btrfs, RFC vr5lw; implemented for [`Btrfs`].
pub trait Quota: Send + Sync {
	/// A subvolume made a member of the binding's qgroup, while nothing is written in it yet.
	fn assign(
		&self,
		subvolume: &std::path::Path,
		qgroup: &str,
	) -> impl Future<Output = Result<(), Fault>> + Send;
	/// The qgroup's limit set, in bytes, none for no limit.
	fn limit(
		&self,
		qgroup: &str,
		bytes: Option<u64>,
	) -> impl Future<Output = Result<(), Fault>> + Send;
}

/// btrfs at the mount its workloads lie on, by its `btrfs` command.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Btrfs {
	/// The mount, `/data`.
	pub mount: PathBuf,
	/// The `btrfs` binary.
	pub binary: PathBuf,
}

/// Why an artifact was not fetched: past its bound, or not to be had now.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Unfetched {
	/// More bytes than the bound.
	TooLarge,
	/// It could not be fetched, and why.
	Unfetchable(String),
}

/// An artifact fetched to a file, at most so many bytes, and the SHA-256 of what was fetched;
/// implemented for [`Https`].
pub trait Fetch: Send + Sync {
	/// The artifact at its address into the file, and its hash.
	fn fetch(
		&self,
		address: &str,
		into: &std::path::Path,
		most: u64,
	) -> impl Future<Output = Result<[u8; 32], Unfetched>> + Send;
}

/// Fetching over HTTPS; and from a `file:` address only where the machine's holder named a
/// directory for it, within that directory alone, a regular file followed through no link, so a
/// caller of `deploy` reads nothing else of the machine. What is refused says no path and no
/// system error back.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Https {
	/// The one directory `file:` addresses may name, none where they are refused.
	pub local: Option<PathBuf>,
}

/// The OCI runtime binaries, by their paths.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Runtimes {
	/// runc, the default.
	pub runc: PathBuf,
	/// crun.
	pub crun: PathBuf,
	/// youki.
	pub youki: PathBuf,
}

/// The containers of a machine: what reaches containerd, the network, btrfs and an artifact, the
/// runtimes, where artifacts and outputs are kept, and the most an artifact may be, in bytes.
#[derive(Debug, Clone)]
pub struct Containers<C, N, Q, F> {
	/// containerd.
	pub containerd: C,
	/// The network.
	pub network: N,
	/// btrfs.
	pub quota: Q,
	/// The fetch.
	pub fetch: F,
	/// The runtimes.
	pub runtimes: Runtimes,
	/// Where artifacts are fetched to and each container's output is written, on ext4, root's
	/// alone; each container's secrets kept sealed there too, so a reboot puts them back.
	pub state: PathBuf,
	/// Where each container's secrets are written as files, a directory of its own per container,
	/// on tmpfs and root's alone, `/run/monoflake/secrets`; each mounted read-only into its
	/// container, so no value is in a spec.
	pub secrets: PathBuf,
	/// The most an artifact may be.
	pub largest: u64,
}

/// The runtime a deployment runs on: the one it names, or runc; implemented for [`Runtimes`].
pub trait Chosen {
	/// The binary of the runtime named, or runc's.
	fn binary(&self, named: Option<&DeploymentRuntime>) -> &std::path::Path;
}
