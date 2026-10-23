//! Answers each call to echo with the body it was sent, over HTTP at the port it is deployed with,
//! as tests/fixtures/echo-image describes. A fixture's source, one file rustc builds with no crate.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, TcpListener, TcpStream};

/// The port listened on unless `PORT` names another, the one the samples deploy it with.
const PORT: u16 = 8080;

/// One request read and answered, its body sent back where it calls echo.
fn answered(stream: TcpStream) -> std::io::Result<()> {
	let mut reader = BufReader::new(stream.try_clone()?);
	let mut line = String::new();
	reader.read_line(&mut line)?;
	let mut words = line.split_whitespace();
	let (method, path) = (words.next().unwrap_or_default(), words.next().unwrap_or_default());
	let mut length = 0;
	loop {
		let mut header = String::new();
		if reader.read_line(&mut header)? == 0 || header.trim().is_empty() {
			break;
		}
		if let Some((name, value)) = header.split_once(':')
			&& name.trim().eq_ignore_ascii_case("content-length")
		{
			length = value.trim().parse().unwrap_or_default();
		}
	}
	let mut body = vec![0; length];
	reader.read_exact(&mut body)?;
	let (status, body) = match (method, path) {
		("POST", "/echo") => ("200 OK", body),
		_ => ("404 Not Found", b"no export at this path\n".to_vec()),
	};
	let mut stream = stream;
	let head = format!(
		"HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
		body.len()
	);
	stream.write_all(head.as_bytes())?;
	stream.write_all(&body)
}

fn main() -> std::io::Result<()> {
	let port = std::env::var("PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(PORT);
	let listener = TcpListener::bind((Ipv4Addr::UNSPECIFIED, port))?;
	for stream in listener.incoming().flatten() {
		std::thread::spawn(move || answered(stream));
	}
	Ok(())
}
