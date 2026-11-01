"""Tests for the runners: which folders run.py runs when none is given, and what run.lua does with a
folder that does not exist.

    python test/common/run.py test/common
"""

import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))

# Loaded by path, under a name of its own: the in-sim tests import their driver in the same process.
_spec = importlib.util.spec_from_file_location("common_run", os.path.join(HERE, "run.py"))
run = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run)

LUA_FOR_WINDOWS = r"C:\Program Files (x86)\Lua\5.1\lua.exe"


def find_lua():
    """lua5.1 on PATH, else Lua for Windows at its default path, else None."""
    found = shutil.which("lua5.1")
    if found:
        return found
    return LUA_FOR_WINDOWS if os.path.isfile(LUA_FOR_WINDOWS) else None


def touch(root, *parts):
    path = os.path.join(root, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").close()


class SuiteFoldersTest(unittest.TestCase):
    def test_finds_every_folder_holding_a_python_suite(self):
        with tempfile.TemporaryDirectory() as root:
            touch(root, "a", "test_x.py")
            touch(root, "b", "helper.py")
            touch(root, "c", "test_y.py")
            touch(root, "d", "sub", "test_z.py")
            touch(root, "test_top.py")

            self.assertEqual(run.suite_folders(root), [os.path.join(root, "a"), os.path.join(root, "c")])



class RunLuaTest(unittest.TestCase):
    def setUp(self):
        self.lua = find_lua()
        if not self.lua:
            self.skipTest("no Lua 5.1 interpreter")

    def run_lua(self, *args):
        return subprocess.run([self.lua, os.path.join(HERE, "run.lua"), *args], capture_output=True, text=True)

    def test_a_folder_that_does_not_exist_is_refused(self):
        missing = os.path.join(HERE, "..", "no-such-folder")
        result = self.run_lua(missing, "contact")
        self.assertEqual(result.returncode, 1)
        self.assertIn("run.lua: no such folder: " + missing, result.stdout)

    def test_with_no_folder_it_finds_the_suites_of_every_folder(self):
        # test_dcs_stub.lua is in test/common/, which no list ever named: only discovery finds it.
        result = self.run_lua("test_dcs_stub")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("--- test_dcs_stub.lua ---", result.stdout)


if __name__ == "__main__":
    unittest.main()
