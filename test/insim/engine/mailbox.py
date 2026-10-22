"""The client side of dcs-hotload's mailbox: `user-inbox/<name>.lua` in, `user-outbox/<name>.lua` out.

A command is a Lua file. Hotload runs it once it has held still for a second, and writes its outbox
twice: `status = "started"`, then the final record. Nothing here knows what a command means.
"""

import os
from pathlib import Path

from . import luadata

__all__ = ["Mailbox"]


class Mailbox:
    def __init__(self, root):
        self.inbox = Path(root) / "user-inbox"
        self.outbox = Path(root) / "user-outbox"

    def ensure(self):
        self.inbox.mkdir(parents=True, exist_ok=True)
        self.outbox.mkdir(parents=True, exist_ok=True)

    def send(self, name, code):
        """Write `<name>.lua.tmp`, then rename it: hotload never sees half a command (it only picks `*.lua`)."""
        tmp = self.inbox / (name + ".lua.tmp")
        tmp.write_text(code, encoding="utf-8", newline="\n")
        os.replace(tmp, self.inbox / (name + ".lua"))

    def outcome(self, name):
        """The outbox as a dict, or None when it is absent or cannot be read yet (hotload may be writing it)."""
        try:
            text = (self.outbox / (name + ".lua")).read_text(encoding="utf-8")
            record = luadata.parse(text)
        except (OSError, ValueError):  # LuaDataError is a ValueError, so is a decoding error
            return None
        return record if isinstance(record, dict) else None

    def clear(self, name):
        for folder in (self.inbox, self.outbox):
            self._remove(folder / (name + ".lua"))

    def clear_prefixes(self, prefixes):
        for folder in (self.inbox, self.outbox):
            if folder.is_dir():
                for path in folder.iterdir():
                    if path.name.startswith(tuple(prefixes)):
                        self._remove(path)

    @staticmethod
    def _remove(path):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
