"""Read and write the Lua data literals the in-sim suite exchanges with dcs-hotload.

`parse` reads the value of a `return <value>` chunk: what dcs-hotload writes to an outbox, and the
`scenario.lua` files (which also use bare `name = value` keys). `dump` writes a value back as a chunk
a plain Lua 5.1 script can `dofile`. Tables become `dict`; a table whose keys are exactly 1..n becomes
`list`. Anything else is a `LuaDataError`, which is also what an outbox caught mid-write raises.
"""

import math
import re

__all__ = ["LuaDataError", "parse", "dump"]


class LuaDataError(ValueError):
    pass


_NUMBER = re.compile(r"0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_LONG_OPEN = re.compile(r"\[(=*)\[")
_ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


class _Reader:
    def __init__(self, text):
        self.text = text
        self.pos = 0

    def fail(self, message):
        raise LuaDataError("%s at offset %d" % (message, self.pos))

    def skip(self):
        text = self.text
        while self.pos < len(text):
            if text[self.pos].isspace():
                self.pos += 1
            elif text.startswith("--", self.pos):
                end = text.find("\n", self.pos)
                self.pos = len(text) if end < 0 else end + 1
            else:
                break

    def peek(self):
        self.skip()
        return self.text[self.pos : self.pos + 1]

    def expect(self, char):
        if self.peek() != char:
            self.fail("expected %r" % char)
        self.pos += 1

    def keyword(self, word):
        self.skip()
        match = _NAME.match(self.text, self.pos)
        if not match or match.group(0) != word:
            self.fail("expected %r" % word)
        self.pos = match.end()

    def chunk(self):
        self.keyword("return")
        value = self.value()
        if self.peek() == ";":
            self.pos += 1
        if self.peek():
            self.fail("unexpected text after the value")
        return value

    def value(self):
        char = self.peek()
        if not char:
            self.fail("unexpected end of text")
        if char == "{":
            return self.table()
        if char in ('"', "'"):
            return self.quoted(char)
        if char == "[":
            return self.long_string()
        if char == "-":
            self.pos += 1
            return -self.number_or_special()
        if char.isdigit() or char == ".":
            return self.number_or_special()
        match = _NAME.match(self.text, self.pos)
        if not match:
            self.fail("unexpected %r" % char)
        name = match.group(0)
        if name in ("true", "false", "nil"):
            self.pos = match.end()
            return {"true": True, "false": False, "nil": None}[name]
        return self.number_or_special()

    def number_or_special(self):
        self.skip()
        text = self.text
        if text.startswith("math.huge", self.pos):
            self.pos += len("math.huge")
            return math.inf
        if text.startswith("0/0", self.pos):
            self.pos += 3
            return math.nan
        match = _NUMBER.match(text, self.pos)
        if not match:
            self.fail("expected a number")
        self.pos = match.end()
        literal = match.group(0)
        if literal[:2] in ("0x", "0X"):
            return int(literal, 16)
        if literal.isdigit():
            return int(literal)
        return float(literal)

    def quoted(self, quote):
        text = self.text
        self.pos += 1
        out = []
        while True:
            if self.pos >= len(text):
                self.fail("unfinished string")
            char = text[self.pos]
            self.pos += 1
            if char == quote:
                return "".join(out)
            if char == "\n":
                self.fail("newline in string")
            if char != "\\":
                out.append(char)
                continue
            if self.pos >= len(text):
                self.fail("unfinished string")
            esc = text[self.pos]
            if esc.isdigit():
                digits = re.match(r"\d{1,3}", text[self.pos :]).group(0)
                self.pos += len(digits)
                if int(digits) > 255:
                    self.fail("escape out of range")
                out.append(chr(int(digits)))
            elif esc in _ESCAPES:
                self.pos += 1
                out.append(_ESCAPES[esc])
            else:
                self.fail("unknown escape \\%s" % esc)

    def long_string(self):
        match = _LONG_OPEN.match(self.text, self.pos)
        if not match:
            self.fail("expected a value")
        close = "]" + match.group(1) + "]"
        end = self.text.find(close, match.end())
        if end < 0:
            self.fail("unfinished long string")
        body = self.text[match.end() : end]
        self.pos = end + len(close)
        return body[1:] if body.startswith("\n") else body

    def table(self):
        self.expect("{")
        result = {}
        position = 0
        while self.peek() != "}":
            if not self.peek():
                self.fail("unfinished table")
            if self.peek() == "[" and not _LONG_OPEN.match(self.text, self.pos):
                self.pos += 1
                key = self.value()
                self.expect("]")
                self.expect("=")
                if key is None:
                    self.fail("nil table key")
                result[key] = self.value()
            else:
                name = _NAME.match(self.text, self.pos)
                if name and name.group(0) not in ("true", "false", "nil", "math") and self._equals_follows(name.end()):
                    self.pos = name.end()
                    self.expect("=")
                    result[name.group(0)] = self.value()
                else:
                    position += 1
                    result[position] = self.value()
            if self.peek() in (",", ";"):
                self.pos += 1
            elif self.peek() != "}":
                self.fail("expected ',' or '}'")
        self.pos += 1
        count = len(result)
        if count and all(isinstance(k, int) and not isinstance(k, bool) and 1 <= k <= count for k in result):
            return [result[k] for k in range(1, count + 1)]
        return result

    def _equals_follows(self, index):
        text = self.text
        while index < len(text) and text[index].isspace():
            index += 1
        return text.startswith("=", index) and not text.startswith("==", index)


def parse(text):
    return _Reader(text).chunk()


_DUMP_ESCAPES = {'"': '\\"', "\\": "\\\\", "\n": "\\\n", "\r": "\\r"}


def _string(value):
    out = []
    for index, char in enumerate(value):
        if char in _DUMP_ESCAPES:
            out.append(_DUMP_ESCAPES[char])
        elif ord(char) < 32 or ord(char) == 127:
            # three digits when a digit follows, as Lua's %q does, so the next character is not absorbed
            following = value[index + 1 : index + 2]
            out.append("\\%03d" % ord(char) if following.isdigit() else "\\%d" % ord(char))
        else:
            out.append(char)
    return '"' + "".join(out) + '"'


def _value(value):
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if value != value:
            return "0/0"
        if value == math.inf:
            return "math.huge"
        if value == -math.inf:
            return "-math.huge"
        return repr(value)
    if isinstance(value, str):
        return _string(value)
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(_value(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ", ".join("[%s] = %s" % (_value(k), _value(v)) for k, v in value.items()) + "}"
    raise LuaDataError("cannot dump %s" % type(value).__name__)


def dump(value):
    return "return " + _value(value) + "\n"
