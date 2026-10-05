//! What each endpoint asks the agent for: which tool, with which arguments, answered in which
//! shape, paged how, and kept for how long. spec/architecture/grok/twitter.md.

use std::collections::HashMap;

use serde_json::{Value, json};

use super::{shape, time};

/// A post over an hour old can no longer be edited, and neither can a list that ended an hour ago.
pub const IMMUTABLE: &str = "public, max-age=31536000, immutable";
pub const RECENT: &str = "public, max-age=900";
pub const NO_STORE: &str = "no-store";

/// The most a latest-first list pages to in one request; ten a page, so ten prompts at most.
const MAX_LIST: usize = 100;
/// What one search call returns at most.
pub const PAGE: usize = 10;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Mode {
	Latest,
	Top,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Task {
	Post { id: String },
	Thread { id: String },
	Keyword(Keyword),
	Semantic { arguments: Value, until: Option<i64> },
	Users { query: String, count: usize },
	User { username: String },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Keyword {
	pub query: String,
	pub mode: Mode,
	pub limit: usize,
	/// Posts at or below this id, the `max_id:` a client's cursor continues from.
	pub cursor: Option<u128>,
	pub until: Option<i64>,
	/// A post the search finds that is not one of the results: the post whose replies these are.
	pub skip: Option<String>,
}

pub type Params = HashMap<String, String>;

fn id(id: &str) -> Result<String, String> {
	shape::is_id(id).then(|| id.to_owned()).ok_or_else(|| format!("{id:?} is not a post id"))
}

fn username(name: &str) -> Result<String, String> {
	let name = name.trim_start_matches('@');
	shape::is_username(name)
		.then(|| name.to_owned())
		.ok_or_else(|| format!("{name:?} is not a username"))
}

fn number(params: &Params, name: &str, default: usize, max: usize) -> Result<usize, String> {
	match params.get(name) {
		None => Ok(default),
		Some(value) => match value.parse::<usize>() {
			Ok(number) if (1..=max).contains(&number) => Ok(number),
			_ => Err(format!("{name} must be a number from 1 to {max}")),
		},
	}
}

fn day(params: &Params, name: &str) -> Result<Option<String>, String> {
	match params.get(name) {
		None => Ok(None),
		Some(value) if time::parse_day(value).is_some() => Ok(Some(value.clone())),
		Some(_) => Err(format!("{name} must be a date, YYYY-MM-DD")),
	}
}

fn text(params: &Params, name: &str) -> Result<String, String> {
	params
		.get(name)
		.map(|value| value.trim())
		.filter(|value| !value.is_empty())
		.map(str::to_owned)
		.ok_or_else(|| format!("{name} is required"))
}

fn flag(params: &Params, name: &str) -> Result<bool, String> {
	match params.get(name).map(String::as_str) {
		None | Some("false") | Some("0") => Ok(false),
		Some("true") | Some("1") => Ok(true),
		Some(_) => Err(format!("{name} must be true or false")),
	}
}

/// A latest-first search of `query`, with the list parameters every search endpoint takes.
fn keyword(
	query: String,
	params: &Params,
	mode: Mode,
	skip: Option<String>,
) -> Result<Task, String> {
	let (since, until) = (day(params, "since")?, day(params, "until")?);
	let mut query = query;
	for (operator, value) in [("since", &since), ("until", &until)] {
		if let Some(value) = value {
			query.push_str(&format!(" {operator}:{value}"));
		}
	}
	let max = if mode == Mode::Latest { MAX_LIST } else { PAGE };
	let cursor = match params.get("cursor") {
		None => None,
		Some(_) if mode == Mode::Top => {
			return Err("cursor pages a latest-first list; top is one page".into());
		}
		Some(value) => {
			Some(value.parse::<u128>().map_err(|_| "cursor is not one this server gave".to_owned())?)
		}
	};
	Ok(Task::Keyword(Keyword {
		query,
		mode,
		limit: number(params, "limit", PAGE, max)?,
		cursor,
		until: until.as_deref().and_then(time::parse_day),
		skip,
	}))
}

pub fn post(post_id: &str) -> Result<Task, String> {
	Ok(Task::Post { id: id(post_id)? })
}

pub fn thread(post_id: &str) -> Result<Task, String> {
	Ok(Task::Thread { id: id(post_id)? })
}

pub fn replies(post_id: &str, params: &Params) -> Result<Task, String> {
	let post_id = id(post_id)?;
	keyword(format!("conversation_id:{post_id}"), params, Mode::Latest, Some(post_id))
}

pub fn quotes(post_id: &str, params: &Params) -> Result<Task, String> {
	keyword(format!("quoted_tweet_id:{}", id(post_id)?), params, Mode::Latest, None)
}

pub fn reposts(post_id: &str, params: &Params) -> Result<Task, String> {
	keyword(format!("retweets_of_tweet_id:{}", id(post_id)?), params, Mode::Latest, None)
}

pub fn users(params: &Params) -> Result<Task, String> {
	Ok(Task::Users { query: text(params, "q")?, count: number(params, "limit", 5, 20)? })
}

pub fn user(name: &str) -> Result<Task, String> {
	Ok(Task::User { username: username(name)? })
}

/// A user's own posts, replies left out unless asked for.
pub fn user_posts(name: &str, params: &Params) -> Result<Task, String> {
	let name = username(name)?;
	let replies = if flag(params, "replies")? { "" } else { " -filter:replies" };
	keyword(format!("from:{name}{replies}"), params, Mode::Latest, None)
}

pub fn user_media(name: &str, params: &Params) -> Result<Task, String> {
	keyword(format!("from:{} filter:media", username(name)?), params, Mode::Latest, None)
}

pub fn mentions(name: &str, params: &Params) -> Result<Task, String> {
	let name = username(name)?;
	keyword(format!("@{name} -from:{name}"), params, Mode::Latest, None)
}

/// X's advanced search, the query passed through with every operator it may carry.
pub fn search(params: &Params) -> Result<Task, String> {
	let mode = match params.get("mode").map(String::as_str) {
		None | Some("latest") => Mode::Latest,
		Some("top") => Mode::Top,
		Some(_) => return Err("mode must be latest or top".into()),
	};
	keyword(text(params, "q")?, params, mode, None)
}

/// `x_semantic_search`, every filter it takes.
pub fn semantic(params: &Params) -> Result<Task, String> {
	let list = |name: &str| -> Result<Option<Vec<String>>, String> {
		params.get(name).map(|value| value.split(',').map(username).collect()).transpose()
	};
	let mut arguments =
		json!({ "query": text(params, "q")?, "limit": number(params, "limit", PAGE, PAGE)? });
	let (since, until) = (day(params, "since")?, day(params, "until")?);
	if let Some(since) = since {
		arguments["from_date"] = since.into();
	}
	if let Some(until) = &until {
		arguments["to_date"] = until.clone().into();
	}
	if let Some(usernames) = list("usernames")? {
		arguments["usernames"] = usernames.into();
	}
	if let Some(excluded) = list("exclude")? {
		arguments["exclude_usernames"] = excluded.into();
	}
	if let Some(score) = params.get("min_score") {
		let score: f64 = score.parse().map_err(|_| "min_score must be a number".to_owned())?;
		arguments["min_score_threshold"] = score.into();
	}
	// `to_date` includes its day, so the list is closed once that day has ended.
	Ok(Task::Semantic {
		arguments,
		until: until.as_deref().and_then(time::parse_day).map(|day| day + 86400),
	})
}

impl Task {
	pub fn schema(&self) -> Value {
		match self {
			Task::Post { .. } => shape::found_post_schema(),
			Task::Thread { .. } => shape::thread_schema(),
			Task::Keyword(_) | Task::Semantic { .. } => shape::posts_schema(),
			Task::Users { .. } => shape::users_schema(),
			Task::User { .. } => shape::found_user_schema(),
		}
	}

	/// The prompt for one call. Arguments are given as the JSON the tool takes, so there is nothing
	/// for the model to decide but to make the call and write down what comes back.
	pub fn prompt(&self, page: Option<(usize, Option<u128>)>) -> String {
		let call = |tool: &str, arguments: Value| {
			format!("Call {tool} exactly once, with these arguments: {arguments}.")
		};
		match self {
			Task::Post { id } => format!(
				"{} Report the requested post as \"post\" with found true, and the post it quotes, if any, as its \"quoted\". If the post does not exist or is unavailable, found is false and post is null.",
				call("x_thread_fetch", json!({ "post_id": id }))
			),
			Task::Thread { id } => format!(
				"{} Report the requested post as \"post\", the posts above it in its thread as \"parents\" oldest first, and the replies to it as \"replies\". If the post does not exist, found is false, post is null and both lists are empty.",
				call("x_thread_fetch", json!({ "post_id": id }))
			),
			Task::Keyword(search) => {
				let (limit, cursor) = page.unwrap_or((search.limit.min(PAGE), search.cursor));
				let mut query = search.query.clone();
				if let Some(cursor) = cursor {
					query.push_str(&format!(" max_id:{cursor}"));
				}
				let mode = if search.mode == Mode::Latest { "Latest" } else { "Top" };
				format!(
					"{} Report every post it returns, in the order it returns them, as \"posts\".",
					call("x_keyword_search", json!({ "query": query, "limit": limit, "mode": mode }))
				)
			}
			Task::Semantic { arguments, .. } => format!(
				"{} Report every post it returns, in the order it returns them, as \"posts\".",
				call("x_semantic_search", arguments.clone())
			),
			Task::Users { query, count } => format!(
				"{} Report every user it returns, in the order it returns them, as \"users\".",
				call("x_user_search", json!({ "query": query, "count": count }))
			),
			Task::User { username } => format!(
				"{} Report the user whose handle is exactly @{username}, ignoring case, as \"user\" with found true. If none has that handle, found is false and user is null.",
				call("x_user_search", json!({ "query": username, "count": 5 }))
			),
		}
	}

	/// How long a response may be kept (spec/architecture/grok/twitter.md, "Freshness is
	/// Cache-Control").
	pub fn cache_control(&self, data: &Value, now: i64) -> &'static str {
		let closed = |instant: Option<i64>| instant.is_some_and(|instant| instant <= now - 3600);
		let settled = match self {
			Task::Post { .. } => closed(data["created_at"].as_str().and_then(time::parse_timestamp)),
			Task::Keyword(search) => closed(search.until),
			Task::Semantic { until, .. } => closed(*until),
			_ => false,
		};
		if settled { IMMUTABLE } else { RECENT }
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn params(pairs: &[(&str, &str)]) -> Params {
		pairs.iter().map(|(key, value)| (key.to_string(), value.to_string())).collect()
	}

	#[test]
	fn a_user_timeline_leaves_replies_out_unless_asked() {
		let Task::Keyword(search) = user_posts("@ichralpha", &params(&[])).unwrap() else { panic!() };
		assert_eq!(search.query, "from:ichralpha -filter:replies");
		let Task::Keyword(search) =
			user_posts("ichralpha", &params(&[("replies", "true"), ("since", "2026-09-01")])).unwrap()
		else {
			panic!()
		};
		assert_eq!(search.query, "from:ichralpha since:2026-09-01");
	}

	#[test]
	fn parameters_are_checked() {
		assert!(post("12ab").is_err());
		assert!(user("not a name").is_err());
		assert!(search(&params(&[])).is_err(), "q is required");
		assert!(search(&params(&[("q", "x"), ("limit", "500")])).is_err());
		assert!(
			search(&params(&[("q", "x"), ("mode", "top"), ("limit", "20")])).is_err(),
			"top is one page"
		);
		assert!(search(&params(&[("q", "x"), ("mode", "top"), ("cursor", "5")])).is_err());
		assert!(search(&params(&[("q", "x"), ("until", "yesterday")])).is_err());
	}

	#[test]
	fn a_page_bounds_its_query_below_the_cursor() {
		let task = search(&params(&[("q", "grok"), ("cursor", "2104132837968580723")])).unwrap();
		let prompt = task.prompt(None);
		assert!(prompt.contains(r#""query":"grok max_id:2104132837968580723""#), "{prompt}");
		assert!(prompt.contains(r#""mode":"Latest""#));
	}

	#[test]
	fn semantic_takes_every_filter() {
		let task = semantic(&params(&[
			("q", "red flowers"),
			("usernames", "a,@b"),
			("exclude", "c"),
			("min_score", "0.3"),
			("since", "2026-01-01"),
		]))
		.unwrap();
		let Task::Semantic { arguments, .. } = task else { panic!() };
		assert_eq!(arguments["usernames"], json!(["a", "b"]));
		assert_eq!(arguments["exclude_usernames"], json!(["c"]));
		assert_eq!(arguments["min_score_threshold"], 0.3);
		assert_eq!(arguments["from_date"], "2026-01-01");
	}

	#[test]
	fn old_posts_and_closed_lists_are_immutable() {
		let now = time::parse_timestamp("2026-09-27T12:00:00Z").unwrap();
		let task = post("1").unwrap();
		assert_eq!(
			task.cache_control(&json!({ "created_at": "2026-09-27T10:59:59Z" }), now),
			IMMUTABLE
		);
		assert_eq!(task.cache_control(&json!({ "created_at": "2026-09-27T11:30:00Z" }), now), RECENT);
		assert_eq!(task.cache_control(&json!({ "created_at": null }), now), RECENT);
		let closed = search(&params(&[("q", "x"), ("until", "2026-09-27")])).unwrap();
		assert_eq!(closed.cache_control(&Value::Null, now), IMMUTABLE);
		let open = search(&params(&[("q", "x")])).unwrap();
		assert_eq!(open.cache_control(&Value::Null, now), RECENT);
	}
}
