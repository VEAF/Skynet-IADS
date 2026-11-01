"""Discover and run every test_*.py of the given folders in one unittest run.

Usage:  python test/common/run.py [folder...] [filenameSubstring]

An argument holding a path separator is a folder; with none, every folder directly under test/ that
holds a test_*.py runs. The same rule as run.lua, so one command line shape serves both languages.
"""

import glob
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def suite_folders(root):
    """Every folder directly under root that holds a test_*.py, sorted."""
    folders = [os.path.join(root, name) for name in sorted(os.listdir(root))]
    return [f for f in folders if os.path.isdir(f) and glob.glob(os.path.join(f, "test_*.py"))]


def main(argv):
    folders = [a for a in argv if "/" in a or "\\" in a]
    names = [a for a in argv if a not in folders]
    pattern = "test_*%s*.py" % names[-1] if names else "test_*.py"
    suite = unittest.TestSuite()
    loader = unittest.TestLoader()
    for folder in folders or suite_folders(os.path.join(HERE, "..")):
        folder = os.path.abspath(folder)
        if not os.path.isdir(folder):
            print("run.py: no such folder: %s" % folder)
            return 1
        suite.addTests(loader.discover(folder, pattern=pattern, top_level_dir=folder))
    result = unittest.TextTestRunner().run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
