"""Tests for test/insim/engine/mailbox.py -- the client of dcs-hotload's user-inbox / user-outbox.

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
from engine import mailbox  # noqa: E402


class MailboxTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.box = mailbox.Mailbox(self.root)
        self.box.ensure()

    def test_ensure_creates_both_folders(self):
        self.assertTrue((self.root / "user-inbox").is_dir())
        self.assertTrue((self.root / "user-outbox").is_dir())

    def test_send_leaves_only_the_final_name(self):
        self.box.send("a-1", "return 1")
        self.assertEqual((self.root / "user-inbox" / "a-1.lua").read_text(), "return 1")
        self.assertEqual(os.listdir(self.root / "user-inbox"), ["a-1.lua"])

    def test_outcome_absent_is_none(self):
        self.assertIsNone(self.box.outcome("a-1"))

    def test_outcome_parses_the_outbox(self):
        (self.root / "user-outbox" / "a-1.lua").write_bytes(b'return {\r\n  ["status"] = "done",\r\n  ["result"] = 3,\r\n}\r\n')
        self.assertEqual(self.box.outcome("a-1"), {"status": "done", "result": 3})

    def test_mailbox_unreadable_outbox_is_none(self):
        (self.root / "user-outbox" / "a-1.lua").write_text('return {\n  ["status"] = "do')
        self.assertIsNone(self.box.outcome("a-1"))

    def test_clear_removes_both_files(self):
        self.box.send("a-1", "x")
        (self.root / "user-outbox" / "a-1.lua").write_text("return {}")
        self.box.clear("a-1")
        self.box.clear("a-1")
        self.assertEqual(os.listdir(self.root / "user-inbox"), [])
        self.assertEqual(os.listdir(self.root / "user-outbox"), [])

    def test_clear_prefixes_keeps_the_others(self):
        for name in ("probe-1", "stop-2", "a-3"):
            self.box.send(name, "x")
            (self.root / "user-outbox" / (name + ".lua")).write_text("return {}")
        self.box.clear_prefixes(["probe-", "stop-"])
        self.assertEqual(os.listdir(self.root / "user-inbox"), ["a-3.lua"])
        self.assertEqual(os.listdir(self.root / "user-outbox"), ["a-3.lua"])


if __name__ == "__main__":
    unittest.main()
