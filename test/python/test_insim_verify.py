"""Tests for test/insim/engine/verify.py -- judging a recorded result with luaunit outside DCS.

Run from anywhere:

    python -m unittest discover -s test/python -p "test_insim_*.py"
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "test", "insim"))
from engine import verify  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "insim-fixtures" / "verify"

try:
    LUA = verify.find_lua(None)
except verify.VerifyError:
    LUA = None


@unittest.skipUnless(LUA, "no Lua 5.1 interpreter found")
class JudgeTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.result_file = Path(tmp.name) / "r.lua"

    def test_pass(self):
        self.assertEqual(verify.judge(LUA, FIXTURES / "sam-one", {"sam": 1}, self.result_file), (True, ""))

    def test_fail_carries_luaunit_message(self):
        ok, msg = verify.judge(LUA, FIXTURES / "sam-one", {"sam": 2}, self.result_file)
        self.assertFalse(ok)
        self.assertIn("expected: 1, actual: 2", msg)

    def test_missing_verify_is_an_error(self):
        with self.assertRaises(verify.VerifyError):
            verify.judge(LUA, FIXTURES / "no-verify", {}, self.result_file)

    def test_verify_that_does_not_compile_is_an_error(self):
        with self.assertRaises(verify.VerifyError):
            verify.judge(LUA, FIXTURES / "bad-syntax", {}, self.result_file)

    def test_verify_that_returns_no_function_is_an_error(self):
        with self.assertRaises(verify.VerifyError):
            verify.judge(LUA, FIXTURES / "not-a-function", {}, self.result_file)

    def test_unloadable_result_file_is_an_error_with_its_message(self):
        self.result_file.write_text("return {", encoding="utf-8")
        args = [LUA, str(verify.RUNNER), str(FIXTURES / "sam-one" / "verify.lua"), str(self.result_file)]
        proc = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("r.lua", proc.stdout)

    def test_runtime_error_on_stderr_alone_is_an_error_not_a_fail(self):
        done = mock.Mock(returncode=1, stdout="", stderr="lua: boom")
        with mock.patch("subprocess.run", return_value=done):
            with self.assertRaisesRegex(verify.VerifyError, "boom"):
                verify.judge(LUA, FIXTURES / "sam-one", {"sam": 1}, self.result_file)

    def test_interpreter_that_cannot_start_is_an_error(self):
        with self.assertRaises(verify.VerifyError):
            verify.judge(str(FIXTURES / "no-such-lua"), FIXTURES / "sam-one", {"sam": 1}, self.result_file)


class FindLuaTest(unittest.TestCase):
    def test_find_lua_prefers_explicit(self):
        self.assertEqual(verify.find_lua("/my/lua"), "/my/lua")

    def test_find_lua_uses_path_then_default(self):
        with mock.patch("shutil.which", return_value="/usr/bin/lua5.1"):
            self.assertEqual(verify.find_lua(None), "/usr/bin/lua5.1")
        with mock.patch("shutil.which", return_value=None), mock.patch("os.path.isfile", return_value=True):
            self.assertEqual(verify.find_lua(None), verify.DEFAULT_LUA)

    def test_find_lua_none_found_names_the_three(self):
        with mock.patch("shutil.which", return_value=None), mock.patch("os.path.isfile", return_value=False):
            with self.assertRaises(verify.VerifyError) as cm:
                verify.find_lua(None)
        text = str(cm.exception)
        for part in ("--lua", "lua5.1", verify.DEFAULT_LUA):
            self.assertIn(part, text)


if __name__ == "__main__":
    unittest.main()
