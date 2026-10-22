"""Tests for test/insim/skynet_script.py -- the Skynet script the test mission loads. The build is a fake.

Run from anywhere:

    python -m unittest discover -s test/python -p "test_insim_*.py"
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
        (self.repo / "demo-missions").mkdir()
        (self.repo / "build-tools" / "listToMerge.txt").write_text("# comment\n\na.lua\nb.lua\n", encoding="utf-8")
        (self.repo / "skynet-iads-source" / "a.lua").write_text("a = 1\n", encoding="utf-8")
        (self.repo / "skynet-iads-source" / "b.lua").write_text("b = 2\n", encoding="utf-8")
        self.builds = 0
        self.target = self.repo / "build" / "insim" / "skynet-iads-insim.lua"

    def build(self, repo):
        self.builds += 1
        a = (repo / "skynet-iads-source" / "a.lua").read_text(encoding="utf-8")
        (repo / "demo-missions" / "skynet-iads-compiled.lua").write_text("built " + a, encoding="utf-8")

    def prepare(self, forced=None):
        return skynet_script.prepare(self.repo, forced, build=self.build)

    def test_default_builds_once(self):
        self.assertEqual(self.prepare(), self.target)
        self.prepare()
        self.assertEqual(self.builds, 1)
        self.assertEqual(self.target.read_text(encoding="utf-8"), "built a = 1\n")

    def test_rebuilds_when_a_source_changes(self):
        self.prepare()
        (self.repo / "skynet-iads-source" / "b.lua").write_text("b = 3\n", encoding="utf-8")
        self.prepare()
        self.assertEqual(self.builds, 2)

    def test_forced_then_default_rebuilds(self):
        self.prepare()
        forced = self.repo / "forced.lua"
        forced.write_text("forced\n", encoding="utf-8")
        self.prepare(forced)
        self.assertEqual(self.target.read_text(encoding="utf-8"), "forced\n")
        self.assertEqual(self.builds, 1)
        self.prepare()
        self.assertEqual(self.builds, 2)
        self.assertEqual(self.target.read_text(encoding="utf-8"), "built a = 1\n")

    def test_rebuilds_when_the_file_was_replaced(self):
        self.prepare()
        self.target.write_text("something else\n", encoding="utf-8")
        self.prepare()
        self.assertEqual(self.builds, 2)
        self.assertEqual(self.target.read_text(encoding="utf-8"), "built a = 1\n")


if __name__ == "__main__":
    unittest.main()
