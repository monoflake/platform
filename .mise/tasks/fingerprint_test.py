"""fingerprint.py against small sources: `python3 .mise/tasks/fingerprint_test.py`."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fingerprint import ignored, rust_tokens, same  # noqa: E402

RUST = '''//! The crate.

/// A greeting, said once.
pub fn greet<'a>(name: &'a str, times: u8) -> String {
	// Said as many times as asked.
	let line = format!("hello, {name} // not a comment /* nor this */");
	let raw = r#"a "quoted" // word"#;
	let quote = '\\'';
	let brace = '{';
	/* a block /* nested */ still a comment */
	'outer: for _ in 0..times {
		break 'outer;
	}
	match times {
		0 => String::new(),
		_ => { line.repeat(times as usize) },
	}
}
'''

# RUST as rustfmt might lay it out, its comments rewritten and the optional commas moved.
REFLOWED = '''/*! The crate, said otherwise. */

/** A greeting. */
pub fn greet<'a>(
	name: &'a str,
	times: u8,
) -> String {
	let line =
		format!("hello, {name} // not a comment /* nor this */",);
	let raw = r#"a "quoted" // word"#;
	let quote = '\\'';
	let brace = '{';
	'outer: for _ in 0..times { break 'outer; }
	match times {
		0 => String::new(),
		_ => {
			line.repeat(times as usize)
		}
	}
}
'''


class Rust(unittest.TestCase):
	def test_comments_and_layout_are_no_change(self):
		self.assertTrue(same("src/lib.rs", RUST, REFLOWED))

	def test_a_changed_token_is_a_change(self):
		self.assertFalse(same("src/lib.rs", RUST, RUST.replace("0..times", "1..times")))
		self.assertFalse(same("src/lib.rs", RUST, RUST.replace("u8", "u16")))

	def test_a_change_inside_a_literal_is_a_change_however_it_looks(self):
		self.assertFalse(same("src/lib.rs", RUST, RUST.replace("// not a comment", "//  not a comment")))
		self.assertFalse(same("src/lib.rs", RUST, RUST.replace('// word"#', '//word"#')))
		self.assertFalse(same("src/lib.rs", RUST, RUST.replace("'{'", "'}'")))

	def test_literals_and_lifetimes_are_tokens_of_their_own(self):
		tokens = rust_tokens("x = b'a' + '\\n'; fn f<'a>() -> &'a [u8] { br##\"x\"# y\"## }")
		self.assertIn("b'a'", tokens)
		self.assertIn("'\\n'", tokens)
		self.assertIn("'a", tokens)
		self.assertIn('br##"x"# y"##', tokens)
		self.assertEqual(rust_tokens("r#type c\"s\""), ["r#type", 'c"s"'])

	def test_a_tuple_of_one_keeps_its_comma(self):
		self.assertFalse(same("a.rs", "let x = (1,);", "let x = (1);"))
		self.assertTrue(same("a.rs", "f(1, 2,);", "f(1, 2);"))
		self.assertTrue(same("a.rs", "let v = [1, 2,];", "let v = [1, 2];"))
		self.assertTrue(same("a.rs", 'format!("x",); f::<u8>(a,)', 'format!("x"); f::<u8>(a)'))
		self.assertFalse(same("a.rs", "Some((x,))", "Some((x))"))
		self.assertFalse(same("a.rs", "return (x,);", "return (x);"))

	def test_punctuation_is_one_character_a_token(self):
		self.assertTrue(same("a.rs", "if a&&b {}", "if a && b {}"))
		self.assertFalse(same("a.rs", "a + b", "a - b"))

	def test_an_unfinished_source_is_read_to_its_end(self):
		self.assertEqual(rust_tokens('let s = "open'), ["let", "s", "=", '"open'])
		self.assertEqual(rust_tokens("x /* open"), ["x"])


class Lines(unittest.TestCase):
	DOCKERFILE = "# syntax=docker/dockerfile:1\n# check=skip=X\n# A comment.\nFROM a\n\n\tRUN b \\\n\t# inside\n\t\tc\n"

	def test_a_dockerfiles_comments_and_blank_lines_are_no_change(self):
		edited = self.DOCKERFILE.replace("# A comment.", "# Another.\n\n").replace("# inside", "# else")
		self.assertTrue(same("apps/x/y/Dockerfile", self.DOCKERFILE, edited))

	def test_a_directive_is_not_a_comment(self):
		edited = self.DOCKERFILE.replace("# check=skip=X\n", "")
		self.assertFalse(same("apps/x/y/Dockerfile", self.DOCKERFILE, edited))
		self.assertFalse(same("apps/x/y/Dockerfile", self.DOCKERFILE, self.DOCKERFILE.replace("RUN b", "RUN d")))

	def test_a_heredoc_is_read_as_written(self):
		before = "FROM a\nCOPY <<EOF /etc/x\n# kept\nEOF\n# dropped\n"
		self.assertTrue(same("Dockerfile", before, before.replace("# dropped", "# gone")))
		self.assertFalse(same("Dockerfile", before, before.replace("# kept", "# changed")))

	def test_the_image_task_and_the_ignore_file_drop_their_comments(self):
		task = "#!/usr/bin/env bash\n# Why.\nset -e\n\nbuild # a note\n"
		self.assertTrue(same(".mise/tasks/image", task, task.replace("# Why.", "# Because.")))
		self.assertFalse(same(".mise/tasks/image", task, task.replace("bash", "sh")))
		self.assertFalse(same(".mise/tasks/image", task, task.replace("# a note", "# another")))
		self.assertTrue(same(".dockerignore", "# Out.\n**/target\n", "**/target\n\n"))

	def test_any_other_file_is_its_bytes(self):
		self.assertFalse(same("apps/x/y/checks.toml", "a = 1\n", "a = 1 # one\n"))
		self.assertFalse(same("apps/x/y/run.sh", "# a\nx\n", "# b\nx\n"))


class Toml(unittest.TestCase):
	def test_a_declaration_is_its_value(self):
		before = 'name = "geo" # the app\n[container]\nport = 1\n'
		self.assertTrue(same("apps/x/geo/service.toml", before, '# Geo.\nname = "geo"\n\n[container]\nport = 1\n'))
		self.assertFalse(same("apps/x/geo/service.toml", before, before.replace("port = 1", "port = 2")))
		self.assertTrue(same("libs/a/Cargo.toml", '[package]\nname = "a"\n', '[package]\n# A.\nname = "a"\n'))

	def test_a_file_that_appears_or_goes_is_a_change(self):
		self.assertFalse(same("a.rs", None, "fn f() {}"))
		self.assertFalse(same("a.rs", "fn f() {}", None))
		self.assertTrue(same("a.rs", None, None))


class Ignored(unittest.TestCase):
	def test_prose_licenses_and_what_a_crate_builds_for_its_tests_go_into_no_image(self):
		crates = ("apps/data/primary", "libs/deploy")
		for path in ("README.md", "apps/data/primary/README.md", "LICENSE", "libs/deploy/LICENSE-MIT"):
			self.assertTrue(ignored(path, crates), path)
		for path in ("apps/data/primary/tests/one.rs", "libs/deploy/benches/b.rs", "libs/deploy/examples/e.rs"):
			self.assertTrue(ignored(path, crates), path)
		for path in ("apps/data/primary/src/tests.rs", "libs/deploy/src/tests/mod.rs", "apps/data/primary/tests"):
			self.assertFalse(ignored(path, crates), path)
		self.assertFalse(ignored("apps/x/tests/a.rs", crates))


if __name__ == "__main__":
	unittest.main()
