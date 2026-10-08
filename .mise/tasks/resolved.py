"""What each crate is built from beyond this repository's files, read at two revisions: the packages
it resolves to, and the parts of the root Cargo.toml it inherits. Read by `deployable`, so a
change to either rebuilds only the images whose inputs moved. Cargo.lock is read first, as text:
a crate whose packages there did not move did not. Every package any member enables lands in the
lockfile, so one that did is asked of cargo, which builds each image's crate alone and says what
that compiles; where cargo cannot answer, the lockfile's word stands.
"""

import subprocess
import tomllib

# The profile every image is built with, `cargo build --profile container` in each Dockerfile.
IMAGE_PROFILE = "container"

# What every image is built for: `$arch-unknown-linux-musl` in each Dockerfile.
TARGETS = ("aarch64-unknown-linux-musl", "x86_64-unknown-linux-musl")

# Parts of `[workspace]` no image is built from as such: who is a member moves Cargo.lock and the
# member's own files, both read apart, and lints and metadata change warnings and tools, not output.
UNBUILT = ("members", "exclude", "default-members", "lints", "metadata")


def closures(lock, crates):
	"""Crate -> every package it reaches in the lockfile `lock`, itself included, each as its name,
	version, source and checksum; None for a crate the lockfile does not hold."""
	by_name = {}
	for package in tomllib.loads(lock).get("package", []):
		by_name.setdefault(package["name"], []).append(package)

	def resolved(reference):
		# `name`, `name version` or `name version (source)`: as much as tells it apart.
		name, *rest = reference.split(" ", 2)
		found = by_name.get(name, [])
		if rest:
			found = [package for package in found if package["version"] == rest[0]]
		if len(rest) > 1:
			found = [package for package in found if package.get("source") == rest[1].strip("()")]
		return found

	def key(package):
		return tuple(package.get(field, "") for field in ("name", "version", "source", "checksum"))

	result = {}
	for crate in crates:
		queue = [package for package in by_name.get(crate, []) if "source" not in package]
		seen = set()
		while queue:
			package = queue.pop()
			if key(package) in seen:
				continue
			seen.add(key(package))
			for reference in package.get("dependencies", []):
				queue.extend(resolved(reference))
		result[crate] = frozenset(seen) if seen else None
	return result


def lock_moved(base, head, crates):
	"""The crates of `crates` whose packages differ between the two lockfiles."""
	before, after = closures(base, crates), closures(head, crates)
	return {crate for crate in crates if before[crate] != after[crate]}


def built_from(tree, crate, cwd):
	"""What `cargo build -p crate` compiles for an image in `tree`, each package with its features
	and with paths made relative to the tree; None where cargo cannot say."""
	root = str(tree.resolve())
	command = ["cargo", "tree", "--locked", "--manifest-path", f"{root}/Cargo.toml", "-p", crate]
	command += ["-e", "normal,build", "--prefix", "none", "--format", "{p} {f}"]
	for target in TARGETS:
		command += ["--target", target]
	answer = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
	if answer.returncode != 0:
		return None
	lines = answer.stdout.splitlines()
	return frozenset(line.replace(" (*)", "").replace(root, "") for line in lines)


def tree_moved(base, head, crates, cwd):
	"""The crates cargo builds from something else in the tree `head` than in `base`; any it
	cannot read in either counts as moved."""
	moved = set()
	for crate in crates:
		before = built_from(base, crate, cwd)
		if before is None or before != built_from(head, crate, cwd):
			moved.add(crate)
	return moved


def _profiles(manifest):
	"""The profiles an image's build reads, following `inherits` from the image's own."""
	profiles = manifest.get("profile", {})
	chain, name = {"release"}, IMAGE_PROFILE
	while name and name not in chain:
		chain.add(name)
		name = profiles.get(name, {}).get("inherits")
	return chain


def _inherits(member, table, key):
	"""Whether `member` takes `key` of `[workspace.<table>]` with `workspace = true`."""
	if table == "package":
		return member.get("package", {}).get(key) == {"workspace": True}
	sections = [member] + list(member.get("target", {}).values())
	kinds = ("dependencies", "dev-dependencies", "build-dependencies")
	for section in sections:
		for kind in kinds:
			entry = section.get(kind, {}).get(key)
			if isinstance(entry, dict) and entry.get("workspace") is True:
				return True
	return False


def _has_path(table):
	"""Whether any entry under `table` names a `path`."""
	if not isinstance(table, dict):
		return False
	return "path" in table or any(_has_path(value) for value in table.values())


def manifest_moved(base, head, members):
	"""The crates a change to the root Cargo.toml reaches, or None where it reaches every image or
	cannot be told. `members` maps each crate to its own Cargo.toml, parsed."""
	before, after = tomllib.loads(base), tomllib.loads(head)
	reached = set()
	for top in set(before) | set(after):
		old, new = before.get(top, {}), after.get(top, {})
		if old == new:
			continue
		if top == "profile":
			chain = _profiles(before) | _profiles(after)
			if any(old.get(name) != new.get(name) for name in chain):
				return None
		elif top in ("patch", "replace"):
			# One from the registry or git moves Cargo.lock, which is read apart; a path's does not.
			if _has_path(old) or _has_path(new):
				return None
		elif top == "workspace":
			for part in set(old) | set(new):
				was, now = old.get(part) or {}, new.get(part) or {}
				if was == now or part in UNBUILT:
					continue
				if part not in ("dependencies", "package"):
					return None
				for key in set(was) | set(now):
					if was.get(key) != now.get(key):
						reached |= {name for name, one in members.items() if _inherits(one, part, key)}
		else:
			return None
	return reached
