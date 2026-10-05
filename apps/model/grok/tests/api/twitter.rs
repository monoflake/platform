//! The `/twitter/` endpoints against the fake agent, which answers X prompts from their schema
//! (fake.rs). Two servers: one with fast response on, as shipped, and one waiting for every fetch
//! with a two-second budget, where a slow answer is cut off.

use std::time::Duration;

use serde_json::Value;

use super::{BEARER, Server, content, field, user};

const IMMUTABLE: &str = "public, max-age=31536000, immutable";
const RECENT: &str = "public, max-age=900";

struct Answer {
	status: u16,
	cache_control: String,
	retry_after: Option<String>,
	body: Value,
}

async fn fetch(server: &Server, path: &str) -> Answer {
	let response = server
		.client
		.get(format!("{}{path}", server.base))
		.header("authorization", BEARER)
		.send()
		.await
		.unwrap();
	let header =
		|name: &str| response.headers().get(name).map(|value| value.to_str().unwrap().to_owned());
	let (cache_control, retry_after) =
		(header("cache-control").unwrap_or_default(), header("retry-after"));
	Answer {
		status: response.status().as_u16(),
		cache_control,
		retry_after,
		body: response.json().await.unwrap(),
	}
}

async fn fetches(server: &Server) -> u64 {
	let (_, stats) = server.chat(serde_json::json!({ "messages": [user("STATS")] })).await;
	field(content(&stats), "fetches").parse().unwrap()
}

/// The fetch count once no refresh is running any more.
async fn settled_fetches(server: &Server) -> u64 {
	let mut last = fetches(server).await;
	loop {
		tokio::time::sleep(Duration::from_millis(200)).await;
		let now = fetches(server).await;
		if now == last {
			return now;
		}
		last = now;
	}
}

fn ids(answer: &Answer) -> Vec<u128> {
	answer.body["data"]
		.as_array()
		.unwrap()
		.iter()
		.map(|post| post["id"].as_str().unwrap().parse().unwrap())
		.collect()
}

pub async fn run_all(server: &Server) {
	answers_at_once_and_refreshes_behind(server).await;
	println!("test twitter::answers_at_once_and_refreshes_behind ... ok");
	keeps_what_can_no_longer_change(server).await;
	println!("test twitter::keeps_what_can_no_longer_change ... ok");
}

/// Asks until the answer is no longer `202`.
async fn settle(server: &Server, path: &str) -> Answer {
	let mut answer = fetch(server, path).await;
	for _ in 0..50 {
		if answer.status != 202 {
			break;
		}
		tokio::time::sleep(Duration::from_millis(100)).await;
		answer = fetch(server, path).await;
	}
	answer
}

pub async fn run_waiting(server: &Server) {
	macro_rules! run {
		($($case:ident),* $(,)?) => {$(
			$case(server).await;
			println!("test twitter::{} ... ok", stringify!($case));
		)*};
	}
	run!(
		reads_a_post_and_keeps_it_by_age,
		reads_a_thread,
		pages_a_search_along_its_cursor,
		stops_where_the_results_do,
		drops_what_does_not_check_out,
		leaves_the_root_out_of_its_replies,
		returns_what_it_got_when_time_runs_out,
		finds_users,
		passes_every_semantic_filter,
		refuses_bad_parameters,
	);
}

async fn answers_at_once_and_refreshes_behind(server: &Server) {
	let path = "/twitter/posts/2104132837968580727";
	let first = fetch(server, path).await;
	assert_eq!(first.status, 202, "nothing held yet: {:?}", first.body);
	assert_eq!(first.cache_control, "no-store");
	assert_eq!(first.retry_after.as_deref(), Some("10"));

	let answer = settle(server, path).await;
	assert_eq!(answer.status, 200);
	assert_eq!(
		answer.body["data"]["url"],
		format!("{}/fake_user/status/2104132837968580727", monoflake::EXTERNAL_X_WEB)
	);
	assert_eq!(answer.cache_control, RECENT, "posted within the hour");

	// The request that got the 200 started a refresh of its own; wait it out, or the next request
	// joins it rather than starting one.
	let before = settled_fetches(server).await;
	let again = fetch(server, path).await;
	assert_eq!(again.status, 200, "answered from what is held");
	for _ in 0..50 {
		if fetches(server).await > before {
			return;
		}
		tokio::time::sleep(Duration::from_millis(100)).await;
	}
	panic!("the request did not refresh what it answered from");
}

async fn keeps_what_can_no_longer_change(server: &Server) {
	let path = "/twitter/posts/2104132837968580724";
	let answer = settle(server, path).await;
	assert_eq!(answer.status, 200);
	let post = &answer.body["data"];
	assert_eq!(post["quoted"]["id"], "2104132837968580723");
	assert_eq!(post["media"][0]["url"], format!("{}/media/fake.jpg", monoflake::EXTERNAL_X_MEDIA));
	assert_eq!(answer.cache_control, IMMUTABLE, "posted in 2025");
	let kept = std::fs::read_dir(server._data.0.join("twitter")).unwrap().count();
	assert!(kept >= 1, "kept on the volume");

	let before = settled_fetches(server).await;
	for _ in 0..3 {
		assert_eq!(fetch(server, path).await.cache_control, IMMUTABLE);
	}
	tokio::time::sleep(Duration::from_millis(300)).await;
	assert_eq!(fetches(server).await, before, "a settled post is never fetched again");
}

async fn reads_a_post_and_keeps_it_by_age(server: &Server) {
	let missing = fetch(server, "/twitter/posts/404").await;
	assert_eq!(missing.status, 404);
	assert_eq!(missing.body["error"]["type"], "not_found");
	assert_eq!(missing.cache_control, RECENT);
	let recent = fetch(server, "/twitter/posts/1007").await;
	assert_eq!(recent.status, 200);
	assert_eq!(recent.cache_control, RECENT, "posted within the hour");
	assert!(recent.body["data"]["quoted"].is_null());
	assert!(recent.body["meta"]["fetched_at"].is_string());
}

async fn reads_a_thread(server: &Server) {
	let thread = fetch(server, "/twitter/posts/1004/thread").await;
	assert_eq!(thread.status, 200);
	let data = &thread.body["data"];
	assert_eq!(data["post"]["id"], "1004");
	assert_eq!(data["parents"].as_array().unwrap().len(), 1);
	assert_eq!(data["replies"].as_array().unwrap().len(), 2);
	assert_eq!(thread.cache_control, RECENT, "a thread still gathers replies");
}

async fn pages_a_search_along_its_cursor(server: &Server) {
	let first = fetch(server, "/twitter/search?q=grok&limit=25").await;
	assert_eq!(first.status, 200);
	let found = ids(&first);
	assert_eq!(found.len(), 25);
	assert_eq!(found[0], 1000);
	assert!(found.windows(2).all(|pair| pair[0] > pair[1]), "newest first, no repeats");
	assert_eq!(first.body["meta"]["complete"], true);
	assert_eq!(first.body["meta"]["next_cursor"], "975");
	let next = fetch(server, "/twitter/search?q=grok&limit=5&cursor=975").await;
	assert_eq!(ids(&next)[0], 975);
	let closed = fetch(server, "/twitter/search?q=grok&limit=2&until=2020-01-01").await;
	assert_eq!(closed.cache_control, IMMUTABLE, "a list that ended long ago");
}

async fn stops_where_the_results_do(server: &Server) {
	let short = fetch(server, "/twitter/search?q=SHORT&limit=10").await;
	assert_eq!(ids(&short).len(), 3);
	assert!(short.body["meta"]["next_cursor"].is_null());
	let top = fetch(server, "/twitter/search?q=grok&mode=top&limit=10").await;
	assert!(top.body["meta"]["next_cursor"].is_null(), "top is one page");
}

async fn drops_what_does_not_check_out(server: &Server) {
	let dirty = fetch(server, "/twitter/search?q=DIRTY&limit=3").await;
	assert_eq!(dirty.status, 200);
	assert!(!ids(&dirty).is_empty());
	assert!(ids(&dirty).iter().all(|id| *id < 1000), "the post with a bad id is gone");
}

async fn leaves_the_root_out_of_its_replies(server: &Server) {
	let replies = fetch(server, "/twitter/posts/1000/replies?limit=3").await;
	assert_eq!(ids(&replies), [999, 998, 997]);
}

async fn returns_what_it_got_when_time_runs_out(server: &Server) {
	let partial = fetch(server, "/twitter/search?q=SLOWLIST&limit=10").await;
	assert_eq!(partial.status, 200, "{:?}", partial.body);
	assert_eq!(partial.body["meta"]["complete"], false);
	let count = ids(&partial).len();
	assert!((1..10).contains(&count), "some of it, not all: {count}");
	assert!(partial.body["meta"]["next_cursor"].is_string());
}

async fn finds_users(server: &Server) {
	let users = fetch(server, "/twitter/users/search?q=a&limit=2").await;
	assert_eq!(users.body["data"].as_array().unwrap().len(), 2);
	assert_eq!(users.body["data"][0]["url"], format!("{}/user0", monoflake::EXTERNAL_X_WEB));
	let one = fetch(server, "/twitter/users/@fake").await;
	assert_eq!(one.status, 200);
	assert_eq!(one.body["data"]["followers"], 7);
	assert_eq!(fetch(server, "/twitter/users/nobody").await.status, 404);
}

async fn passes_every_semantic_filter(server: &Server) {
	let found = fetch(
		server,
		"/twitter/search/semantic?q=red&usernames=a,b&exclude=c&min_score=0.3&since=2026-01-01",
	)
	.await;
	let echoed = found.body["data"][0]["text"].as_str().unwrap().to_owned();
	for part in [
		r#""usernames":["a","b"]"#,
		r#""exclude_usernames":["c"]"#,
		r#""min_score_threshold":0.3"#,
		r#""from_date":"2026-01-01""#,
	] {
		assert!(echoed.contains(part), "{part} in {echoed}");
	}
}

async fn refuses_bad_parameters(server: &Server) {
	for path in [
		"/twitter/search",
		"/twitter/posts/abc",
		"/twitter/search?q=x&limit=0",
		"/twitter/users/not%20a%20name",
	] {
		let answer = fetch(server, path).await;
		assert_eq!(answer.status, 400, "{path}");
		assert_eq!(answer.cache_control, "no-store");
	}
	let response =
		server.client.get(format!("{}/twitter/posts/1", server.base)).send().await.unwrap();
	assert_eq!(response.status().as_u16(), 401);
}
