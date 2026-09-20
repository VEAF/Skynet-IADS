#!/usr/bin/env python3
"""Check, sync, or remove a test suite from the in-sim mission archives.

Two `.miz` files carry an in-sim suite, and both are handled here:

  * `unit-tests/skynet-unit-tests.miz`
  * `unit-tests/highdigitsams/highdigitsams-unit-tests.miz`

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

A script inside an archive is also a COPY of a file that lives in the repository, and the copies
drift. `unit-tests/skynet-unit-tests.miz` carried Skynet 3.3.0 from December 2023 until
2026-09-20, so every in-sim run for three years measured code this project had stopped shipping;
`test-skynet-iads.lua` inside it was missing a test its loose copy gained in August 2026. `check`
now compares every script against the file it is a copy of, and `sync` writes the repository's
version back into the archives.

Usage, from anywhere:

    python build-tools/miz-suite.py check
    python build-tools/miz-suite.py sync
    python build-tools/miz-suite.py extract <dir>
    python build-tools/miz-suite.py remove test-skynet-iads-jammer.lua [...]

Every command works on both archives unless `--miz <path>` narrows it to one. `remove` and `sync`
re-run every check against the result and refuse to write if anything is off, so a failed run
leaves the `.miz` untouched. `extract` writes every Lua file to `<dir>/<archive name>/`, so
something that knows Lua can parse them — `.github/workflows/lua-tests.yml` runs both on every
pull request.

What is left that only DCS can answer is narrow: whether the simulator accepts the mission file
and runs its triggers. The wiring, the syntax of every script inside, and whether those scripts
are the ones this repository ships are all checked here.
"""

import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = "l10n/DEFAULT/"
MAP_RESOURCE = L10N + "mapResource"

#: Every archive carrying an in-sim suite, repository-relative.
ARCHIVES = (
    os.path.join("unit-tests", "skynet-unit-tests.miz"),
    os.path.join("unit-tests", "highdigitsams", "highdigitsams-unit-tests.miz"),
)

#: The deliverable. Both archives carry a copy of it under this member name, and that copy is what
#: the in-sim suite actually exercises -- so it is the one that matters most to keep current. It is
#: NOT committed (`.gitignore` line 12): it has to be built before `check` or `sync` can see it.
ARTIFACT = "skynet-iads-compiled.lua"
ARTIFACT_SOURCE = os.path.join("demo-missions", ARTIFACT)
BUILD_SCRIPT = "pwsh -File build-tools/build-compiled-script.ps1"

#: The artifact's first line stamps the minute it was built, so two builds of identical sources
#: never match byte for byte. The version stays in the comparison -- only the clock is dropped.
BUILD_STAMP = re.compile(rb"BUILD TIME: [^-]*---")

#: Scripts vendored from elsewhere, which have no copy in this repository for `check` to compare
#: against. Empty since 2026-09-20, when MiST left both archives: anything baked in from now on is
#: reported until it is either given a copy here or listed as a deliberate exception.
NO_SOURCE_IN_REPO = ()

ACTION_BLOCK = r"([ \t]*)\[(\d+)\] = \r?\n\1\{.*?\r?\n\1\}, -- end of \[\2\]\r?\n"
ACTIONS_ARRAY = r'\["actions"\] = \r?\n([ \t]*)\{\r?\n(.*?)\r?\n\1\}, -- end of \["actions"\]'


def read_all(path):
    with zipfile.ZipFile(path) as z:
        order = [i.filename for i in z.infolist()]
        return {n: z.read(n) for n in order}, order


def source_of(miz, member):
    """The repository file a `l10n/DEFAULT/*.lua` member is a copy of, or None.

    Looked up in the archive's own directory first, so `highdigitsams/` wins for its own scripts,
    then in `unit-tests/` for what the two archives share (`luaunit.lua` sits there and nowhere
    else).
    """
    name = member[len(L10N) :]
    if name == ARTIFACT:
        # Built, not committed, so it is missing on a fresh checkout until the build has run.
        return ARTIFACT_SOURCE if os.path.isfile(os.path.join(ROOT, ARTIFACT_SOURCE)) else None
    for folder in (os.path.dirname(miz), os.path.join("unit-tests")):
        candidate = os.path.join(folder, name)
        if os.path.isfile(os.path.join(ROOT, candidate)):
            return candidate
    return None


def normalised(blob):
    """Bytes with line endings flattened, for comparing a member against a working-tree file.

    The archives hold CRLF throughout, and so does a Windows checkout with `core.autocrlf=true` --
    but a CI runner checks the same files out with LF. Comparing raw bytes would report every
    script as drifted on Linux and none on Windows, which is worse than not comparing at all.
    """
    return blob.replace(b"\r\n", b"\n")


def comparable(name, blob):
    """`normalised`, plus the artifact's build stamp dropped so two builds can be compared."""
    blob = normalised(blob)
    if name == ARTIFACT:
        blob = BUILD_STAMP.sub(b"BUILD TIME: ---", blob, count=1)
    return blob


def parse_map_resource(text):
    return dict(re.findall(r'\["(ResKey_Action_\d+)"\]\s*=\s*"([^"]+)"', text))


def action_blocks(body):
    return list(re.finditer(ACTION_BLOCK, body, re.S))


def trigrules_of(mission):
    start = mission.find('["trigrules"]')
    if start < 0:
        raise SystemExit("FAIL: the mission has no trigrules section")
    return start, mission.find('-- end of ["trigrules"]', start)


def check_sources(miz, entries):
    """Every script in the archive is the file this repository ships. Returns a list of problems."""
    problems = []
    folder = os.path.dirname(miz)
    in_archive = set()

    for member in sorted(n for n in entries if n.startswith(L10N) and n.endswith(".lua")):
        name = member[len(L10N) :]
        source = source_of(miz, member)
        if source is None:
            if name == ARTIFACT:
                problems.append("%s has not been built -- run `%s`" % (ARTIFACT_SOURCE, BUILD_SCRIPT))
            elif name not in NO_SOURCE_IN_REPO:
                problems.append("%s has no copy in the repository to be checked against" % name)
            continue
        in_archive.add(os.path.normpath(source))
        with open(os.path.join(ROOT, source), "rb") as handle:
            if comparable(name, handle.read()) != comparable(name, entries[member]):
                problems.append("%s differs from %s -- run `miz-suite.py sync`" % (name, source))

    # The drift also runs the other way: a suite added to the repository and never baked in is a
    # test nobody runs, which is exactly how `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage`
    # sat outside the mission from August 2026.
    for entry in sorted(os.listdir(os.path.join(ROOT, folder))):
        if not entry.endswith(".lua"):
            continue
        loose = os.path.normpath(os.path.join(folder, entry))
        if loose not in in_archive:
            problems.append("%s is in the repository but no trigger in this archive loads it" % loose)

    return problems


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


def write_archive(miz, entries, order):
    with zipfile.ZipFile(os.path.join(ROOT, miz), "w", zipfile.ZIP_DEFLATED) as z:
        for name in order:
            if name in entries:
                z.writestr(name, entries[name])
    print("written: %s" % miz)


def do_check(miz, entries, sources=True):
    problems, _, compiled = check(entries)
    if sources:
        problems += check_sources(miz, entries)
    for p in problems:
        print("  -", p)
    if problems:
        return None
    mapping = parse_map_resource(entries[MAP_RESOURCE].decode("utf-8"))
    print("wiring consistent, %d scripts loaded in this order:" % len(compiled))
    for i, key in enumerate(compiled, start=1):
        print("  %2d. %s  (%s)" % (i, mapping[key], key))
    return compiled


def do_sync(miz, entries, order):
    """Write the repository's copy of every script back into the archive."""
    if L10N + ARTIFACT in entries and not os.path.isfile(os.path.join(ROOT, ARTIFACT_SOURCE)):
        print("FAIL: %s has not been built -- run `%s`" % (ARTIFACT_SOURCE, BUILD_SCRIPT))
        return 2
    # Wiring only: the source comparison is the thing this command is about to fix, so refusing to
    # run while it fails would make the command unable to do its job.
    if do_check(miz, entries, sources=False) is None:
        print("FAIL: the archive is already inconsistent; not touching it")
        return 2

    refreshed = []
    for member in sorted(n for n in entries if n.startswith(L10N) and n.endswith(".lua")):
        name = member[len(L10N) :]
        source = source_of(miz, member)
        if source is None:
            if name == ARTIFACT:
                print("FAIL: %s has not been built -- run `%s`" % (ARTIFACT_SOURCE, BUILD_SCRIPT))
                return 2
            continue
        with open(os.path.join(ROOT, source), "rb") as handle:
            wanted = handle.read()
        # Written as CRLF whatever the checkout looks like, so that syncing on Linux and syncing on
        # Windows produce the same archive. The rest of these files are CRLF already.
        wanted = normalised(wanted).replace(b"\n", b"\r\n")
        # Compared the way `check` compares, so that rebuilding the artifact -- which restamps its
        # first line every minute -- does not make every `sync` rewrite the archive for nothing.
        if comparable(name, wanted) != comparable(name, entries[member]):
            entries[member] = wanted
            refreshed.append("%s <- %s" % (name, source))

    if not refreshed:
        print("%s: already in sync" % miz)
        return 0

    for line in refreshed:
        print("  refreshed %s" % line)

    if do_check(miz, entries) is None:
        print("FAIL: the result would be inconsistent; nothing written")
        return 2
    write_archive(miz, entries, order)
    print("The wiring and the scripts' syntax are checked; whether DCS accepts the mission is not.")
    return 0


def do_remove(miz, entries, order, names):
    if do_check(miz, entries) is None:
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

    if do_check(miz, entries) is None:
        print("FAIL: the result would be inconsistent; nothing written")
        return 2
    write_archive(miz, entries, order)
    print("The wiring and the scripts' syntax are checked; whether DCS accepts the mission is not.")
    return 0


#: Archive members that are Lua without carrying the extension. `mission` and `mapResource` are
#: the two this tool edits, so they are the two it most needs parsed; `dictionary` and the rest
#: come along because they are Lua too and a corrupted one is just as fatal.
LUA_WITHOUT_EXTENSION = ("mission", "options", "warehouses", L10N + "mapResource", L10N + "dictionary")


def do_extract(miz, entries, target):
    """Write every Lua file in the archive to target/<archive name>/, flattening the paths.

    Members that are Lua but carry no extension get a `.lua` suffix, so a caller can parse the
    whole directory with one glob. Each archive gets its own subdirectory because both carry a
    `skynet-iads-compiled.lua` and one would otherwise silently overwrite the other.
    """
    target = os.path.join(target, os.path.basename(miz)[: -len(".miz")])
    if not os.path.isdir(target):
        os.makedirs(target)
    written = 0
    for name, blob in sorted(entries.items()):
        if name.endswith(".lua"):
            out = name.replace("/", "_")
        elif name in LUA_WITHOUT_EXTENSION:
            out = name.replace("/", "_") + ".lua"
        else:
            continue
        with open(os.path.join(target, out), "wb") as handle:
            handle.write(blob)
        written += 1
    print("extracted %d Lua files to %s" % (written, target))
    return 0


def selected(argv):
    """The archives to work on, and argv with `--miz <path>` taken out."""
    rest = list(argv)
    if "--miz" not in rest:
        return list(ARCHIVES), rest
    at = rest.index("--miz")
    if at + 1 >= len(rest):
        raise SystemExit("FAIL: --miz needs a path")
    wanted = os.path.normpath(rest[at + 1])
    del rest[at : at + 2]
    for miz in ARCHIVES:
        if os.path.normpath(miz) == wanted:
            return [miz], rest
    raise SystemExit("FAIL: %s is not one of the known archives: %s" % (wanted, ", ".join(ARCHIVES)))


def main(argv):
    if len(argv) < 2 or argv[1] not in ("check", "sync", "extract", "remove"):
        print(__doc__)
        return 1
    command = argv[1]
    archives, rest = selected(argv[2:])

    if command == "remove" and not rest:
        print("FAIL: remove needs at least one script name")
        return 1
    if command == "extract" and not rest:
        print("FAIL: extract needs a target directory")
        return 1

    status = 0
    for miz in archives:
        print("== %s" % miz)
        entries, order = read_all(os.path.join(ROOT, miz))
        if command == "check":
            status = max(status, 0 if do_check(miz, entries) is not None else 2)
        elif command == "sync":
            status = max(status, do_sync(miz, entries, order))
        elif command == "extract":
            status = max(status, do_extract(miz, entries, rest[0]))
        else:
            # `remove` names a script, and the same one (MiST) lives in both archives. Skipping the
            # archives that do not have it lets one command clear it everywhere.
            mapping = parse_map_resource(entries[MAP_RESOURCE].decode("utf-8"))
            present = [n for n in rest if n in mapping.values()]
            if not present:
                print("  - none of %s is in this archive; skipped" % ", ".join(rest))
                continue
            status = max(status, do_remove(miz, entries, order, present))
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
