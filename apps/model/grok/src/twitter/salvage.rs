//! What a cut-off answer still holds. A turn stopped by the time budget leaves a JSON document
//! written partway; every item of its list whose JSON closed is kept
//! (spec/architecture/grok/twitter.md, "Time is the one limit").

use serde_json::Value;

/// The complete elements of the array under `key`, from JSON that may stop anywhere after them.
pub fn complete_items(text: &str, key: &str) -> Vec<Value> {
	let needle = format!("\"{key}\"");
	let Some(at) = text.find(&needle) else { return Vec::new() };
	let rest = &text[at + needle.len()..];
	let Some(open) = rest.find('[') else { return Vec::new() };
	if !rest[..open].trim().trim_start_matches(':').trim().is_empty() {
		return Vec::new();
	}
	let body = &rest[open + 1..];

	let mut items = Vec::new();
	let (mut depth, mut start) = (0usize, None);
	let (mut in_string, mut escaped) = (false, false);
	for (index, character) in body.char_indices() {
		if in_string {
			match character {
				_ if escaped => escaped = false,
				'\\' => escaped = true,
				'"' => in_string = false,
				_ => {}
			}
			continue;
		}
		match character {
			'"' => in_string = true,
			'{' | '[' => {
				if depth == 0 {
					start = Some(index);
				}
				depth += 1;
			}
			'}' | ']' if depth == 0 => break,
			'}' | ']' => {
				depth -= 1;
				if depth == 0
					&& let Some(from) = start.take()
					&& let Ok(item) = serde_json::from_str(&body[from..=index])
				{
					items.push(item);
				}
			}
			_ => {}
		}
	}
	items
}

#[cfg(test)]
mod tests {
	use super::complete_items;

	#[test]
	fn keeps_the_items_that_closed() {
		let text =
			r#"{"posts":[{"id":"3","text":"a } in text"},{"id":"2","media":[{"url":"x"}]},{"id":"1","te"#;
		let items = complete_items(text, "posts");
		assert_eq!(items.len(), 2);
		assert_eq!(items[0]["text"], "a } in text");
		assert_eq!(items[1]["media"][0]["url"], "x");
	}

	#[test]
	fn a_whole_document_gives_every_item() {
		assert_eq!(
			complete_items(r#"{"posts": [{"id":"1"},{"id":"2"}], "more": true}"#, "posts").len(),
			2
		);
	}

	#[test]
	fn nothing_written_is_nothing() {
		assert!(complete_items(r#"{"pos"#, "posts").is_empty());
		assert!(complete_items(r#"{"posts":"#, "posts").is_empty());
		assert!(complete_items(r#"{"posts":[{"id":"1\"}"#, "posts").is_empty());
	}
}
