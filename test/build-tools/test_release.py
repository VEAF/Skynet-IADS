"""Tests for build-tools/release.py, which prepares a release and packages it into build/release/.

Run from anywhere:

    python test/common/run.py test/build-tools release

The changelog and version rules are pinned on strings and small files; the packaging on a repository
built per test, so what is pinned is the release's rules and not the sources of the day.
"""

import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, *path.split("/")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rel = _load("release", "build-tools/release.py")

CHANGELOG = "# Changelog\n\nIntro.\n\n## [Unreleased]\n\n### Fixed\n\n- a fix\n\n## [3.5.0] — 2026-09-21\n\n- old\n"
DATE = "2026-11-08"


class FreezeTest(unittest.TestCase):
    def test_renames_unreleased_and_opens_a_fresh_one(self):
        frozen = rel.freeze_changelog(CHANGELOG, "3.6.0", DATE)
        self.assertIn("## [Unreleased]\n\n## [3.6.0] — 2026-11-08\n\n### Fixed\n\n- a fix\n", frozen)
        self.assertIn("Intro.", frozen)
        self.assertIn("## [3.5.0] — 2026-09-21\n\n- old\n", frozen)
        self.assertEqual(frozen.count("## [Unreleased]"), 1)

    def test_second_run_changes_nothing(self):
        frozen = rel.freeze_changelog(CHANGELOG, "3.6.0", DATE)
        self.assertEqual(rel.freeze_changelog(frozen, "3.6.0", "2026-12-01"), frozen)

    def test_second_run_refuses_entries_merged_since(self):
        frozen = rel.freeze_changelog(CHANGELOG, "3.6.0", DATE)
        late = frozen.replace("## [Unreleased]\n\n", "## [Unreleased]\n\n- late entry\n\n")
        with self.assertRaises(rel.ReleaseError) as caught:
            rel.freeze_changelog(late, "3.6.0", DATE)
        self.assertIn("- late entry", str(caught.exception))
        self.assertIn("[3.6.0]", str(caught.exception))

    def test_refuses_an_empty_unreleased(self):
        empty = CHANGELOG.replace("### Fixed\n\n- a fix\n\n", "")
        with self.assertRaises(rel.ReleaseError):
            rel.freeze_changelog(empty, "3.6.0", DATE)

    def test_keeps_crlf(self):
        frozen = rel.freeze_changelog(CHANGELOG.replace("\n", "\r\n"), "3.6.0", DATE)
        self.assertNotIn("\n", frozen.replace("\r\n", ""))
        self.assertIn("## [3.6.0] — 2026-11-08\r\n", frozen)


class SectionBodyTest(unittest.TestCase):
    def test_body_between_headings(self):
        frozen = rel.freeze_changelog(CHANGELOG, "3.6.0", DATE)
        self.assertEqual(rel.section_body(frozen, "3.6.0"), "### Fixed\n\n- a fix")

    def test_last_section_of_the_file(self):
        self.assertEqual(rel.section_body(CHANGELOG, "3.5.0"), "- old")

    def test_literal_match(self):
        text = "## [3.6.01] — x\n\n- a\n\n## [3.6.0-rc1] — x\n\n- b\n"
        self.assertIsNone(rel.section_body(text, "3.6.0"))

    def test_blank_section_is_none(self):
        self.assertIsNone(rel.section_body("## [3.6.0] — x\n\n\n## [3.5.0] — y\n- old\n", "3.6.0"))

    def test_crlf(self):
        frozen = rel.freeze_changelog(CHANGELOG.replace("\n", "\r\n"), "3.6.0", DATE)
        self.assertEqual(rel.section_body(frozen, "3.6.0"), "### Fixed\n\n- a fix")


class VersionTest(unittest.TestCase):
    SOURCE = b'-- header\r\nSkynetIADS.version = "3.5.0"\r\n'

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        (self.repo / "skynet-iads-source").mkdir()
        self.write_source(self.SOURCE)
        patcher = mock.patch.object(rel, "tag_exists", return_value=False)
        self.tag_exists = patcher.start()
        self.addCleanup(patcher.stop)

    def write_source(self, data):
        (self.repo / "skynet-iads-source" / "skynet-iads.lua").write_bytes(data)

    def test_parse_refuses_malformed(self):
        for text in ("v3.6.0", "3.6", "3.6.0-rc1", ""):
            with self.subTest(text=text), self.assertRaises(rel.ReleaseError) as caught:
                rel.parse_version(text)
            self.assertIn("X.Y.Z", str(caught.exception))

    def test_numeric_comparison(self):
        self.write_source(b'SkynetIADS.version = "3.9.0"\n')
        rel.check_new_version(self.repo, "3.10.0")
        with self.assertRaises(rel.ReleaseError):
            rel.check_new_version(self.repo, "3.8.9")

    def test_equal_untagged_is_a_second_run(self):
        rel.check_new_version(self.repo, "3.5.0")

    def test_tagged_is_refused(self):
        self.tag_exists.return_value = True
        with self.assertRaises(rel.ReleaseError) as caught:
            rel.check_new_version(self.repo, "3.6.0")
        self.assertIn("v3.6.0", str(caught.exception))

    @unittest.skipIf(shutil.which("git") is None, "no git")
    def test_tag_exists_reads_git(self):
        mock.patch.stopall()
        git = ["git", "-C", str(self.repo), "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(git + ["init", "-q"], check=True)
        subprocess.run(git + ["add", "."], check=True)
        subprocess.run(git + ["commit", "-q", "-m", "x"], check=True)
        subprocess.run(git + ["tag", "v1.2.3"], check=True)
        self.assertTrue(rel.tag_exists(self.repo, "v1.2.3"))
        self.assertFalse(rel.tag_exists(self.repo, "v1.2.4"))

    def test_check_tag(self):
        rel.check_tag("v3.6.0", "3.6.0")
        for tag in ("3.6.0", "v3.6.0-rc1", "v3.6.1"):
            with self.subTest(tag=tag), self.assertRaises(rel.ReleaseError):
                rel.check_tag(tag, "3.6.0")

    def test_set_code_version_touches_only_the_number(self):
        rel.set_code_version(self.repo, "3.6.0")
        data = (self.repo / "skynet-iads-source" / "skynet-iads.lua").read_bytes()
        self.assertEqual(data, self.SOURCE.replace(b"3.5.0", b"3.6.0"))
        self.assertEqual(rel.code_version(self.repo), "3.6.0")


if __name__ == "__main__":
    unittest.main()
