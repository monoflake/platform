//! The proxy: each connection passed whole, byte for byte, to the member that is the target when it
//! arrives, and closed the moment that member stops being it -- HAProxy's `on-marked-down
//! shutdown-sessions`, which Pigsty sets in roles/pgsql/templates/service.cfg. With no target, a
//! connection is closed as it is accepted. No TLS is ended, nothing pooled, nothing parsed.

use crate::check::Timings;
use crate::config::Member;
use crate::state::State;
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Mutex, Semaphore};

pub struct Proxy {
	pub state: Arc<State>,
	pub members: HashMap<String, Member>,
	pub timings: Timings,
	slots: Arc<Semaphore>,
	waiting: AtomicUsize,
}

impl Proxy {
	pub fn new(state: Arc<State>, members: &[Member], timings: Timings) -> Arc<Self> {
		Arc::new(Self {
			state,
			members: members.iter().map(|member| (member.name.clone(), member.clone())).collect(),
			slots: Arc::new(Semaphore::new(timings.maxconn)),
			timings,
			waiting: AtomicUsize::new(0),
		})
	}

	pub async fn serve(self: Arc<Self>, listener: TcpListener) {
		loop {
			let Ok((client, _)) = listener.accept().await else { continue };
			let proxy = self.clone();
			tokio::spawn(async move { proxy.pass(client).await });
		}
	}

	/// One connection, from accepting it to closing it. Dropping a stream closes it. The target is
	/// read from a subscription taken first, and read again once the slot is had and the member
	/// reached, so a move while it waited closes the connection rather than pumping it to a member
	/// that is no longer primary.
	async fn pass(&self, client: TcpStream) {
		let mut changes = self.state.watch();
		let Some(name) = changes.borrow_and_update().member().map(str::to_owned) else { return };
		let Some(member) = self.members.get(&name) else { return };
		let Some(_slot) = self.slot().await else { return };
		let Some(server) = self.connect(member).await else { return };
		if changes.borrow_and_update().member() != Some(name.as_str()) {
			return;
		}
		let _ = client.set_nodelay(true);
		let _ = server.set_nodelay(true);
		let moved = async move {
			loop {
				if changes.changed().await.is_err() {
					return;
				}
				if changes.borrow_and_update().member() != Some(name.as_str()) {
					return;
				}
			}
		};
		tokio::select! {
			() = pump(client, server, self.timings.idle) => {}
			() = moved => {}
		}
	}

	/// A slot among `maxconn`, waited for `queue_timeout` at most and by `maxqueue` at once.
	async fn slot(&self) -> Option<tokio::sync::OwnedSemaphorePermit> {
		if let Ok(slot) = self.slots.clone().try_acquire_owned() {
			return Some(slot);
		}
		if self.waiting.fetch_add(1, Ordering::SeqCst) >= self.timings.maxqueue {
			self.waiting.fetch_sub(1, Ordering::SeqCst);
			return None;
		}
		let slot =
			tokio::time::timeout(self.timings.queue_timeout, self.slots.clone().acquire_owned()).await;
		self.waiting.fetch_sub(1, Ordering::SeqCst);
		slot.ok()?.ok()
	}

	/// The target's Postgres, tried once and then `retries` times more, each `connect_timeout`.
	async fn connect(&self, member: &Member) -> Option<TcpStream> {
		let address = member.postgres_address();
		for _ in 0..=self.timings.retries {
			let attempt = TcpStream::connect(address.as_str());
			if let Ok(Ok(stream)) = tokio::time::timeout(self.timings.connect_timeout, attempt).await {
				return Some(stream);
			}
		}
		eprintln!("primary: {} did not take a connection; it was closed", member.name);
		None
	}
}

/// Both directions copied until either ends or nothing has passed either way for `idle`.
async fn pump(client: TcpStream, server: TcpStream, idle: std::time::Duration) {
	let last = Arc::new(Mutex::new(Instant::now()));
	let (client_in, client_out) = client.into_split();
	let (server_in, server_out) = server.into_split();
	let quiet = {
		let last = last.clone();
		async move {
			loop {
				let since = last.lock().await.elapsed();
				if since >= idle {
					return;
				}
				tokio::time::sleep(idle - since).await;
			}
		}
	};
	tokio::select! {
		() = copy(client_in, server_out, last.clone()) => {}
		() = copy(server_in, client_out, last) => {}
		() = quiet => {}
	}
}

async fn copy(
	mut from: tokio::net::tcp::OwnedReadHalf,
	mut to: tokio::net::tcp::OwnedWriteHalf,
	last: Arc<Mutex<Instant>>,
) {
	let mut buffer = vec![0; 32 * 1024];
	loop {
		match from.read(&mut buffer).await {
			Ok(0) | Err(_) => return,
			Ok(read) => {
				if to.write_all(&buffer[..read]).await.is_err() {
					return;
				}
				*last.lock().await = Instant::now();
			}
		}
	}
}
