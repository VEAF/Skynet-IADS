#!/usr/bin/env python3
"""Refresh, or check, the Skynet script the demo missions carry.

The demos are committed whole, every script inside. The one that changes is the Skynet script, and
only for a release, so that a demo carries the released Skynet:

    python demo-missions/update-skynet-script.py update                 # embed a build, write the hashes
    python demo-missions/update-skynet-script.py check                  # the demos match their hashes
    python demo-missions/update-skynet-script.py check --against-build  # ...and a build of the sources

`update` replaces the content of `l10n/DEFAULT/skynet-iads-compiled.lua` in each demo with a build
made in memory, leaves every other member of the archive as it is, and writes
`demo-missions/skynet-script.sha256` in `sha256sum`'s format. Each hash is of the embedded script,
not of the archive, so `sha256sum -c` does not apply. It never rewires a mission: a demo without
that member is refused, and nothing is written.
"""

import hashlib
import importlib.util
import os
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

#: The demos, repository-relative, with forward slashes: the paths the hash file carries.
DEMOS = (
    "demo-missions/skynet-test-persian-gulf.miz",
    "demo-missions/moose_a2a_connector/skynet-and-moose-a2a-dispatcher.miz",
)
MEMBER = "l10n/DEFAULT/skynet-iads-compiled.lua"
HASH_FILE = "demo-missions/skynet-script.sha256"

_spec = importlib.util.spec_from_file_location("build_compiled_script", ROOT / "build-tools" / "build-compiled-script.py")
_build = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_build)


class UpdateError(Exception):
    """A demo cannot be read or refreshed: most often, it has no Skynet script to replace."""


def _path(root, relative):
    return Path(root, *relative.split("/"))


def embedded(root, demo):
    """The bytes of the Skynet script *demo* carries."""
    with zipfile.ZipFile(_path(root, demo)) as z:
        if MEMBER not in z.namelist():
            raise UpdateError("%s has no %s to replace" % (demo, MEMBER))
        return z.read(MEMBER)


def replace_member(root, demo, member, data):
    """Replace the content of *member* in *demo*, leaving every other member exactly as it was."""
    path = _path(root, demo)
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        if member not in [i.filename for i in infos]:
            raise UpdateError("%s has no %s to replace" % (demo, member))
        contents = [(i, data if i.filename == member else z.read(i.filename)) for i in infos]
    handle, temporary = tempfile.mkstemp(dir=path.parent, suffix=".miz")
    os.close(handle)
    try:
        with zipfile.ZipFile(temporary, "w") as z:
            for info, blob in contents:
                z.writestr(info, blob)
        os.replace(temporary, path)
    except BaseException:
        os.remove(temporary)
        raise


def write_hashes(root):
    lines = ["%s  %s\n" % (hashlib.sha256(embedded(root, demo)).hexdigest(), demo) for demo in DEMOS]
    _path(root, HASH_FILE).write_bytes("".join(lines).encode("utf-8"))


def _read_hashes(root):
    hashes = {}
    for line in _path(root, HASH_FILE).read_bytes().decode("utf-8").splitlines():
        if line.strip():
            digest, _, demo = line.strip().partition("  ")
            hashes[demo] = digest
    return hashes


def update(root=ROOT):
    try:
        for demo in DEMOS:
            embedded(root, demo)
        script = _build.build(root).encode("utf-8")
    except (UpdateError, _build.BuildError) as error:
        print("FAIL: %s" % error)
        return 1
    for demo in DEMOS:
        replace_member(root, demo, MEMBER, script)
        print("updated: %s" % demo)
    write_hashes(root)
    print("written: %s" % HASH_FILE)
    return 0


def check(root=ROOT, against_build=False):
    try:
        hashes = _read_hashes(root)
        build = _build.build(root).encode("utf-8") if against_build else None
    except (OSError, _build.BuildError) as error:
        print("FAIL: %s" % error)
        return 1
    status = 0
    for demo in DEMOS:
        try:
            script = embedded(root, demo)
        except (OSError, UpdateError) as error:
            print("FAIL  %s: %s" % (demo, error))
            status = 1
            continue
        if demo not in hashes:
            print("FAIL  %s: no line in %s" % (demo, HASH_FILE))
            status = 1
        elif hashlib.sha256(script).hexdigest() != hashes[demo]:
            print("FAIL  %s: its Skynet script does not match %s" % (demo, HASH_FILE))
            status = 1
        elif build is not None and script != build:
            print("FAIL  %s: its Skynet script is not a build of the current sources -- run `update`" % demo)
            status = 1
        else:
            print("ok    %s" % demo)
    for demo in sorted(set(hashes) - set(DEMOS)):
        print("FAIL  %s: a line in %s for a demo that is not one" % (demo, HASH_FILE))
        status = 1
    return status


def main(argv):
    if argv == ["update"]:
        return update()
    if argv == ["check"]:
        return check()
    if argv == ["check", "--against-build"]:
        return check(against_build=True)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
