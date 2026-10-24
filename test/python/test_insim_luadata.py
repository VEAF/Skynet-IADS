"""Tests for test/insim/engine/luadata.py -- the reader of dcs-hotload's Lua result files.

Run from anywhere:

    python -m unittest discover -s test/python -p "test_insim_*.py"
"""

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "test", "insim"))
from engine import luadata  # noqa: E402


class ParseTest(unittest.TestCase):
    def test_hotload_outbox(self):
        text = '-- dcs-hotload result\nreturn {\n  ["duration"] = 0.1,\n  ["label"] = "inbox/x",\n  ["result"] = {\n    [1] = "a",\n    [2] = true,\n  },\n  ["status"] = "done",\n}\n'
        self.assertEqual(luadata.parse(text), {"duration": 0.1, "label": "inbox/x", "result": ["a", True], "status": "done"})

    def test_bare_keys_for_scenario_files(self):
        self.assertEqual(luadata.parse('return { tier = "minimal", timeout = 120 }'), {"tier": "minimal", "timeout": 120})

    def test_q_escapes(self):  # %q: \" \\ backslash-newline \r \000
        self.assertEqual(luadata.parse('return "a\\"b\\\\c\\\nd\\re\\000"'), 'a"b\\c\nd\re\x00')

    def test_special_numbers(self):
        v = luadata.parse("return { math.huge, -math.huge, 0/0, -3, 1e-05 }")
        self.assertEqual(v[:2], [float("inf"), float("-inf")])
        self.assertTrue(v[2] != v[2])
        self.assertEqual(v[3:], [-3, 1e-05])

    def test_sparse_table_stays_dict(self):
        self.assertEqual(luadata.parse("return { [1] = 1, [3] = 3 }"), {1: 1, 3: 3})

    def test_truncated_text_raises(self):  # an outbox caught mid-write
        with self.assertRaises(luadata.LuaDataError):
            luadata.parse('return {\n  ["status"] = "do')

    def test_empty_and_partial_text_raise(self):
        for text in ("", "-- only a comment\n", "return", "return {", 'return { ["a"] = }', "return 1 2"):
            with self.subTest(text=text):
                with self.assertRaises(luadata.LuaDataError):
                    luadata.parse(text)

    def test_long_brackets_nil_and_separators(self):
        self.assertEqual(luadata.parse("return { a = [[x\ny]], b = nil; c = false }"), {"a": "x\ny", "c": False, "b": None})

    def test_comments_and_unknown_escape(self):
        self.assertEqual(luadata.parse("-- a\n-- b\nreturn {}"), {})
        with self.assertRaises(luadata.LuaDataError):
            luadata.parse('return "\\q"')


class DumpTest(unittest.TestCase):
    def test_dump_round_trips(self):
        v = {"sam": 1, "names": ["a", 'q"\n'], "ok": True, "inf": float("inf")}
        self.assertEqual(luadata.parse(luadata.dump(v)), v)

    def test_round_trips_every_kind(self):
        v = {
            "none": None,
            "neg": float("-inf"),
            "f": 0.1,
            "tiny": 1e-05,
            "i": -3,
            "s": 'a"b\\c\nd\re\x00\x01\t7',
            "nested": [[1, 2], {"k": [True, False]}],
            "ints": {1: "a", 3: "c"},
            "key with space": 1,
        }
        self.assertEqual(luadata.parse(luadata.dump(v)), v)
        nan = luadata.parse(luadata.dump(float("nan")))
        self.assertTrue(nan != nan)

    def test_dump_is_a_return_chunk(self):
        self.assertTrue(luadata.dump({"a": 1}).startswith("return "))


if __name__ == "__main__":
    unittest.main()
