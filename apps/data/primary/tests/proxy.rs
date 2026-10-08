//! The proxy end to end on the loopback: fake Patroni RESTs whose `/primary` answer is turned at
//! will, and echo servers standing for each member's Postgres, each naming itself in what it
//! sends back.

use axum::Router;
use axum::extract::State as Shared;
use axum::http::StatusCode;
use axum::routing::get;
use primary::check::{PIGSTY, Target, Timings};
use primary::config::Member;
use primary::proxy::Proxy;
use primary::state::State;
use primary::watch;
use std::sync::Arc;
use std::sync::atomic::{AtomicU16, Ordering};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

/// Pigsty's shape, its intervals in tens of milliseconds.
const FAST: Timings = Timings {
	inter: Duration::from_millis(20),
	fastinter: Duration::from_millis(10),
	downinter: Duration::from_millis(20),
	check_timeout: Duration::from_millis(200),
	connect_timeout: Duration::from_millis(200),
	retries: 1,
	maxconn: 100,
	maxqueue: 10,
	queue_timeout: Duration::from_millis(100),
	..PIGSTY
};

struct Fake {
	member: Member,
	answer: Arc<AtomicU16>,
}

/// A member: its REST answering `/primary` with what `answer` holds, and its Postgres an echo that
/// puts its name before what it is sent, or nothing listening at all.
async fn member(name: &str, answer: u16, postgres: bool) -> Fake {
	let answer = Arc::new(AtomicU16::new(answer));
	let rest = TcpListener::bind("127.0.0.1:0").await.unwrap();
	let rest_port = rest.local_addr().unwrap().port();
	let routes = Router::new()
		.route(
			"/primary",
			get(|Shared(answer): Shared<Arc<AtomicU16>>| async move {
				StatusCode::from_u16(answer.load(Ordering::SeqCst)).unwrap()
			}),
		)
		.with_state(answer.clone());
	tokio::spawn(async move { axum::serve(rest, routes).await });
	let echo = TcpListener::bind("127.0.0.1:0").await.unwrap();
	let postgres_port = echo.local_addr().unwrap().port();
	if postgres {
		let name = name.to_owned();
		tokio::spawn(async move {
			while let Ok((mut stream, _)) = echo.accept().await {
				let name = name.clone();
				tokio::spawn(async move {
					let mut buffer = [0; 1024];
					while let Ok(read) = stream.read(&mut buffer).await {
						if read == 0 {
							return;
						}
						let reply = [name.as_bytes(), b":", &buffer[..read]].concat();
						if stream.write_all(&reply).await.is_err() {
							return;
						}
					}
				});
			}
		});
	} else {
		drop(echo);
	}
	let member = Member {
		name: name.into(),
		host: "127.0.0.1".into(),
		rest: rest_port,
		postgres: postgres_port,
	};
	Fake { member, answer }
}

/// The proxy over `fakes`, its checks running, and the port it answers on.
async fn proxy(fakes: &[&Fake]) -> (Arc<State>, u16) {
	proxy_with(fakes, FAST).await
}

async fn proxy_with(fakes: &[&Fake], timings: Timings) -> (Arc<State>, u16) {
	let members: Vec<Member> = fakes.iter().map(|fake| fake.member.clone()).collect();
	let state = Arc::new(State::new(&members));
	let client = watch::asker();
	for member in &members {
		tokio::spawn(watch::check(member.clone(), state.clone(), timings, client.clone()));
	}
	let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
	let port = listener.local_addr().unwrap().port();
	tokio::spawn(Proxy::new(state.clone(), &members, timings).serve(listener));
	(state, port)
}

async fn until(state: &State, wanted: Target) {
	for _ in 0..200 {
		if state.target() == wanted {
			return;
		}
		tokio::time::sleep(Duration::from_millis(10)).await;
	}
	panic!("the target stayed {:?}, not {wanted:?}", state.target());
}

fn one(name: &str) -> Target {
	Target::One { member: name.into() }
}

/// What the far end sends back for `message`, or None when the connection is closed instead.
async fn exchange(stream: &mut TcpStream, message: &str) -> Option<String> {
	stream.write_all(message.as_bytes()).await.ok()?;
	let mut buffer = [0; 1024];
	match tokio::time::timeout(Duration::from_secs(2), stream.read(&mut buffer)).await {
		Ok(Ok(0) | Err(_)) => None,
		Ok(Ok(read)) => Some(String::from_utf8_lossy(&buffer[..read]).into_owned()),
		Err(_) => panic!("neither an answer nor a close"),
	}
}

async fn connect(port: u16) -> TcpStream {
	TcpStream::connect(("127.0.0.1", port)).await.unwrap()
}

#[tokio::test(flavor = "multi_thread")]
async fn passes_bytes_to_the_primary_and_follows_a_switch_closing_the_old_sessions() {
	let (tyo, rdu) = (member("tyo", 200, true).await, member("rdu", 503, true).await);
	let (state, port) = proxy(&[&tyo, &rdu]).await;
	until(&state, one("tyo")).await;
	let mut session = connect(port).await;
	assert_eq!(exchange(&mut session, "select 1").await.as_deref(), Some("tyo:select 1"));

	// tyo stops answering as primary and rdu starts: for a moment both or neither are, then rdu.
	tyo.answer.store(503, Ordering::SeqCst);
	rdu.answer.store(200, Ordering::SeqCst);
	until(&state, one("rdu")).await;
	// The session to tyo is closed at once, not left to write to a demoted member.
	assert_eq!(exchange(&mut session, "select 2").await, None);
	let mut fresh = connect(port).await;
	assert_eq!(exchange(&mut fresh, "select 3").await.as_deref(), Some("rdu:select 3"));
}

#[tokio::test(flavor = "multi_thread")]
async fn closes_new_connections_while_no_member_or_two_answer_as_primary() {
	let (tyo, rdu) = (member("tyo", 503, true).await, member("rdu", 503, true).await);
	let (state, port) = proxy(&[&tyo, &rdu]).await;
	tokio::time::sleep(Duration::from_millis(150)).await;
	assert_eq!(state.target(), Target::None);
	assert_eq!(exchange(&mut connect(port).await, "select 1").await, None);

	tyo.answer.store(200, Ordering::SeqCst);
	rdu.answer.store(200, Ordering::SeqCst);
	until(&state, Target::Many { members: vec!["rdu".into(), "tyo".into()] }).await;
	assert_eq!(exchange(&mut connect(port).await, "select 1").await, None);

	rdu.answer.store(503, Ordering::SeqCst);
	until(&state, one("tyo")).await;
	assert_eq!(exchange(&mut connect(port).await, "select 1").await.as_deref(), Some("tyo:select 1"));
}

#[tokio::test(flavor = "multi_thread")]
async fn a_primary_whose_postgres_does_not_answer_gets_the_connection_closed() {
	let tyo = member("tyo", 200, false).await;
	let (state, port) = proxy(&[&tyo]).await;
	until(&state, one("tyo")).await;
	assert_eq!(exchange(&mut connect(port).await, "select 1").await, None);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_member_whose_rest_does_not_answer_is_never_the_target() {
	let tyo = member("tyo", 200, true).await;
	let mut silent = member("rdu", 200, true).await;
	// Nothing listens where rdu's REST is said to be.
	silent.member.rest = TcpListener::bind("127.0.0.1:0").await.unwrap().local_addr().unwrap().port();
	let (state, port) = proxy(&[&tyo, &silent]).await;
	until(&state, one("tyo")).await;
	assert_eq!(exchange(&mut connect(port).await, "x").await.as_deref(), Some("tyo:x"));
	assert!(state.members()["rdu"].last.is_some() && !state.members()["rdu"].up);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_connection_whose_target_moved_while_it_waited_is_closed_not_passed_to_the_old_one() {
	let (tyo, rdu) = (member("tyo", 200, true).await, member("rdu", 503, true).await);
	// One slot, waited for long enough: the second connection reads its target, then waits.
	let one_slot = Timings { maxconn: 1, queue_timeout: Duration::from_secs(5), ..FAST };
	let (state, port) = proxy_with(&[&tyo, &rdu], one_slot).await;
	until(&state, one("tyo")).await;
	let mut first = connect(port).await;
	assert_eq!(exchange(&mut first, "a").await.as_deref(), Some("tyo:a"));
	let mut waiting = connect(port).await;
	waiting.write_all(b"b").await.unwrap();
	tokio::time::sleep(Duration::from_millis(50)).await;

	// The move closes the first session, which frees the slot the second was waiting for; it then
	// reaches tyo, no longer primary, and must be closed there rather than passed to it.
	tyo.answer.store(503, Ordering::SeqCst);
	rdu.answer.store(200, Ordering::SeqCst);
	until(&state, one("rdu")).await;
	let mut buffer = [0; 64];
	let read = tokio::time::timeout(Duration::from_secs(2), waiting.read(&mut buffer)).await;
	assert!(
		matches!(read, Ok(Ok(0) | Err(_))),
		"{:?}",
		read.map(|r| r.map(|n| String::from_utf8_lossy(&buffer[..n]).into_owned()))
	);
	assert_eq!(exchange(&mut connect(port).await, "c").await.as_deref(), Some("rdu:c"));
}
