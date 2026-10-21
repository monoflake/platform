//! containerd over its gRPC API, by `containerd-client`: the one module that speaks its types.
//! https://github.com/containerd/containerd/tree/main/api

mod import;
mod oci;

use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::time::Duration;

use containerd_client::services::v1::container::Runtime;
use containerd_client::services::v1::containers_client::ContainersClient;
use containerd_client::services::v1::introspection_client::IntrospectionClient;
use containerd_client::services::v1::leases_client::LeasesClient;
use containerd_client::services::v1::snapshots::snapshots_client::SnapshotsClient;
use containerd_client::services::v1::snapshots::{
	MountsRequest, PrepareSnapshotRequest, RemoveSnapshotRequest,
};
use containerd_client::services::v1::tasks_client::TasksClient;
use containerd_client::services::v1::{
	Container, CreateContainerRequest, CreateTaskRequest, DeleteContainerRequest, DeleteTaskRequest,
	GetContainerRequest, GetRequest, KillRequest, ListContainersRequest, ListTasksRequest,
	PluginsRequest, StartRequest, WaitRequest,
};
use containerd_client::services::v1::{CreateRequest as CreateLease, DeleteRequest as DeleteLease};
use containerd_client::tonic::metadata::MetadataValue;
use containerd_client::tonic::transport::Channel;
use containerd_client::tonic::{Code, Request, Status};
use containerd_client::types::v1::{Process, Status as Run};
use prost_types::Any;

use crate::{Containerd, Fault, Image, Listed, Mount, Socket, Spec, Task};

/// The snapshotter every layer is unpacked onto, RFC vr5lw.
const SNAPSHOTTER: &str = "btrfs";
/// The shim every runtime runs through, by its binary, `docs/lessons/machines.md`.
const SHIM: &str = "io.containerd.runc.v2";
const SPEC_TYPE: &str = "types.containerd.io/opencontainers/runtime-spec/1/Spec";
const RUNC_OPTIONS: &str = "containerd.runc.v1.Options";
/// `containerd.runc.v1.Options`'s `binary_name`, a string, as its protobuf writes field 6.
const BINARY_NAME: u8 = (6 << 3) | 2;
/// The label a container's output is kept under, so its task is made again on resuming.
const OUTPUT: &str = "monoflake.output";
const SIGTERM: u32 = 15;
const SIGKILL: u32 = 9;

/// A message within a namespace, as containerd reads it from a request's metadata.
fn within<T>(namespace: &str, message: T) -> Result<Request<T>, Fault> {
	let mut request = Request::new(message);
	let value = MetadataValue::try_from(namespace)
		.map_err(|_| Fault(format!("{namespace}: not a namespace containerd takes")))?;
	request.metadata_mut().insert("containerd-namespace", value);
	Ok(request)
}

/// The lease a snapshot is held by from its preparing until a container names it, as containerd's
/// collector removes an active snapshot nothing references.
fn lease(key: &str) -> String {
	format!("prepare-{key}")
}

fn failed(what: &str) -> impl Fn(Status) -> Fault + '_ {
	move |status| Fault(format!("{what}: {:?}: {}", status.code(), status.message()))
}

/// What is not there, as none; any other failure as it is.
fn found<T>(result: Result<T, Status>, what: &str) -> Result<Option<T>, Fault> {
	match result {
		Ok(value) => Ok(Some(value)),
		Err(status) if status.code() == Code::NotFound => Ok(None),
		Err(status) => Err(failed(what)(status)),
	}
}

/// What is there already, as made.
fn made<T>(result: Result<T, Status>, what: &str) -> Result<Option<T>, Fault> {
	match result {
		Ok(value) => Ok(Some(value)),
		Err(status) if status.code() == Code::AlreadyExists => Ok(None),
		Err(status) => Err(failed(what)(status)),
	}
}

fn varint(mut number: u64, into: &mut Vec<u8>) {
	while number >= 0x80 {
		into.push(u8::try_from(number & 0x7f).unwrap_or_default() | 0x80);
		number >>= 7;
	}
	into.push(u8::try_from(number).unwrap_or_default());
}

/// `containerd.runc.v1.Options` naming the runtime's binary, encoded as protobuf writes it.
fn runc_options(binary: &Path) -> Vec<u8> {
	let name = binary.to_string_lossy();
	let mut bytes = vec![BINARY_NAME];
	varint(u64::try_from(name.len()).unwrap_or_default(), &mut bytes);
	bytes.extend_from_slice(name.as_bytes());
	bytes
}

fn to_ours(mounts: Vec<containerd_client::types::Mount>) -> Vec<Mount> {
	mounts
		.into_iter()
		.map(|m| Mount { kind: m.r#type, source: m.source, options: m.options })
		.collect()
}

fn to_theirs(mounts: &[Mount]) -> Vec<containerd_client::types::Mount> {
	mounts
		.iter()
		.map(|m| containerd_client::types::Mount {
			r#type: m.kind.clone(),
			source: m.source.clone(),
			target: String::new(),
			options: m.options.clone(),
		})
		.collect()
}

fn task_of(process: &Process) -> Task {
	match Run::try_from(process.status) {
		Ok(Run::Created) => Task::Created,
		Ok(Run::Running) => Task::Running,
		Ok(Run::Stopped) => Task::Stopped(process.exit_status),
		Ok(Run::Unknown | Run::Paused | Run::Pausing) | Err(_) => Task::Other,
	}
}

/// The subvolume id a btrfs mount names, `subvolid=<n>` among its options.
fn subvolume_id(mounts: &[containerd_client::types::Mount]) -> Option<&str> {
	mounts.iter().flat_map(|m| m.options.iter()).find_map(|o| o.strip_prefix("subvolid="))
}

impl Socket {
	async fn channel(&self) -> Result<Channel, Fault> {
		containerd_client::connect(&self.path)
			.await
			.map_err(|e| Fault(format!("{}: {e}", self.path.display())))
	}

	async fn task(
		&self,
		channel: &Channel,
		namespace: &str,
		id: &str,
	) -> Result<Option<Process>, Fault> {
		let request =
			within(namespace, GetRequest { container_id: id.to_owned(), exec_id: String::new() })?;
		let got = found(TasksClient::new(channel.clone()).get(request).await, "get the task")?;
		Ok(got.and_then(|r| r.into_inner().process))
	}

	async fn container(
		&self,
		channel: &Channel,
		namespace: &str,
		id: &str,
	) -> Result<Option<Container>, Fault> {
		let request = within(namespace, GetContainerRequest { id: id.to_owned() })?;
		let got =
			found(ContainersClient::new(channel.clone()).get(request).await, "get the container")?;
		Ok(got.and_then(|r| r.into_inner().container))
	}

	async fn mounts(
		&self,
		channel: &Channel,
		namespace: &str,
		key: &str,
	) -> Result<Vec<containerd_client::types::Mount>, Fault> {
		let request = within(
			namespace,
			MountsRequest { snapshotter: SNAPSHOTTER.to_owned(), key: key.to_owned() },
		)?;
		let response = SnapshotsClient::new(channel.clone())
			.mounts(request)
			.await
			.map_err(failed("the snapshot's mounts"))?;
		Ok(response.into_inner().mounts)
	}

	async fn create_task(
		&self,
		channel: &Channel,
		namespace: &str,
		id: &str,
		rootfs: Vec<containerd_client::types::Mount>,
		output: &Path,
	) -> Result<(), Fault> {
		if let Some(parent) = output.parent() {
			tokio::fs::create_dir_all(parent)
				.await
				.map_err(|e| Fault(format!("{}: {e}", parent.display())))?;
		}
		let uri = format!("file://{}", output.display());
		let request = within(
			namespace,
			CreateTaskRequest {
				container_id: id.to_owned(),
				rootfs,
				stdout: uri.clone(),
				stderr: uri,
				..Default::default()
			},
		)?;
		made(TasksClient::new(channel.clone()).create(request).await, "create the task")?;
		Ok(())
	}

	/// The snapshot's lease ended, none to end being no failure.
	async fn release(&self, channel: &Channel, namespace: &str, key: &str) -> Result<(), Fault> {
		let request = within(namespace, DeleteLease { id: lease(key), sync: false })?;
		found(LeasesClient::new(channel.clone()).delete(request).await, "end the snapshot's lease")?;
		Ok(())
	}

	async fn kill(
		&self,
		channel: &Channel,
		namespace: &str,
		id: &str,
		signal: u32,
	) -> Result<(), Fault> {
		let request = within(
			namespace,
			KillRequest { container_id: id.to_owned(), exec_id: String::new(), signal, all: true },
		)?;
		found(TasksClient::new(channel.clone()).kill(request).await, "signal the task")?;
		Ok(())
	}

	async fn wait(&self, channel: &Channel, namespace: &str, id: &str) -> Result<(), Fault> {
		let request =
			within(namespace, WaitRequest { container_id: id.to_owned(), exec_id: String::new() })?;
		found(TasksClient::new(channel.clone()).wait(request).await, "wait on the task")?;
		Ok(())
	}

	/// The task signalled, waited on so long, then killed and waited on.
	async fn ended(
		&self,
		channel: &Channel,
		namespace: &str,
		id: &str,
		grace: u64,
	) -> Result<(), Fault> {
		self.kill(channel, namespace, id, SIGTERM).await?;
		match tokio::time::timeout(Duration::from_millis(grace), self.wait(channel, namespace, id))
			.await
		{
			Ok(waited) => waited,
			Err(_) => {
				self.kill(channel, namespace, id, SIGKILL).await?;
				self.wait(channel, namespace, id).await
			}
		}
	}
}

impl Containerd for Socket {
	async fn import(&self, namespace: &str, archive: &Path) -> Result<Image, Fault> {
		let channel = self.channel().await?;
		import::imported(&channel, namespace, archive).await
	}

	async fn prepare(&self, namespace: &str, key: &str, image: &Image) -> Result<Vec<Mount>, Fault> {
		let channel = self.channel().await?;
		let held = within(namespace, CreateLease { id: lease(key), labels: HashMap::new() })?;
		made(LeasesClient::new(channel.clone()).create(held).await, "lease the snapshot")?;
		let mut request = within(
			namespace,
			PrepareSnapshotRequest {
				snapshotter: SNAPSHOTTER.to_owned(),
				key: key.to_owned(),
				parent: image.chain.clone(),
				labels: HashMap::new(),
			},
		)?;
		let leased =
			MetadataValue::try_from(lease(key)).map_err(|_| Fault(format!("{key}: no lease's id")))?;
		request.metadata_mut().insert("containerd-lease", leased);
		match made(
			SnapshotsClient::new(channel.clone()).prepare(request).await,
			"prepare the snapshot",
		)? {
			Some(prepared) => Ok(to_ours(prepared.into_inner().mounts)),
			None => Ok(to_ours(self.mounts(&channel, namespace, key).await?)),
		}
	}

	async fn snapshot_path(&self, namespace: &str, key: &str) -> Result<PathBuf, Fault> {
		let channel = self.channel().await?;
		let filter = format!("type==io.containerd.snapshotter.v1,id=={SNAPSHOTTER}");
		let plugins = IntrospectionClient::new(channel.clone())
			.plugins(PluginsRequest { filters: vec![filter] })
			.await
			.map_err(failed("the snapshotter's plugin"))?
			.into_inner()
			.plugins;
		let root = plugins
			.iter()
			.find_map(|p| p.exports.get("root"))
			.map(PathBuf::from)
			.ok_or_else(|| Fault("the btrfs snapshotter exports no root".into()))?;
		let mounts = self.mounts(&channel, namespace, key).await?;
		let id =
			subvolume_id(&mounts).ok_or_else(|| Fault(format!("{key}: its mounts name no subvolid")))?;
		// The snapshotter keeps an active snapshot at `<root>/active/<its own id>`, which only btrfs
		// tells from the subvolume's id; the command is the system's, as the snapshotter's own is.
		let output = tokio::process::Command::new("btrfs")
			.args(["inspect-internal", "subvolid-resolve", id])
			.arg(&root)
			.output()
			.await
			.map_err(|e| Fault(format!("btrfs inspect-internal subvolid-resolve: {e}")))?;
		let resolved = String::from_utf8_lossy(&output.stdout);
		let resolved = Path::new(resolved.trim());
		let own = resolved.file_name().filter(|_| output.status.success());
		let active = resolved.parent().and_then(Path::file_name).is_some_and(|p| p == "active");
		match own {
			Some(own) if active => Ok(root.join("active").join(own)),
			Some(_) | None => Err(Fault(format!(
				"subvolume {id} of {key} resolves to {} {}",
				resolved.display(),
				String::from_utf8_lossy(&output.stderr).trim()
			))),
		}
	}

	async fn create(
		&self,
		namespace: &str,
		spec: &Spec,
		rootfs: &[Mount],
		output: &Path,
	) -> Result<(), Fault> {
		let channel = self.channel().await?;
		let mut labels: HashMap<String, String> = spec.labels.clone().into_iter().collect();
		labels.insert(OUTPUT.to_owned(), output.display().to_string());
		let runtime_spec = serde_json::to_vec(&spec.runtime_spec)
			.map_err(|e| Fault(format!("the runtime spec: {e}")))?;
		let options = Any { type_url: RUNC_OPTIONS.to_owned(), value: runc_options(&spec.binary) };
		let container = Container {
			id: spec.id.clone(),
			labels,
			image: spec.image.clone(),
			runtime: Some(Runtime { name: SHIM.to_owned(), options: Some(options) }),
			spec: Some(Any { type_url: SPEC_TYPE.to_owned(), value: runtime_spec }),
			snapshotter: SNAPSHOTTER.to_owned(),
			snapshot_key: spec.snapshot.clone(),
			..Default::default()
		};
		let request = within(namespace, CreateContainerRequest { container: Some(container) })?;
		made(ContainersClient::new(channel.clone()).create(request).await, "create the container")?;
		self.release(&channel, namespace, &spec.snapshot).await?;
		self.create_task(&channel, namespace, &spec.id, to_theirs(rootfs), output).await
	}

	async fn start(&self, namespace: &str, id: &str) -> Result<u32, Fault> {
		let channel = self.channel().await?;
		let task = self.task(&channel, namespace, id).await?;
		let state = task.as_ref().map(task_of);
		match state {
			Some(Task::Running) => return Ok(task.map_or(0, |t| t.pid)),
			Some(Task::Created) => {}
			Some(Task::Other) => {
				return Err(Fault(format!("{id}: its task is neither created, running nor stopped")));
			}
			Some(Task::Stopped(_)) | None => {
				// A task ended is not started again: it is deleted and made anew, as it was made.
				if state.is_some() {
					let request = within(namespace, DeleteTaskRequest { container_id: id.to_owned() })?;
					found(TasksClient::new(channel.clone()).delete(request).await, "delete the task")?;
				}
				let container = self
					.container(&channel, namespace, id)
					.await?
					.ok_or_else(|| Fault(format!("{id}: no container")))?;
				let output =
					container.labels.get(OUTPUT).ok_or_else(|| Fault(format!("{id}: no label {OUTPUT}")))?;
				let rootfs = self.mounts(&channel, namespace, &container.snapshot_key).await?;
				self.create_task(&channel, namespace, id, rootfs, Path::new(output)).await?;
			}
		}
		let request =
			within(namespace, StartRequest { container_id: id.to_owned(), exec_id: String::new() })?;
		let started =
			TasksClient::new(channel).start(request).await.map_err(failed("start the task"))?;
		Ok(started.into_inner().pid)
	}

	async fn stop(&self, namespace: &str, id: &str, grace: u64) -> Result<(), Fault> {
		let channel = self.channel().await?;
		match self.task(&channel, namespace, id).await?.as_ref().map(task_of) {
			None | Some(Task::Stopped(_)) => Ok(()),
			Some(Task::Created | Task::Running | Task::Other) => {
				self.ended(&channel, namespace, id, grace).await
			}
		}
	}

	async fn remove(&self, namespace: &str, id: &str) -> Result<(), Fault> {
		let channel = self.channel().await?;
		match self.task(&channel, namespace, id).await?.as_ref().map(task_of) {
			None => {}
			Some(state) => {
				match state {
					Task::Stopped(_) => {}
					Task::Created | Task::Running | Task::Other => {
						self.kill(&channel, namespace, id, SIGKILL).await?;
						self.wait(&channel, namespace, id).await?;
					}
				}
				let request = within(namespace, DeleteTaskRequest { container_id: id.to_owned() })?;
				found(TasksClient::new(channel.clone()).delete(request).await, "delete the task")?;
			}
		}
		// Where the container is gone already, its snapshot is found by the key it was made with.
		let key = self
			.container(&channel, namespace, id)
			.await?
			.map_or_else(|| id.to_owned(), |c| c.snapshot_key);
		let request = within(namespace, DeleteContainerRequest { id: id.to_owned() })?;
		found(ContainersClient::new(channel.clone()).delete(request).await, "delete the container")?;
		let request = within(
			namespace,
			RemoveSnapshotRequest { snapshotter: SNAPSHOTTER.to_owned(), key: key.clone() },
		)?;
		found(SnapshotsClient::new(channel.clone()).remove(request).await, "remove the snapshot")?;
		self.release(&channel, namespace, &key).await
	}

	async fn list(&self, namespace: &str) -> Result<Vec<Listed>, Fault> {
		let channel = self.channel().await?;
		let request = within(namespace, ListContainersRequest { filters: Vec::new() })?;
		let containers = ContainersClient::new(channel.clone())
			.list(request)
			.await
			.map_err(failed("list the containers"))?
			.into_inner()
			.containers;
		let request = within(namespace, ListTasksRequest { filter: String::new() })?;
		let tasks: BTreeMap<String, Task> = TasksClient::new(channel)
			.list(request)
			.await
			.map_err(failed("list the tasks"))?
			.into_inner()
			.tasks
			.iter()
			// A task listed names its container by its own id, `container_id` left for an exec's.
			.map(|p| {
				let of = if p.container_id.is_empty() { &p.id } else { &p.container_id };
				(of.clone(), task_of(p))
			})
			.collect();
		Ok(
			containers
				.into_iter()
				.map(|c| Listed {
					task: tasks.get(&c.id).copied(),
					labels: c.labels.into_iter().collect(),
					id: c.id,
				})
				.collect(),
		)
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn the_binary_is_field_six_of_the_options() {
		let bytes = runc_options(Path::new("/run/current-system/sw/bin/crun"));
		assert_eq!(bytes[0], 0x32);
		assert_eq!(bytes[1], 31);
		assert_eq!(&bytes[2..], b"/run/current-system/sw/bin/crun");
		let mut long = Vec::new();
		varint(300, &mut long);
		assert_eq!(long, [0xac, 0x02]);
	}

	#[test]
	fn a_btrfs_mount_names_its_subvolume() {
		let mounts = vec![containerd_client::types::Mount {
			r#type: "btrfs".into(),
			source: "/dev/vda3".into(),
			target: String::new(),
			options: vec!["subvolid=271".into()],
		}];
		assert_eq!(subvolume_id(&mounts), Some("271"));
	}
}
