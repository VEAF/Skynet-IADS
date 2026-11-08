#!/usr/bin/env python3
"""Prepare a Skynet release, and package it into build/release/.

    python build-tools/release.py X.Y.Z          # prepare: version, changelog, demos -- then package
    python build-tools/release.py                # package and check, changing no committed file
    python build-tools/release.py --tag vX.Y.Z   # the same, as the release workflow runs it on a tag

The first call is made on the release branch. The other two leave build/release/ holding exactly
what a release attaches: the compiled script, the two demos and notes.md. CONTRIBUTING.md has the
procedure.
"""

import argparse
import datetime
import importlib.util
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_build = _load("build_compiled_script", "build-tools/build-compiled-script.py")
_demos = _load("update_skynet_script", "demo-missions/update-skynet-script.py")

#: Where Lua for Windows installs its interpreter, which is not on PATH.
LUA_FOR_WINDOWS = r"C:\Program Files (x86)\Lua\5.1\lua.exe"


class ReleaseError(Exception):
    """A release cannot be prepared or packaged as asked; the message says why."""


UNRELEASED = "## [Unreleased]"
VERSION_FORMAT = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def _version_file(root):
    return Path(root) / "skynet-iads-source" / "skynet-iads.lua"


def parse_version(text):
    """(major, minor, patch) of *text*, which must be three numbers and nothing else."""
    if not VERSION_FORMAT.match(text):
        raise ReleaseError("'%s' is not a version: expected X.Y.Z, three numbers" % text)
    return tuple(int(part) for part in text.split("."))


def code_version(root):
    """SkynetIADS.version, read the way the build reads it."""
    path = _version_file(root)
    match = _build.VERSION.search(path.read_text(encoding="utf-8-sig")) if path.is_file() else None
    if not match:
        raise ReleaseError("Could not find SkynetIADS.version in %s" % path)
    return match.group(1)


def tag_exists(root, tag):
    """Whether the local repository has *tag*. A tag belongs to no branch: a `git pull` on
    develop brings the tags of master's history too."""
    try:
        result = subprocess.run(["git", "-C", str(root), "tag", "-l", tag], capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise ReleaseError("Could not list the git tags: %s" % error)
    return bool(result.stdout.strip())


def check_new_version(root, version):
    """Refuse a version to prepare that is malformed, lower than the code's, or already released.
    The code's own version, untagged, is a second run of the same preparation."""
    current = code_version(root)
    if parse_version(version) < parse_version(current):
        raise ReleaseError("%s is lower than the code's version, %s" % (version, current))
    if tag_exists(root, "v" + version):
        raise ReleaseError("v%s is already tagged: that version is released" % version)


def check_tag(tag, version):
    """Refuse a tag that is not v + X.Y.Z, or that does not name *version*."""
    if not tag.startswith("v") or not VERSION_FORMAT.match(tag[1:]):
        raise ReleaseError("tag %s is not vX.Y.Z" % tag)
    if tag[1:] != version:
        raise ReleaseError("tag %s does not match SkynetIADS.version %s" % (tag, version))


def set_code_version(root, version):
    """Write *version* into SkynetIADS.version, leaving every other byte of the file as it is."""
    path = _version_file(root)
    with open(path, encoding="utf-8", newline="") as source:
        text = source.read()
    match = _build.VERSION.search(text)
    if not match:
        raise ReleaseError("Could not find SkynetIADS.version in %s" % path)
    with open(path, "w", encoding="utf-8", newline="") as source:
        source.write(text[: match.start(1)] + version + text[match.end(1) :])


def _heading(version):
    # The closing bracket is part of the match: 3.6.0 must not find [3.6.01] or [3.6.0-rc1].
    return "## [%s]" % version


def _section(lines, start):
    """The index of the line ending the section whose heading is at *start*."""
    for index in range(start + 1, len(lines)):
        if lines[index].startswith("## ["):
            return index
    return len(lines)


def freeze_changelog(text, version, date):
    """*text* with [Unreleased] renamed to [version] -- date, under a fresh, empty [Unreleased].

    Unchanged when [version] already exists and [Unreleased] is empty: a second run of the same
    preparation. The file's own line endings are kept.
    """
    lines = text.splitlines(keepends=True)
    newline = "\r\n" if "\r\n" in text else "\n"
    starts = [i for i, line in enumerate(lines) if line.rstrip("\r\n") == UNRELEASED]
    if not starts:
        raise ReleaseError("CHANGELOG.md has no %s section" % UNRELEASED)
    start = starts[0]
    end = _section(lines, start)
    body = lines[start + 1 : end]
    entries = [line.rstrip("\r\n") for line in body if line.strip()]
    if any(line.startswith(_heading(version)) for line in lines):
        if entries:
            raise ReleaseError(
                "%s holds entries merged since the preparation; they ship in %s, so move them "
                "into %s by hand:\n%s" % (UNRELEASED, version, _heading(version), "\n".join(entries))
            )
        return text
    if not entries:
        raise ReleaseError("%s is empty: there is nothing to release" % UNRELEASED)
    frozen = [UNRELEASED + newline, newline, "%s — %s%s" % (_heading(version), date, newline)]
    return "".join(lines[:start] + frozen + body + lines[end:])


def section_body(text, version):
    """The body of [version] in *text*, LF-joined and without surrounding blank lines; None when
    the section is missing or blank."""
    lines = [line.rstrip("\r\n") for line in text.splitlines(keepends=True)]
    starts = [i for i, line in enumerate(lines) if line.startswith(_heading(version))]
    if not starts:
        return None
    body = lines[starts[0] + 1 : _section(lines, starts[0])]
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return "\n".join(body) if body else None


def find_lua():
    """The command of the first Lua 5.1 interpreter that runs, or None."""
    for command in (["lua5.1"], ["lua"], [LUA_FOR_WINDOWS]):
        try:
            probe = subprocess.run(command + ["-e", "assert(_VERSION == 'Lua 5.1')"], capture_output=True)
        except OSError:
            continue
        if probe.returncode == 0:
            return command
    return None


def _refuse_or_warn(strict, message):
    if strict:
        raise ReleaseError(message)
    print("warning: %s" % message)


def package(root, tag=None):
    """Fill build/release/ with what the release attaches, checking it on the way. Changes no
    committed file. With *tag*, as on the release workflow, every warning is a refusal."""
    root = Path(root)
    version = code_version(root)
    if tag is not None:
        check_tag(tag, version)
    out = root / "build" / "release"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    try:
        script = _build.build(root)
    except _build.BuildError as error:
        raise ReleaseError(str(error))
    (out / "skynet-iads-compiled.lua").write_bytes(script.encode("utf-8"))
    # The demos ship as committed, so they must already carry this build: refreshing them here
    # would publish missions nobody reviewed.
    if _demos.check(root, against_build=True) != 0:
        return 1
    for demo in _demos.DEMOS:
        shutil.copyfile(root / demo, out / Path(demo).name)
    notes = section_body((root / "CHANGELOG.md").read_text(encoding="utf-8"), version)
    if notes is None:
        _refuse_or_warn(tag is not None, "CHANGELOG.md has no [%s] section" % version)
    else:
        (out / "notes.md").write_bytes((notes + "\n").encode("utf-8"))
    lua = find_lua()
    if lua is None:
        _refuse_or_warn(tag is not None, "no Lua 5.1 found, test_compiled_script skipped")
    elif subprocess.run(lua + ["test/common/run.lua", "test_compiled_script"], cwd=root).returncode != 0:
        return 1
    print("release: build/release/ holds %s" % version)
    return 0


def prepare(root, version, today):
    """Set the version, freeze the changelog and refresh the demos, then package. Every refusal
    comes before the first write."""
    root = Path(root)
    check_new_version(root, version)
    changelog = root / "CHANGELOG.md"
    with open(changelog, encoding="utf-8", newline="") as handle:
        frozen = freeze_changelog(handle.read(), version, today)
    with open(changelog, "w", encoding="utf-8", newline="") as handle:
        handle.write(frozen)
    set_code_version(root, version)
    if _demos.update(root) != 0:
        return 1
    return package(root)


def main(argv):
    parser = argparse.ArgumentParser(description="Prepare a Skynet release, or package it into build/release/.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("version", nargs="?", help="prepare this version, X.Y.Z, then package it")
    group.add_argument("--tag", help="package for this tag, vX.Y.Z, refusing anything that does not fit")
    args = parser.parse_args(argv)
    try:
        if args.version is not None:
            return prepare(ROOT, args.version, datetime.date.today().isoformat())
        return package(ROOT, args.tag)
    except ReleaseError as error:
        print("FAIL: %s" % error)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
