#!/usr/bin/env python3
"""Check, or remove a test suite from, unit-tests/skynet-unit-tests.miz.

A `.miz` is a zip, and a script baked into one is wired in FOUR places. All four have to move
together or the mission loads a resource key that names nothing:

  1. `l10n/DEFAULT/<name>.lua`   the script itself
  2. `l10n/DEFAULT/mapResource`  `["ResKey_Action_NNN"] = "<name>.lua"`
  3. `mission`, `trig.actions`   the compiled Lua the simulator runs:
                                 `a_do_script_file(getValueResourceByKey("ResKey_Action_NNN"));`
  4. `mission`, `trigrules`      the Mission Editor's own structured copy of the same trigger — an
                                 array of `[n] = { ["file"] = "ResKey_Action_NNN", ... }` whose
                                 indices have to stay contiguous

Forgetting (4) is the trap: the two copies of the trigger disagree, and depending on which one
reads it you get a mission that runs the script but shows an empty trigger in the editor, or the
reverse. `check` asserts that they agree, entry for entry and in order.

Usage, from the repository root:

    python build-tools/miz-suite.py check
    python build-tools/miz-suite.py remove test-skynet-iads-jammer.lua [...]

`remove` re-runs every check against the result and refuses to write if anything is off, so a
failed run leaves the `.miz` untouched. What it cannot check is DCS itself: load the mission once
in the simulator after a removal.
"""

import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIZ = os.path.join(ROOT, "unit-tests", "skynet-unit-tests.miz")
L10N = "l10n/DEFAULT/"
MAP_RESOURCE = L10N + "mapResource"

ACTION_BLOCK = r"([ \t]*)\[(\d+)\] = \r?\n\1\{.*?\r?\n\1\}, -- end of \[\2\]\r?\n"
ACTIONS_ARRAY = r'\["actions"\] = \r?\n([ \t]*)\{\r?\n(.*?)\r?\n\1\}, -- end of \["actions"\]'


def read_all(path):
    with zipfile.ZipFile(path) as z:
        order = [i.filename for i in z.infolist()]
        return {n: z.read(n) for n in order}, order


def parse_map_resource(text):
    return dict(re.findall(r'\["(ResKey_Action_\d+)"\]\s*=\s*"([^"]+)"', text))


def action_blocks(body):
    return list(re.finditer(ACTION_BLOCK, body, re.S))


def trigrules_of(mission):
    start = mission.find('["trigrules"]')
    if start < 0:
        raise SystemExit("FAIL: the mission has no trigrules section")
    return start, mission.find('-- end of ["trigrules"]', start)


def check(entries):
    """Every wiring invariant, asserted against an in-memory .miz. Returns a list of problems."""
    problems = []
    mapping = parse_map_resource(entries[MAP_RESOURCE].decode("utf-8"))
    mission = entries["mission"].decode("utf-8")
    referenced = set(re.findall(r"ResKey_Action_\d+", mission))

    for key in sorted(referenced):
        if key not in mapping:
            problems.append("mission references %s, which mapResource does not define" % key)
        elif L10N + mapping[key] not in entries:
            problems.append("%s names %s, which is not in the archive" % (key, mapping[key]))

    scripts = {n for n in entries if n.startswith(L10N) and n.endswith(".lua")}
    named = {L10N + v for k, v in mapping.items() if k in referenced}
    for orphan in sorted(scripts - named):
        problems.append("%s is in the archive but no trigger loads it" % orphan)

    compiled = re.findall(r'a_do_script_file\(getValueResourceByKey\(\\"(ResKey_Action_\d+)\\"\)\)', mission)
    start, end = trigrules_of(mission)
    trigrules = mission[start:end]
    editor = re.findall(r'\["file"\] = "(ResKey_Action_\d+)"', trigrules)
    if compiled != editor:
        problems.append(
            "trig.actions and trigrules disagree:\n    compiled: %s\n    editor:   %s" % (compiled, editor)
        )

    for am in re.finditer(ACTIONS_ARRAY, trigrules, re.S):
        idx = [int(b.group(2)) for b in action_blocks(am.group(2) + "\n")]
        if idx and idx != list(range(1, len(idx) + 1)):
            problems.append("trigrules action indices are not contiguous: %s" % idx)

    for name, blob in entries.items():
        if name in ("mission", MAP_RESOURCE):
            continue
        for key in sorted(set(re.findall(rb"ResKey_Action_\d+", blob))):
            k = key.decode()
            if k not in mapping:
                problems.append("%s names %s, which mapResource does not define" % (name, k))
    return problems, mapping, compiled


def drop_from_trigrules(mission, dead_keys):
    """Drop the trigrules action entries naming dead_keys, renumbering what is left."""
    start, end = trigrules_of(mission)
    section = mission[start:end]
    removed = 0
    # Collected first and applied back to front, so that each rewrite keeps the offsets of the
    # ones still to come. Replacing by matched text instead would rewrite the wrong trigger the
    # day two of them happen to hold the same actions.
    rewrites = []
    for am in re.finditer(ACTIONS_ARRAY, section, re.S):
        blocks = action_blocks(am.group(2) + "\n")
        if not blocks:
            continue
        kept = []
        for block in blocks:
            key = re.search(r'\["file"\] = "(ResKey_Action_\d+)"', block.group(0))
            if key and key.group(1) in dead_keys:
                removed += 1
            else:
                kept.append(block.group(0))
        renumbered = []
        for i, text in enumerate(kept, start=1):
            text = re.sub(r"^([ \t]*)\[\d+\] = ", r"\g<1>[%d] = " % i, text, count=1)
            text = re.sub(r"\}, -- end of \[\d+\]\r?\n$", "}, -- end of [%d]\n" % i, text, count=1)
            renumbered.append(text)
        rewrites.append((am.start(2), am.end(2), "".join(renumbered).rstrip("\n")))

    for begin, finish, text in reversed(rewrites):
        section = section[:begin] + text + section[finish:]
    return mission[:start] + section + mission[end:], removed


def do_check(entries):
    problems, _, compiled = check(entries)
    for p in problems:
        print("  -", p)
    if problems:
        return None
    mapping = parse_map_resource(entries[MAP_RESOURCE].decode("utf-8"))
    print("wiring consistent, %d scripts loaded in this order:" % len(compiled))
    for i, key in enumerate(compiled, start=1):
        print("  %2d. %s  (%s)" % (i, mapping[key], key))
    return compiled


def do_remove(entries, order, names):
    if do_check(entries) is None:
        print("FAIL: the archive is already inconsistent; not touching it")
        return 2

    mapping = parse_map_resource(entries[MAP_RESOURCE].decode("utf-8"))
    by_name = {v: k for k, v in mapping.items()}
    mission = entries["mission"].decode("utf-8")
    map_text = entries[MAP_RESOURCE].decode("utf-8")
    dead = set()

    for name in names:
        key = by_name.get(name)
        if key is None:
            print("FAIL: %s has no mapResource entry" % name)
            return 2
        call = 'a_do_script_file(getValueResourceByKey(\\"%s\\"));' % key
        if call not in mission:
            print("FAIL: no do_script_file call for %s (%s)" % (name, key))
            return 2
        mission = mission.replace(call, "", 1)

        line = re.search(r'\r?\n[ \t]*\["%s"\][^\n]*\r?\n' % key, map_text)
        if line is None:
            print("FAIL: no mapResource line for %s" % key)
            return 2
        map_text = map_text[: line.start()] + "\n" + map_text[line.end() :]

        del entries[L10N + name]
        dead.add(key)
        print("removed %s (%s)" % (name, key))

    mission, dropped = drop_from_trigrules(mission, dead)
    if dropped != len(names):
        print("FAIL: expected to drop %d trigrules entries, dropped %d" % (len(names), dropped))
        return 2
    print("trigrules: dropped %d action entries and renumbered the rest" % dropped)

    entries["mission"] = mission.encode("utf-8")
    entries[MAP_RESOURCE] = map_text.encode("utf-8")

    if do_check(entries) is None:
        print("FAIL: the result would be inconsistent; nothing written")
        return 2

    with zipfile.ZipFile(MIZ, "w", zipfile.ZIP_DEFLATED) as z:
        for name in order:
            if name in entries:
                z.writestr(name, entries[name])
    print("written: %s" % os.path.relpath(MIZ, ROOT))
    print("Load the mission once in DCS: nothing here can check that for you.")
    return 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("check", "remove"):
        print(__doc__)
        return 1
    entries, order = read_all(MIZ)
    if argv[1] == "check":
        return 0 if do_check(entries) is not None else 2
    if len(argv) < 3:
        print("FAIL: remove needs at least one script name")
        return 1
    return do_remove(entries, order, argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
