"""The Skynet script the test mission loads: the repository's build, copied to build/insim/.

The copy is rebuilt only when `build-tools/listToMerge.txt` or a source it lists changed, or when the
copy itself was replaced. A forced script (`--skynet FILE`) is copied as is and never kept by a default run.
"""

import hashlib
import json
import shutil
import subprocess
from pathlib import Path

__all__ = ["prepare", "run_build"]


def run_build(repo):
    subprocess.run(["pwsh", "-File", str(Path(repo) / "build-tools" / "build-compiled-script.ps1")], check=True)


def _sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _sources_sha256(repo):
    manifest = repo / "build-tools" / "listToMerge.txt"
    digest = hashlib.sha256(manifest.read_bytes())
    for line in manifest.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            digest.update((repo / "skynet-iads-source" / line).read_bytes())
    return digest.hexdigest()


def prepare(repo, forced, build=run_build):
    """Make the copy; returns (path, what was done): "up to date", "rebuilt" or "forced"."""
    repo = Path(repo)
    target = repo / "build" / "insim" / "skynet-iads-insim.lua"
    state_file = repo / "build" / "insim" / "skynet-script.json"
    target.parent.mkdir(parents=True, exist_ok=True)

    if forced is not None:
        shutil.copyfile(forced, target)
        sources = None
        done = "forced"
    else:
        sources = _sources_sha256(repo)
        try:
            state = json.loads(state_file.read_text(encoding="utf-8"))
            if state["sources_sha256"] == sources and target.is_file() and _sha256(target) == state["file_sha256"]:
                return target, "up to date"
        except (OSError, ValueError, KeyError):
            pass
        build(repo)
        shutil.copyfile(repo / "demo-missions" / "skynet-iads-compiled.lua", target)
        done = "rebuilt"

    state_file.write_text(json.dumps({"sources_sha256": sources, "file_sha256": _sha256(target)}), encoding="utf-8")
    return target, done
