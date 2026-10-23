"""Tests for test/insim/engine/suite.py -- scenarios, the command chain, verdicts and the report.

The driver is a FakeDriver answering from a table; the judge is a fake. Nothing needs DCS.

Run from anywhere:

    python -m unittest discover -s test/python -p "test_insim_*.py"
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "test", "insim"))
from engine import luadata, suite  # noqa: E402
from engine.driver import Outcome  # noqa: E402

DONE = Outcome("done")


class FakeDriver:
    def __init__(self, table, journal=None, mission_time=0.0):
        self.table = table
        self.journal = journal or {}
        self.mission_time = mission_time
        self.keys = []
        self.calls = []

    def entry(self, key):
        return self.journal.get(key)

    def wait_for_mission(self, hint):
        return {"mission": "m1", "time": self.mission_time}

    def run(self, key, name_prefix, code, timeout):
        self.keys.append(key)
        self.calls.append((key, name_prefix, code, timeout))
        return self.table.get(key, DONE)


def judge_ok(scenario, result):
    return True, ""


def scenario(**kw):
    values = dict(name="s", tier="minimal", mission="m1", timeout=30, has_teardown=True)
    values.update(kw)
    return suite.Scenario(**values)


def run_with(table, judge=judge_ok, journal=None, mission_time=0.0, **kw):
    driver = FakeDriver(table, journal, mission_time)
    return suite.run_scenario(driver, judge, scenario(**kw), "m1"), driver


class ChainTest(unittest.TestCase):
    def test_pass_runs_the_whole_chain(self):
        v, driver = run_with({"s/run": Outcome("done", result={"n": 1})})
        self.assertEqual(driver.keys, ["s/setup", "s/run", "s/teardown", "s/cleanup"])
        self.assertEqual((v.verdict, v.result, v.warnings), ("pass", {"n": 1}, []))

    def test_commands(self):
        _, driver = run_with({})
        self.assertEqual(driver.calls[0], ("s/setup", "s-setup", 'return Hotload.load("insim").phase("s", "setup")', 30))
        self.assertEqual(driver.calls[3], ("s/cleanup", "s-cleanup", 'return Hotload.load("insim").cleanup("s")', 30))

    def test_no_teardown_file(self):
        _, driver = run_with({}, has_teardown=False)
        self.assertEqual(driver.keys, ["s/setup", "s/run", "s/cleanup"])

    def test_setup_failure_skips_run_but_cleans(self):
        v, driver = run_with({"s/setup": Outcome("fail", error="boom")})
        self.assertEqual(driver.keys, ["s/setup", "s/teardown", "s/cleanup"])
        self.assertEqual((v.verdict, v.message), ("fail", "boom"))

    def test_invalid_mark(self):
        v, _ = run_with({"s/setup": Outcome("fail", error="INSIM-INVALID: no SAM")})
        self.assertEqual((v.verdict, v.message), ("invalid", "no SAM"))

    def test_invalid_mark_from_run(self):
        v, _ = run_with({"s/run": Outcome("fail", error="INSIM-INVALID: no radar")})
        self.assertEqual((v.verdict, v.message), ("invalid", "no radar"))

    def test_refused_is_a_fail(self):
        v, _ = run_with({"s/run": Outcome("refused", error="busy")})
        self.assertEqual((v.verdict, v.message), ("fail", "busy"))

    def test_timeout_is_a_fail(self):
        v, _ = run_with({"s/run": Outcome("timeout", error="timed out after 30 s")})
        self.assertEqual((v.verdict, v.message), ("fail", "timed out after 30 s"))

    def test_stopped_by_hand_is_a_fail(self):
        v, _ = run_with({"s/run": Outcome("stopped")})
        self.assertEqual(v.verdict, "fail")

    def test_crash_stops_the_scenario(self):
        v, driver = run_with({"s/run": Outcome("crashed", error="the mission restarted")})
        self.assertEqual(driver.keys, ["s/setup", "s/run", "s/cleanup"])
        self.assertEqual((v.verdict, v.message), ("crashed", "the mission restarted during run"))

    def test_setup_crash_stops_at_setup(self):
        v, driver = run_with({"s/setup": Outcome("crashed", error="DCS went down")})
        self.assertEqual(driver.keys, ["s/setup", "s/cleanup"])
        self.assertEqual((v.verdict, v.message), ("crashed", "DCS went down during setup"))

    def test_teardown_crash_stops_at_teardown(self):
        v, driver = run_with({"s/teardown": Outcome("crashed", error="DCS went down")})
        self.assertEqual(driver.keys, ["s/setup", "s/run", "s/teardown", "s/cleanup"])
        self.assertEqual((v.verdict, v.message), ("crashed", "DCS went down during teardown"))

    def test_cleanup_crash_is_crashed(self):
        v, driver = run_with({"s/cleanup": Outcome("crashed", error="DCS went down")})
        self.assertEqual(driver.keys, ["s/setup", "s/run", "s/teardown", "s/cleanup"])
        self.assertEqual((v.verdict, v.message), ("crashed", "DCS went down during cleanup"))

    def test_crash_sends_only_cleanup_afterwards(self):
        _, driver = run_with({"s/run": Outcome("crashed", error="x")})
        self.assertEqual(driver.calls[-1][2], 'return Hotload.load("insim").cleanup("s")')

    def test_judge_is_not_called_after_a_crash_or_a_failed_phase(self):
        for table in (
            {"s/setup": Outcome("crashed")},
            {"s/run": Outcome("crashed")},
            {"s/teardown": Outcome("crashed")},
            {"s/cleanup": Outcome("crashed")},
            {"s/setup": Outcome("fail", error="x")},
            {"s/run": Outcome("timeout", error="x")},
        ):
            called = []
            run_with(table, judge=lambda s, r: called.append(1) or (True, ""))
            self.assertEqual(called, [], table)

    def test_cleanup_failure_warns(self):
        v, _ = run_with({"s/cleanup": Outcome("fail", error="nope")})
        self.assertEqual(v.verdict, "pass")
        self.assertEqual(v.warnings, ["cleanup failed: nope — the next scenario may start from a dirty world"])

    def test_teardown_failure_warns(self):
        v, _ = run_with({"s/teardown": Outcome("fail", error="nope")})
        self.assertEqual(v.warnings, ["teardown failed: nope — the next scenario may start from a dirty world"])

    def test_other_mission_is_skipped(self):
        driver = FakeDriver({})
        v = suite.run_scenario(driver, judge_ok, scenario(mission="m2"), "m1")
        self.assertEqual((v.verdict, v.message, driver.keys), ("skipped", "needs m2", []))

    def test_verify_failure_is_a_fail(self):
        v, _ = run_with({"s/run": Outcome("done", result=2)}, judge=lambda s, r: (False, "expected: 1, actual: 2"))
        self.assertEqual((v.verdict, v.message, v.result), ("fail", "expected: 1, actual: 2", 2))


class ResumeTest(unittest.TestCase):
    """A scenario resumed from the journal: mission-side state survives only within one mission instance."""

    JOURNAL = {"s/setup": {"key": "s/setup", "name": "s-setup-1", "sent_at": 38.1, "state": "ended"}}

    def test_mission_restarted_since_the_last_phase_is_crashed(self):
        v, driver = run_with({}, journal=self.JOURNAL, mission_time=12.1)
        self.assertEqual(driver.keys, ["s/cleanup"])
        self.assertEqual((v.verdict, v.message), ("crashed", "DCS went down after setup"))

    def test_mission_not_restarted_continues_the_chain(self):
        v, driver = run_with({}, journal=self.JOURNAL, mission_time=50)
        self.assertEqual(driver.keys, ["s/setup", "s/run", "s/teardown", "s/cleanup"])
        self.assertEqual(v.verdict, "pass")

    def test_nothing_journaled_or_cleanup_ended_is_unaffected(self):
        journal = dict(self.JOURNAL)
        journal["s/cleanup"] = {"key": "s/cleanup", "name": "s-cleanup-1", "sent_at": 40.0, "state": "ended"}
        _, driver = run_with({}, journal=journal, mission_time=1)
        self.assertEqual(driver.keys, ["s/setup", "s/run", "s/teardown", "s/cleanup"])


class FolderTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name)

    def make(self, name, meta='tier = "minimal", mission = "m1", timeout = 30', files=("setup", "run", "verify")):
        d = self.folder / name
        d.mkdir()
        (d / "scenario.lua").write_text("return { %s }\n" % meta, encoding="utf-8")
        for f in files:
            (d / (f + ".lua")).write_text("return 1\n", encoding="utf-8")

    def test_discover(self):
        self.make("b", files=("setup", "run", "verify", "teardown"))
        self.make("a", meta='mission = "m2", timeout = 5')
        found = suite.discover(self.folder)
        self.assertEqual([s.name for s in found], ["a", "b"])
        self.assertEqual(found[0], suite.Scenario("a", None, "m2", 5, False))
        self.assertEqual(found[1], suite.Scenario("b", "minimal", "m1", 30, True))

    def test_folder_without_run_is_refused(self):
        self.make("a", files=("setup", "verify"))
        with self.assertRaisesRegex(suite.SuiteError, "a.*run.lua"):
            suite.discover(self.folder)

    def test_scenario_without_timeout_is_refused(self):
        self.make("a", meta='mission = "m1"')
        with self.assertRaisesRegex(suite.SuiteError, "a.*timeout"):
            suite.discover(self.folder)

    def test_scenario_without_mission_is_refused(self):
        self.make("a", meta="timeout = 3")
        with self.assertRaisesRegex(suite.SuiteError, "a.*mission"):
            suite.discover(self.folder)

    def test_block_comment_in_scenario_lua_is_a_suite_error_naming_the_file(self):
        self.make("a")
        (self.folder / "a" / "scenario.lua").write_text('--[[\nnote\n]]\nreturn { mission = "m1", timeout = 3 }\n', encoding="utf-8")
        with self.assertRaisesRegex(suite.SuiteError, "a.*scenario.lua"):
            suite.discover(self.folder)

    def test_plain_files_are_ignored(self):
        self.make("a")
        (self.folder / "README.md").write_text("x", encoding="utf-8")
        self.assertEqual([s.name for s in suite.discover(self.folder)], ["a"])


class SelectTest(unittest.TestCase):
    def setUp(self):
        self.all = [scenario(name="a", tier="minimal"), scenario(name="b", tier="full"), scenario(name="c", tier=None)]

    def names(self, tier, names):
        return [s.name for s in suite.select(self.all, tier, names)]

    def test_select_by_tier_and_name(self):
        self.assertEqual(self.names("minimal", []), ["a"])
        self.assertEqual(self.names("full", []), ["a", "b"])
        self.assertEqual(self.names("minimal", ["c", "b"]), ["c", "b"])

    def test_unknown_name_is_refused(self):
        with self.assertRaisesRegex(suite.SuiteError, "nope"):
            self.names("minimal", ["a", "nope"])


class ReportTest(unittest.TestCase):
    def verdicts(self):
        return [
            suite.Verdict("a", "pass", "", 1, []),
            suite.Verdict("b", "fail", "bad | thing", None, ["w"]),
            suite.Verdict("c", "skipped", "needs m2", None, []),
        ]

    def test_exit_code(self):
        v = self.verdicts()
        self.assertEqual(suite.exit_code([v[0], v[2]]), 0)
        self.assertEqual(suite.exit_code(v), 1)
        for bad in ("invalid", "crashed"):
            self.assertEqual(suite.exit_code([suite.Verdict("x", bad, "", None, [])]), 1)

    def test_summary(self):
        text = suite.summary(self.verdicts())
        self.assertIn("a: pass", text)
        self.assertIn("b: fail - bad | thing", text)
        self.assertIn("1 pass, 1 fail, 0 invalid, 0 crashed, 1 skipped", text)

    def test_write_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "r.md"
            suite.write_report(self.verdicts(), path)
            lines = path.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0], "| name | verdict | message | result | warnings |")
        self.assertIn("| b | fail | bad \\| thing |  | w |", lines)


class RejudgeTest(unittest.TestCase):
    def test_rejudge_uses_recorded_results(self):
        with tempfile.TemporaryDirectory() as tmp:
            journal = Path(tmp) / "j.jsonl"
            entries = [
                {"key": "a/setup", "state": "ended", "outcome": {"status": "done"}},
                {"key": "a/run", "state": "ended", "outcome": {"status": "done", "result": luadata.dump({"n": 2, 1: 5})}},
                {"key": "b/setup", "state": "ended", "outcome": {"status": "fail", "error": "boom"}},
                {"key": "c/setup", "state": "sent", "name": "c-setup-1", "sent_at": 1},
            ]
            journal.write_text("".join(json.dumps(e) + "\n" for e in entries), encoding="utf-8")
            seen = []

            def judge(s, result):
                seen.append((s.name, result))
                return False, "expected: 1, actual: 2"

            scenarios = [scenario(name=n) for n in "abcd"]
            verdicts = suite.rejudge(journal, scenarios, judge)
        self.assertEqual(seen, [("a", {"n": 2, 1: 5})])
        self.assertEqual([(v.name, v.verdict, v.message) for v in verdicts], [("a", "fail", "expected: 1, actual: 2"), ("b", "fail", "boom")])

    def journal_of(self, tmp, entries):
        journal = Path(tmp) / "j.jsonl"
        journal.write_text("".join(json.dumps(e) + "\n" for e in entries), encoding="utf-8")
        return journal

    def test_rejudge_keeps_a_crash_from_any_phase(self):
        for phase in ("setup", "run", "teardown", "cleanup"):
            entries = [
                {"key": "a/setup", "state": "ended", "outcome": {"status": "done"}},
                {"key": "a/run", "state": "ended", "outcome": {"status": "done", "result": "return 1\n"}},
                {"key": "a/" + phase, "state": "ended", "outcome": {"status": "crashed", "error": "gone"}},
            ]
            with tempfile.TemporaryDirectory() as tmp:
                verdicts = suite.rejudge(self.journal_of(tmp, entries), [scenario(name="a")], judge_ok)
            self.assertEqual([(v.verdict, v.message) for v in verdicts], [("crashed", "gone during " + phase)], phase)

    def test_rejudge_keeps_teardown_and_cleanup_warnings(self):
        entries = [
            {"key": "a/setup", "state": "ended", "outcome": {"status": "done"}},
            {"key": "a/run", "state": "ended", "outcome": {"status": "done", "result": "return 1\n"}},
            {"key": "a/teardown", "state": "ended", "outcome": {"status": "fail", "error": "t"}},
            {"key": "a/cleanup", "state": "ended", "outcome": {"status": "fail", "error": "c"}},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            verdicts = suite.rejudge(self.journal_of(tmp, entries), [scenario(name="a")], judge_ok)
        self.assertEqual([w.split(" failed")[0] for w in verdicts[0].warnings], ["teardown", "cleanup"])

    def test_rejudge_omits_a_scenario_whose_run_has_not_ended(self):
        with tempfile.TemporaryDirectory() as tmp:
            journal = Path(tmp) / "j.jsonl"
            entries = [
                {"key": "a/setup", "state": "ended", "outcome": {"status": "done"}},
                {"key": "a/run", "state": "sent", "name": "a-run-1", "sent_at": 1},
                {"key": "b/setup", "state": "ended", "outcome": {"status": "done"}},
            ]
            journal.write_text("".join(json.dumps(e) + "\n" for e in entries), encoding="utf-8")
            self.assertEqual(suite.rejudge(journal, [scenario(name="a"), scenario(name="b")], judge_ok), [])

    def test_rejudge_without_a_journal(self):
        self.assertEqual(suite.rejudge(Path("nowhere.jsonl"), [scenario()], judge_ok), [])


if __name__ == "__main__":
    unittest.main()
