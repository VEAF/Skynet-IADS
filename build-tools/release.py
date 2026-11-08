#!/usr/bin/env python3
"""Prepare a Skynet release, and package it into build/release/.

    python build-tools/release.py X.Y.Z          # prepare: version, changelog, demos -- then package
    python build-tools/release.py                # package and check, changing no committed file
    python build-tools/release.py --tag vX.Y.Z   # the same, as the release workflow runs it on a tag

The first call is made on the release branch. The other two leave build/release/ holding exactly
what a release attaches: the compiled script, the two demos and notes.md. CONTRIBUTING.md has the
procedure.
"""

import importlib.util
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

_spec = importlib.util.spec_from_file_location("build_compiled_script", ROOT / "build-tools" / "build-compiled-script.py")
_build = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_build)


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
