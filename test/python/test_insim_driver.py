"""Tests for test/insim/engine/driver.py -- sends mailbox commands, waits, resumes, stops a hung one.

The mission is a FakeMission with a fake clock: no test sleeps for real.

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
from engine import driver, mailbox  # noqa: E402


class FakeMission:
    """The Mailbox interface in memory, plus a sim clock and a few scripted commands."""

    def __init__(self):
        self.real = 0.0
        self.sim = 5.0
        self.resume_at = 0.0
        self.pause_on_pick = 0.0
        self.on_hang = None
        self.inbox = {}
        self.outbox = {}
        self.active = {}  # run name -> sim time it finishes at, or None for a hung one
        self.sent_codes = []
        self.sent_names = []

    # the Mailbox interface
    def ensure(self):
        pass

    def send(self, name, code):
        self.inbox[name] = code
        self.sent_codes.append(code)
        self.sent_names.append(name)

    def outcome(self, name):
        record = self.outbox.get(name)
        return dict(record) if record else None

    def clear(self, name):
        self.inbox.pop(name, None)
        self.outbox.pop(name, None)

    def clear_prefixes(self, prefixes):
        for name in [n for n in list(self.inbox) + list(self.outbox) if n.startswith(tuple(prefixes))]:
            self.clear(name)

    # the fake world
    @property
    def paused(self):
        return self.real < self.resume_at

    def pause_for(self, real_seconds):
        self.resume_at = self.real + real_seconds

    def restart(self, sim=0.0):
        self.sim = sim
        self.active = {}

    def clock(self):
        return self.real

    def sleep(self, seconds):
        self.real += seconds
        if not self.paused:
            self.sim += seconds
        self.tick()

    def tick(self):
        if self.paused:
            return
        for name, finish in list(self.active.items()):
            if finish is not None and self.sim >= finish:
                del self.active[name]
                self.outbox[name].update(status="done", finished=self.sim, duration=finish - self.outbox[name]["started"])
        for name, code in list(self.inbox.items()):
            if name not in self.outbox:
                self.pick(name, code)

    def pick(self, name, code):
        label = "inbox/" + name
        if code == "LOST":
            return  # the command is never picked up
        if name.startswith("probe-"):
            self.outbox[name] = {"label": label, "status": "done", "result": {"mission": "m", "time": self.sim}}
        elif code.startswith("return Hotload.stop("):
            target = code.split('"')[1][len("inbox/") :]
            alive = target in self.active
            if alive:
                del self.active[target]
                self.outbox[target].update(status="stopped", finished=self.sim)
            self.outbox[name] = {"label": label, "status": "done", "result": alive}
        else:
            self.outbox[name] = {"label": label, "status": "started", "started": self.sim}
            if code == "return 1":
                self.outbox[name].update(status="done", result=1, finished=self.sim, duration=0)
            elif code == "boom":
                self.outbox[name].update(status="fail", error="boom", finished=self.sim, duration=0)
            elif code == "HANG":
                self.active[name] = None
                if self.on_hang:
                    self.on_hang()
            elif code == "TAKES_20_SIM_S":
                self.active[name] = self.sim + 20
                if self.pause_on_pick:
                    self.pause_for(self.pause_on_pick)


class DriverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.journal = Path(self.tmp.name) / "journal.jsonl"
        self.fake = FakeMission()
        self.said = []
        self.d = self.make()

    def make(self):
        return driver.Driver(self.fake, self.journal, clock=self.fake.clock, sleep=self.fake.sleep, say=self.said.append)

    def test_done_command(self):
        o = self.d.run("a/setup", "a-setup", "return 1", 60)
        self.assertEqual((o.status, o.result), ("done", 1))

    def test_fail_carries_the_error(self):
        o = self.d.run("a/setup", "a-setup", "boom", 60)
        self.assertEqual((o.status, o.error), ("fail", "boom"))

    def test_files_are_cleared_after_the_run(self):
        self.d.run("a/setup", "a-setup", "return 1", 60)
        self.assertEqual((self.fake.inbox, self.fake.outbox), ({}, {}))

    def test_hung_command_is_stopped_on_sim_time(self):
        o = self.d.run("a/run", "a-run", "HANG", 30)
        self.assertEqual(o.status, "timeout")
        self.assertIn("timed out after 30 s", o.error)
        self.assertTrue(any('Hotload.stop("inbox/a-run-' in c for c in self.fake.sent_codes))

    def test_pause_is_neither_timeout_nor_crash(self):
        self.fake.pause_on_pick = 120
        o = self.d.run("a/run", "a-run", "TAKES_20_SIM_S", 30)
        self.assertEqual(o.status, "done")
        self.assertEqual(self.said.count(driver.SILENCE), 1)

    def test_mission_restart_is_a_crash(self):
        self.fake.on_hang = self.fake.restart
        o = self.d.run("a/run", "a-run", "HANG", 30)
        self.assertEqual(o.status, "crashed")

    def test_unseen_restart_is_a_crash_at_timeout(self):
        self.fake.on_hang = lambda: self.fake.restart(sim=1000)
        o = self.d.run("a/run", "a-run", "HANG", 30)
        self.assertEqual(o.status, "crashed")

    def test_command_never_picked_up_fails_instead_of_waiting_forever(self):
        o = self.d.run("a/run", "a-run", "LOST", 30)
        self.assertEqual(o.status, "fail")
        self.assertEqual(o.error, "never picked up by the mission (no readable outbox after 30 s)")
        self.assertTrue(any('Hotload.stop("inbox/a-run-' in c for c in self.fake.sent_codes))

    def test_journal_keeps_the_result_as_the_live_run_saw_it(self):
        result = {1: 1, 3: 3, "x": 2}
        self.fake.pick = lambda name, code: self.fake.outbox.update(
            {name: {"label": "inbox/" + name, "status": "done", "result": result, "started": 0, "duration": 0}}
        ) if not name.startswith("probe-") else FakeMission.pick(self.fake, name, code)
        live = self.d.run("a/run", "a-run", "x", 30)
        again = self.make().run("a/run", "a-run", "x", 30)
        self.assertEqual(live.result, result)
        self.assertEqual(again, live)
        self.assertEqual(driver.read_outcome(driver.read_journal(self.journal)["a/run"]).result, result)

    def test_resume_returns_recorded_outcome_without_sending(self):
        first = self.d.run("a/setup", "a-setup", "return 1", 60)
        sent = len(self.fake.sent_names)
        again = self.make().run("a/setup", "a-setup", "return 2", 60)
        self.assertEqual(again, first)
        self.assertEqual(len(self.fake.sent_names), sent)

    def test_resume_in_flight_waits_on_the_same_name(self):
        self.journal.write_text(json.dumps({"key": "a/run", "name": "a-run-1", "sent_at": 5.0, "state": "sent"}) + "\n")
        self.fake.inbox["a-run-1"] = "TAKES_20_SIM_S"
        self.fake.outbox["a-run-1"] = {"label": "inbox/a-run-1", "status": "started", "started": 5.0}
        self.fake.active["a-run-1"] = 25.0
        o = self.make().run("a/run", "a-run", "TAKES_20_SIM_S", 60)
        self.assertEqual(o.status, "done")
        self.assertEqual([n for n in self.fake.sent_names if not n.startswith("probe-")], [])

    def test_leftover_probe_and_stop_files_are_cleared(self):
        root = Path(self.tmp.name) / "mb"
        box = mailbox.Mailbox(root)
        box.ensure()
        for name in ("probe-1", "stop-2", "a-run-3"):
            box.send(name, "x")
            (root / "user-outbox" / (name + ".lua")).write_text("return {}")
        driver.Driver(box, self.journal)
        self.assertEqual(os.listdir(root / "user-inbox"), ["a-run-3.lua"])
        self.assertEqual(os.listdir(root / "user-outbox"), ["a-run-3.lua"])

    def test_status_none_when_unanswered_and_probe_cleared(self):
        self.fake.pause_for(1000)
        self.assertIsNone(self.d.status(patience=10))
        self.assertEqual((self.fake.inbox, self.fake.outbox), ({}, {}))

    def test_wait_for_mission_says_hint_once(self):
        self.fake.pause_for(30)
        self.assertEqual(self.d.wait_for_mission("run the mission")["mission"], "m")
        self.assertEqual(self.said, ["run the mission"])


if __name__ == "__main__":
    unittest.main()
