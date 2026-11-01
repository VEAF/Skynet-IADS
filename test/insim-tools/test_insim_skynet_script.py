"""Tests for test/insim/skynet_script.py -- the Skynet script the test mission loads. The build is a fake.

Run from anywhere:

    python -m unittest discover -s test/insim-tools -p "test_insim_*.py"
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "test", "insim"))
import skynet_script  # noqa: E402


class SkynetScriptTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        (self.repo / "build-tools").mkdir()
        (self.repo / "skynet-iads-source").mkdir()
        (self.repo / "build-tools" / "listToMerge.txt").write_text("# comment\n\na.lua\nb.lua\n", encoding="utf-8")
        (self.repo / "skynet-iads-source" / "a.lua").write_text("a = 1\n", encoding="utf-8")
        (self.repo / "skynet-iads-source" / "b.lua").write_text("b = 2\n", encoding="utf-8")
        self.target = self.repo / "build" / "insim" / "skynet-iads-insim.lua"

    def build(self, repo):
        return "built " + (repo / "skynet-iads-source" / "a.lua").read_text(encoding="utf-8")

    def prepare(self, forced=None):
        return skynet_script.prepare(self.repo, forced, build=self.build)

    def test_default_writes_then_is_up_to_date(self):
        self.assertEqual(self.prepare(), (self.target, "rebuilt"))
        self.assertEqual(self.prepare(), (self.target, "up to date"))
        self.assertEqual(self.target.read_text(encoding="utf-8"), "built a = 1\n")

    def test_rebuilds_when_a_source_changes(self):
        self.prepare()
        (self.repo / "skynet-iads-source" / "a.lua").write_text("a = 3\n", encoding="utf-8")
        self.assertEqual(self.prepare(), (self.target, "rebuilt"))
        self.assertEqual(self.target.read_text(encoding="utf-8"), "built a = 3\n")

    def test_forced_then_default_rebuilds(self):
        self.prepare()
        forced = self.repo / "forced.lua"
        forced.write_text("forced\n", encoding="utf-8")
        self.assertEqual(self.prepare(forced), (self.target, "forced"))
        self.assertEqual(self.target.read_text(encoding="utf-8"), "forced\n")
        self.assertEqual(self.prepare(), (self.target, "rebuilt"))
        self.assertEqual(self.target.read_text(encoding="utf-8"), "built a = 1\n")

    def test_rebuilds_when_the_file_was_replaced(self):
        self.prepare()
        self.target.write_text("something else\n", encoding="utf-8")
        self.assertEqual(self.prepare(), (self.target, "rebuilt"))
        self.assertEqual(self.target.read_text(encoding="utf-8"), "built a = 1\n")

    def test_no_state_file(self):
        self.prepare()
        self.assertEqual([p.name for p in self.target.parent.iterdir()], [self.target.name])

    def test_default_build_is_the_repository_build(self):
        (self.repo / "skynet-iads-source" / "skynet-iads.lua").write_text('SkynetIADS.version = "9.9.9"\n', encoding="utf-8")
        (self.repo / "build-tools" / "listToMerge.txt").write_text("a.lua\n", encoding="utf-8")
        self.assertEqual(skynet_script.build_text(self.repo), 'env.info("--- SKYNET VERSION: 9.9.9 ---")\na = 1\n')


if __name__ == "__main__":
    unittest.main()
