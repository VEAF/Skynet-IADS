"""Tests for test/insim/run.py -- the one command. Build, Mailbox, Driver and the judge are fakes.

Run from anywhere:

    python -m unittest discover -s test/python -p "test_insim_*.py"
"""

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime
from pathlib import Path
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "test", "insim"))
import run  # noqa: E402
from engine.driver import Outcome  # noqa: E402

SCENARIO_LUA = 'return { mission = "m1", timeout = 5, tier = "minimal" }'


class FakeMailbox:
    created = []

    def __init__(self, root):
        self.root = root
        FakeMailbox.created.append(self)

    def ensure(self):
        pass


class FakeDriver:
    created = []
    current = True

    def __init__(self, mailbox, journal):
        self.keys = []
        FakeDriver.created.append(self)

    def wait_for_mission(self, hint):
        self.hint = hint
        return {"mission": "m1", "time": 1}

    def run(self, key, name_prefix, code, timeout):
        self.keys.append(key)
        if key.startswith("check/"):
            return Outcome("done", FakeDriver.current)
        return Outcome("done", {"key": key})


class RunTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        scenarios = self.repo / "test" / "insim" / "scenarios"
        for name in ("alpha", "beta"):
            folder = scenarios / name
            folder.mkdir(parents=True)
            (folder / "scenario.lua").write_text(SCENARIO_LUA, encoding="utf-8")
            for part in ("setup", "run", "verify"):
                (folder / (part + ".lua")).write_text("", encoding="utf-8")
        (self.repo / "test" / "insim" / "miz").mkdir(parents=True)
        FakeMailbox.created, FakeDriver.created, FakeDriver.current = [], [], True
        self.prepare_script = mock.Mock()
        self.prepare_mission = mock.Mock()
        for patch in (
            mock.patch.object(run, "Mailbox", FakeMailbox),
            mock.patch.object(run, "Driver", FakeDriver),
            mock.patch.object(run.skynet_script, "prepare", self.prepare_script),
            mock.patch.object(run.mission, "prepare", self.prepare_mission),
            mock.patch.object(run.verify, "judge", lambda lua, d, result, f: (True, "")),
        ):
            patch.start()
            self.addCleanup(patch.stop)
        (self.repo / "test" / "insim" / "miz" / "m1.template.miz").write_bytes(b"")

    def main(self, *argv, when=datetime(2026, 1, 2, 3, 4, 5)):
        out = io.StringIO()
        with redirect_stdout(out):
            code = run.main(["--lua", "lua"] + list(argv), repo=self.repo, now=lambda: when)
        return code, out.getvalue()

    def results(self):
        return sorted((self.repo / "build" / "insim" / "results").iterdir())

    def test_run_passes_and_writes_the_results_folder(self):
        code, out = self.main()
        self.assertEqual(code, 0)
        folder = self.results()[0]
        self.assertEqual(folder.name, "20260102-030405")
        self.assertEqual(json.loads((folder / "run.json").read_text()), {"tier": "minimal", "names": []})
        self.assertTrue((folder / "report.md").is_file())
        self.assertIn("alpha: pass", out)
        self.assertIn("beta: pass", out)
        self.prepare_script.assert_called_once_with(self.repo, None)

    def test_run_refuses_a_stale_mission(self):
        FakeDriver.current = False
        code, out = self.main()
        self.assertEqual(code, 2)
        self.assertIn("the mission runs an older Skynet script: restart the mission", out)
        keys = FakeDriver.created[0].keys
        self.assertEqual(len(keys), 1)
        self.assertTrue(keys[0].startswith("check/"))

    def test_run_resume_reuses_selection(self):
        self.main("alpha")
        code, out = self.main("--resume", "--tier", "full", "beta", when=datetime(2027, 1, 1))
        self.assertEqual(code, 0)
        self.assertEqual(len(self.results()), 1)
        keys = FakeDriver.created[1].keys
        self.assertTrue(all(k.startswith("check/") or k.startswith("alpha/") for k in keys), keys)
        self.assertNotEqual(FakeDriver.created[0].keys[0], keys[0])  # a resumed run asks again
        self.assertNotIn("beta", out)

    def test_run_verify_sends_nothing(self):
        self.main("alpha")
        FakeMailbox.created, FakeDriver.created = [], []
        self.prepare_script.reset_mock()
        with mock.patch.object(run.suite, "rejudge", return_value=[]) as rejudge:
            code, _ = self.main("--verify")
        self.assertEqual(code, 0)
        self.assertEqual(FakeMailbox.created, [])
        self.assertEqual(FakeDriver.created, [])
        self.prepare_script.assert_not_called()
        self.assertEqual([s.name for s in rejudge.call_args[0][1]], ["alpha"])

    def test_unknown_scenario_is_refused_before_anything_is_sent(self):
        code, out = self.main("nope")
        self.assertEqual(code, 2)
        self.assertIn("unknown scenario", out)
        self.assertEqual(FakeDriver.created, [])


if __name__ == "__main__":
    unittest.main()
