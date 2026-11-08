"""Builds the deliverable: every source listed in build-tools/listToMerge.txt, concatenated in that
order under a first line naming the version read from skynet-iads-source/skynet-iads.lua.

Usage, from anywhere:

    python build-tools/build-compiled-script.py                  # writes build/skynet-iads-compiled.lua
    python build-tools/build-compiled-script.py --output FILE

The build is reproducible: the same commit gives the same bytes on any machine. The first line
carries no build time, sources are read as UTF-8 with any byte-order mark dropped, and the output is
UTF-8 with LF line endings. So whether a file is the build of the current sources is answered by
building again, in memory, and comparing: `build()` returns the text for callers that do that.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION = re.compile(r'SkynetIADS\.version\s*=\s*"([^"]+)"')


class BuildError(Exception):
    """The sources cannot be built: a listed file is missing, or the version is not found."""


def _read(path):
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    if text and not text.endswith("\n"):
        text += "\n"
    return text


def build(root=ROOT):
    """Return the compiled script built from the sources under *root*."""
    root = Path(root)
    sources = root / "skynet-iads-source"
    version_file = sources / "skynet-iads.lua"
    match = VERSION.search(_read(version_file)) if version_file.is_file() else None
    if not match:
        raise BuildError("Could not find SkynetIADS.version in %s" % version_file)

    manifest = root / "build-tools" / "listToMerge.txt"
    names = [line.strip() for line in _read(manifest).split("\n")]
    names = [name for name in names if name and not name.startswith("#")]
    missing = [name for name in names if not (sources / name).is_file()]
    if missing:
        raise BuildError("Missing source file(s) listed in listToMerge.txt: %s" % ", ".join(missing))

    banner = 'env.info("--- SKYNET VERSION: %s ---")\n' % match.group(1)
    return banner + "".join(_read(sources / name) for name in names)


def main(argv):
    parser = argparse.ArgumentParser(description="Build the compiled Skynet script.")
    parser.add_argument("--output", type=Path, help="where to write it (default: build/skynet-iads-compiled.lua)")
    args = parser.parse_args(argv)
    try:
        text = build(ROOT)
    except BuildError as error:
        print(error, file=sys.stderr)
        return 1
    output = args.output or ROOT / "build" / "skynet-iads-compiled.lua"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(text.encode("utf-8"))
    print("Built %s (%s)" % (output, VERSION.search(text).group(1)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
