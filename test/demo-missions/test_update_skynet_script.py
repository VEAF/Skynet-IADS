"""Tests for demo-missions/update-skynet-script.py, which refreshes and checks the demos' Skynet script.

Run from anywhere:

    python test/common/run.py test/demo-missions

Each test builds a repository of its own: two demos holding a placeholder where the Skynet script
goes, and sources small enough to build. What is pinned is that only that one member ever changes,
and that the hash file says what the demos carry.
"""

import hashlib
import importlib.util
import io
import os
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, *path.split("/")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


uss = _load("update_skynet_script", "demo-missions/update-skynet-script.py")
bcs = _load("build_compiled_script", "build-tools/build-compiled-script.py")

VERSION_SOURCE = 'SkynetIADS = {}\nSkynetIADS.version = "9.9.9"\n'
OTHER = "l10n/DEFAULT/other.lua"
OTHER_DATE = (2023, 12, 1, 10, 30, 0)


class UpdaterTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "skynet-iads-source").mkdir()
        (self.root / "build-tools").mkdir()
        (self.root / "skynet-iads-source" / "skynet-iads.lua").write_text(VERSION_SOURCE, encoding="utf-8")
        (self.root / "build-tools" / "listToMerge.txt").write_text("skynet-iads.lua\n", encoding="utf-8")
        for demo in uss.DEMOS:
            self.demo(demo)

    def demo(self, demo, with_member=True):
        path = self.root / demo
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, "w") as z:
            z.writestr(zipfile.ZipInfo("mission", date_time=OTHER_DATE), b"mission = {}\n")
            if with_member:
                info = zipfile.ZipInfo(uss.MEMBER, date_time=OTHER_DATE)
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, b"--SKYNET-PLACEHOLDER\n")
            info = zipfile.ZipInfo(OTHER, date_time=OTHER_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, b"trigger.action.outText('hello', 10)\n" * 50)

    def run_quietly(self, function, *args, **kwargs):
        with redirect_stdout(io.StringIO()):
            return function(*args, **kwargs)

    def hash_file(self):
        return self.root / uss.HASH_FILE

    def members(self, demo):
        with zipfile.ZipFile(self.root / demo) as z:
            return [(i.filename, i.compress_type, i.date_time, z.read(i.filename)) for i in z.infolist()]

    def test_update_embeds_the_build(self):
        self.assertEqual(self.run_quietly(uss.update, self.root), 0)
        for demo in uss.DEMOS:
            self.assertEqual(uss.embedded(self.root, demo), bcs.build(self.root).encode("utf-8"))

    def test_update_leaves_every_other_member_as_it_is(self):
        before = {demo: self.members(demo) for demo in uss.DEMOS}
        self.run_quietly(uss.update, self.root)
        for demo in uss.DEMOS:
            after = self.members(demo)
            self.assertEqual([m[0] for m in after], [m[0] for m in before[demo]])
            kept = [m for m in before[demo] if m[0] != uss.MEMBER]
            self.assertEqual([m for m in after if m[0] != uss.MEMBER], kept)

    def test_update_writes_the_hash_file_in_sha256sum_format(self):
        self.run_quietly(uss.update, self.root)
        expected = "".join(
            "%s  %s\n" % (hashlib.sha256(uss.embedded(self.root, demo)).hexdigest(), demo) for demo in uss.DEMOS
        )
        self.assertEqual(self.hash_file().read_bytes().decode("utf-8"), expected)

    def test_update_refuses_a_demo_without_the_member(self):
        self.demo(uss.DEMOS[1], with_member=False)
        first = (self.root / uss.DEMOS[0]).read_bytes()
        self.assertEqual(self.run_quietly(uss.update, self.root), 1)
        self.assertEqual((self.root / uss.DEMOS[0]).read_bytes(), first)
        self.assertFalse(self.hash_file().exists())

    def test_check_passes_after_update(self):
        self.run_quietly(uss.update, self.root)
        self.assertEqual(self.run_quietly(uss.check, self.root), 0)
        self.assertEqual(self.run_quietly(uss.check, self.root, against_build=True), 0)

    def test_check_fails_on_a_changed_script(self):
        self.run_quietly(uss.update, self.root)
        uss.replace_member(self.root, uss.DEMOS[0], uss.MEMBER, b"-- something else\n")
        self.assertEqual(self.run_quietly(uss.check, self.root), 1)

    def test_check_fails_when_a_demo_has_no_line(self):
        self.run_quietly(uss.update, self.root)
        lines = self.hash_file().read_text(encoding="utf-8").splitlines(True)
        self.hash_file().write_text(lines[0], encoding="utf-8")
        self.assertEqual(self.run_quietly(uss.check, self.root), 1)

    def test_check_fails_on_a_line_for_no_demo(self):
        self.run_quietly(uss.update, self.root)
        with open(self.hash_file(), "a", encoding="utf-8", newline="\n") as handle:
            handle.write("%s  demo-missions/nothing.miz\n" % ("0" * 64))
        self.assertEqual(self.run_quietly(uss.check, self.root), 1)

    def test_check_reads_a_crlf_hash_file(self):
        self.run_quietly(uss.update, self.root)
        text = self.hash_file().read_bytes().replace(b"\n", b"\r\n")
        self.hash_file().write_bytes(text)
        self.assertEqual(self.run_quietly(uss.check, self.root), 0)

    def test_check_against_build_fails_when_the_sources_moved(self):
        self.run_quietly(uss.update, self.root)
        (self.root / "skynet-iads-source" / "skynet-iads.lua").write_text(
            VERSION_SOURCE.replace("9.9.9", "9.9.10"), encoding="utf-8"
        )
        self.assertEqual(self.run_quietly(uss.check, self.root), 0)
        self.assertEqual(self.run_quietly(uss.check, self.root, against_build=True), 1)

    def test_update_refuses_sources_that_do_not_build(self):
        (self.root / "skynet-iads-source" / "skynet-iads.lua").write_text("SkynetIADS = {}\n", encoding="utf-8")
        before = {demo: (self.root / demo).read_bytes() for demo in uss.DEMOS}
        self.assertEqual(self.run_quietly(uss.update, self.root), 1)
        self.assertEqual({demo: (self.root / demo).read_bytes() for demo in uss.DEMOS}, before)
        self.assertFalse(self.hash_file().exists())

    def test_update_reports_a_missing_demo(self):
        (self.root / uss.DEMOS[1]).unlink()
        self.assertEqual(self.run_quietly(uss.update, self.root), 1)

    def test_update_reports_a_corrupt_demo(self):
        (self.root / uss.DEMOS[1]).write_bytes(b"not a zip")
        self.assertEqual(self.run_quietly(uss.update, self.root), 1)

    def test_update_reports_a_demo_it_cannot_replace(self):
        with mock.patch.object(uss.os, "replace", side_effect=PermissionError("locked")):
            out = io.StringIO()
            with redirect_stdout(out):
                self.assertEqual(uss.update(self.root), 1)
        self.assertIn(uss.DEMOS[0], out.getvalue())

    def test_check_reports_a_corrupt_demo(self):
        self.run_quietly(uss.update, self.root)
        (self.root / uss.DEMOS[0]).write_bytes(b"not a zip")
        self.assertEqual(self.run_quietly(uss.check, self.root), 1)

    def test_check_reports_an_unreadable_hash_file(self):
        self.run_quietly(uss.update, self.root)
        self.hash_file().write_bytes(b"\xff\xfe\x00")
        self.assertEqual(self.run_quietly(uss.check, self.root), 1)

    def test_main_rejects_an_unknown_command(self):
        self.assertEqual(self.run_quietly(uss.main, ["stub"]), 2)


if __name__ == "__main__":
    unittest.main()
