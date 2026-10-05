//! The shapes the model answers in, and the checks what it wrote must pass before it is returned.
//! Every field here is one the model copied from a tool result (spec/architecture/grok/twitter.md,
//! "The results reach the model and nothing else"), so each is checked for what it can be checked
//! for.

use serde_json::{Map, Value, json};

use super::time;

/// Hosts X serves media and avatars from. A URL on any other host is not one a tool returned.
const MEDIA_HOSTS: [&str; 3] = ["pbs.twimg.com", "video.twimg.com", "abs.twimg.com"];

fn object(properties: Value) -> Value {
	let required: Vec<&String> = properties.as_object().unwrap().keys().collect();
	json!({ "type": "object", "properties": properties, "required": required, "additionalProperties": false })
}

fn nullable(schema: Value) -> Value {
	json!({ "anyOf": [schema, { "type": "null" }] })
}

fn post_fields() -> Map<String, Value> {
	let count = json!({ "type": "integer" });
	let fields = json!({
		"id": { "type": "string", "description": "The post id, digits only, exactly as the tool gave it" },
		"text": { "type": "string", "description": "The post's text, exactly as the tool gave it" },
		"created_at": { "type": "string", "description": "ISO 8601 UTC, like 2026-09-27T08:55:36Z" },
		"conversation_id": { "type": ["string", "null"] },
		"author": object(json!({
			"username": { "type": "string", "description": "The handle without @" },
			"name": { "type": "string" },
			"avatar_url": { "type": ["string", "null"] },
		})),
		"metrics": object(json!({
			"likes": count, "reposts": count, "quotes": count,
			"replies": count, "bookmarks": count, "views": count,
		})),
		"media": { "type": "array", "items": object(json!({
			"type": { "type": "string", "description": "photo, video or animated_gif" },
			"url": { "type": "string" },
		})) },
	});
	fields.as_object().unwrap().clone()
}

/// A post, and with it the post it quotes, one level deep.
pub fn post_schema() -> Value {
	let mut fields = post_fields();
	fields.insert("quoted".into(), nullable(object(Value::Object(post_fields()))));
	object(Value::Object(fields))
}

pub fn user_schema() -> Value {
	object(json!({
		"id": { "type": ["string", "null"], "description": "The user id, digits only" },
		"username": { "type": "string", "description": "The handle without @" },
		"name": { "type": "string" },
		"avatar_url": { "type": ["string", "null"] },
		"bio": { "type": ["string", "null"] },
		"followers": { "type": ["integer", "null"] },
		"verified": { "type": ["string", "null"], "description": "The verification the tool reports, or null" },
	}))
}

/// The list goes first, so a document cut off partway still holds its complete items.
pub fn posts_schema() -> Value {
	object(json!({ "posts": { "type": "array", "items": post_schema() } }))
}

pub fn users_schema() -> Value {
	object(json!({ "users": { "type": "array", "items": user_schema() } }))
}

pub fn found_post_schema() -> Value {
	object(json!({ "found": { "type": "boolean" }, "post": nullable(post_schema()) }))
}

pub fn found_user_schema() -> Value {
	object(json!({ "found": { "type": "boolean" }, "user": nullable(user_schema()) }))
}

pub fn thread_schema() -> Value {
	object(json!({
		"found": { "type": "boolean" },
		"post": nullable(post_schema()),
		"parents": { "type": "array", "items": post_schema(), "description": "Posts above it, oldest first" },
		"replies": { "type": "array", "items": post_schema() },
	}))
}

pub fn is_id(text: &str) -> bool {
	!text.is_empty() && text.len() <= 20 && text.bytes().all(|byte| byte.is_ascii_digit())
}

pub fn is_username(text: &str) -> bool {
	!text.is_empty()
		&& text.len() <= 15
		&& text.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
}

fn media_url(url: &str) -> bool {
	let Some(rest) = url.strip_prefix("https://") else { return false };
	MEDIA_HOSTS.contains(&rest.split('/').next().unwrap_or_default())
}

fn string(value: &Value) -> Option<String> {
	value.as_str().map(str::to_owned)
}

/// A post as returned: checked, its timestamp normalized, its URL built. None for anything that is
/// not one -- an id that is not digits, a handle that is not a handle.
pub fn post(value: &Value) -> Option<Value> {
	let mut post = post_core(value)?;
	let quoted = post_core(&value["quoted"]);
	post["quoted"] = quoted.unwrap_or(Value::Null);
	Some(post)
}

fn post_core(value: &Value) -> Option<Value> {
	let id = value["id"].as_str().filter(|id| is_id(id))?;
	let username = value["author"]["username"].as_str().map(|name| name.trim_start_matches('@'))?;
	if !is_username(username) {
		return None;
	}
	let created_at =
		value["created_at"].as_str().and_then(time::parse_timestamp).map(time::format_timestamp);
	let metric = |name: &str| value["metrics"][name].as_u64().map(Value::from).unwrap_or(Value::Null);
	let media: Vec<Value> = value["media"]
		.as_array()
		.map(|media| {
			media
				.iter()
				.filter(|item| item["url"].as_str().is_some_and(media_url))
				.map(|item| json!({ "type": item["type"].as_str().unwrap_or("photo"), "url": item["url"] }))
				.collect()
		})
		.unwrap_or_default();
	Some(json!({
		"id": id,
		"url": format!("{}/{username}/status/{id}", monoflake::EXTERNAL_X_WEB),
		"text": string(&value["text"]).unwrap_or_default(),
		"created_at": created_at,
		"conversation_id": value["conversation_id"].as_str().filter(|id| is_id(id)),
		"author": {
			"username": username,
			"name": string(&value["author"]["name"]).unwrap_or_default(),
			"avatar_url": value["author"]["avatar_url"].as_str().filter(|url| media_url(url)),
		},
		"metrics": {
			"likes": metric("likes"), "reposts": metric("reposts"), "quotes": metric("quotes"),
			"replies": metric("replies"), "bookmarks": metric("bookmarks"), "views": metric("views"),
		},
		"media": media,
	}))
}

pub fn user(value: &Value) -> Option<Value> {
	let username = value["username"].as_str().map(|name| name.trim_start_matches('@'))?;
	if !is_username(username) {
		return None;
	}
	Some(json!({
		"id": value["id"].as_str().filter(|id| is_id(id)),
		"username": username,
		"url": format!("{}/{username}", monoflake::EXTERNAL_X_WEB),
		"name": string(&value["name"]).unwrap_or_default(),
		"avatar_url": value["avatar_url"].as_str().filter(|url| media_url(url)),
		"bio": value["bio"].as_str(),
		"followers": value["followers"].as_u64(),
		"verified": value["verified"].as_str(),
	}))
}

#[cfg(test)]
mod tests {
	use super::*;

	fn raw() -> Value {
		json!({
			"id": "2104132837968580724",
			"text": "又 一年",
			"created_at": "2026-09-27T08:55:36Z",
			"conversation_id": null,
			"author": { "username": "@ichralpha", "name": "Chrys", "avatar_url": format!("{}/profile_images/1/a.jpg", monoflake::EXTERNAL_X_MEDIA) },
			"metrics": { "likes": 2, "reposts": 0, "quotes": 0, "replies": 0, "bookmarks": 0, "views": 40 },
			"media": [
				{ "type": "photo", "url": format!("{}/media/HTNhoxGacAAGlVU.jpg", monoflake::EXTERNAL_X_MEDIA) },
				{ "type": "photo", "url": "https://evil.example.com/x.jpg" },
			],
			"quoted": { "id": "1971221715452854390", "text": "彼岸花", "created_at": "2025-09-25T14:34:15Z", "author": { "username": "ichralpha", "name": "Chrys" }, "media": [] },
		})
	}

	#[test]
	fn a_post_is_checked_and_given_its_url() {
		let post = post(&raw()).unwrap();
		assert_eq!(
			post["url"],
			format!("{}/ichralpha/status/2104132837968580724", monoflake::EXTERNAL_X_WEB)
		);
		assert_eq!(post["author"]["username"], "ichralpha");
		assert_eq!(post["media"].as_array().unwrap().len(), 1, "media off X's hosts is dropped");
		assert_eq!(post["quoted"]["id"], "1971221715452854390");
		assert_eq!(post["metrics"]["views"], 40);
	}

	#[test]
	fn what_is_not_a_post_is_nothing() {
		let mut bad = raw();
		bad["id"] = "12ab".into();
		assert!(post(&bad).is_none());
		let mut bad = raw();
		bad["author"]["username"] = "not a handle".into();
		assert!(post(&bad).is_none());
	}

	#[test]
	fn an_unreadable_time_is_null() {
		let mut odd = raw();
		odd["created_at"] = "Sun, 27 Sep 2026 08:55:36 GMT".into();
		assert!(post(&odd).unwrap()["created_at"].is_null());
	}

	#[test]
	fn schemas_require_every_field() {
		let schema = post_schema();
		assert_eq!(
			schema["required"].as_array().unwrap().len(),
			schema["properties"].as_object().unwrap().len()
		);
		assert_eq!(schema["additionalProperties"], false);
	}
}
