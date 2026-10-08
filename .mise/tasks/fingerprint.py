"""What a file is to a build: two revisions of it compare equal here when no image built from them
could tell them apart. Rust source is its tokens, without comments or layout; a Dockerfile, a
`.dockerignore` and the image task are their lines without comments or blank ones; a declaration
or a crate's manifest is its parsed value. Anything else is its bytes. Read by `deployable`. The
same file is in infra's and platform's .mise/tasks, kept identical by hand, since the two share
no library of tasks."""

import re
import tomllib
from pathlib import PurePosixPath

# Where a crate keeps what `cargo build` never compiles into its binary.
UNBUILT_DIRECTORIES = ("tests", "benches", "examples")

# A Dockerfile's parser directives, which look like comments and change the build.
DIRECTIVE = re.compile(r"#\s*(syntax|check|escape)\s*=", re.IGNORECASE)

# A heredoc's opening, `<<EOF`, `<<-EOF` or with the word quoted.
HEREDOC = re.compile(r"<<(-?)\s*[\"']?([A-Za-z_][A-Za-z0-9_]*)[\"']?")

# What starts a raw string, and a raw identifier, at the start of a token.
RAW_STRING = re.compile(r'(?:br|cr|r)(#*)"')
RAW_IDENTIFIER = re.compile(r"r#[A-Za-z_][A-Za-z0-9_]*")

# A character that may continue an identifier, a keyword or a number.
WORD = re.compile(r"[A-Za-z0-9_]")

OPENING, CLOSING = ("(", "[", "{"), (")", "]", "}")

# Words after which `(` opens a tuple, not a call's arguments.
KEYWORDS = {"return", "in", "match", "if", "while", "break", "else", "let", "for", "move", "yield"}


def ignored(path, crate_directories=()):
	"""Whether `path` goes into no image at all: prose, a license, or what a crate builds only for
	its tests, benchmarks and examples."""
	name = PurePosixPath(path).name
	if name.endswith(".md") or name.startswith("LICENSE"):
		return True
	for directory in crate_directories:
		rest = path[len(directory) + 1 :] if path.startswith(directory + "/") else ""
		if "/" in rest and rest.split("/", 1)[0] in UNBUILT_DIRECTORIES:
			return True
	return False


def rust_tokens(text):
	"""The tokens of Rust source `text`, comments and whitespace dropped. A literal is kept whole, so
	a change inside a string is a change; punctuation is one character a token, so `&&` and `& &`,
	which rustfmt rewrites one into the other, are the same; and the commas rustfmt adds and
	removes as it wraps a line are dropped, see `_without_optional_commas`."""
	tokens, i, n = [], 0, len(text)
	while i < n:
		c = text[i]
		if c.isspace():
			i += 1
		elif text.startswith("//", i):
			end = text.find("\n", i)
			i = n if end < 0 else end
		elif text.startswith("/*", i):
			depth, i = 1, i + 2
			while i < n and depth:
				if text.startswith("/*", i):
					depth, i = depth + 1, i + 2
				elif text.startswith("*/", i):
					depth, i = depth - 1, i + 2
				else:
					i += 1
		elif raw := RAW_STRING.match(text, i):
			close = '"' + raw.group(1)
			end = text.find(close, raw.end())
			end = n if end < 0 else end + len(close)
			tokens.append(text[i:end])
			i = end
		elif c == '"' or (c in "bc" and text.startswith('"', i + 1)):
			start = i
			i += 1 if c == '"' else 2
			while i < n and text[i] != '"':
				i += 2 if text[i] == "\\" else 1
			i += 1
			tokens.append(text[start:i])
		elif c == "'" or (c == "b" and text.startswith("'", i + 1)):
			start = i
			i += 1 if c == "'" else 2
			if text.startswith("\\", i) or text.startswith("'", i + 1):
				# A character: an escape, or one character and its closing quote.
				while i < n and text[i] != "'":
					i += 2 if text[i] == "\\" else 1
				i += 1
			else:
				# A lifetime or a label: the quote and the name after it.
				while i < n and WORD.match(text[i]):
					i += 1
			tokens.append(text[start:i])
		elif raw := RAW_IDENTIFIER.match(text, i):
			tokens.append(raw.group(0))
			i = raw.end()
		elif WORD.match(c):
			start = i
			while i < n and WORD.match(text[i]):
				i += 1
			tokens.append(text[start:i])
		else:
			tokens.append(c)
			i += 1
	return _without_optional_commas(_unbraced(_without_optional_semicolons(tokens)))


def _closing(tokens, index):
	"""The index of the bracket closing the one at `index`, or the end."""
	depth = 0
	for at in range(index, len(tokens)):
		if tokens[at] in OPENING:
			depth += 1
		elif tokens[at] in CLOSING:
			depth -= 1
			if depth == 0:
				return at
	return len(tokens)


def _unbraced(tokens):
	"""`tokens` with the body of every match arm and closure that is a block of one expression
	written without its braces, `=> { x }` as `=> x,` and `|y| { x }` as `|y| x`, as rustfmt
	writes it once it fits on a line."""
	tokens, at = list(tokens), 0
	while at + 1 < len(tokens):
		arm = tokens[at : at + 3] == ["=", ">", "{"]
		if not arm and tokens[at : at + 2] != ["|", "{"]:
			at += 1
			continue
		brace = at + 2 if arm else at + 1
		end = _closing(tokens, brace)
		inner, depth, statement = tokens[brace + 1 : end], 0, False
		for token in inner:
			depth += (token in OPENING) - (token in CLOSING)
			statement |= depth == 0 and token == ";"
		if inner and not statement and end < len(tokens):
			comma = [","] if arm and tokens[end + 1 : end + 2] != [","] else []
			tokens[brace : end + 1] = inner + comma
		at = brace
	return tokens


def _without_optional_semicolons(tokens):
	"""`tokens` without the `;` after a `return`, `break` or `continue` that ends a block, which
	rustfmt adds when it puts the block on lines of its own and which changes nothing there."""
	kept, starts = [], []
	for index, token in enumerate(tokens):
		after = tokens[index + 1] if index + 1 < len(tokens) else ""
		if token == ";" and starts and starts[-1] is not None:
			if after == "}" and kept[starts[-1] : starts[-1] + 1] in (["return"], ["break"], ["continue"]):
				continue
			kept.append(token)
			starts[-1] = len(kept)
			continue
		kept.append(token)
		if token in OPENING:
			# A statement begins only in a block.
			starts.append(len(kept) if token == "{" else None)
		elif token in CLOSING and starts:
			starts.pop()
	return kept


def _without_optional_commas(tokens):
	"""`tokens` without the commas that mean nothing: one ending a list, right before `)`, `]`, `}`
	or `>`, and one right after a block's `}` with more to follow, as after a match arm. The comma
	ending a tuple's parentheses with no other is kept, since it makes `(x,)` a tuple; parentheses
	after a name, `!`, `)`, `]` or `>` are a call's, whose last comma means nothing."""
	# Each open bracket: its commas so far, and whether it holds a call's arguments.
	kept, brackets = [], []
	for index, token in enumerate(tokens):
		before = tokens[index - 1] if index else ""
		after = tokens[index + 1] if index + 1 < len(tokens) else ""
		if token == ",":
			if brackets:
				brackets[-1][0] += 1
			if before == "}" and after not in CLOSING + (">",):
				continue
		elif (token in CLOSING or token == ">") and kept and kept[-1] == ",":
			tuple_of_one = token == ")" and brackets and brackets[-1] == [1, False]
			if not tuple_of_one:
				kept.pop()
		if token in OPENING:
			named = WORD.match(before[:1]) and before not in KEYWORDS and not before[:1].isdigit()
			brackets.append([0, bool(named) or before in ("!", ")", "]", ">")])
		elif token in CLOSING and brackets:
			brackets.pop()
		kept.append(token)
	return kept


def dockerfile_lines(text):
	"""A Dockerfile's lines without its comments and blank lines, as Docker's own parser drops them;
	a parser directive is kept, and so is every line of a heredoc, which Docker reads as written."""
	kept, until, dashed = [], None, False
	for line in text.splitlines():
		if until is not None:
			kept.append(line)
			if (line.lstrip("\t") if dashed else line) == until:
				until = None
			continue
		stripped = line.strip()
		if not stripped or (stripped.startswith("#") and not DIRECTIVE.match(stripped)):
			continue
		kept.append(line.rstrip())
		if opened := HEREDOC.search(line):
			dashed, until = opened.group(1) == "-", opened.group(2)
	return kept


def shell_lines(text):
	"""A script's or an ignore file's lines without the blank ones and those that are only a
	comment; a first line that is a shebang is kept."""
	lines = text.splitlines()
	head = lines[:1] if lines and lines[0].startswith("#!") else []
	rest = [line.rstrip() for line in lines[len(head) :]]
	return head + [line for line in rest if line.strip() and not line.strip().startswith("#")]


def toml_value(text):
	"""A TOML file's value, or its text where it does not parse."""
	try:
		return tomllib.loads(text)
	except tomllib.TOMLDecodeError:
		return text


def _normalizer(path):
	"""How `path` is read for a build, by its kind; None for its bytes."""
	name = PurePosixPath(path).name
	if name.endswith(".rs"):
		return rust_tokens
	if name == "Dockerfile" or name.endswith(".Dockerfile"):
		return dockerfile_lines
	if name in ("service.toml", "Cargo.toml"):
		return toml_value
	if name == ".dockerignore" or path == ".mise/tasks/image":
		return shell_lines
	return None


def normalized(path):
	"""Whether `path` is read as more than its bytes, and so is worth reading at all."""
	return _normalizer(path) is not None


def same(path, before, after):
	"""Whether `before` and `after`, `path` at two revisions, or None where it is absent, build the
	same."""
	if before is None or after is None or before == after:
		return before == after
	normalize = _normalizer(path)
	return normalize is not None and normalize(before) == normalize(after)
