//! How a name of `model/contracts.json` is written in Rust: a type's or a choice's in upper camel
//! case, a constant's in upper snake case, a field's as it is, a keyword raw.

/// Rust's keywords, strict and reserved, 2024 edition's among them: a field so named is written
/// raw, `r#type`.
const KEYWORDS: &[&str] = &[
	"abstract", "as", "async", "await", "become", "box", "break", "const", "continue", "do", "dyn",
	"else", "enum", "extern", "false", "final", "fn", "for", "gen", "if", "impl", "in", "let",
	"loop", "macro", "match", "mod", "move", "mut", "override", "priv", "pub", "ref", "return",
	"static", "struct", "trait", "true", "try", "type", "typeof", "unsafe", "unsized", "use",
	"virtual", "where", "while", "yield",
];

/// The keywords no raw identifier may be.
const UNRAWABLE: &[&str] = &["crate", "self", "super", "_"];

/// A type's name, `bucket-kind`: lowercase words, joined by hyphens.
pub(super) fn is_type_name(name: &str) -> bool {
	words(name, '-')
}

/// A field's, a choice's, a case's, an interface's or an operation's name, `best_effort`:
/// lowercase words, joined by underscores.
pub(super) fn is_snake_name(name: &str) -> bool {
	words(name, '_') && !UNRAWABLE.contains(&name)
}

/// Whether `name` is lowercase letters and digits, led by a letter, in words joined by `joint`.
fn words(name: &str, joint: char) -> bool {
	name.split(joint).all(|word| {
		!word.is_empty() && word.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
	}) && name.starts_with(|c: char| c.is_ascii_lowercase())
}

/// `bucket-kind` as `BucketKind`, `best_effort` as `BestEffort`.
pub(super) fn camel(name: &str) -> String {
	name
		.split(['-', '_'])
		.flat_map(|word| {
			let mut chars = word.chars();
			chars.next().map(|c| c.to_ascii_uppercase()).into_iter().chain(chars)
		})
		.collect()
}

/// `read` as `READ`, `best_effort` as `BEST_EFFORT`.
pub(super) fn upper_snake(name: &str) -> String {
	name.replace('-', "_").to_ascii_uppercase()
}

/// A field's name as an identifier: itself, or raw where it is a keyword.
pub(super) fn ident(name: &str) -> String {
	if KEYWORDS.contains(&name) { format!("r#{name}") } else { name.to_owned() }
}
