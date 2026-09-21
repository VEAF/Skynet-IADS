"""Tests for build-tools/run-smoke.py -- the runner's own logic, never a real DCS.

Run from anywhere:

    python -m unittest discover -s test/python

There is no simulator here and there never will be, so what is testable is everything around the
simulator: how a reply is read, when a check is skipped, how a polled check reaches a verdict, and
-- the one that earns its place -- that no expectation can be satisfied by a value the transport
destroyed. CTLD's runner has the same shape of test for the same reason: the runner is the piece
that decides what a release is told, so a defect in it is a defect in every check at once.
"""

import importlib.util
import io
import json
import os
import sys
import unittest
import urllib.error
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_spec = importlib.util.spec_from_file_location("run_smoke", os.path.join(ROOT, "build-tools", "run-smoke.py"))
rs = importlib.util.module_from_spec(_spec)
# Registered before executing, because `@dataclass` resolves its annotations through
# `sys.modules[cls.__module__]`. A module loaded by spec alone is not there, and the decorator dies
# on a None lookup -- which looks like a defect in run-smoke.py and is not.
sys.modules["run_smoke"] = rs
_spec.loader.exec_module(rs)


class FakeBridge:
    """Answers a scripted sequence, and records what it was asked."""

    def __init__(self, replies):
        self.replies = list(replies)
        self.sent = []

    def exec_lua(self, code):
        self.sent.append(code)
        reply = self.replies.pop(0) if self.replies else self.replies
        if isinstance(reply, Exception):
            raise reply
        return reply


def _check(**kwargs):
    defaults = dict(
        name="probe",
        target="demo",
        tier="fast",
        lua="return 'x'",
        expect=lambda v: v == "ok",
        why="because",
    )
    defaults.update(kwargs)
    return rs.Check(**defaults)


class ExpectationsTest(unittest.TestCase):
    """The sweep VMCT paid for, applied to our own checks."""

    def test_no_expectation_is_satisfied_by_a_lost_reply(self):
        # A boolean `false` and a table both arrive as '' through dcs-bridge.lua's handleExec. An
        # expectation that '' can satisfy would go green on a reply that proves nothing ran.
        for check in rs.CHECKS:
            for lost in rs.TRANSPORT_LOSS:
                with self.subTest(check=check.name, reply=repr(lost)):
                    self.assertFalse(check.expect(lost))

    def test_no_expectation_is_satisfied_by_a_lua_error(self):
        # The bridge separates errors properly, but a check that pcalls its own body returns the
        # message as an ordinary answer. `_pcall` prefixes it `raised:` for exactly this.
        for check in rs.CHECKS:
            for error in ("raised: attempt to index a nil value", "[string \"x\"]:1: bad argument"):
                with self.subTest(check=check.name, reply=error):
                    self.assertFalse(check.expect(error))

    def test_every_check_returns_something(self):
        for check in rs.CHECKS:
            with self.subTest(check=check.name):
                self.assertIn("return", check.lua)
                self.assertIn(check.target, rs.TARGETS)
                self.assertIn(check.tier, ("fast", "slow"))
                self.assertTrue(check.why.strip(), "a check has to say what it is for")

    def test_targets_name_the_built_mission_not_the_committed_archive(self):
        # The committed archives hold placeholders. Naming one here sends somebody to open a mission
        # that says "unbuilt" on screen, and then to wonder why every check failed. The README said
        # build/missions/ and --list said otherwise; the tool is the one people read.
        for name, path in rs.TARGETS.items():
            with self.subTest(target=name):
                self.assertTrue(path.startswith("build/missions/"), path)

    def test_check_names_are_unique(self):
        names = [c.name for c in rs.CHECKS]
        self.assertEqual(len(names), len(set(names)))


class NamedChecksTest(unittest.TestCase):
    """A couple of expectations pinned by example, so a rewrite of the Lua cannot drift silently."""

    def _expect(self, name):
        return next(c.expect for c in rs.CHECKS if c.name == name)

    def test_artifact_loaded_wants_a_version_shaped_answer(self):
        expect = self._expect("artifact-loaded")
        self.assertTrue(expect("3.5.0"))
        self.assertTrue(expect("3.5.0-develop"))
        self.assertFalse(expect("skynet-absent"))
        self.assertFalse(expect("nil"))
        self.assertFalse(expect("table: 0x00a1b2c3"))

    def test_networks_built_wants_the_counts_a_real_run_measured(self):
        expect = self._expect("networks-built")
        self.assertTrue(expect("sam:13 ewr:8"))
        # a partial discovery is the failure that matters, and "non-zero" would have passed it
        self.assertFalse(expect("sam:1 ewr:8"))
        self.assertFalse(expect("sam:13 ewr:1"))
        self.assertFalse(expect("sam:0 ewr:0"))
        self.assertFalse(expect("no-red-iads"))

    def test_jammer_alive_separates_gone_from_dead(self):
        expect = self._expect("jammer-alive")
        self.assertTrue(expect("alive"))
        self.assertFalse(expect("emitter-gone"))
        self.assertFalse(expect("emitter-dead"))

    def test_no_mist_wants_the_word_nil(self):
        expect = self._expect("no-mist")
        self.assertTrue(expect("nil"))
        self.assertFalse(expect("table"))


class SelectTest(unittest.TestCase):
    def test_target_filters(self):
        self.assertTrue(all(c.target == "demo" for c in rs.select("demo", "all", None)))
        self.assertTrue(all(c.target == "lastline" for c in rs.select("lastline", "all", None)))

    def test_tier_defaults_exclude_the_slow_ones(self):
        self.assertTrue(all(c.tier == "fast" for c in rs.select(None, "fast", None)))
        self.assertTrue(rs.select(None, "slow", None), "there is at least one slow check")

    def test_all_keeps_every_tier(self):
        self.assertEqual(len(rs.select(None, "all", None)), len(rs.CHECKS))

    def test_only_picks_by_name(self):
        chosen = rs.select(None, "all", ["jammer-alive"])
        self.assertEqual([c.name for c in chosen], ["jammer-alive"])

    def test_an_unknown_name_selects_nothing(self):
        self.assertEqual(rs.select(None, "all", ["nope"]), [])


class RunCheckTest(unittest.TestCase):
    def setUp(self):
        self.slept = []

    def sleep(self, seconds):
        self.slept.append(seconds)

    def test_a_passing_check_is_not_polled(self):
        bridge = FakeBridge(["ok"])
        outcome = rs.run_check(bridge, _check(), 60, self.sleep)
        self.assertTrue(outcome.passed)
        self.assertEqual(outcome.verdict, "ok")
        self.assertEqual(self.slept, [])

    def test_a_failing_verdict_is_reported_as_it_came(self):
        bridge = FakeBridge(["emitter-gone"])
        outcome = rs.run_check(bridge, _check(), 60, self.sleep)
        self.assertFalse(outcome.passed)
        self.assertEqual(outcome.verdict, "emitter-gone")

    def test_a_polled_check_waits_for_a_terminal_verdict(self):
        bridge = FakeBridge(["RUNNING", "RUNNING", "PASS"])
        check = _check(poll=True, expect=lambda v: v == "PASS")
        outcome = rs.run_check(bridge, check, 60, self.sleep)
        self.assertTrue(outcome.passed)
        self.assertEqual(len(self.slept), 2)

    def test_a_polled_check_gives_up_at_the_timeout(self):
        bridge = FakeBridge(["RUNNING"] * 20)
        check = _check(poll=True, expect=lambda v: v == "PASS")
        outcome = rs.run_check(bridge, check, 10, self.sleep)
        self.assertFalse(outcome.passed)
        self.assertIn("still RUNNING", outcome.detail)

    def test_an_empty_reply_aborts_rather_than_failing(self):
        # The distinction matters: "failed" sends somebody hunting a defect in Skynet, when what
        # happened is that the check returned a boolean and the transport ate it.
        bridge = FakeBridge([""])
        outcome = rs.run_check(bridge, _check(), 60, self.sleep)
        self.assertFalse(outcome.passed)
        self.assertEqual(outcome.verdict, "ABORT")
        self.assertIn("must return a word", outcome.detail)

    def test_arming_runs_once_and_before_the_poll(self):
        bridge = FakeBridge(["armed", "PASS"])
        check = _check(arm="return SKYNET_TEST.launchIntruder()", poll=True, expect=lambda v: v == "PASS")
        rs.run_check(bridge, check, 60, self.sleep)
        self.assertEqual(len(bridge.sent), 2)
        self.assertIn("launchIntruder", bridge.sent[0])

    def test_a_failure_to_arm_aborts_without_polling(self):
        bridge = FakeBridge([RuntimeError("no such function")])
        check = _check(arm="return nope()", poll=True)
        outcome = rs.run_check(bridge, check, 60, self.sleep)
        self.assertEqual(outcome.verdict, "ABORT")
        self.assertIn("arming failed", outcome.detail)


class BridgeTest(unittest.TestCase):
    """The reply shapes, including the one that lies."""

    class _Response(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

    def _answering(self, payload=None, error=None):
        """Patch urlopen for the duration of a `with`, so no test leaks into the next."""

        def fake_urlopen(request, timeout=None):
            if error:
                raise error
            return self._Response(json.dumps(payload).encode())

        return mock.patch.object(rs.urllib.request, "urlopen", fake_urlopen)

    def test_a_lua_error_arrives_as_http_200_and_must_raise(self):
        # This is the whole reason the runner reads the body rather than the status code. VMCT's
        # harness went green on an error message because the transport handed it over as an answer.
        with self._answering({"error": '[string "x"]:1: attempt to index nil'}):
            with self.assertRaises(RuntimeError):
                rs.Bridge("http://x", "tok").exec_lua("return 1")

    def test_a_result_comes_back_as_a_string(self):
        with self._answering({"result": "alive"}):
            self.assertEqual(rs.Bridge("http://x", "tok").exec_lua("return 1"), "alive")

    def test_ready_false_is_a_skip_not_a_failure(self):
        with self._answering({"ready": False}):
            with self.assertRaises(rs.NotReady):
                rs.Bridge("http://x", "tok").exec_lua("return 1")

    def test_503_is_a_skip(self):
        with self._answering(error=urllib.error.HTTPError("u", 503, "x", {}, None)):
            with self.assertRaises(rs.NotReady):
                rs.Bridge("http://x", "tok").exec_lua("return 1")

    def test_403_says_the_token_lacks_superuser(self):
        with self._answering(error=urllib.error.HTTPError("u", 403, "x", {}, None)):
            with self.assertRaises(rs.BridgeRefused) as caught:
                rs.Bridge("http://x", "tok").exec_lua("return 1")
        self.assertIn("superuser", str(caught.exception))

    def test_an_unreachable_server_is_a_skip(self):
        with self._answering(error=urllib.error.URLError("refused")):
            with self.assertRaises(rs.NotReady):
                rs.Bridge("http://x", "tok").exec_lua("return 1")


class TokenTest(unittest.TestCase):
    def test_the_flag_wins(self):
        self.assertEqual(rs.find_token("explicit"), "explicit")

    def test_the_environment_is_next(self):
        os.environ["DCS_BRIDGE_API_KEY"] = "from-env"
        try:
            self.assertEqual(rs.find_token(None), "from-env")
        finally:
            del os.environ["DCS_BRIDGE_API_KEY"]

    def test_an_empty_flag_does_not_override_the_other_sources(self):
        os.environ["DCS_BRIDGE_API_KEY"] = "from-env"
        try:
            self.assertEqual(rs.find_token(""), "from-env")
        finally:
            del os.environ["DCS_BRIDGE_API_KEY"]

    def test_no_token_anywhere_stops_before_the_first_request(self):
        # Without this, the run reaches dcs-serve with an empty bearer and comes back 403, whose
        # message blames the superuser role -- when the truth is that nothing was sent.
        with mock.patch.object(rs, "find_token", lambda _: ""):
            with mock.patch("sys.stdout", io.StringIO()) as out:
                self.assertEqual(rs.main(["--target", "demo"]), 2)
        self.assertIn("no token", out.getvalue())


class ReportTest(unittest.TestCase):
    def test_all_passing_exits_zero(self):
        out = io.StringIO()
        outcomes = [rs.Outcome(_check(), "ok", True)]
        self.assertEqual(rs.report(outcomes, out), 0)

    def test_one_failure_exits_one_and_prints_the_why(self):
        out = io.StringIO()
        outcomes = [rs.Outcome(_check(why="the jammer must survive"), "emitter-gone", False)]
        self.assertEqual(rs.report(outcomes, out), 1)
        self.assertIn("the jammer must survive", out.getvalue())

    def test_nothing_selected_is_not_a_failure(self):
        self.assertEqual(rs.report([], io.StringIO()), 0)


if __name__ == "__main__":
    unittest.main()
