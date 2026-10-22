"""Sends one mailbox command, waits for its outcome, and tells a pause from a crash.

The driver is keyed and journalled so a run resumes: a key whose outcome is journalled is not sent
again, and a key sent but not ended is waited on under the same name. Waiting watches the sim clock
through a probe command: it freezes when DCS is paused, and restarts from 0 with the mission.
"""

import json
import time
from dataclasses import dataclass
from pathlib import Path

__all__ = ["Outcome", "Driver", "SILENCE", "read_journal"]

SILENCE = "no answer from the mission: paused, or DCS is down — restart the mission to resume"
POLL = 2.0  # seconds between two looks at a command's outbox
PROBE_POLL = 1.0  # hotload polls its inbox every second
PROBE_REPLACED_AFTER = 6.0  # a probe left unanswered this long (real seconds) is replaced by a fresh one
FINAL = ("done", "fail", "stopped", "refused")


@dataclass
class Outcome:
    status: str  # done, fail, stopped, refused, timeout, crashed
    result: object = None
    error: str = None
    duration: float = None


def _unique():
    return format(time.time_ns(), "x")


def read_journal(path):
    """The journal's entries by key, each key's last one; a missing file is an empty journal."""
    path = Path(path)
    entries = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            try:
                entry = json.loads(line)
            except ValueError:
                continue  # a torn last line from a killed driver
            entries[entry["key"]] = entry
    return entries


class Driver:
    def __init__(self, mailbox, journal, probe_code='return Hotload.load("insim").status()', clock=time.monotonic, sleep=time.sleep, say=print):
        self.mailbox = mailbox
        self.journal = Path(journal)
        self.probe_code = probe_code
        self.clock = clock
        self.sleep = sleep
        self.say = say
        mailbox.clear_prefixes(["probe-", "stop-"])

    def status(self, patience=10.0):
        """The probe's `{mission, time}`, or None when it has not answered within `patience` real seconds."""
        name = "probe-" + _unique()
        self.mailbox.send(name, self.probe_code)
        deadline = self.clock() + patience
        try:
            while True:
                answer = self._answer(name)
                if answer is not None or self.clock() >= deadline:
                    return answer
                self.sleep(PROBE_POLL)
        finally:
            self.mailbox.clear(name)

    def wait_for_mission(self, hint):
        said = False
        while True:
            answer = self.status()
            if answer is not None:
                return answer
            if not said:
                self.say(hint)
                said = True

    def run(self, key, name_prefix, code, timeout):
        entry = read_journal(self.journal).get(key)
        if entry and entry.get("state") == "ended":
            return Outcome(**entry["outcome"])
        if entry:
            name, sent_at = entry["name"], entry["sent_at"]
        else:
            sent_at = self.wait_for_mission(SILENCE)["time"]
            name = "%s-%s" % (name_prefix, _unique())
            self._append({"key": key, "name": name, "sent_at": sent_at, "state": "sent"})
            self.mailbox.send(name, code)
        outcome = self._wait(name, sent_at, timeout)
        self._append({"key": key, "state": "ended", "outcome": outcome.__dict__})
        self.mailbox.clear(name)
        return outcome

    def _wait(self, name, sent_at, timeout):
        mailbox = self.mailbox
        probe = None  # [name, sent at (real)] of the probe in flight
        stop = None  # name of the stop command, once sent
        now_sim = None  # the latest sim time a probe reported
        last_answer = self.clock()
        silent = False
        try:
            while True:
                record = mailbox.outcome(name)
                if record and record.get("status") in FINAL:
                    return self._final(record, stop is not None, timeout)
                if stop is not None:
                    stopped = mailbox.outcome(stop)
                    if stopped and stopped.get("status") == "done" and stopped.get("result") is False:
                        record = mailbox.outcome(name)
                        if record and record.get("status") in FINAL:
                            return self._final(record, True, timeout)
                        return Outcome("crashed", error="the run no longer exists: the mission restarted")
                if probe is not None:
                    answer = self._answer(probe[0])
                    if answer is not None:
                        mailbox.clear(probe[0])
                        probe = None
                        last_answer, silent = self.clock(), False
                        now_sim = answer["time"]
                        if now_sim < sent_at:
                            return Outcome("crashed", error="the mission restarted")
                    elif self.clock() - probe[1] > PROBE_REPLACED_AFTER:
                        mailbox.clear(probe[0])
                        probe = None
                if probe is None:
                    probe = ["probe-" + _unique(), self.clock()]
                    mailbox.send(probe[0], self.probe_code)
                if not silent and self.clock() - last_answer > 10.0:
                    silent = True
                    self.say(SILENCE)
                if stop is None and now_sim is not None and record and record.get("status") == "started":
                    if now_sim - record["started"] > timeout:
                        stop = "stop-" + _unique()
                        mailbox.send(stop, 'return Hotload.stop("inbox/%s")' % name)
                self.sleep(POLL)
        finally:
            if probe is not None:
                mailbox.clear(probe[0])
            if stop is not None:
                mailbox.clear(stop)

    def _final(self, record, stop_sent, timeout):
        if record["status"] == "stopped" and stop_sent:
            return Outcome("timeout", error="timed out after %g s" % timeout, duration=record.get("duration"))
        return Outcome(record["status"], record.get("result"), record.get("error"), record.get("duration"))

    def _answer(self, name):
        record = self.mailbox.outcome(name)
        if record and record.get("status") == "done" and isinstance(record.get("result"), dict):
            return record["result"]
        return None

    def _append(self, entry):
        self.journal.parent.mkdir(parents=True, exist_ok=True)
        with self.journal.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry) + "\n")
            handle.flush()
