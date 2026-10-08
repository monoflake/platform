"""deployable's choice of images, against this repository's own apps:
`python3 .mise/tasks/deployable_test.py`."""

import importlib.machinery
import importlib.util
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
loader = importlib.machinery.SourceFileLoader("deployable", str(HERE / "deployable"))
spec = importlib.util.spec_from_loader("deployable", loader)
deployable = importlib.util.module_from_spec(spec)
loader.exec_module(deployable)

DECLARED = deployable.apps()
GEO = "apps/compute/geo/src/main.rs"


class Revision:
	"""A revision holding `texts`, path to text, and the working copy's text of any other path."""

	def __init__(self, texts):
		self.texts = texts

	def read(self, path):
		if path in self.texts:
			return self.texts[path]
		file = deployable.ROOT / path
		return file.read_text() if file.exists() else None


def rebuilt(path, change=None):
	"""The images a change to `path` needs, by `change`, a function of its text; given none, with
	no revisions to read, as `--files` asks."""
	if change is None:
		return deployable.needed([path], DECLARED)
	before = (deployable.ROOT / path).read_text()
	revisions = (Revision({path: before}), Revision({path: change(before)}))
	return deployable.needed([path], DECLARED, revisions)


class Fingerprints(unittest.TestCase):
	def test_a_comment_in_rust_is_no_change(self):
		self.assertEqual(rebuilt(GEO, lambda text: "// A note.\n" + text.replace("\n", "\n/* and */\n", 3)), [])

	def test_a_reformat_is_no_change(self):
		self.assertEqual(rebuilt(GEO, lambda text: text.replace("\t", "    ").replace(" {\n", "\n{\n")), [])

	def test_a_changed_token_is_a_rebuild(self):
		self.assertEqual(rebuilt(GEO, lambda text: text + "\nfn another() {}\n"), ["geo"])
		self.assertEqual(rebuilt(GEO), ["geo"])

	def test_prose_and_tests_build_nothing(self):
		for path in ("apps/compute/geo/README.md", "apps/data/primary/tests/proxy.rs", "LICENSE"):
			self.assertEqual(rebuilt(path), [], path)

	def test_a_comment_in_a_declaration_is_no_change_and_a_value_is_a_rebuild(self):
		declaration = "apps/compute/geo/service.toml"
		self.assertEqual(rebuilt(declaration, lambda text: "# Why.\n" + text), [])
		changed = rebuilt(declaration, lambda text: text.replace('name = "geo"', 'name = "geo"\nhealth_timeout = 9'))
		self.assertEqual(changed, ["geo"])

	def test_a_comment_in_a_dockerfile_is_no_change(self):
		dockerfile = "apps/compute/geo/Dockerfile"
		self.assertEqual(rebuilt(dockerfile, lambda text: text + "\n# Done.\n"), [])
		self.assertEqual(rebuilt(dockerfile, lambda text: text.replace("FROM ", "FROM --platform=$BUILDPLATFORM ", 1)), ["geo"])

	def test_the_build_is_every_image_unless_only_its_comments_moved(self):
		self.assertEqual(rebuilt(".dockerignore", lambda text: text + "# More.\n"), [])
		self.assertEqual(rebuilt(".dockerignore", lambda text: text + "**/cache\n"), sorted(DECLARED))

	def test_a_binarys_directory_holds_nothing_else_its_image_is_built_from(self):
		# apt's units and apk's door are installed on the node, never built into the image.
		for path in ("apps/system/apt/units/apt-nightly-update.service", "apps/system/apk/door/apk-door.sh"):
			self.assertEqual(rebuilt(path), [], path)
		# What a binary includes is in it.
		self.assertEqual(rebuilt("apps/observe/probe/checks.toml"), ["probe"])
		# deployer copies its whole directory, so anything there is its image's.
		self.assertNotIn("deployer", deployable.cargo_built(DECLARED, deployable.rust_graph()[0]))
		self.assertEqual(rebuilt("apps/system/deployer/src/extra.ts"), ["deployer"])


if __name__ == "__main__":
	unittest.main()
