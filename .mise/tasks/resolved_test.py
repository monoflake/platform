"""resolved.py against small lockfiles and manifests: `python3 .mise/tasks/resolved_test.py`."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from resolved import closures, lock_moved, manifest_moved  # noqa: E402


def lock(*packages):
	"""A lockfile of `(name, version, source or None, [dependency references])`."""
	text = "version = 4\n"
	for name, version, source, dependencies in packages:
		text += f'\n[[package]]\nname = "{name}"\nversion = "{version}"\n'
		if source:
			text += f'source = "{source}"\nchecksum = "{name}{version}"\n'
		if dependencies:
			text += "dependencies = [" + ", ".join(f'"{one}"' for one in dependencies) + "]\n"
	return text


# A source as the lockfile spells one; its text is never read.
REGISTRY = "registry+crates-io"
BASE = lock(
	("ledger", "0.0.0", None, ["serde"]),
	("probe", "0.0.0", None, ["serde", "getrandom"]),
	("serde", "1.0.0", REGISTRY, []),
	("getrandom", "0.2.0", REGISTRY, ["wasi"]),
	("wasi", "0.11.0", REGISTRY, []),
)


class Lockfile(unittest.TestCase):
	def test_a_new_dependency_moves_the_crate_that_takes_it_alone(self):
		head = lock(
			("ledger", "0.0.0", None, ["serde", "tokio-postgres"]),
			("probe", "0.0.0", None, ["serde", "getrandom"]),
			("serde", "1.0.0", REGISTRY, []),
			("tokio-postgres", "0.7.0", REGISTRY, ["getrandom"]),
			("getrandom", "0.2.0", REGISTRY, ["wasi"]),
			("wasi", "0.11.0", REGISTRY, []),
		)
		self.assertEqual(lock_moved(BASE, head, {"ledger", "probe"}), {"ledger"})

	def test_a_shared_package_at_another_version_moves_every_crate_that_reaches_it(self):
		head = BASE.replace('"wasi"\nversion = "0.11.0"', '"wasi"\nversion = "0.11.1"')
		self.assertEqual(lock_moved(BASE, head, {"ledger", "probe"}), {"probe"})

	def test_a_reference_spelled_out_beside_a_second_version_is_the_same_package(self):
		head = lock(
			("ledger", "0.0.0", None, ["serde", "wasi 0.14.0"]),
			("probe", "0.0.0", None, ["serde", "getrandom"]),
			("serde", "1.0.0", REGISTRY, []),
			("getrandom", "0.2.0", REGISTRY, ["wasi 0.11.0"]),
			("wasi", "0.11.0", REGISTRY, []),
			("wasi", "0.14.0", REGISTRY, []),
		)
		self.assertEqual(lock_moved(BASE, head, {"ledger", "probe"}), {"ledger"})

	def test_a_crate_the_lockfile_does_not_hold_has_nothing_to_compare(self):
		self.assertIsNone(closures(BASE, {"quorum"})["quorum"])
		self.assertEqual(lock_moved(BASE, BASE, {"quorum"}), set())


ROOT = """
[workspace]
resolver = "3"
members = ["apps/ledger", "apps/probe"]

[workspace.package]
edition = "2024"

[workspace.dependencies]
serde = "1"

[profile.dev]
opt-level = 0

[profile.container]
inherits = "release"
lto = "fat"
"""

MEMBERS = {
	"ledger": {
		"package": {"edition": {"workspace": True}},
		"dependencies": {"serde": {"workspace": True}},
	},
	"probe": {"package": {"edition": "2021"}, "dependencies": {"serde": "1"}},
}


class Manifest(unittest.TestCase):
	def moved(self, head):
		return manifest_moved(ROOT, head, MEMBERS)

	def test_a_profile_no_image_is_built_with_moves_nothing(self):
		self.assertEqual(self.moved(ROOT.replace("opt-level = 0", "opt-level = 1")), set())

	def test_the_image_profile_or_one_it_inherits_moves_every_image(self):
		self.assertIsNone(self.moved(ROOT.replace('lto = "fat"', 'lto = "thin"')))
		self.assertIsNone(self.moved(ROOT + "\n[profile.release]\ndebug = true\n"))

	def test_a_workspace_dependency_moves_the_crates_that_inherit_it(self):
		self.assertEqual(self.moved(ROOT.replace('serde = "1"', 'serde = "1.0.200"')), {"ledger"})

	def test_a_workspace_package_key_moves_the_crates_that_inherit_it(self):
		self.assertEqual(self.moved(ROOT.replace('edition = "2024"', 'edition = "2021"')), {"ledger"})

	def test_membership_moves_nothing_by_itself(self):
		self.assertEqual(self.moved(ROOT.replace('"apps/probe"]', '"apps/probe", "apps/new"]')), set())

	def test_what_cannot_be_told_apart_moves_every_image(self):
		self.assertIsNone(self.moved(ROOT.replace('resolver = "3"', 'resolver = "2"')))
		self.assertIsNone(self.moved(ROOT + '\n[patch.crates-io]\nserde = { path = "../serde" }\n'))
		self.assertIsNone(self.moved(ROOT + "\n[unknown]\nkey = 1\n"))

	def test_a_patch_from_a_registry_or_git_is_left_to_the_lockfile(self):
		patch = '\n[patch.crates-io]\nserde = { version = "1.0.201", registry = "mirror" }\n'
		self.assertEqual(self.moved(ROOT + patch), set())


if __name__ == "__main__":
	unittest.main()
