//! A container's network: a named network namespace, `/run/netns/<id>` as `ip netns` makes it,
//! joined to a bridge by the CNI plugins `loopback`, `bridge` and `host-local`, each run by its
//! binary as a runtime runs one. What `bridge` answered to ADD is kept, as DEL is given it again.
//! https://github.com/containernetworking/cni/blob/main/SPEC.md

use std::net::{IpAddr, SocketAddr};
use std::path::{Path, PathBuf};
use std::process::Stdio;

use serde_json::{Value, json};
use tokio::io::AsyncWriteExt;

use crate::{Attachment, Bridge, Fault, Network};

/// The CNI version the configuration is written in.
const VERSION: &str = "1.0.0";

/// Where named network namespaces are, as `ip netns` keeps them.
const NETNS: &str = "/run/netns";

/// The interface a container reaches the bridge by.
const INTERFACE: &str = "eth0";

/// What one plugin is asked: its command and its interface.
struct Call<'a> {
	command: &'a str,
	id: &'a str,
	interface: &'a str,
	netns: &'a Path,
}

impl Bridge {
	fn kept(&self, id: &str) -> PathBuf {
		self.state.join(format!("{id}.json"))
	}

	fn loopback(&self) -> Value {
		json!({ "cniVersion": VERSION, "name": "loopback", "type": "loopback" })
	}

	// open: who may reach a container's address from beyond the machine, and what may leave it,
	// `?egress`, are not decided. Until they are, nothing forwards a port to it, its bridge
	// masquerades what leaves, and no rule keeps one container from another on the bridge.
	fn bridge(&self) -> Value {
		json!({
			"cniVersion": VERSION,
			"name": self.name,
			"type": "bridge",
			"bridge": self.name,
			"isGateway": true,
			"ipMasq": true,
			"hairpinMode": true,
			"ipam": {
				"type": "host-local",
				"ranges": [[{ "subnet": self.subnet }]],
				"routes": [{ "dst": "0.0.0.0/0" }],
				"dataDir": self.state.join("ipam"),
			},
		})
	}

	/// A plugin run with its configuration on its input, and what it answered.
	async fn plugin(&self, kind: &str, call: &Call<'_>, config: &Value) -> Result<Value, Fault> {
		let binary = self.plugins.join(kind);
		let at = |e: std::io::Error| Fault(format!("{} {}: {e}", binary.display(), call.command));
		let mut child = tokio::process::Command::new(&binary)
			.env("CNI_COMMAND", call.command)
			.env("CNI_CONTAINERID", call.id)
			.env("CNI_NETNS", call.netns)
			.env("CNI_IFNAME", call.interface)
			.env("CNI_PATH", &self.plugins)
			.stdin(Stdio::piped())
			.stdout(Stdio::piped())
			.stderr(Stdio::piped())
			.spawn()
			.map_err(at)?;
		if let Some(mut input) = child.stdin.take() {
			input.write_all(config.to_string().as_bytes()).await.map_err(at)?;
		}
		let output = child.wait_with_output().await.map_err(at)?;
		let answered = String::from_utf8_lossy(&output.stdout);
		if output.status.success() {
			if answered.trim().is_empty() {
				return Ok(Value::Null);
			}
			return serde_json::from_str(&answered)
				.map_err(|e| Fault(format!("{} {}: its answer: {e}", binary.display(), call.command)));
		}
		Err(Fault(format!(
			"{} {}: {} {}",
			binary.display(),
			call.command,
			answered.trim(),
			String::from_utf8_lossy(&output.stderr).trim()
		)))
	}

	async fn ip(&self, args: &[&str]) -> Result<(), Fault> {
		let output = tokio::process::Command::new("ip")
			.args(args)
			.output()
			.await
			.map_err(|e| Fault(format!("ip {}: {e}", args.join(" "))))?;
		if output.status.success() {
			Ok(())
		} else {
			Err(Fault(format!(
				"ip {}: {}",
				args.join(" "),
				String::from_utf8_lossy(&output.stderr).trim()
			)))
		}
	}

	/// What ADD made undone, by what it answered.
	async fn undone(&self, id: &str, netns: &Path, answered: &Value) -> Result<(), Fault> {
		let mut config = self.bridge();
		if let Some(object) = config.as_object_mut() {
			object.insert("prevResult".to_owned(), answered.clone());
		}
		self
			.plugin("bridge", &Call { command: "DEL", id, interface: INTERFACE, netns }, &config)
			.await?;
		self
			.plugin("loopback", &Call { command: "DEL", id, interface: "lo", netns }, &self.loopback())
			.await?;
		Ok(())
	}
}

/// The address ADD gave the container's interface, from its result's `ips`.
fn address(answered: &Value) -> Result<IpAddr, Fault> {
	answered
		.get("ips")
		.and_then(Value::as_array)
		.and_then(|ips| ips.first())
		.and_then(|ip| ip.get("address"))
		.and_then(Value::as_str)
		.and_then(|a| a.split('/').next())
		.and_then(|a| a.parse().ok())
		.ok_or_else(|| Fault(format!("bridge ADD answered no address: {answered}")))
}

async fn exists(path: &Path) -> bool {
	tokio::fs::try_exists(path).await.unwrap_or(false)
}

impl Network for Bridge {
	async fn attach(&self, id: &str, port: u16) -> Result<Attachment, Fault> {
		let netns = Path::new(NETNS).join(id);
		let kept = self.kept(id);
		let at = |e: std::io::Error, p: &Path| Fault(format!("{}: {e}", p.display()));
		if let Ok(text) = tokio::fs::read_to_string(&kept).await {
			let answered: Value =
				serde_json::from_str(&text).map_err(|e| Fault(format!("{}: {e}", kept.display())))?;
			if exists(&netns).await {
				return Ok(Attachment { address: SocketAddr::new(address(&answered)?, port), netns });
			}
			// The namespace went with a restart: its address is given back, and all made again.
			self.undone(id, &netns, &answered).await?;
			tokio::fs::remove_file(&kept).await.map_err(|e| at(e, &kept))?;
		}
		tokio::fs::create_dir_all(&self.state).await.map_err(|e| at(e, &self.state))?;
		if !exists(&netns).await {
			self.ip(&["netns", "add", id]).await?;
		}
		self
			.plugin(
				"loopback",
				&Call { command: "ADD", id, interface: "lo", netns: &netns },
				&self.loopback(),
			)
			.await?;
		let answered = self
			.plugin(
				"bridge",
				&Call { command: "ADD", id, interface: INTERFACE, netns: &netns },
				&self.bridge(),
			)
			.await?;
		tokio::fs::write(&kept, answered.to_string()).await.map_err(|e| at(e, &kept))?;
		Ok(Attachment { address: SocketAddr::new(address(&answered)?, port), netns })
	}

	async fn detach(&self, id: &str) -> Result<(), Fault> {
		let netns = Path::new(NETNS).join(id);
		let kept = self.kept(id);
		if let Ok(text) = tokio::fs::read_to_string(&kept).await {
			let answered: Value =
				serde_json::from_str(&text).map_err(|e| Fault(format!("{}: {e}", kept.display())))?;
			self.undone(id, &netns, &answered).await?;
			tokio::fs::remove_file(&kept).await.map_err(|e| Fault(format!("{}: {e}", kept.display())))?;
		}
		if exists(&netns).await {
			self.ip(&["netns", "delete", id]).await?;
		}
		Ok(())
	}
}

#[cfg(test)]
mod tests {
	use super::address;
	use serde_json::json;

	#[test]
	fn the_address_is_the_first_of_the_result() {
		let answered = json!({
			"cniVersion": "1.0.0",
			"interfaces": [{ "name": "eth0", "sandbox": "/run/netns/x" }],
			"ips": [{ "interface": 0, "address": "10.88.0.7/16", "gateway": "10.88.0.1" }],
		});
		assert_eq!(address(&answered).unwrap().to_string(), "10.88.0.7");
		assert!(address(&json!({ "ips": [] })).is_err());
	}
}
