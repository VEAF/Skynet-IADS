"""Tests for build-tools/release.py, which prepares a release and packages it into build/release/.

Run from anywhere:

    python test/common/run.py test/build-tools release

The changelog and version rules are pinned on strings and small files; the packaging on a repository
built per test, so what is pinned is the release's rules and not the sources of the day.
"""

import importlib.util
import io
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, *path.split("/")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rel = _load("release", "build-tools/release.py")
demos = _load("update_skynet_script", "demo-missions/update-skynet-script.py")
build = _load("build_compiled_script", "build-tools/build-compiled-script.py")

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
        for text in ("v3.6.0", "3.6", "3.6.0-rc1", "", "3.06.0", "03.6.0"):
            with self.subTest(text=text), self.assertRaises(rel.ReleaseError) as caught:
                rel.parse_version(text)
            self.assertIn("X.Y.Z", str(caught.exception))

    def test_parse_accepts_zero_parts(self):
        self.assertEqual(rel.parse_version("0.10.0"), (0, 10, 0))

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


class RepoTest(unittest.TestCase):
    """A repository of its own: sources, two demos carrying a build, a changelog."""

    VERSION = "3.6.0"
    FROZEN = True

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        (self.repo / "skynet-iads-source").mkdir()
        (self.repo / "build-tools").mkdir()
        self.source('SkynetIADS = {}\nSkynetIADS.version = "%s"\n' % self.VERSION)
        (self.repo / "build-tools" / "listToMerge.txt").write_text("skynet-iads.lua\n", encoding="utf-8")
        for demo in demos.DEMOS:
            path = self.repo / demo
            path.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(path, "w") as z:
                z.writestr("mission", b"mission = {}\n")
                z.writestr(demos.MEMBER, b"--SKYNET-PLACEHOLDER\n")
        self.changelog(rel.freeze_changelog(CHANGELOG, "3.6.0", DATE) if self.FROZEN else CHANGELOG)
        self.quietly(demos.update, self.repo)
        for name, value in (("find_lua", None), ("tag_exists", False)):
            patcher = mock.patch.object(rel, name, return_value=value)
            setattr(self, name, patcher.start())
            self.addCleanup(patcher.stop)

    def source(self, text):
        (self.repo / "skynet-iads-source" / "skynet-iads.lua").write_text(text, encoding="utf-8")

    def changelog(self, text):
        (self.repo / "CHANGELOG.md").write_text(text, encoding="utf-8")

    def quietly(self, function, *args):
        out = io.StringIO()
        with redirect_stdout(out):
            result = function(*args)
        self.output = out.getvalue()
        return result

    def release_dir(self):
        return self.repo / "build" / "release"

    def committed(self):
        return {
            path.relative_to(self.repo).as_posix(): path.read_bytes()
            for path in self.repo.rglob("*")
            if path.is_file() and path.relative_to(self.repo).parts[0] != "build"
        }


class PackageTest(RepoTest):
    def test_writes_the_release(self):
        self.assertEqual(self.quietly(rel.package, self.repo), 0)
        self.assertEqual(
            sorted(os.listdir(self.release_dir())),
            ["notes.md", "skynet-and-moose-a2a-dispatcher.miz", "skynet-iads-compiled.lua", "skynet-test-persian-gulf.miz"],
        )
        self.assertEqual((self.release_dir() / "skynet-iads-compiled.lua").read_bytes(), build.build(self.repo).encode("utf-8"))
        for demo in demos.DEMOS:
            self.assertEqual((self.release_dir() / Path(demo).name).read_bytes(), (self.repo / demo).read_bytes())
        self.assertEqual((self.release_dir() / "notes.md").read_bytes(), b"### Fixed\n\n- a fix\n")

    def test_empties_build_release_first(self):
        self.release_dir().mkdir(parents=True)
        (self.release_dir() / "notes.md").write_text("stale", encoding="utf-8")
        (self.release_dir() / "extra.txt").write_text("stale", encoding="utf-8")
        self.quietly(rel.package, self.repo)
        self.assertFalse((self.release_dir() / "extra.txt").exists())
        self.assertEqual((self.release_dir() / "notes.md").read_bytes(), b"### Fixed\n\n- a fix\n")

    def test_changes_no_committed_file(self):
        before = self.committed()
        self.quietly(rel.package, self.repo)
        self.assertEqual(self.committed(), before)

    def test_stale_demos_fail(self):
        self.source('SkynetIADS = {}\nSkynetIADS.version = "3.6.0"\nx = 1\n')
        self.assertEqual(self.quietly(rel.package, self.repo), 1)
        self.assertIn("release.py", self.output)

    def test_build_release_that_cannot_be_emptied_is_a_refusal(self):
        self.release_dir().mkdir(parents=True)
        with mock.patch.object(rel.shutil, "rmtree", side_effect=PermissionError("in use")):
            with self.assertRaises(rel.ReleaseError) as caught:
                self.quietly(rel.package, self.repo)
        self.assertIn("build/release", str(caught.exception))

    def test_tag_mismatch_fails_before_writing(self):
        with self.assertRaises(rel.ReleaseError):
            self.quietly(rel.package, self.repo, "v3.6.1")
        self.assertFalse(self.release_dir().exists())

    def test_missing_section_warns_without_tag_fails_with(self):
        self.changelog(CHANGELOG)
        self.assertEqual(self.quietly(rel.package, self.repo), 0)
        self.assertIn("warning", self.output)
        self.assertFalse((self.release_dir() / "notes.md").exists())
        with self.assertRaises(rel.ReleaseError):
            self.quietly(rel.package, self.repo, "v3.6.0")

    def test_no_lua_warns_without_tag_fails_with(self):
        self.assertEqual(self.quietly(rel.package, self.repo), 0)
        self.assertIn("skipped", self.output)
        with self.assertRaises(rel.ReleaseError):
            self.quietly(rel.package, self.repo, "v3.6.0")

    def test_lua_failure_fails(self):
        self.find_lua.return_value = ["lua5.1"]
        with mock.patch.object(rel.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)) as run:
            self.assertEqual(self.quietly(rel.package, self.repo), 1)
        args, kwargs = run.call_args
        self.assertEqual(args[0][-2:], ["test/common/run.lua", "test_compiled_script"])
        self.assertEqual(kwargs["cwd"], self.repo)


class PrepareTest(RepoTest):
    VERSION = "3.5.0"
    FROZEN = False

    def test_prepares_and_packages(self):
        self.assertEqual(self.quietly(rel.prepare, self.repo, "3.6.0", DATE), 0)
        self.assertEqual(rel.code_version(self.repo), "3.6.0")
        self.assertIn("## [3.6.0] — 2026-11-08", (self.repo / "CHANGELOG.md").read_text(encoding="utf-8"))
        self.assertEqual(self.quietly(demos.check, self.repo, True), 0)
        self.assertTrue((self.release_dir() / "notes.md").exists())

    def test_refusal_writes_nothing(self):
        before = self.committed()
        for version in ("3.4.0", "v3.6.0", "3.6"):
            with self.subTest(version=version), self.assertRaises(rel.ReleaseError):
                self.quietly(rel.prepare, self.repo, version, DATE)
        self.assertEqual(self.committed(), before)

    def test_failed_demo_refresh_says_to_run_release_again(self):
        with mock.patch.object(rel._demos, "replace_member", side_effect=rel._demos.UpdateError("locked")):
            self.assertEqual(self.quietly(rel.prepare, self.repo, "3.6.0", DATE), 1)
        self.assertIn("release.py", self.output)


class MainTest(RepoTest):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(rel, "ROOT", self.repo)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_version_and_tag_exclude_each_other(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
            rel.main(["3.6.0", "--tag", "v3.6.0"])
        self.assertEqual(caught.exception.code, 2)

    def test_refusal_prints_fail(self):
        self.assertEqual(self.quietly(rel.main, ["v3.6.0"]), 1)
        self.assertTrue(self.output.startswith("FAIL:"))


if __name__ == "__main__":
    unittest.main()
