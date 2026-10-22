"""Judge a scenario's recorded result with its verify.lua and luaunit, in a plain Lua 5.1 outside DCS."""

import os
import shutil
import subprocess
from pathlib import Path

from . import luadata

__all__ = ["VerifyError", "DEFAULT_LUA", "find_lua", "judge"]

DEFAULT_LUA = r"C:\Program Files (x86)\Lua\5.1\lua.exe"
RUNNER = Path(__file__).resolve().parent / "verify.lua"


class VerifyError(RuntimeError):
    pass


def find_lua(explicit):
    """The interpreter: `--lua`, else `lua5.1` on PATH, else Lua for Windows' default path."""
    if explicit:
        return explicit
    found = shutil.which("lua5.1")
    if found:
        return found
    if os.path.isfile(DEFAULT_LUA):
        return DEFAULT_LUA
    raise VerifyError("no Lua 5.1 interpreter found: pass --lua, put lua5.1 on PATH, or install it at %s" % DEFAULT_LUA)


def judge(lua, scenario_dir, result, result_file):
    """Run the scenario's verify.lua against `result`: (True, "") if it passes, (False, message) if it fails."""
    result_file = Path(result_file)
    result_file.write_text(luadata.dump(result), encoding="utf-8", newline="\n")
    verify_file = Path(scenario_dir) / "verify.lua"
    try:
        proc = subprocess.run(
            [lua, str(RUNNER), str(verify_file), str(result_file)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except OSError as e:
        raise VerifyError("cannot start the Lua interpreter %s: %s" % (lua, e)) from e
    output = proc.stdout.strip()
    if proc.returncode == 0:
        return True, ""
    if proc.returncode == 1:
        return False, output
    raise VerifyError("%s: %s" % (verify_file, output or proc.stderr.strip() or "exit %d" % proc.returncode))
