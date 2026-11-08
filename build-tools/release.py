#!/usr/bin/env python3
"""Prepare a Skynet release, and package it into build/release/.

    python build-tools/release.py X.Y.Z          # prepare: version, changelog, demos -- then package
    python build-tools/release.py                # package and check, changing no committed file
    python build-tools/release.py --tag vX.Y.Z   # the same, as the release workflow runs it on a tag

The first call is made on the release branch. The other two leave build/release/ holding exactly
what a release attaches: the compiled script, the two demos and notes.md. CONTRIBUTING.md has the
procedure.
"""


class ReleaseError(Exception):
    """A release cannot be prepared or packaged as asked; the message says why."""


UNRELEASED = "## [Unreleased]"


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
