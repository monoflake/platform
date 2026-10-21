//! `model/contracts.json` read into its [`Model`], and held to what the Rust written from it needs:
//! every name one Rust can write, every key and code within its type once, every type a shape or
//! an operation names declared, every reason's failure a choice of `failure` and its message in
//! `messages`, and the call and the answer as `Envelope` and `Answer` read them.

use std::collections::BTreeSet;

use serde_json::{Map, Value, json};

use super::model::{
	Case, Choice, Declared, Def, Field, Interface, Model, Operation, Prim, Reason, Shape,
};
use super::names;
use crate::Unread;

type Got<T> = Result<T, Unread>;

/// The type every reason's failure is a choice of.
pub(super) const FAILURE: &str = "failure";

/// The type an answer's `error` holds.
const ERROR: &str = "error";

/// The field an answer's case is named by, which no field of `error` may be.
const STATUS: &str = "status";

/// Why the part at `at` is not read.
fn unread(at: &str, expected: impl Into<String>) -> Unread {
	Unread { at: at.to_owned(), expected: expected.into() }
}

/// `at`, one step further in.
fn join(at: &str, step: impl std::fmt::Display) -> String {
	if at.is_empty() { step.to_string() } else { format!("{at}/{step}") }
}

fn object<'a>(value: &'a Value, at: &str) -> Got<&'a Map<String, Value>> {
	value.as_object().ok_or_else(|| unread(at, "an object"))
}

fn member<'a>(object: &'a Map<String, Value>, name: &str, at: &str) -> Got<&'a Value> {
	object.get(name).ok_or_else(|| unread(&join(at, name), "a value"))
}

fn array<'a>(value: &'a Value, at: &str) -> Got<&'a [Value]> {
	value.as_array().map(Vec::as_slice).ok_or_else(|| unread(at, "an array"))
}

fn text<'a>(value: &'a Value, at: &str) -> Got<&'a str> {
	value.as_str().ok_or_else(|| unread(at, "a string"))
}

fn integer(value: &Value, at: &str) -> Got<i64> {
	value.as_i64().ok_or_else(|| unread(at, "an integer"))
}

/// A name as `is` holds it, `what` saying what that is where it is not.
fn name(value: &Value, at: &str, is: fn(&str) -> bool, what: &str) -> Got<String> {
	let name = text(value, at)?;
	if is(name) { Ok(name.to_owned()) } else { Err(unread(at, what)) }
}

const SNAKE: &str =
	"a name of lowercase words joined by underscores, no keyword Rust cannot write raw";
const KEBAB: &str = "a name of lowercase words joined by hyphens";

/// Every item of `items`, each distinct by `by`, where none is `what` twice.
fn distinct<T, K: Ord>(items: &[T], at: &str, what: &str, by: impl Fn(&T) -> K) -> Got<()> {
	let mut seen = BTreeSet::new();
	match items.iter().enumerate().find(|(_, item)| !seen.insert(by(item))) {
		Some((i, _)) => Err(unread(&join(at, i), format!("{what} no other beside it has"))),
		None => Ok(()),
	}
}

/// The contracts, read and held.
pub(super) fn contracts(value: &Value) -> Got<Model> {
	let top = object(value, "")?;
	let types = object(member(top, "types", "")?, "types")?;
	let known: BTreeSet<&str> = types.keys().map(String::as_str).collect();
	let types = types
		.iter()
		.map(|(name, def)| {
			let at = join("types", name);
			if !names::is_type_name(name) {
				return Err(unread(&at, KEBAB));
			}
			Ok(Declared { name: name.clone(), def: declared(def, &at, &known)? })
		})
		.collect::<Got<Vec<_>>>()?;
	call(member(top, "call", "")?)?;
	answer(member(top, "answer", "")?, &types)?;
	let shell = fields(member(top, "shell", "")?, "shell", &known, None)?;
	let failures = failures(&types)?;
	let messages = messages(member(top, "messages", "")?)?;
	let held = Held { failures: &failures, messages: &messages };
	let every = reasons(member(top, "reasons", "")?, "reasons", &held)?;
	let calling = reasons(member(top, "calling", "")?, "calling", &held)?;
	let interfaces = object(member(top, "interfaces", "")?, "interfaces")?
		.iter()
		.map(|(name, i)| interface(name, i, &join("interfaces", name), &known, &held))
		.collect::<Got<Vec<_>>>()?;
	Ok(Model { types, shell, reasons: every, calling, interfaces, messages })
}

/// The answer every operation gives, held to the one `Answer` reads and writes, as the call is to
/// `Envelope`: its case by `status`, `success` code 1 holding the output as `data` at key 1, and
/// `error` code 2 holding the fields of `error`, a record none of whose fields is `status` or at
/// key 0, where the case stands.
fn answer(value: &Value, types: &[Declared]) -> Got<()> {
	let expected = json!({
		"tag": STATUS,
		"cases": [
			{ "name": "success", "code": 1, "fields": [{ "name": "data", "key": 1, "shape": { "output": "operation" } }] },
			{ "name": "error", "code": 2, "type": ERROR },
		],
	});
	if *value != expected {
		return Err(unread(
			"answer",
			"the answer Answer reads: by status, success 1 holding data at 1, the output, and error 2 \
			 holding the type error",
		));
	}
	let at = join("types", ERROR);
	let Some(Def::Record(fields)) = types.iter().find(|t| t.name == ERROR).map(|t| &t.def) else {
		return Err(unread(&at, "a record, an answer's error"));
	};
	match fields.iter().position(|f| f.name == STATUS || f.key == 0) {
		Some(i) => Err(unread(
			&join(&join(&at, "record"), i),
			"a field other than status, at a key other than 0",
		)),
		None => Ok(()),
	}
}

/// Each reason's default message, by its name.
fn messages(value: &Value) -> Got<Vec<(String, String)>> {
	object(value, "messages")?
		.iter()
		.map(|(name, message)| {
			let at = join("messages", name);
			if !names::is_snake_name(name) {
				return Err(unread(&at, SNAKE));
			}
			Ok((name.clone(), text(message, &at)?.to_owned()))
		})
		.collect()
}

/// What every reason is held to: its failure one of `failures`, its name one `messages` has.
struct Held<'a> {
	failures: &'a [String],
	messages: &'a [(String, String)],
}

/// The call every operation's body is, held to the one `Envelope` reads and writes: its fields are
/// the runtime's, written once there, so they are checked here rather than written from. Its `typ`,
/// the protected header of a call signed whole, is its signer's, and passed over.
fn call(value: &Value) -> Got<()> {
	let fields = member(object(value, "call")?, "fields", "call")?;
	let expected = json!([
		{ "name": "interface", "key": 1, "shape": { "prim": "string" } },
		{ "name": "operation", "key": 2, "shape": { "prim": "string" } },
		{ "name": "input", "key": 3, "shape": { "input": "operation" } },
		{ "name": "capabilities", "key": 4, "shape": { "list": { "prim": "bytes" } }, "optional": true },
	]);
	if *fields == expected {
		Ok(())
	} else {
		Err(unread(
			"call/fields",
			"the fields Envelope reads: interface 1 and operation 2, strings; input 3, as its operation \
			 names; capabilities 4, an optional list of bytes",
		))
	}
}

/// The choices of `failure`, which every reason's failure is one of.
fn failures(types: &[Declared]) -> Got<Vec<String>> {
	match types.iter().find(|t| t.name == FAILURE).map(|t| &t.def) {
		Some(Def::Enum { choices, .. }) => Ok(choices.iter().map(|c| c.name.clone()).collect()),
		Some(Def::Record(_) | Def::Union { .. } | Def::Flags(_)) | None => {
			Err(unread(&join("types", FAILURE), "an enumeration, every reason's failure"))
		}
	}
}

fn declared(value: &Value, at: &str, known: &BTreeSet<&str>) -> Got<Def> {
	let def = object(value, at)?;
	if let Some(record) = def.get("record") {
		return Ok(Def::Record(fields(record, &join(at, "record"), known, None)?));
	}
	if let Some(choices) = def.get("enum") {
		let choices = choices_of(choices, &join(at, "enum"))?;
		let ordered = member(def, "ordered", at)?
			.as_bool()
			.ok_or_else(|| unread(&join(at, "ordered"), "a boolean"))?;
		if ordered && choices.windows(2).any(|w| matches!(w, [a, b] if a.code >= b.code)) {
			return Err(unread(&join(at, "enum"), "an ordered enumeration's codes, rising as declared"));
		}
		return Ok(Def::Enum { choices, ordered });
	}
	if let Some(union) = def.get("union") {
		let at = join(at, "union");
		let union = object(union, &at)?;
		let tag = name(member(union, "tag", &at)?, &join(&at, "tag"), names::is_snake_name, SNAKE)?;
		let cases = member(union, "cases", &at)?;
		let at = join(&at, "cases");
		let cases = array(cases, &at)?
			.iter()
			.enumerate()
			.map(|(i, c)| case(c, &join(&at, i), known, &tag))
			.collect::<Got<Vec<_>>>()?;
		distinct(&cases, &at, "a name", |c| c.name.clone())?;
		distinct(&cases, &at, "a name in upper camel case", |c| names::camel(&c.name))?;
		distinct(&cases, &at, "a code", |c| c.code)?;
		return Ok(Def::Union { tag, cases });
	}
	if let Some(flags) = def.get("flags") {
		let at = join(at, "flags");
		let flags = choices_of(flags, &at)?;
		distinct(&flags, &at, "a name in upper snake case", |c| names::upper_snake(&c.name))?;
		if let Some(i) =
			flags.iter().position(|c| u32::try_from(c.code).map_or(true, |b| !b.is_power_of_two()))
		{
			return Err(unread(&join(&join(&at, i), "code"), "a bit of 32, a power of two"));
		}
		return Ok(Def::Flags(flags));
	}
	Err(unread(at, "a record, an enum, a union or flags"))
}

fn case(value: &Value, at: &str, known: &BTreeSet<&str>, tag: &str) -> Got<Case> {
	let case = object(value, at)?;
	Ok(Case {
		name: name(member(case, "name", at)?, &join(at, "name"), names::is_snake_name, SNAKE)?,
		code: integer(member(case, "code", at)?, &join(at, "code"))?,
		fields: fields(member(case, "fields", at)?, &join(at, "fields"), known, Some(tag))?,
	})
}

fn choices_of(value: &Value, at: &str) -> Got<Vec<Choice>> {
	let choices = array(value, at)?
		.iter()
		.enumerate()
		.map(|(i, c)| {
			let at = join(at, i);
			let choice = object(c, &at)?;
			Ok(Choice {
				name: name(member(choice, "name", &at)?, &join(&at, "name"), names::is_snake_name, SNAKE)?,
				code: integer(member(choice, "code", &at)?, &join(&at, "code"))?,
			})
		})
		.collect::<Got<Vec<_>>>()?;
	distinct(&choices, at, "a name", |c| c.name.clone())?;
	distinct(&choices, at, "a name in upper camel case", |c| names::camel(&c.name))?;
	distinct(&choices, at, "a code", |c| c.code)?;
	Ok(choices)
}

/// A record's fields, or a case's beside its union's `tag`, which holds key 0 and its name.
fn fields(value: &Value, at: &str, known: &BTreeSet<&str>, tag: Option<&str>) -> Got<Vec<Field>> {
	let fields = array(value, at)?
		.iter()
		.enumerate()
		.map(|(i, f)| {
			let at = join(at, i);
			let field = object(f, &at)?;
			let optional = match field.get("optional") {
				Some(o) => o.as_bool().ok_or_else(|| unread(&join(&at, "optional"), "a boolean"))?,
				None => false,
			};
			let field = Field {
				name: name(member(field, "name", &at)?, &join(&at, "name"), names::is_snake_name, SNAKE)?,
				key: integer(member(field, "key", &at)?, &join(&at, "key"))?,
				shape: shape(member(field, "shape", &at)?, &join(&at, "shape"), known)?,
				optional,
			};
			match tag {
				Some(tag) if field.name == tag => {
					Err(unread(&join(&at, "name"), "a name other than its union's tag"))
				}
				Some(_) if field.key == 0 => {
					Err(unread(&join(&at, "key"), "a key other than 0, its union's case"))
				}
				Some(_) | None => Ok(field),
			}
		})
		.collect::<Got<Vec<_>>>()?;
	distinct(&fields, at, "a name", |f| f.name.clone())?;
	distinct(&fields, at, "a key", |f| f.key)?;
	Ok(fields)
}

fn shape(value: &Value, at: &str, known: &BTreeSet<&str>) -> Got<Shape> {
	let shape = object(value, at)?;
	if let Some(prim) = shape.get("prim") {
		let at = join(at, "prim");
		return Ok(Shape::Prim(match text(prim, &at)? {
			"bool" => Prim::Bool,
			"string" => Prim::String,
			"float64" => Prim::Float64,
			"int32" => Prim::Int32,
			"uint32" => Prim::Uint32,
			"int53" => Prim::Int53,
			"uint53" => Prim::Uint53,
			"bytes" => Prim::Bytes,
			"hash" => Prim::Hash,
			"secret" => Prim::Secret,
			_ => return Err(unread(&at, "a primitive of the subset")),
		}));
	}
	if let Some(kind) = shape.get("id") {
		text(kind, &join(at, "id"))?;
		return Ok(Shape::Id);
	}
	if let Some(name) = shape.get("type") {
		let at = join(at, "type");
		let name = text(name, &at)?;
		return if known.contains(name) {
			Ok(Shape::Type(name.to_owned()))
		} else {
			Err(unread(&at, "a type of types"))
		};
	}
	if let Some(item) = shape.get("list") {
		return Ok(Shape::List(Box::new(self::shape(item, &join(at, "list"), known)?)));
	}
	if let Some(entry) = shape.get("map") {
		return Ok(Shape::Map(Box::new(self::shape(entry, &join(at, "map"), known)?)));
	}
	Err(unread(at, "a prim, an id, a type, a list or a map"))
}

fn reasons(value: &Value, at: &str, held: &Held) -> Got<Vec<Reason>> {
	array(value, at)?
		.iter()
		.enumerate()
		.map(|(i, r)| {
			let at = join(at, i);
			let reason = object(r, &at)?;
			let failure = text(member(reason, "failure", &at)?, &join(&at, "failure"))?;
			if !held.failures.iter().any(|f| f == failure) {
				return Err(unread(&join(&at, "failure"), "a choice of types/failure"));
			}
			let name =
				name(member(reason, "name", &at)?, &join(&at, "name"), names::is_snake_name, SNAKE)?;
			let Some((_, message)) = held.messages.iter().find(|(n, _)| *n == name) else {
				return Err(unread(&join(&at, "name"), "a reason messages gives a message"));
			};
			Ok(Reason { message: message.clone(), name, failure: failure.to_owned() })
		})
		.collect()
}

fn interface(
	name: &str,
	value: &Value,
	at: &str,
	known: &BTreeSet<&str>,
	held: &Held,
) -> Got<Interface> {
	if !names::is_snake_name(name) {
		return Err(unread(at, SNAKE));
	}
	let interface = object(value, at)?;
	let version = integer(member(interface, "version", at)?, &join(at, "version"))?;
	let version = u32::try_from(version)
		.map_err(|_| unread(&join(at, "version"), "a version of 0 to 2^32 - 1"))?;
	let ops_at = join(at, "operations");
	let operations = array(member(interface, "operations", at)?, &ops_at)?
		.iter()
		.enumerate()
		.map(|(i, o)| {
			let at = join(&ops_at, i);
			let op = object(o, &at)?;
			let type_of = |field: &str| -> Got<String> {
				let name = text(member(op, field, &at)?, &join(&at, field))?;
				if known.contains(name) {
					Ok(name.to_owned())
				} else {
					Err(unread(&join(&at, field), "a type of types"))
				}
			};
			Ok(Operation {
				name: self::name(
					member(op, "name", &at)?,
					&join(&at, "name"),
					names::is_snake_name,
					SNAKE,
				)?,
				input: type_of("input")?,
				output: type_of("output")?,
				reasons: reasons(member(op, "reasons", &at)?, &join(&at, "reasons"), held)?,
			})
		})
		.collect::<Got<Vec<_>>>()?;
	distinct(&operations, &ops_at, "a name in upper camel case", |o| names::camel(&o.name))?;
	Ok(Interface { name: name.to_owned(), version, operations })
}
