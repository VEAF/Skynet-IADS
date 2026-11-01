"""Tests for test/common/run.py: which folders it runs when none is given.

    python test/common/run.py test/common
"""

import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))

# Loaded by path, under a name of its own: the in-sim tests import their driver in the same process.
_spec = importlib.util.spec_from_file_location("common_run", os.path.join(HERE, "run.py"))
run = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run)


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


if __name__ == "__main__":
    unittest.main()
