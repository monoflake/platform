//! envelope*'s module `contracts` written from the [`Model`], as the library's `src/lib.rs` names
//! every item of it: each type and its `Encoded` by the helpers of the library's `wire`, the shell,
//! the reasons, each interface's operations, and the two functions by a type's name.

use std::collections::BTreeSet;

use super::model::{Case, Choice, Declared, Def, Field, Interface, Model, Prim, Reason, Shape};
use super::names;
use super::read::FAILURE;
use crate::Unread;

/// The names the module already holds or takes from beside it, which no type's may be: what it
/// imports, what it writes of its own, and what the prelude gives that it writes with.
const TAKEN: &[&str] = &[
	"BTreeMap",
	"Bounded",
	"Box",
	"Encoded",
	"Err",
	"Int53",
	"Malformed",
	"None",
	"Ok",
	"Operation",
	"Option",
	"Reason",
	"Result",
	"Self",
	"Shell",
	"Some",
	"Step",
	"String",
	"Uint53",
	"Vec",
];

/// The names an interface's module imports, which no operation's may be.
const TAKEN_BY_INTERFACE: &[&str] = &["Operation", "Reason"];

/// The source written, a line at a time, indented by tabs.
struct Out {
	text: String,
	depth: usize,
}

impl Out {
	fn line(&mut self, line: &str) {
		if !line.is_empty() {
			self.text.extend(std::iter::repeat_n('\t', self.depth));
			self.text.push_str(line);
		}
		self.text.push('\n');
	}

	/// A line that opens a block, the lines after it one tab further in.
	fn open(&mut self, line: &str) {
		self.line(line);
		self.depth = self.depth.saturating_add(1);
	}

	/// A line that closes a block.
	fn close(&mut self, line: &str) {
		self.depth = self.depth.saturating_sub(1);
		self.line(line);
	}
}

/// Which of the two forms a value is written in or read from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Form {
	Json,
	Cbor,
}

impl Form {
	fn name(self) -> &'static str {
		match self {
			Self::Json => "json",
			Self::Cbor => "cbor",
		}
	}

	fn value(self) -> &'static str {
		match self {
			Self::Json => "serde_json::Value",
			Self::Cbor => "codec::Value",
		}
	}
}

/// The helpers of `wire` a primitive is written and read with, by the stem of their names.
fn stem(prim: Prim) -> &'static str {
	match prim {
		Prim::Bool => "bool",
		Prim::String => "string",
		Prim::Float64 => "float",
		Prim::Int32 => "int32",
		Prim::Uint32 => "uint32",
		Prim::Int53 => "int53",
		Prim::Uint53 => "uint53",
		Prim::Bytes | Prim::Secret => "bytes",
		Prim::Hash => "hash",
	}
}

fn rust_type(shape: &Shape) -> String {
	match shape {
		Shape::Prim(Prim::Bool) => "bool".to_owned(),
		Shape::Prim(Prim::String) => "String".to_owned(),
		Shape::Prim(Prim::Float64) => "f64".to_owned(),
		Shape::Prim(Prim::Int32) => "i32".to_owned(),
		Shape::Prim(Prim::Uint32) | Shape::Id => "u32".to_owned(),
		Shape::Prim(Prim::Int53) => "Int53".to_owned(),
		Shape::Prim(Prim::Uint53) => "Uint53".to_owned(),
		Shape::Prim(Prim::Bytes | Prim::Secret) => "Vec<u8>".to_owned(),
		Shape::Prim(Prim::Hash) => "[u8; 32]".to_owned(),
		Shape::Type(name) => names::camel(name),
		Shape::List(item) => format!("Vec<{}>", rust_type(item)),
		Shape::Map(entry) => format!("BTreeMap<String, {}>", rust_type(entry)),
	}
}

/// A function reading `shape` from `form`, as a path or a closure.
fn reader(shape: &Shape, form: Form) -> String {
	let f = form.name();
	match shape {
		Shape::Prim(prim) => format!("wire::{}_from_{f}", stem(*prim)),
		Shape::Id => format!("wire::uint32_from_{f}"),
		Shape::Type(name) => format!("{}::from_{f}", names::camel(name)),
		Shape::List(item) => format!("|v| wire::list_from_{f}(v, {})", reader(item, form)),
		Shape::Map(entry) => format!("|v| wire::map_from_{f}(v, {})", reader(entry, form)),
	}
}

/// A function writing `shape` in `form`, as a path or a closure.
fn writer(shape: &Shape, form: Form) -> String {
	let f = form.name();
	match shape {
		Shape::Prim(prim) => format!("wire::{}_to_{f}", stem(*prim)),
		Shape::Id => format!("wire::uint32_to_{f}"),
		Shape::Type(name) => format!("{}::to_{f}", names::camel(name)),
		Shape::List(item) => format!("|v| wire::list_to_{f}(v, {})", writer(item, form)),
		Shape::Map(entry) => format!("|v| wire::map_to_{f}(v, {})", writer(entry, form)),
	}
}

/// `shape` written in `form` from `arg`, a reference to it.
fn write(shape: &Shape, form: Form, arg: &str) -> String {
	let f = form.name();
	match shape {
		Shape::List(item) => format!("wire::list_to_{f}({arg}, {})", writer(item, form)),
		Shape::Map(entry) => format!("wire::map_to_{f}({arg}, {})", writer(entry, form)),
		Shape::Prim(_) | Shape::Id | Shape::Type(_) => format!("{}({arg})", writer(shape, form)),
	}
}

/// A field's value as a record or a union writes it, `Some` of it or, if optional, as it is held:
/// `place` is where it is, `self.name` or a binding, and `borrowed` whether that is a reference.
fn field_value(field: &Field, form: Form, place: &str, borrowed: bool) -> String {
	if field.optional {
		format!("{place}.as_ref().map({})", writer(&field.shape, form))
	} else if borrowed {
		format!("Some({})", write(&field.shape, form, place))
	} else {
		format!("Some({})", write(&field.shape, form, &format!("&{place}")))
	}
}

/// The fields of `fields` as a record's or a union's writer lists them, each `(name, value)`.
fn written(out: &mut Out, fields: &[Field], form: Form, place: impl Fn(&Field) -> (String, bool)) {
	for field in fields {
		let (at, borrowed) = place(field);
		let value = field_value(field, form, &at, borrowed);
		match form {
			Form::Json => out.line(&format!("({:?}, {value}),", field.name)),
			Form::Cbor => out.line(&format!("({}, {value}),", field.key)),
		}
	}
}

/// Each field read from `object` or `map`, as a struct literal's lines.
fn read_fields(out: &mut Out, fields: &[Field], form: Form) {
	for field in fields {
		let reader = reader(&field.shape, form);
		let call = match (form, field.optional) {
			(Form::Json, false) => format!("wire::field_json(object, {:?}, {reader})", field.name),
			(Form::Json, true) => format!("wire::optional_json(object, {:?}, {reader})", field.name),
			(Form::Cbor, false) => {
				format!("wire::field_cbor(map, {}, {:?}, {reader})", field.key, field.name)
			}
			(Form::Cbor, true) => {
				format!("wire::optional_cbor(map, {}, {:?}, {reader})", field.key, field.name)
			}
		};
		out.line(&format!("{}: {call}?,", names::ident(&field.name)));
	}
}

/// A field's doc comment.
fn field_doc(field: &Field) -> String {
	if field.optional {
		format!("/// `{}`, key {}, absent when it has nothing to say.", field.name, field.key)
	} else {
		format!("/// `{}`, key {}.", field.name, field.key)
	}
}

/// The fields, as a struct's or a case's lines.
fn declare_fields(out: &mut Out, fields: &[Field], public: bool) {
	for field in fields {
		out.line(&field_doc(field));
		let ty = rust_type(&field.shape);
		let ty = if field.optional { format!("Option<{ty}>") } else { ty };
		let visibility = if public { "pub " } else { "" };
		out.line(&format!("{visibility}{}: {ty},", names::ident(&field.name)));
	}
}

fn record(out: &mut Out, rust: &str, doc: &str, fields: &[Field]) {
	out.line(doc);
	out.line("#[derive(Debug, Clone, PartialEq)]");
	if fields.is_empty() {
		out.line(&format!("pub struct {rust} {{}}"));
	} else {
		out.open(&format!("pub struct {rust} {{"));
		declare_fields(out, fields, true);
		out.close("}");
	}
	out.line("");
	out.open(&format!("impl Encoded for {rust} {{"));
	for form in [Form::Json, Form::Cbor] {
		let f = form.name();
		out.open(&format!("fn to_{f}(&self) -> {} {{", form.value()));
		out.open(&format!("wire::record_{f}(["));
		written(out, fields, form, |field| (format!("self.{}", names::ident(&field.name)), false));
		out.close("])");
		out.close("}");
		out.line("");
		out.open(&format!("fn from_{f}({f}: &{}) -> Result<Self, Malformed> {{", form.value()));
		let within = match form {
			Form::Json => "object",
			Form::Cbor => "map",
		};
		if fields.is_empty() {
			out.line(&format!("wire::{within}_{f}({f})?;"));
			out.line("Ok(Self {})");
		} else {
			out.line(&format!("let {within} = wire::{within}_{f}({f})?;"));
			out.open("Ok(Self {");
			read_fields(out, fields, form);
			out.close("})");
		}
		out.close("}");
		if form == Form::Json {
			out.line("");
		}
	}
	out.close("}");
}

/// What a reader of `choices` expects, in each form: their names, and their codes.
fn expected(choices: impl Iterator<Item = (String, i64)> + Clone) -> (String, String) {
	let names: Vec<String> = choices.clone().map(|(name, _)| name).collect();
	let codes: Vec<String> = choices.map(|(_, code)| code.to_string()).collect();
	(format!("one of {}", names.join(", ")), format!("one of {}", codes.join(", ")))
}

fn enumeration(out: &mut Out, declared: &Declared, rust: &str, choices: &[Choice], ordered: bool) {
	if ordered {
		out.line(&format!(
			"/// `{}`, an enumeration of `model/contracts.json`, ordered by its codes.",
			declared.name
		));
		out.line("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]");
	} else {
		out.line(&format!("/// `{}`, an enumeration of `model/contracts.json`.", declared.name));
		out.line("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]");
	}
	out.open(&format!("pub enum {rust} {{"));
	for choice in choices {
		out.line(&format!("/// `{}`, code {}.", choice.name, choice.code));
		out.line(&format!("{},", names::camel(&choice.name)));
	}
	out.close("}");
	out.line("");
	let (json, cbor) = expected(choices.iter().map(|c| (c.name.clone(), c.code)));
	out.open(&format!("impl Encoded for {rust} {{"));
	out.open("fn to_json(&self) -> serde_json::Value {");
	out.open("wire::name_to_json(match self {");
	for choice in choices {
		out.line(&format!("Self::{} => {:?},", names::camel(&choice.name), choice.name));
	}
	out.close("})");
	out.close("}");
	out.line("");
	out.open("fn from_json(json: &serde_json::Value) -> Result<Self, Malformed> {");
	out.open(&format!("match wire::name_from_json(json, {json:?})? {{"));
	for choice in choices {
		out.line(&format!("{:?} => Ok(Self::{}),", choice.name, names::camel(&choice.name)));
	}
	out.line(&format!("_ => Err(wire::unexpected({json:?})),"));
	out.close("}");
	out.close("}");
	out.line("");
	out.open("fn to_cbor(&self) -> codec::Value {");
	out.open("wire::code_to_cbor(match self {");
	for choice in choices {
		out.line(&format!("Self::{} => {},", names::camel(&choice.name), choice.code));
	}
	out.close("})");
	out.close("}");
	out.line("");
	out.open("fn from_cbor(cbor: &codec::Value) -> Result<Self, Malformed> {");
	out.open(&format!("match wire::code_from_cbor(cbor, {cbor:?})? {{"));
	for choice in choices {
		out.line(&format!("{} => Ok(Self::{}),", choice.code, names::camel(&choice.name)));
	}
	out.line(&format!("_ => Err(wire::unexpected({cbor:?})),"));
	out.close("}");
	out.close("}");
	out.close("}");
}

/// A case's pattern, binding each of its fields by its name.
fn pattern(case: &Case) -> String {
	let variant = names::camel(&case.name);
	if case.fields.is_empty() {
		format!("Self::{variant}")
	} else {
		let fields: Vec<String> = case.fields.iter().map(|f| names::ident(&f.name)).collect();
		format!("Self::{variant} {{ {} }}", fields.join(", "))
	}
}

fn union(out: &mut Out, declared: &Declared, rust: &str, tag: &str, cases: &[Case]) {
	out.line(&format!(
		"/// `{}`, a union of `model/contracts.json`, its case named by `{tag}` in JSON and key 0 in CBOR.",
		declared.name
	));
	out.line("#[derive(Debug, Clone, PartialEq)]");
	out.open(&format!("pub enum {rust} {{"));
	for case in cases {
		out.line(&format!("/// `{}`, code {}.", case.name, case.code));
		let variant = names::camel(&case.name);
		if case.fields.is_empty() {
			out.line(&format!("{variant},"));
		} else {
			out.open(&format!("{variant} {{"));
			declare_fields(out, &case.fields, false);
			out.close("},");
		}
	}
	out.close("}");
	out.line("");
	let (json, cbor) = expected(cases.iter().map(|c| (c.name.clone(), c.code)));
	out.open(&format!("impl Encoded for {rust} {{"));
	for form in [Form::Json, Form::Cbor] {
		let f = form.name();
		out.open(&format!("fn to_{f}(&self) -> {} {{", form.value()));
		out.open("match self {");
		for case in cases {
			let head = match form {
				Form::Json => format!("wire::union_json({tag:?}, {:?}, [", case.name),
				Form::Cbor => format!("wire::union_cbor({}, [", case.code),
			};
			if case.fields.is_empty() {
				out.line(&format!("{} => {head}]),", pattern(case)));
			} else {
				out.open(&format!("{} => {head}", pattern(case)));
				written(out, &case.fields, form, |field| (names::ident(&field.name), true));
				out.close("]),");
			}
		}
		out.close("}");
		out.close("}");
		out.line("");
		out.open(&format!("fn from_{f}({f}: &{}) -> Result<Self, Malformed> {{", form.value()));
		let (within, expected) = match form {
			Form::Json => ("object", &json),
			Form::Cbor => ("map", &cbor),
		};
		out.line(&format!("let {within} = wire::{within}_{f}({f})?;"));
		out.open(&format!("match wire::case_{f}({within}, {tag:?})? {{"));
		for case in cases {
			let variant = names::camel(&case.name);
			let label = match form {
				Form::Json => format!("{:?}", case.name),
				Form::Cbor => case.code.to_string(),
			};
			if case.fields.is_empty() {
				out.line(&format!("{label} => Ok(Self::{variant}),"));
			} else {
				out.open(&format!("{label} => Ok(Self::{variant} {{"));
				read_fields(out, &case.fields, form);
				out.close("}),");
			}
		}
		out.line(&format!("_ => Err(wire::unknown_case({tag:?}, {expected:?})),"));
		out.close("}");
		out.close("}");
		if form == Form::Json {
			out.line("");
		}
	}
	out.close("}");
}

fn flags(out: &mut Out, declared: &Declared, rust: &str, flags: &[Choice]) {
	out.line(&format!(
		"/// `{}`, a set of names of `model/contracts.json`, each a bit of the `u32` it holds.",
		declared.name
	));
	out.line("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]");
	out.open(&format!("pub struct {rust}("));
	out.line("/// The bits set.");
	out.line("pub u32,");
	out.close(");");
	out.line("");
	out.open(&format!("impl {rust} {{"));
	for (i, flag) in flags.iter().enumerate() {
		if i > 0 {
			out.line("");
		}
		out.line(&format!("/// `{}`, bit {}.", flag.name, flag.code));
		out.line(&format!("pub const {}: u32 = {};", names::upper_snake(&flag.name), flag.code));
	}
	out.close("}");
	out.line("");
	let names: Vec<String> = flags.iter().map(|f| format!("({:?}, {})", f.name, f.code)).collect();
	let names = format!("&[{}]", names.join(", "));
	out.open(&format!("impl Encoded for {rust} {{"));
	out.open("fn to_json(&self) -> serde_json::Value {");
	out.line(&format!("wire::flags_to_json(self.0, {names})"));
	out.close("}");
	out.line("");
	out.open("fn from_json(json: &serde_json::Value) -> Result<Self, Malformed> {");
	out.line(&format!("wire::flags_from_json(json, {names}).map(Self)"));
	out.close("}");
	out.line("");
	out.open("fn to_cbor(&self) -> codec::Value {");
	out.line("wire::uint32_to_cbor(&self.0)");
	out.close("}");
	out.line("");
	out.open("fn from_cbor(cbor: &codec::Value) -> Result<Self, Malformed> {");
	out.line(&format!("wire::flags_from_cbor(cbor, {names}).map(Self)"));
	out.close("}");
	out.close("}");
}

/// A constant `&[Reason]` led by `head`, a reason a line, `failure` the path of the type `failure`.
fn reasons(out: &mut Out, head: &str, reasons: &[Reason], failure: &str) {
	if reasons.is_empty() {
		out.line(&format!("{head} = &[];"));
		return;
	}
	out.open(&format!("{head} = &["));
	for r in reasons {
		out.line(&format!(
			"Reason {{ name: {:?}, failure: {failure}::{} }},",
			r.name,
			names::camel(&r.failure)
		));
	}
	out.close("];");
}

fn interface(out: &mut Out, interface: &Interface, at: &str) -> Result<(), Unread> {
	if let Some(op) = interface
		.operations
		.iter()
		.find(|o| TAKEN_BY_INTERFACE.contains(&names::camel(&o.name).as_str()))
	{
		return Err(Unread {
			at: at.to_owned(),
			expected: format!("an operation's name other than {}, which its module imports", op.name),
		});
	}
	out.line(&format!("/// The interface `{}`.", interface.name));
	out.open(&format!("pub mod {} {{", names::ident(&interface.name)));
	out.line("use crate::{Operation, Reason};");
	out.line("");
	out.line("/// Its version, raised as a record's is.");
	out.line(&format!("pub const VERSION: u32 = {};", interface.version));
	let failure = format!("crate::contracts::{}", names::camel(FAILURE));
	for op in &interface.operations {
		let rust = names::camel(&op.name);
		out.line("");
		out.line(&format!(
			"/// `{}`, at `POST /{}/{}`: `{}` in, `{}` out.",
			op.name, interface.name, op.name, op.input, op.output
		));
		out.line("#[derive(Debug, Clone, Copy, PartialEq, Eq)]");
		out.line(&format!("pub struct {rust};"));
		out.line("");
		out.open(&format!("impl Operation for {rust} {{"));
		out.line(&format!("type Input = crate::contracts::{};", names::camel(&op.input)));
		out.line(&format!("type Output = crate::contracts::{};", names::camel(&op.output)));
		out.line("");
		out.line(&format!("const INTERFACE: &'static str = {:?};", interface.name));
		out.line(&format!("const VERSION: u32 = {};", interface.version));
		out.line(&format!("const NAME: &'static str = {:?};", op.name));
		reasons(out, "const REASONS: &'static [Reason]", &op.reasons, &failure);
		out.close("}");
	}
	out.close("}");
	Ok(())
}

/// Every shape of the contracts' fields, nested ones among them.
fn shapes(model: &Model) -> Vec<&Shape> {
	fn within<'a>(shape: &'a Shape, all: &mut Vec<&'a Shape>) {
		all.push(shape);
		match shape {
			Shape::List(inner) | Shape::Map(inner) => within(inner, all),
			Shape::Prim(_) | Shape::Id | Shape::Type(_) => {}
		}
	}
	let mut all = Vec::new();
	let fields = model.types.iter().flat_map(|t| match &t.def {
		Def::Record(fields) => fields.iter().collect::<Vec<_>>(),
		Def::Union { cases, .. } => cases.iter().flat_map(|c| &c.fields).collect(),
		Def::Enum { .. } | Def::Flags(_) => Vec::new(),
	});
	for field in fields.chain(&model.shell) {
		within(&field.shape, &mut all);
	}
	all
}

/// The module `contracts`, whole.
pub(super) fn module(model: &Model) -> Result<String, Unread> {
	let mut seen = BTreeSet::new();
	for declared in &model.types {
		let rust = names::camel(&declared.name);
		if TAKEN.contains(&rust.as_str()) || !seen.insert(rust.clone()) {
			return Err(Unread {
				at: format!("types/{}", declared.name),
				expected: format!("a name whose Rust, {rust}, nothing else in the module is"),
			});
		}
	}
	let mut out = Out { text: String::new(), depth: 0 };
	out.line("// The contracts of model/contracts.json, written by envelope-generator, RFC fhg6w: never edited");
	out.line("// and never committed.");
	out.line("");
	let shapes = shapes(model);
	let has = |prim: Prim| shapes.iter().any(|s| **s == Shape::Prim(prim));
	if shapes.iter().any(|s| matches!(s, Shape::Map(_))) {
		out.line("use std::collections::BTreeMap;");
		out.line("");
	}
	let mut imports = vec!["Encoded"];
	if has(Prim::Int53) {
		imports.push("Int53");
	}
	imports.extend(["Malformed", "Reason"]);
	if has(Prim::Uint53) {
		imports.push("Uint53");
	}
	imports.push("wire");
	out.line(&format!("use crate::{{{}}};", imports.join(", ")));
	for declared in &model.types {
		out.line("");
		let rust = names::camel(&declared.name);
		match &declared.def {
			Def::Record(fields) => {
				let doc = format!("/// `{}`, a record of `model/contracts.json`.", declared.name);
				record(&mut out, &rust, &doc, fields);
			}
			Def::Enum { choices, ordered } => enumeration(&mut out, declared, &rust, choices, *ordered),
			Def::Union { tag, cases } => union(&mut out, declared, &rust, tag, cases),
			Def::Flags(choices) => flags(&mut out, declared, &rust, choices),
		}
	}
	out.line("");
	let doc = "/// The shell every record's row is, `model/contracts.json`'s `shell`: its kind, its id, the\n/// generation that wrote it, its version, and its content, absent once the record is deleted.";
	record(&mut out, "Shell", doc, &model.shell);
	let failure = names::camel(FAILURE);
	out.line("");
	out.line("/// The reasons every operation may fail for, declared by none.");
	reasons(&mut out, "pub const REASONS: &[Reason]", &model.reasons, &failure);
	out.line("");
	out.line("/// The reasons a call between apps adds.");
	reasons(&mut out, "pub const CALLING: &[Reason]", &model.calling, &failure);
	out.line("");
	out.line("/// Each interface of `model/contracts.json`, an operation reached at");
	out.line("/// `POST /{interface}/{operation}`.");
	out.open("pub mod interface {");
	for (i, each) in model.interfaces.iter().enumerate() {
		if i > 0 {
			out.line("");
		}
		interface(&mut out, each, &format!("interfaces/{}", each.name))?;
	}
	out.close("}");
	for (form, from, to, doc) in [
		(
			Form::Json,
			"json",
			"cbor",
			"/// The JSON read as the type `name` and written as its CBOR, or none where no type is so named.",
		),
		(
			Form::Cbor,
			"cbor",
			"json",
			"/// The CBOR read as the type `name` and written as its JSON, or none where no type is so named.",
		),
	] {
		out.line("");
		out.line(doc);
		out.open(&format!(
			"pub fn {from}_to_{to}(name: &str, {from}: &{}) -> Option<Result<{}, Malformed>> {{",
			form.value(),
			match form {
				Form::Json => Form::Cbor.value(),
				Form::Cbor => Form::Json.value(),
			}
		));
		out.open("match name {");
		for declared in &model.types {
			out.line(&format!(
				"{:?} => Some(wire::{from}_to_{to}::<{}>({from})),",
				declared.name,
				names::camel(&declared.name)
			));
		}
		out.line("_ => None,");
		out.close("}");
		out.close("}");
	}
	Ok(out.text)
}
