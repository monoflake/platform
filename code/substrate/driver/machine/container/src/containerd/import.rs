//! An OCI image layout archive imported by containerd's transfer service over its streaming
//! service, unpacked onto btrfs.
//! https://github.com/containerd/containerd/blob/main/core/transfer/streaming/stream.go

use std::path::Path;

use containerd_client::services::v1::content_client::ContentClient;
use containerd_client::services::v1::images_client::ImagesClient;
use containerd_client::services::v1::snapshots::UsageRequest;
use containerd_client::services::v1::snapshots::snapshots_client::SnapshotsClient;
use containerd_client::services::v1::streaming_client::StreamingClient;
use containerd_client::services::v1::transfer_client::TransferClient;
use containerd_client::services::v1::{
	GetImageRequest, ReadContentRequest, StreamInit, TransferRequest,
};
use containerd_client::to_any;
use containerd_client::tonic::codegen::tokio_stream::wrappers::ReceiverStream;
use containerd_client::tonic::transport::Channel;
use containerd_client::types::Platform as Theirs;
use containerd_client::types::transfer::{
	Data, ImageImportStream, ImageStore, UnpackConfiguration,
};
use serde_json::Value;
use tokio::io::AsyncReadExt;

use super::oci::{self, Kind, Platform};
use super::{SNAPSHOTTER, failed, within};
use crate::{Fault, Image};

/// The most a chunk sent holds, as containerd's own client sends.
const CHUNK: usize = 32 * 1024;
/// The most an index, a manifest or a configuration may be.
const BLOB: usize = 4 * 1024 * 1024;
/// How deep indexes may nest before a manifest.
const DEPTH: usize = 4;
const WINDOW_UPDATE: &str = "containerd.types.transfer.WindowUpdate";

/// The `update` a `WindowUpdate` carries, field 1, a varint.
fn window(value: &[u8]) -> i64 {
	let Some((&0x08, rest)) = value.split_first() else {
		return 0;
	};
	let mut number: u64 = 0;
	for (at, byte) in rest.iter().take(10).enumerate() {
		number |= u64::from(byte & 0x7f) << (7 * at);
		if byte & 0x80 == 0 {
			break;
		}
	}
	// An int32's varint, a negative one never sent.
	i64::from(i32::try_from(number).unwrap_or_default())
}

/// The archive's name in the namespace, after its file.
fn named(archive: &Path) -> String {
	let stem = archive.file_stem().map_or_else(|| "artifact".into(), |s| s.to_string_lossy());
	format!("artifact/{stem}")
}

pub(super) async fn imported(
	channel: &Channel,
	namespace: &str,
	archive: &Path,
) -> Result<Image, Fault> {
	let name = named(archive);
	let stream = format!("import-{}", name.replace('/', "-"));
	let mut file = tokio::fs::File::open(archive)
		.await
		.map_err(|e| Fault(format!("{}: {e}", archive.display())))?;

	let (sender, receiver) = tokio::sync::mpsc::channel(8);
	let gone = |_| Fault("the import stream closed".into());
	sender.send(to_any(&StreamInit { id: stream.clone() })).await.map_err(gone)?;
	let mut inbound = StreamingClient::new(channel.clone())
		.stream(within(namespace, ReceiverStream::new(receiver))?)
		.await
		.map_err(failed("open the import stream"))?
		.into_inner();
	inbound.message().await.map_err(failed("the import stream's ack"))?;

	let here = Platform::here();
	let platform =
		Theirs { os: here.os.into(), architecture: here.architecture.into(), ..Default::default() };
	let source =
		to_any(&ImageImportStream { stream, media_type: String::new(), force_compress: false });
	let destination = to_any(&ImageStore {
		name: name.clone(),
		unpacks: vec![UnpackConfiguration {
			platform: Some(platform),
			snapshotter: SNAPSHOTTER.into(),
		}],
		..Default::default()
	});
	let request = within(
		namespace,
		TransferRequest { source: Some(source), destination: Some(destination), options: None },
	)?;
	let mut client = TransferClient::new(channel.clone());
	let transfer = client.transfer(request);

	// The archive is sent as the receiver opens its window, and the stream closed at its end.
	let send = async move {
		let mut open: i64 = 0;
		let mut buffer = vec![0u8; CHUNK];
		loop {
			while open <= 0 {
				match inbound.message().await.map_err(failed("the import stream"))? {
					Some(any) if any.type_url.ends_with(WINDOW_UPDATE) => open += window(&any.value),
					Some(_) => {}
					None => return Ok::<(), Fault>(()),
				}
			}
			let most = usize::try_from(open).unwrap_or(CHUNK).min(CHUNK);
			let chunk = buffer.get_mut(..most).unwrap_or_default();
			let read =
				file.read(chunk).await.map_err(|e| Fault(format!("{}: {e}", archive.display())))?;
			let Some(data) = chunk.get(..read).filter(|d| !d.is_empty()) else {
				break;
			};
			open -= i64::try_from(read).unwrap_or(open);
			sender.send(to_any(&Data { data: data.to_vec() })).await.map_err(gone)?;
		}
		drop(sender);
		// What the receiver still says is read to its end, so the stream closes as it means to.
		while inbound.message().await.map_err(failed("the import stream"))?.is_some() {}
		Ok(())
	};
	tokio::pin!(transfer);
	tokio::select! {
		done = &mut transfer => { done.map_err(failed("import the archive"))?; }
		sent = send => {
			sent?;
			transfer.await.map_err(failed("import the archive"))?;
		}
	}
	read_image(channel, namespace, &name, &here).await
}

async fn blob(channel: &Channel, namespace: &str, digest: &str) -> Result<Value, Fault> {
	let request =
		within(namespace, ReadContentRequest { digest: digest.to_owned(), offset: 0, size: 0 })?;
	let mut stream = ContentClient::new(channel.clone())
		.read(request)
		.await
		.map_err(failed("read content"))?
		.into_inner();
	let mut bytes = Vec::new();
	while let Some(part) = stream.message().await.map_err(failed("read content"))? {
		bytes.extend_from_slice(&part.data);
		if bytes.len() > BLOB {
			return Err(Fault(format!("{digest}: past {BLOB} bytes")));
		}
	}
	serde_json::from_slice(&bytes).map_err(|e| Fault(format!("{digest}: {e}")))
}

/// The image as the namespace holds it, its manifest for this platform, configuration, layers'
/// chain and unpacked size.
async fn read_image(
	channel: &Channel,
	namespace: &str,
	name: &str,
	here: &Platform,
) -> Result<Image, Fault> {
	let request = within(namespace, GetImageRequest { name: name.to_owned() })?;
	let target = ImagesClient::new(channel.clone())
		.get(request)
		.await
		.map_err(failed("get the image"))?
		.into_inner()
		.image
		.and_then(|i| i.target)
		.ok_or_else(|| Fault(format!("{name}: no target")))?;
	let mut at = oci::Descriptor { media_type: target.media_type, digest: target.digest };
	let mut manifest = None;
	for _ in 0..DEPTH {
		let read = blob(channel, namespace, &at.digest).await?;
		match oci::kind(&at.media_type) {
			Some(Kind::Index) => at = oci::chosen(&read, here)?,
			Some(Kind::Manifest) => {
				manifest = Some(read);
				break;
			}
			None => {
				return Err(Fault(format!(
					"{}: a media type not an image's, {}",
					at.digest, at.media_type
				)));
			}
		}
	}
	let manifest = manifest.ok_or_else(|| Fault(format!("{name}: indexes nested past {DEPTH}")))?;
	let config = blob(channel, namespace, &oci::config_of(&manifest)?.digest).await?;
	let chain = oci::chain_ids(&config)?;
	let mut size: u64 = 0;
	for key in &chain {
		let request =
			within(namespace, UsageRequest { snapshotter: SNAPSHOTTER.to_owned(), key: key.clone() })?;
		let usage = SnapshotsClient::new(channel.clone())
			.usage(request)
			.await
			.map_err(failed("a layer's usage"))?;
		size = size.saturating_add(u64::try_from(usage.into_inner().size).unwrap_or_default());
	}
	let top = chain.last().cloned().ok_or_else(|| Fault(format!("{name}: no layers")))?;
	Ok(Image { name: name.to_owned(), chain: top, config: oci::image_config(&config), size })
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn a_window_update_is_read_from_its_bytes() {
		// 65536, containerd's window, as protobuf writes field 1.
		assert_eq!(window(&[0x08, 0x80, 0x80, 0x04]), 65536);
		assert_eq!(window(&[]), 0);
	}

	#[test]
	fn an_archive_is_named_after_its_file() {
		assert_eq!(named(Path::new("/var/lib/x/b1-ab12.tar")), "artifact/b1-ab12");
	}
}
