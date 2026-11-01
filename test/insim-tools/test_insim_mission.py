"""Tests for test/insim/engine/mission.py -- the mission's working copy, built from a synthetic template.

Run from anywhere:

    python -m unittest discover -s test/insim-tools -p "test_insim_*.py"
"""

import json
import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "test", "insim"))
from engine import mission  # noqa: E402

P = mission.PLACEHOLDER


def make_zip(path, entries):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, text in entries.items():
            z.writestr(name, text.encode("utf-8"))


def read_member(path, name):
    with zipfile.ZipFile(path) as z:
        return z.read(name).decode("utf-8")


class PrepareTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.root = self.tmp / "dcs-hotload"
        self.root.mkdir()
        self.t = self.tmp / "template.miz"
        self.w = self.tmp / "working.miz"
        self.entries = {
            "mission": 'mission = { text = "dofile(\\"' + P + '/dcs-hotload.lua\\")", a = "' + P + '/x" }',
            "options": "options = {}",
        }
        make_zip(self.t, self.entries)

    def test_writes_the_path_in_both_places(self):
        self.assertTrue(mission.prepare(self.t, self.w, self.root))
        text = read_member(self.w, "mission")
        self.assertEqual(text.count(self.root.resolve().as_posix()), 2)
        self.assertNotIn(mission.PLACEHOLDER, text)
        self.assertEqual(read_member(self.w, "options"), read_member(self.t, "options"))

    def test_records_what_it_was_built_from(self):
        mission.prepare(self.t, self.w, self.root)
        info = json.loads(self.w.with_suffix(".json").read_text(encoding="utf-8"))
        self.assertEqual(info["hotload_root"], self.root.resolve().as_posix())
        self.assertEqual(len(info["template_sha256"]), 64)

    def test_leaves_an_up_to_date_copy_alone(self):
        mission.prepare(self.t, self.w, self.root)
        self.assertFalse(mission.prepare(self.t, self.w, self.root))

    def test_rewrites_after_a_template_change(self):
        mission.prepare(self.t, self.w, self.root)
        make_zip(self.t, dict(self.entries, options="options = { changed = true }"))
        self.assertTrue(mission.prepare(self.t, self.w, self.root))
        self.assertIn("changed", read_member(self.w, "options"))

    def test_rewrites_for_another_checkout(self):
        mission.prepare(self.t, self.w, self.root)
        other = self.tmp / "other" / "dcs-hotload"
        other.mkdir(parents=True)
        self.assertTrue(mission.prepare(self.t, self.w, other))
        self.assertIn(other.resolve().as_posix(), read_member(self.w, "mission"))

    def test_path_with_spaces_and_accents(self):
        root = self.tmp / "Mes Projets é" / "dcs-hotload"
        root.mkdir(parents=True)
        mission.prepare(self.t, self.w, root)
        self.assertIn(root.resolve().as_posix(), read_member(self.w, "mission"))

    def test_refuses_a_template_without_two_placeholders(self):
        for count in (0, 1, 3):
            with self.subTest(count=count):
                bad = self.tmp / "bad.miz"
                make_zip(bad, {"mission": " ".join([P] * count), "options": ""})
                with self.assertRaises(mission.MissionError):
                    mission.prepare(bad, self.w, self.root)
                self.assertFalse(self.w.exists())


if __name__ == "__main__":
    unittest.main()
