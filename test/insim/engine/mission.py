"""The mission DCS opens for the in-sim suite: the committed template with this checkout's hotload path.

The template carries `PLACEHOLDER` where the absolute path of dcs-hotload goes. DCS stores a DO SCRIPT
action's text twice in the `mission` entry (in `trigrules` and in the compiled `trig.actions` string),
so the placeholder appears twice. The path is written with forward slashes, which needs no escaping
inside that Lua string literal.
"""

import hashlib
import json
import zipfile
from pathlib import Path

__all__ = ["PLACEHOLDER", "MissionError", "prepare"]

PLACEHOLDER = "@BASE_HOTLOAD_PATH@"


class MissionError(Exception):
    pass


def prepare(template: Path, working: Path, hotload_root: Path) -> bool:
    """Write `working` from `template` when it is missing or built from something else; True if written."""
    template, working = Path(template), Path(working)
    path = Path(hotload_root).resolve().as_posix()
    digest = hashlib.sha256(template.read_bytes()).hexdigest()
    state = {"template_sha256": digest, "hotload_root": path}
    state_file = working.with_suffix(".json")

    if working.exists() and state_file.exists():
        try:
            if json.loads(state_file.read_text(encoding="utf-8")) == state:
                return False
        except ValueError:
            pass

    with zipfile.ZipFile(template) as src:
        text = src.read("mission").decode("utf-8")
        found = text.count(PLACEHOLDER)
        if found != 2:
            raise MissionError(f"{template}: 'mission' holds {PLACEHOLDER} {found} time(s), expected 2")
        working.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(working, "w", zipfile.ZIP_DEFLATED) as dst:
            for info in src.infolist():
                data = src.read(info.filename)
                if info.filename == "mission":
                    data = text.replace(PLACEHOLDER, path).encode("utf-8")
                dst.writestr(info.filename, data, compress_type=zipfile.ZIP_DEFLATED)
    state_file.write_text(json.dumps(state), encoding="utf-8")
    return True
