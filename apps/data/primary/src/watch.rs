//! Each member's check, on its own schedule: `GET /primary` on its Patroni REST, which answers
//! `200` on the primary alone. See check.rs.

use crate::check::Timings;
use crate::config::Member;
use crate::state::State;
use bytes::Bytes;
use http_body_util::Empty;
use hyper::Request;
use hyper_util::client::legacy::Client;
use hyper_util::client::legacy::connect::HttpConnector;
use hyper_util::rt::TokioExecutor;
use std::sync::Arc;

pub type Asker = Client<HttpConnector, Empty<Bytes>>;

pub fn asker() -> Asker {
	Client::builder(TokioExecutor::new()).build(HttpConnector::new())
}

/// The status `GET /primary` answers with, or why there was none.
pub async fn ask(client: &Asker, member: &Member, timings: &Timings) -> Result<u16, String> {
	let request = Request::get(format!("http://{}/primary", member.rest_address()))
		.body(Empty::new())
		.map_err(|error| error.to_string())?;
	match tokio::time::timeout(timings.check_timeout, client.request(request)).await {
		Ok(Ok(answer)) => Ok(answer.status().as_u16()),
		Ok(Err(error)) => Err(error.to_string()),
		Err(_) => Err(format!("no answer within {}s", timings.check_timeout.as_secs())),
	}
}

/// One member checked for as long as the proxy runs.
pub async fn check(member: Member, state: Arc<State>, timings: Timings, client: Asker) {
	loop {
		let answer = ask(&client, &member, &timings).await;
		let health = state.observe(&member.name, answer, jiff::Timestamp::now(), &timings);
		tokio::time::sleep(health.next(&timings)).await;
	}
}
