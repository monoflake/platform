//! A WebSocket as the mesh and the browser use one, whichever end opened it: axum's for what this
//! relay accepts, tungstenite's for what it dials.

use axum::extract::ws::{Message as Accepted, WebSocket};
use bytes::Bytes;
use futures_util::{SinkExt, StreamExt};
use std::future::Future;
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message as Dialed;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

#[derive(Debug, thiserror::Error)]
#[error("the socket: {0}")]
pub struct SocketError(#[source] Box<dyn std::error::Error + Send + Sync>);

/// A frame, of what this relay reads: text, a pong, or the other end gone. Pings are answered
/// beneath.
#[derive(Debug, PartialEq, Eq)]
pub enum Received {
	Text(String),
	/// The answer to a ping, carrying back what the ping carried.
	Pong(Bytes),
	Closed,
	/// A ping or binary: proof of life, and nothing more.
	Other,
}

pub trait Socket: Send {
	fn send_text(&mut self, text: String) -> impl Future<Output = Result<(), SocketError>> + Send;
	fn ping(&mut self, payload: Bytes) -> impl Future<Output = Result<(), SocketError>> + Send;
	/// Cancel-safe, so it can wait in a `select!` beside the updates.
	fn receive(&mut self) -> impl Future<Output = Result<Received, SocketError>> + Send;
}

impl Socket for WebSocket {
	async fn send_text(&mut self, text: String) -> Result<(), SocketError> {
		self.send(Accepted::Text(text.into())).await.map_err(|error| SocketError(error.into()))
	}

	async fn ping(&mut self, payload: Bytes) -> Result<(), SocketError> {
		self.send(Accepted::Ping(payload)).await.map_err(|error| SocketError(error.into()))
	}

	async fn receive(&mut self) -> Result<Received, SocketError> {
		Ok(match self.recv().await {
			None | Some(Ok(Accepted::Close(_))) => Received::Closed,
			Some(Ok(Accepted::Text(text))) => Received::Text(text.as_str().to_owned()),
			Some(Ok(Accepted::Pong(payload))) => Received::Pong(payload),
			Some(Ok(_)) => Received::Other,
			Some(Err(error)) => return Err(SocketError(error.into())),
		})
	}
}

pub type Dial = WebSocketStream<MaybeTlsStream<TcpStream>>;

impl Socket for Dial {
	async fn send_text(&mut self, text: String) -> Result<(), SocketError> {
		self.send(Dialed::Text(text.into())).await.map_err(|error| SocketError(error.into()))
	}

	async fn ping(&mut self, payload: Bytes) -> Result<(), SocketError> {
		self.send(Dialed::Ping(payload)).await.map_err(|error| SocketError(error.into()))
	}

	async fn receive(&mut self) -> Result<Received, SocketError> {
		Ok(match self.next().await {
			None | Some(Ok(Dialed::Close(_))) => Received::Closed,
			Some(Ok(Dialed::Text(text))) => Received::Text(text.as_str().to_owned()),
			Some(Ok(Dialed::Pong(payload))) => Received::Pong(payload),
			Some(Ok(_)) => Received::Other,
			Some(Err(error)) => return Err(SocketError(error.into())),
		})
	}
}
