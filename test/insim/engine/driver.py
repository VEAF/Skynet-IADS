"""dcs-hotload's Driver, plus what the test layer reads from it: a key's journal entry, and whether a mission runs.

The core sends each command, waits in sim time read from hotload's heartbeat, stops a hung one and
journals every outcome. A run it reports `lost` is gone with the mission that ran it.
"""

import json
from pathlib import Path

import hotload

__all__ = ["Outcome", "Driver", "SILENCE", "prepare_mailbox", "read_journal", "read_outcome"]

Outcome = hotload.Outcome
SILENCE = hotload.SILENCE


def prepare_mailbox(mailbox):
    """Create the mailbox folders, and remove the stop commands a killed driver left."""
    mailbox.inbox.mkdir(parents=True, exist_ok=True)
    mailbox.outbox.mkdir(parents=True, exist_ok=True)
    for path in mailbox.inbox.glob("stop-*.lua"):
        mailbox.clear(path.stem)


def read_journal(path):
    """Each key's journal lines merged, later fields first: an ended key keeps the `sent_at` of its `sent` line."""
    entries = {}
    path = Path(path)
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            try:
                entry = json.loads(line)
            except ValueError:
                continue  # a torn last line from a killed driver
            entries.setdefault(entry["key"], {}).update(entry)
    return entries


def read_outcome(entry):
    """The Outcome an `ended` journal entry holds."""
    fields = dict(entry["outcome"])
    fields["result"] = hotload.parse(fields["result"]) if fields.get("result") is not None else None
    return Outcome(**fields)


class Driver:
    def __init__(self, mailbox, journal, say=print, **clock_and_sleep):
        self.mailbox = mailbox
        self.journal = Path(journal)
        self.say = say
        self.core = hotload.Driver(mailbox, journal=journal, say=say, **clock_and_sleep)

    def entry(self, key):
        """The journal's entry for `key` (`state`, `sent_at`, `outcome`, ...), or None."""
        return read_journal(self.journal).get(key)

    def run(self, key, name_prefix, code, timeout):
        """The core's journalled run, without a silence cap: the suite never concludes anything from silence."""
        return self.core.run(key, name_prefix, code, timeout)

    def wait_for_mission(self, hint):
        """The heartbeat (`mission`, `time`) once it advances; `hint` is said once while it does not."""
        start, said = self.core.clock(), False
        previous = self.mailbox.heartbeat()
        while True:
            self.core.sleep(hotload.POLL)
            beat = self.mailbox.heartbeat()
            if beat and previous and (beat[1], beat[0].get("time")) != (previous[1], previous[0].get("time")):
                return beat[0]
            if not said and self.core.clock() - start > hotload.SILENCE_SAID_AFTER:
                self.say(hint)
                said = True
            previous = beat
