#!/usr/bin/env python3
"""Build, check, or edit the mission archives.

Six `.miz` files carry scripts from this repository, and all six are handled here:

  * `unit-tests/skynet-unit-tests.miz`                                 the in-sim suite
  * `unit-tests/highdigitsams/highdigitsams-unit-tests.miz`            the same, for the mod
  * `unit-tests/last-line-of-defence/skynet-insim-last-line-of-defence.miz`   driven from outside
  * `demo-missions/skynet-test-persian-gulf.miz`                       the demo `documentation/` points at
  * `demo-missions/skynet-test-persian-gulf-stress-test.miz`           the same map, many more sites
  * `demo-missions/moose_a2a_connector/skynet-and-moose-a2a-dispatcher.miz`

The three under `unit-tests/` are developer material; the three under `demo-missions/` are what a
release attaches. Nothing else distinguishes them here.

**The archives in git do not contain the scripts they run.** Each holds a placeholder, and `build`
puts the real files in to produce the mission DCS opens. That is deliberate. A copy of the code
committed beside the code it copies goes stale without a sound: the two in-sim archives ran Skynet
3.3.0 from December 2023 to 2026-09-20 while `develop` moved to 3.5.0, so three years of in-sim runs
measured code this project had stopped shipping; three of the four demo missions carried 3.2 from the
same December, and those are what somebody downloads to learn what Skynet does. Nothing said so in
either case. An assembled mission cannot be out of date, and one opened unbuilt says so on screen
rather than quietly measuring, or demonstrating, the wrong thing.

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

A `mission` is Lua, and **two tools write it in two different shapes**. DCS writes `["trigrules"]`,
`["file"] = "X"` and a `-- end of [n]` comment after every block; VEAF's mission editor re-serialises
the same table as `trigrules`, `file = "X"` and no comments at all, and it can introduce resource
keys that are not `ResKey_Action_NNN` (`skynet-insim-last-line-of-defence.miz` carries
`MCP_MapKey_dcs-bridge`). Both are real and both are committed here, so every pattern below reads
either one. Assuming DCS's shape made this tool see that archive as having an empty `mapResource`.

Usage, from anywhere:

    python build-tools/miz-suite.py build              # assemble the playable missions
    python build-tools/miz-suite.py check              # wiring, and that git holds no copies
    python build-tools/miz-suite.py stub               # put placeholders back (adding a suite)
    python build-tools/miz-suite.py extract <dir>
    python build-tools/miz-suite.py remove test-skynet-iads-jammer.lua [...]

`build` writes to `build/missions/`, which is git-ignored, and needs the deliverable built first
(`pwsh -File build-tools/build-compiled-script.ps1`) because that is generated too. Copy what it
writes into the DCS `Missions` folder under `Saved Games` and open it there. The demo missions it
writes are what `.github/workflows/release.yml` attaches to a release.

Every command works on every archive unless `--miz <path>` narrows it to one. `remove`, `stub` and
`build` re-run the checks against the result and refuse to write if anything is off, so a failed run
leaves the `.miz` untouched. `extract` writes every Lua file to `<dir>/<archive name>/`, so
something that knows Lua can parse them; it is the one command that also accepts an assembled
mission under `build/missions/`, because that is what CI parses — the placeholders would prove
nothing.

What is left that only DCS can answer is narrow: whether the simulator accepts the mission file and
runs its triggers. The wiring, the syntax of every file inside, and whether git is holding a stale
copy of anything are all checked here.
"""

import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = "l10n/DEFAULT/"
MAP_RESOURCE = L10N + "mapResource"

#: Every archive carrying scripts from this repository, repository-relative.
ARCHIVES = (
    os.path.join("unit-tests", "skynet-unit-tests.miz"),
    os.path.join("unit-tests", "highdigitsams", "highdigitsams-unit-tests.miz"),
    os.path.join("demo-missions", "skynet-test-persian-gulf.miz"),
    os.path.join("demo-missions", "skynet-test-persian-gulf-stress-test.miz"),
    os.path.join("demo-missions", "moose_a2a_connector", "skynet-and-moose-a2a-dispatcher.miz"),
    os.path.join("unit-tests", "last-line-of-defence", "skynet-insim-last-line-of-defence.miz"),
)

#: The deliverable, which is what the in-sim suite actually exercises. It is generated, not
#: committed, so `build` needs it built first; `check` only needs to know where it would come from.
ARTIFACT = "skynet-iads-compiled.lua"
ARTIFACT_SOURCE = os.path.join("demo-missions", ARTIFACT)
BUILD_SCRIPT = "pwsh -File build-tools/build-compiled-script.ps1"

#: Where `build` writes the playable missions. Git-ignored: it is output, like the deliverable.
BUILD_DIR = os.path.join("build", "missions")

#: Scripts vendored from elsewhere, which have no copy in this repository. Anything baked into an
#: archive and not named here is reported until it is either given a copy here or added.
#:
#: These are the exception to everything below: `stub` leaves them alone, `check` does not ask them
#: to be placeholders, and `build` steps over them. They are committed inside the archive because
#: there is nowhere else for them to live -- MOOSE is 1.1 MB compressed and belongs to another
#: project, and the bridge is a development tool of VEAF's.
NO_SOURCE_IN_REPO = (
    "Moose.lua",  # github.com/FlightControl-Master/MOOSE, what the a2a-dispatcher demo demonstrates
    "dcs-bridge.lua",  # github.com/VEAF/dcs-bridge, how the last-line-of-defence check is driven
)

#: The line that marks a member as a placeholder rather than a copy of a script.
#:
#: The archives in git hold one of these for every script, and `build` swaps in the real files to
#: produce the mission DCS opens. That is the whole point: a copy committed next to the code it
#: copies goes stale silently, and both of these archives ran Skynet 3.3.0 from December 2023 to
#: 2026-09-20 with nothing saying so. A placeholder cannot go stale, and a mission opened unbuilt
#: says so on screen instead of quietly measuring the wrong thing.
PLACEHOLDER_MARK = "--SKYNET-PLACEHOLDER"

#: A resource key, as it appears in `mapResource` and in the trigger that loads it. DCS names them
#: `ResKey_Action_NNN`; VEAF's mission editor writes its own, such as `MCP_MapKey_dcs-bridge`, so
#: the shape is read rather than assumed.
KEY = r"[A-Za-z_][A-Za-z0-9_.-]*"

#: One `[n] = { ... }` entry of a trigrules `actions` array, in DCS's serialisation and then in the
#: editor's. Both are anchored on the indentation of the opening line, which is what keeps the
#: non-greedy body from stopping at a nested table's closing brace.
ACTION_BLOCKS = (
    r"(?P<indent>[ \t]*)\[(?P<n>\d+)\] = \r?\n(?P=indent)\{.*?\r?\n(?P=indent)\}, -- end of \[(?P=n)\]\r?\n",
    r"(?P<indent>[ \t]*)\[(?P<n>\d+)\] = \{.*?\r?\n(?P=indent)\},\r?\n",
)

#: A trigrules `actions` array, same two serialisations. `body` is the span the callers rewrite.
ACTIONS_ARRAYS = (
    r'\["actions"\] = \r?\n(?P<indent>[ \t]*)\{\r?\n(?P<body>.*?)\r?\n(?P=indent)\}, -- end of \["actions"\]',
    r"^(?P<indent>[ \t]*)actions = \{\r?\n(?P<body>.*?)\r?\n(?P=indent)\},",
)


def read_all(path):
    with zipfile.ZipFile(path) as z:
        order = [i.filename for i in z.infolist()]
        return {n: z.read(n) for n in order}, order


def source_folders(miz):
    """Where a member of this archive is looked for: its own directory, then the family's root.

    `unit-tests/highdigitsams/` wins for its own scripts and falls back to `unit-tests/`, where
    `luaunit.lua` sits and nowhere else; `demo-missions/moose_a2a_connector/` falls back to
    `demo-missions/` the same way. Before the demos joined, the fallback was `unit-tests/` spelled
    out -- which would have sent a demo looking for its setup script among the tests.
    """
    miz = os.path.normpath(miz)
    folders = [os.path.dirname(miz), miz.split(os.sep)[0]]
    return list(dict.fromkeys(folders))


def source_of(miz, member, must_exist=True):
    """The repository file a `l10n/DEFAULT/*.lua` member is a copy of, or None."""
    name = member[len(L10N) :]
    if name == ARTIFACT:
        # Built, not committed, so it is absent on a fresh checkout. `check` still wants to know
        # where it WOULD come from; only `build` needs it to be there.
        if must_exist and not os.path.isfile(os.path.join(ROOT, ARTIFACT_SOURCE)):
            return None
        return ARTIFACT_SOURCE
    for folder in source_folders(miz):
        candidate = os.path.join(folder, name)
        if os.path.isfile(os.path.join(ROOT, candidate)):
            return candidate
    return None


def stale_artifact():
    """Whether the built deliverable predates any source it is built from.

    `build` used to check only that the file existed. It is generated by a separate command, so
    forgetting that command assembled yesterday's Skynet into the mission and said `built:` -- the
    lot's own defect, shrunk from three years to one distracted session, but silent in the same way.
    """
    artifact = os.path.join(ROOT, ARTIFACT_SOURCE)
    if not os.path.isfile(artifact):
        return False  # absent is a different failure, reported with its own message
    built_at = os.path.getmtime(artifact)
    for folder, _, files in os.walk(os.path.join(ROOT, "skynet-iads-source")):
        for name in files:
            if name.endswith(".lua") and os.path.getmtime(os.path.join(folder, name)) > built_at:
                return True
    return False


def normalised(blob):
    """Bytes with line endings flattened, for comparing a member against a working-tree file.

    The archives hold CRLF throughout, and so does a Windows checkout with `core.autocrlf=true` --
    but a CI runner checks the same files out with LF. Comparing raw bytes would report every
    script as drifted on Linux and none on Windows, which is worse than not comparing at all.
    """
    return blob.replace(b"\r\n", b"\n")


def is_placeholder(blob):
    return normalised(blob).startswith(PLACEHOLDER_MARK.encode("utf-8"))


def placeholder(name, loud=False):
    """The stand-in a committed archive carries in place of a script.

    Valid Lua, because CI parses every file in the archive, and it says the same thing twice: in a
    comment for whoever opens the zip, and through `env.error` for whoever opens the mission without
    building it. Only the first one loaded shouts on screen -- ten popups would say it no better.
    """
    lines = [
        PLACEHOLDER_MARK,
        "--",
        "--This is not %s. The archives in git carry a placeholder for every script, and the real" % name,
        "--files are put in by:",
        "--",
        "--    python build-tools/miz-suite.py build",
        "--",
        "--which writes the mission to open in DCS. A copy of a script committed beside the script it",
        "--copies goes stale in silence -- the archives here carried Skynet 3.2 and 3.3.0, both from",
        "--December 2023, until 2026-09-20, and nothing said so. A placeholder cannot.",
        'env.error("SKYNET: this mission was opened unbuilt -- %s is a placeholder. Run: python build-tools/miz-suite.py build"%s)'
        % (name, ", true" if loud else ""),
        "",
    ]
    return "\r\n".join(lines).encode("utf-8")


def parse_map_resource(text):
    """Every `key = "file.lua"` in a mapResource, one entry per line.

    Read line by line rather than with one regex over the file because the two serialisations put
    the key differently -- `["ResKey_Action_172"]` from DCS, a bare `ResKey_Action_172` from the
    editor, and `["MCP_MapKey_dcs-bridge"]` from the editor again when the name needs quoting.
    """
    found = {}
    for line in text.splitlines():
        entry = re.match(r'\s*(?:\["(%s)"\]|(%s))\s*=\s*"([^"]*)"' % (KEY, KEY), line)
        if entry:
            found[entry.group(1) or entry.group(2)] = entry.group(3)
    return found


def first_matching(patterns, text, flags=re.S | re.M):
    """The matches of the first pattern that matches anything.

    The patterns are the same structure written by two tools, so at most one of them can match a
    given file -- trying them in turn is how this tool reads either without being told which.
    """
    for pattern in patterns:
        found = list(re.finditer(pattern, text, flags))
        if found:
            return found
    return []


def action_blocks(body):
    return first_matching(ACTION_BLOCKS, body)


def trigrules_of(mission):
    """The span of the trigrules section, in either serialisation."""
    head = re.search(r'^(?P<indent>[ \t]*)(?:\["trigrules"\]|trigrules)\s*=', mission, re.M)
    if head is None:
        raise SystemExit("FAIL: the mission has no trigrules section")
    end = mission.find('-- end of ["trigrules"]', head.end())
    if end < 0:
        # The editor writes no end-of-block comment, so the section runs to the next key at the
        # same indentation -- `version`, in the one archive that has it.
        nxt = re.compile(r"^%s\w+\s*=" % head.group("indent"), re.M).search(mission, head.end())
        end = nxt.start() if nxt else len(mission)
    return head.start(), end


def check_sources(miz, entries):
    """The committed archive holds a placeholder for every script. Returns the problems, and the
    set of repository files this archive loads.

    This used to compare each member against the file it copied, which meant a committed copy that
    had to be refreshed by hand -- and re-refreshed in every pull request that touched the sources,
    186 KB of binary at a time. The archives carry placeholders now and `build` puts the real
    files in, so there is nothing left to go stale and nothing to compare.

    The other direction -- a loose script no trigger loads -- is `unwired_loose_files`, run once
    over the whole set rather than per archive: three of them share `demo-missions/`, so asking one
    archive to account for every Lua file beside it reports the other two's scripts as orphans.
    """
    problems = []
    wired = set()

    for member in sorted(n for n in entries if n.startswith(L10N) and n.endswith(".lua")):
        name = member[len(L10N) :]
        if name in NO_SOURCE_IN_REPO:
            # Committed inside the archive as-is, and left alone by `stub` and `build`. A
            # placeholder here would be a file `build` never puts back: the mission would load a
            # stand-in for MOOSE and fail at the first `SET_GROUP:New()`.
            if is_placeholder(entries[member]):
                problems.append(
                    "%s is committed inside the archive and this one holds a placeholder for it -- "
                    "restore the archive from git. Nothing can put it back." % name
                )
            continue
        if not is_placeholder(entries[member]):
            problems.append(
                "%s is a real script in a committed archive -- run `miz-suite.py stub`. "
                "Committed archives hold placeholders; `build` makes the playable mission." % name
            )
        source = source_of(miz, member, must_exist=False)
        if source is None:
            problems.append("%s has no file in the repository for `build` to put in" % name)
            continue
        wired.add(os.path.normpath(source))
        if name != ARTIFACT and not os.path.isfile(os.path.join(ROOT, source)):
            problems.append("%s names %s, which is not in the repository" % (name, source))

    return problems, wired


def unwired_loose_files(wired):
    """Loose `.lua` files in the archives' source folders that no trigger anywhere loads.

    The drift runs this way too: a suite added to the repository and never baked in is a test
    nobody runs, which is how `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage` sat outside
    the mission from August 2026. `wired` is the union over every archive, because a folder can
    feed several -- `skynet-iads-setup-persian-gulf.lua` is loaded by two of them.
    """
    problems = []
    folders = []
    for miz in ARCHIVES:
        folders.extend(source_folders(miz))
    for folder in sorted(set(folders)):
        for entry in sorted(os.listdir(os.path.join(ROOT, folder))):
            if not entry.endswith(".lua") or entry == ARTIFACT:
                continue  # the deliverable is generated into demo-missions/, not a loose script
            loose = os.path.normpath(os.path.join(folder, entry))
            if loose not in wired:
                problems.append("%s is in the repository but no trigger in any archive loads it" % loose)
    return problems


def check(entries):
    """Every wiring invariant, asserted against an in-memory .miz. Returns a list of problems."""
    problems = []
    mapping = parse_map_resource(entries[MAP_RESOURCE].decode("utf-8"))
    mission = entries["mission"].decode("utf-8")

    compiled = re.findall(r'a_do_script_file\(getValueResourceByKey\(\\"(%s)\\"\)\)' % KEY, mission)
    start, end = trigrules_of(mission)
    trigrules = mission[start:end]
    editor = re.findall(r'(?:\["file"\]|(?<![\w.])file)\s*=\s*"(%s)"' % KEY, trigrules)
    referenced = set(compiled) | set(editor)

    for key in sorted(referenced):
        if key not in mapping:
            problems.append("mission references %s, which mapResource does not define" % key)
        elif L10N + mapping[key] not in entries:
            problems.append("%s names %s, which is not in the archive" % (key, mapping[key]))

    scripts = {n for n in entries if n.startswith(L10N) and n.endswith(".lua")}
    named = {L10N + v for k, v in mapping.items() if k in referenced}
    for orphan in sorted(scripts - named):
        problems.append("%s is in the archive but no trigger loads it" % orphan)

    if compiled != editor:
        problems.append(
            "trig.actions and trigrules disagree:\n    compiled: %s\n    editor:   %s" % (compiled, editor)
        )

    for am in first_matching(ACTIONS_ARRAYS, trigrules):
        idx = [int(b.group("n")) for b in action_blocks(am.group("body") + "\n")]
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


def drop_from_map_resource(map_text, key):
    """A mapResource with that key's line taken out, or None if there is no such line.

    The key is bracketed by DCS and bare by the editor -- except when it needs quoting, such as
    `MCP_MapKey_dcs-bridge`, which the editor brackets too. Reading only DCS's shape made `remove`
    refuse on the one archive the editor had written, which is how this came to be its own function.
    """
    quoted = re.escape(key)
    line = re.search(r'\r?\n[ \t]*(?:\["%s"\]|%s)\s*=[^\n]*\r?\n' % (quoted, quoted), map_text)
    if line is None:
        return None
    return map_text[: line.start()] + "\n" + map_text[line.end() :]


def drop_from_trigrules(mission, dead_keys):
    """Drop the trigrules action entries naming dead_keys, renumbering what is left."""
    start, end = trigrules_of(mission)
    section = mission[start:end]
    removed = 0
    # Collected first and applied back to front, so that each rewrite keeps the offsets of the
    # ones still to come. Replacing by matched text instead would rewrite the wrong trigger the
    # day two of them happen to hold the same actions.
    rewrites = []
    for am in first_matching(ACTIONS_ARRAYS, section):
        blocks = action_blocks(am.group("body") + "\n")
        if not blocks:
            continue
        kept = []
        for block in blocks:
            key = re.search(r'(?:\["file"\]|(?<![\w.])file)\s*=\s*"(%s)"' % KEY, block.group(0))
            if key and key.group(1) in dead_keys:
                removed += 1
            else:
                kept.append(block.group(0))
        renumbered = []
        for i, text in enumerate(kept, start=1):
            text = re.sub(r"^([ \t]*)\[\d+\] = ", r"\g<1>[%d] = " % i, text, count=1)
            text = re.sub(r"\}, -- end of \[\d+\]\r?\n$", "}, -- end of [%d]\n" % i, text, count=1)
            renumbered.append(text)
        rewrites.append((am.start("body"), am.end("body"), "".join(renumbered).rstrip("\n")))

    for begin, finish, text in reversed(rewrites):
        section = section[:begin] + text + section[finish:]
    return mission[:start] + section + mission[end:], removed


#: Every entry this tool writes is stamped with this instead of the current time.
#:
#: `writestr(name, blob)` stamps the minute it ran, so rewriting an archive whose contents did not
#: change still produced a different file -- a binary diff in the pull request for nothing, which is
#: the noise this whole design removes. 1980-01-01 00:00:00 is the earliest a zip can represent.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def write_zip(path, entries, order):
    """Write a zip deterministically: same contents in, same bytes out.

    `compress_type` has to be set on each ZipInfo. A ZipInfo built by hand defaults to ZIP_STORED
    and ignores the mode the ZipFile was opened with, which is silent and only visible on the scale:
    it took skynet-unit-tests.miz from 56 KB to 908 KB, a bigger file than the copies this design
    removed.
    """
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name in order:
            if name in entries:
                info = zipfile.ZipInfo(name, date_time=ZIP_EPOCH)
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, entries[name])


def write_archive(miz, entries, order):
    write_zip(os.path.join(ROOT, miz), entries, order)
    print("written: %s" % miz)


def do_check(miz, entries, sources=True, wired=None):
    """Every invariant that can be asserted against one archive. `wired` collects, across a run,
    the repository files the archives load -- `unwired_loose_files` reads it at the end."""
    problems, _, compiled = check(entries)
    if sources:
        source_problems, loaded = check_sources(miz, entries)
        problems += source_problems
        if wired is not None:
            wired.update(loaded)
    for p in problems:
        print("  -", p)
    if problems:
        return None
    mapping = parse_map_resource(entries[MAP_RESOURCE].decode("utf-8"))
    print("wiring consistent, %d scripts loaded in this order:" % len(compiled))
    for i, key in enumerate(compiled, start=1):
        print("  %2d. %s  (%s)" % (i, mapping[key], key))
    return compiled


def do_stub(miz, entries, order):
    """Put a placeholder in the committed archive for every script, replacing any real copy.

    Run when a suite is added to an archive, or once to convert an archive that still holds copies.
    Day to day nothing calls it: there is nothing to refresh, which is the point.
    """
    # Wiring only. Whether the archive holds copies is exactly what this command is here to fix.
    if do_check(miz, entries, sources=False) is None:
        print("FAIL: the archive is already inconsistent; not touching it")
        return 2

    stubbed = []
    for member in sorted(n for n in entries if n.startswith(L10N) and n.endswith(".lua")):
        name = member[len(L10N) :]
        if name in NO_SOURCE_IN_REPO:
            continue  # committed as-is: there is no source for `build` to put back over a stub
        # The artifact is loaded first by the mission, so its placeholder is the one that shouts.
        wanted = placeholder(name, loud=(name == ARTIFACT))
        if entries[member] != wanted:
            entries[member] = wanted
            stubbed.append(name)

    if not stubbed:
        print("%s: already stubbed" % miz)
        return 0
    for name in stubbed:
        print("  stubbed %s" % name)

    if do_check(miz, entries) is None:
        print("FAIL: the result would be inconsistent; nothing written")
        return 2
    write_archive(miz, entries, order)
    return 0


def do_build(miz, entries, order):
    """Write the playable mission: the committed archive with the real scripts put in.

    This is what replaces a committed copy of the code. The mission DCS opens is assembled from the
    sources at the moment it is asked for, so it cannot be out of date -- which is the whole defect
    this lot was opened for, and the reason nothing has to be remembered or re-committed.
    """
    if do_check(miz, entries, sources=False) is None:
        print("FAIL: the archive is inconsistent; not building from it")
        return 2
    if stale_artifact():
        print("FAIL: %s is older than the sources it is built from -- run `%s` first." % (ARTIFACT_SOURCE, BUILD_SCRIPT))
        print("      Assembling from it would put yesterday's Skynet in the mission, which is the")
        print("      defect this whole design exists to prevent -- three years of it, once.")
        return 2

    built = []
    for member in sorted(n for n in entries if n.startswith(L10N) and n.endswith(".lua")):
        name = member[len(L10N) :]
        if name in NO_SOURCE_IN_REPO:
            continue  # already in the archive, and there is nowhere else it could come from
        source = source_of(miz, member)
        if source is None:
            if name == ARTIFACT:
                print("FAIL: %s has not been built -- run `%s`" % (ARTIFACT_SOURCE, BUILD_SCRIPT))
                return 2
            print("FAIL: %s has no file in the repository to put in" % name)
            return 2
        with open(os.path.join(ROOT, source), "rb") as handle:
            # CRLF whatever the checkout looks like, so a mission built on Linux and one built on
            # Windows are the same file.
            entries[member] = normalised(handle.read()).replace(b"\n", b"\r\n")
        built.append("%s <- %s" % (name, source))

    if do_check(miz, entries, sources=False) is None:
        print("FAIL: the assembled mission would be inconsistent; nothing written")
        return 2

    out = os.path.join(ROOT, BUILD_DIR)
    if not os.path.isdir(out):
        os.makedirs(out)
    target = os.path.join(out, os.path.basename(miz))
    write_zip(target, entries, order)
    for line in built:
        print("  put in %s" % line)
    print("built: %s" % os.path.relpath(target, ROOT))
    return 0


def do_remove(miz, entries, order, names):
    # Removing a script leaves its loose copy on disk until somebody deletes it, and the archive is
    # meant to be in that state for the length of this command. The scan that reports an unloaded
    # loose file is `unwired_loose_files`, which only `check` runs -- so it is the reminder to
    # remove both copies, and it is not in the way here.
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

        map_text = drop_from_map_resource(map_text, key)
        if map_text is None:
            print("FAIL: no mapResource line for %s" % key)
            return 2

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
    for name in names:
        # Every folder this archive draws from, not just its own: MiST sat in demo-missions/ while
        # one of the archives loading it sat in demo-missions/moose_a2a_connector/, so a reminder
        # looking only beside the .miz said nothing for it.
        for folder in source_folders(miz):
            loose = os.path.join(folder, name)
            if os.path.isfile(os.path.join(ROOT, loose)):
                print("NOTE: %s is still in the repository. A script is removed from BOTH copies." % loose)
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


def selected(argv, command=None):
    """The archives to work on, and argv with `--miz <path>` taken out.

    `extract` may also be pointed at an assembled mission under `build/missions/`, because that is
    what CI needs to parse -- the placeholders in the committed archives would prove nothing. Every
    other command edits the repository and is restricted to the archives it knows.
    """
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
    if command == "extract" and wanted.startswith(os.path.normpath(BUILD_DIR)) and os.path.isfile(
        os.path.join(ROOT, wanted)
    ):
        return [wanted], rest
    raise SystemExit("FAIL: %s is not one of the known archives: %s" % (wanted, ", ".join(ARCHIVES)))


def main(argv):
    if len(argv) < 2 or argv[1] not in ("check", "build", "stub", "extract", "remove"):
        print(__doc__)
        return 1
    command = argv[1]
    archives, rest = selected(argv[2:], command)

    if command == "remove" and not rest:
        print("FAIL: remove needs at least one script name")
        return 1
    if command == "extract" and not rest:
        print("FAIL: extract needs a target directory")
        return 1

    status = 0
    found_somewhere = set()
    wired = set()
    for miz in archives:
        print("== %s" % miz)
        entries, order = read_all(os.path.join(ROOT, miz))
        if command == "check":
            status = max(status, 0 if do_check(miz, entries, wired=wired) is not None else 2)
        elif command == "build":
            status = max(status, do_build(miz, entries, order))
        elif command == "stub":
            status = max(status, do_stub(miz, entries, order))
        elif command == "extract":
            status = max(status, do_extract(miz, entries, rest[0]))
        else:
            # `remove` names a script, and the same one can live in several archives -- MiST was in
            # all six. Skipping the archives that do not have it lets one command clear it
            # everywhere.
            mapping = parse_map_resource(entries[MAP_RESOURCE].decode("utf-8"))
            present = [n for n in rest if n in mapping.values()]
            found_somewhere.update(present)
            if not present:
                print("  - none of %s is in this archive; skipped" % ", ".join(rest))
                continue
            status = max(status, do_remove(miz, entries, order, present))

    # Which loose scripts nothing loads can only be told once every archive has been read, because
    # a folder feeds several of them: `skynet-iads-setup-persian-gulf.lua` is loaded by two. Skipped
    # when `--miz` narrowed the run, since the rest of the answer was never gathered.
    if command == "check" and len(archives) == len(ARCHIVES):
        orphans = unwired_loose_files(wired)
        for orphan in orphans:
            print("  -", orphan)
        if orphans:
            status = max(status, 2)

    # A name in no archive at all is a typo, and skipping every archive for it used to exit 0 --
    # the command reported success for having done nothing, which is how a removal gets believed.
    missing = [n for n in rest if n not in found_somewhere] if command == "remove" else []
    if missing:
        print("FAIL: %s is in no archive; nothing was removed for it" % ", ".join(missing))
        status = max(status, 2)
    if command == "build" and status == 0:
        print("\nCopy the mission you want into the DCS Missions folder under Saved Games.")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
