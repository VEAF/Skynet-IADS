"""Tests for build-tools/build-compiled-script.py, the build of the deliverable.

Run from anywhere:

    python test/common/run.py test/build-tools build_compiled

Each test builds a repository of its own, so what is pinned is the build's rules and not the
sources of the day. Two builds of the same commit must give the same bytes on any machine: that is
what lets a copy be checked by building again and comparing, so line endings and byte-order marks
are pinned as hard as the order.
"""

import importlib.util
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_spec = importlib.util.spec_from_file_location("build_compiled_script", os.path.join(ROOT, "build-tools", "build-compiled-script.py"))
bcs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bcs)

VERSION_SOURCE = 'SkynetIADS = {}\nSkynetIADS.version = "9.9.9"\n'


class BuildTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        (self.repo / "build-tools").mkdir()
        (self.repo / "skynet-iads-source").mkdir()
        self.source("skynet-iads.lua", VERSION_SOURCE)

    def source(self, name, text):
        (self.repo / "skynet-iads-source" / name).write_bytes(text.encode("utf-8") if isinstance(text, str) else text)

    def manifest(self, text):
        (self.repo / "build-tools" / "listToMerge.txt").write_text(text, encoding="utf-8")

    def body(self):
        return bcs.build(self.repo).split("\n", 1)[1]

    def test_order(self):
        self.source("a.lua", "a = 1\n")
        self.source("b.lua", "b = 2\n")
        self.manifest("# a comment\n\nb.lua\na.lua\n")
        self.assertEqual(self.body(), "b = 2\na = 1\n")

    def test_banner(self):
        self.manifest("skynet-iads.lua\n")
        self.assertEqual(bcs.build(self.repo).split("\n", 1)[0], 'env.info("--- SKYNET VERSION: 9.9.9 ---")')

    def test_missing_source(self):
        self.manifest("skynet-iads.lua\nabsent.lua\n")
        with self.assertRaisesRegex(bcs.BuildError, "absent.lua"):
            bcs.build(self.repo)

    def test_missing_version(self):
        self.source("skynet-iads.lua", "SkynetIADS = {}\n")
        self.manifest("skynet-iads.lua\n")
        with self.assertRaises(bcs.BuildError):
            bcs.build(self.repo)

    def test_crlf_and_lf_equal(self):
        self.manifest("a.lua\n")
        self.source("a.lua", b"x = 1\ny = 2\n")
        lf = bcs.build(self.repo)
        self.source("a.lua", b"x = 1\r\ny = 2\r\n")
        crlf = bcs.build(self.repo)
        self.assertEqual(lf, crlf)
        self.assertNotIn("\r", crlf)

    def test_no_cr_in_output(self):
        self.manifest("a.lua\n")
        self.source("a.lua", b"x = 1\ry = 2\n")
        self.assertEqual(self.body(), "x = 1\ny = 2\n")

    def test_bom_dropped(self):
        self.manifest("a.lua\n")
        self.source("a.lua", b"\xef\xbb\xbfx = 1\n")
        self.assertEqual(self.body(), "x = 1\n")

    def test_source_without_final_newline(self):
        self.manifest("a.lua\nb.lua\n")
        self.source("a.lua", "x = 1")
        self.source("b.lua", "y = 2\n")
        self.assertEqual(self.body(), "x = 1\ny = 2\n")

    def test_two_builds_equal(self):
        self.manifest("skynet-iads.lua\n")
        self.assertEqual(bcs.build(self.repo), bcs.build(self.repo))

    def test_cli_writes_lf_utf8(self):
        self.manifest("skynet-iads.lua\n")
        out = self.repo / "out.lua"
        with mock.patch.object(bcs, "ROOT", self.repo), mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
            self.assertEqual(bcs.main(["--output", str(out)]), 0)
        self.assertEqual(out.read_bytes(), bcs.build(self.repo).encode("utf-8"))
        self.assertEqual(stdout.getvalue(), "Built %s (9.9.9)\n" % out)

    def test_cli_creates_output_folder(self):
        self.manifest("skynet-iads.lua\n")
        out = self.repo / "a" / "b" / "out.lua"
        with mock.patch.object(bcs, "ROOT", self.repo), mock.patch("sys.stdout", new_callable=io.StringIO):
            self.assertEqual(bcs.main(["--output", str(out)]), 0)
        self.assertTrue(out.is_file())

    def test_cli_fails_on_a_build_error(self):
        self.manifest("absent.lua\n")
        with mock.patch.object(bcs, "ROOT", self.repo), mock.patch("sys.stderr"):
            self.assertEqual(bcs.main(["--output", str(self.repo / "out.lua")]), 1)


if __name__ == "__main__":
    unittest.main()
