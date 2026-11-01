"""The Skynet script the test mission loads: the repository's build, copied to build/insim/.

The copy is up to date when it equals a build made in memory, so a change to a source, to
`build-tools/listToMerge.txt` or to the build itself is seen. A forced script (`--skynet FILE`) is
copied as is, and the next default run replaces it.
"""

import importlib.util
import shutil
from pathlib import Path

__all__ = ["prepare", "build_text", "BuildError"]

_spec = importlib.util.spec_from_file_location(
    "build_compiled_script", Path(__file__).resolve().parents[2] / "build-tools" / "build-compiled-script.py"
)
_build = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_build)

#: What a build that cannot be made raises: a listed source missing, or no version found.
BuildError = _build.BuildError


def build_text(repo):
    """The compiled script built from *repo*'s sources, by this repository's build."""
    return _build.build(repo)


def prepare(repo, forced, build=build_text):
    """Make the copy; returns (path, what was done): "up to date", "rebuilt" or "forced"."""
    repo = Path(repo)
    target = repo / "build" / "insim" / "skynet-iads-insim.lua"
    target.parent.mkdir(parents=True, exist_ok=True)

    if forced is not None:
        shutil.copyfile(forced, target)
        return target, "forced"

    built = build(repo).encode("utf-8")
    if target.is_file() and target.read_bytes() == built:
        return target, "up to date"
    target.write_bytes(built)
    return target, "rebuilt"
