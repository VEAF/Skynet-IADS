"""Tests for build-tools/release.py, which prepares a release and packages it into build/release/.

Run from anywhere:

    python test/common/run.py test/build-tools release

The changelog and version rules are pinned on strings and small files; the packaging on a repository
built per test, so what is pinned is the release's rules and not the sources of the day.
"""

import importlib.util
import os
import unittest

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


if __name__ == "__main__":
    unittest.main()
