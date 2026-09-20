#!/usr/bin/env python3
"""Generate test/lua/dcs-figures.lua from the DCS data dump, and check it has not drifted.

The problem this answers: **Skynet's tests used to pin figures that belong to Eagle Dynamics.**
`test-skynet-iads-red-sam-sites-and-ew-radars.lua` asserted that the SA-11's missile reaches
35000 m. ED has since made it 46000, so in every mission a Buk battery now wakes 11 km further
out than it used to, and nothing in this project said so -- the assertion only went red when
somebody ran the in-sim mission in DCS, which nobody had done since December 2023.

Rather than pin those numbers harder, this records them. `Quaggles/dcs-lua-datamine` publishes
the dumped DCS database tables; this reads them at a **pinned** commit and writes a committed Lua
table. Two guards then do the work nobody was doing by hand:

  * `check` regenerates against the pin and fails on any difference, so the committed file cannot
    drift from the ref it claims to come from (`.github/workflows/lua-tests.yml`);
  * `.github/workflows/dcs-data-drift.yml` bumps the pin weekly and opens a pull request, whose
    diff says exactly which figure moved.

Usage, from anywhere:

    python build-tools/dcs-figures.py generate
    python build-tools/dcs-figures.py check

## What it records, and what it cannot

**Radars: by unit.** `skynet-iads-supported-types.lua` (`samTypesDB`) names the DCS *type* of every
radar Skynet models. Each one has a file under `_G/db/Units/`, and that file names its sensor
(`Sensors = { RADAR = { "SA-11 Buk TR" } }`), which has its own file under `_G/db/Sensors/Sensor/`
carrying `detection_distance`. Both hops are real links in the data. **34 of the 36** unit types
`samTypesDB` names resolve; the two that do not are `Strela-1 9P31` and `Strela-10M3`, which have no
radar at all -- they are infrared -- and are correct to be missing. (An earlier draft of this
paragraph said 32 of 35, which was the count produced by the non-greedy regex `balanced_block`
replaced -- a comment still teaching the defect below it.)

**Missiles: by missile, not by launcher.** `_G/rockets/<missile>.lua` carries `Range_max` and
`H_max`, which is exactly what `SkynetIADSSAMLauncher:getRange()` and `getMaximumFiringAltitude()`
report. What the dump does NOT carry is which launcher fires which missile: that link lives in
`WS[].LN[].PL[].type_ammunition`, and Quaggles' exporter prunes it -- empty on 50 of the 61 ground
units that have one, "Redacted" on the rest. Measured 2026-09-20, not assumed.

So every missile is recorded, unfiltered, and the reader makes the connection from the name: the
entry that moved from 35000 to 46000 is called "9M38M1 Buk-M1 (SA-11 Gadfly)". Filtering to just
the surface-to-air ones would mean guessing from the `_file` path an ED source file happens to have,
and a filter that misses a SAM costs more than a few hundred lines nobody reads.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join("test", "lua", "dcs-figures.lua")
SUPPORTED_TYPES = os.path.join("skynet-iads-source", "skynet-iads-supported-types.lua")

DATAMINE_REPO = "https://github.com/Quaggles/dcs-lua-datamine.git"

#: Pinned upstream commit. Bump it (and regenerate) to pick up a newer DCS data dump. Shared with
#: VEAF-Mission-Creation-Tools, which pins the same dataset for its own units database.
DATAMINE_REF = "fe1d8008e6e8dc4c1c4e85558cd1b0b29a02da3f"

#: Only these subtrees are checked out, which keeps the clone small.
SPARSE_PATHS = ["_G/db/Sensors", "_G/db/Units", "_G/rockets"]

#: A git ref only ever holds these characters; reject anything else before handing it to git.
SAFE_REF = re.compile(r"^[0-9A-Za-z._/-]+$")

#: Unit types `samTypesDB` lists as radars that genuinely carry none -- infrared SAMs, where Skynet
#: falls back to a default range. Listed so that a radar going missing for any OTHER reason is a
#: failure rather than a silent gap.
RADARLESS_BY_DESIGN = ("Strela-1 9P31", "Strela-10M3")

#: DCS reports a sensor's air detection range against a reference target, not the raw figure in the
#: database: detection range goes as the fourth root of the target's radar cross-section, and the
#: reference is 0.2 m2. So `detectionDistanceAir = detection_distance * 0.2^0.25`.
#:
#: Checked against the two figures a real DCS run reported on 2026-09-20 -- SA-11 SR 9S18M1
#: (100000 -> 66874.03125) and ZSU-23-4 Shilka (7500 -> 5015.552734375). Both land exactly, but only
#: when the arithmetic is done the way DCS does it, in **single precision**: rounding 0.2^0.25 to a
#: 32-bit float and multiplying in 32-bit gives both figures bit for bit. In double precision the
#: SA-11 still lands and the Shilka misses by 4.5e-4 -- one unit in the last place of a 32-bit float
#: at that magnitude, which is what gave it away. Lua is double precision, so the test asserts the
#: relation to a relative tolerance rather than to equality.
#:
#: Recorded here and asserted in test/lua/test_dcs_figures.lua rather than baked into the generated
#: figures, so that what this file commits stays the raw fact the dataset states.
REFERENCE_RCS = 0.2

TOP_LEVEL = r"^\t%s\s*=\s*%s"


def run_git(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True)  # nosec B603


def clone_datamine(dest, ref=DATAMINE_REF):
    """Sparse-clone the datamine at a pinned ref. Only SPARSE_PATHS are materialised."""
    if not SAFE_REF.match(ref):
        raise SystemExit("FAIL: unsafe datamine ref: %r" % ref)
    os.makedirs(dest, exist_ok=True)
    run_git("git", "init", "-q", cwd=dest)
    run_git("git", "remote", "add", "origin", DATAMINE_REPO, cwd=dest)
    run_git("git", "sparse-checkout", "init", "--cone", cwd=dest)
    run_git("git", "sparse-checkout", "set", *SPARSE_PATHS, cwd=dest)
    run_git("git", "fetch", "-q", "--depth=1", "--filter=blob:none", "origin", ref, cwd=dest)
    run_git("git", "checkout", "-q", "FETCH_HEAD", cwd=dest)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def number(text, field):
    """A top-level numeric field of a dumped DCS table, or None.

    Anchored on a single leading tab: the dump indents top-level fields with one, and nested ones
    with more, so this cannot pick up a same-named field from inside a sub-table.
    """
    m = re.search(TOP_LEVEL % (re.escape(field), r"([0-9.eE+-]+)"), text, re.M)
    if not m:
        return None
    value = float(m.group(1))
    return int(value) if value == int(value) else value


def string(text, field):
    m = re.search(TOP_LEVEL % (re.escape(field), r'"([^"]*)"'), text, re.M)
    return m.group(1) if m else None


def index_files(root, *relative):
    """Every .lua under those subtrees, keyed by file name without the extension.

    That name is the DCS type name -- what `unit:getTypeName()` answers and what `samTypesDB` is
    keyed on -- which is what makes the walk from a Skynet type to its data a lookup rather than a
    guess.
    """
    found = {}
    for rel in relative:
        for folder, _, files in os.walk(os.path.join(root, *rel.split("/"))):
            for name in files:
                if name.endswith(".lua"):
                    found.setdefault(name[: -len(".lua")], os.path.join(folder, name))
    return found


def balanced_block(text, brace):
    """The text between the brace at `brace` and the one that closes it.

    Written by counting braces after a non-greedy regex quietly read only the FIRST entry of each
    block: `["searchRadar"] = { ["a"] = { ... }, ["b"] = { ... } }` closes its first sub-table
    before it closes itself, so `.*?\\n\\t+\\},` stopped there. It found 34 radar types where there
    are 36, and 34 is plausible enough that nothing looked wrong. The two that went missing only
    surfaced because test/lua/test_dcs_figures.lua checks this list against the one Lua reads.
    """
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1 : i]
    raise SystemExit("FAIL: unbalanced braces in %s" % SUPPORTED_TYPES)


def top_level_keys(block):
    """The `["key"] = {` names at this block's own level, ignoring anything nested inside them.

    A radar entry holds `["name"] = { ["NATO"] = ... }`, which is a label rather than a unit type,
    so depth matters.
    """
    keys, depth = [], 0
    for token in re.finditer(r'\["([^"]+)"\]\s*=\s*\{|\{|\}', block):
        if token.group(0) == "}":
            depth -= 1
        elif token.group(1) is not None:
            if depth == 0:
                keys.append(token.group(1))
            depth += 1
        else:
            depth += 1
    return keys


def radar_unit_types():
    """Every DCS unit type `samTypesDB` lists under searchRadar or trackingRadar.

    This is the list the figures have to cover, and it is checked from the other side as well:
    test/lua/test_dcs_figures.lua walks the real samTypesDB in Lua and fails on anything the
    generated file is missing, so a parsing slip here cannot pass unnoticed twice.
    """
    text = read(os.path.join(ROOT, SUPPORTED_TYPES))
    names = set()
    for role in ("searchRadar", "trackingRadar"):
        for m in re.finditer(r'\["%s"\]\s*=\s*\{' % role, text):
            names.update(top_level_keys(balanced_block(text, m.end() - 1)))
    return sorted(names)


def collect_radars(dump):
    """{unit type -> (sensor name, detection_distance)} for the radars Skynet models."""
    units = index_files(dump, "_G/db/Units")
    sensors = index_files(dump, "_G/db/Sensors/Sensor")
    radars, missing = {}, []

    for unit_type in radar_unit_types():
        path = units.get(unit_type)
        if path is None:
            missing.append("%s: no unit in the dump" % unit_type)
            continue
        m = re.search(r"RADAR = (\{[^}]*\}|\"[^\"]*\")", read(path))
        if m is None:
            if unit_type not in RADARLESS_BY_DESIGN:
                missing.append("%s: the unit declares no RADAR sensor" % unit_type)
            continue
        for sensor_name in re.findall(r'"([^"]+)"', m.group(1)):
            sensor_path = sensors.get(sensor_name)
            if sensor_path is None:
                missing.append("%s: sensor %r is not in the dump" % (unit_type, sensor_name))
                continue
            distance = number(read(sensor_path), "max_measuring_distance")
            # detection_distance is a nested table of per-aspect figures whose entries are equal in
            # every SAM sensor seen so far; max_measuring_distance is the same number as a scalar,
            # except on a few trackers where it is larger. Read the table's first figure, and keep
            # max_measuring_distance only as the fallback.
            nested = re.search(r"detection_distance = \{ \{ ([0-9.]+)", read(sensor_path))
            if nested:
                distance = number("\t_ = " + nested.group(1), "_")
            if distance is None:
                missing.append("%s: sensor %r states no detection distance" % (unit_type, sensor_name))
                continue
            # Keyed by both, because a unit may declare several radar sensors and all of them are
            # worth recording. The rendered Lua table is keyed by unit type alone, though, so two
            # sensors on one unit would emit two entries under the same key -- Lua takes the last
            # and nothing goes red. Reported here instead of written out quietly; no unit at the
            # current pin does it, so this is a trap set for a future bump rather than a bug today.
            if unit_type in {u for u, _, _ in radars.values()}:
                missing.append(
                    "%s declares more than one radar sensor (%s); the generated table is keyed by "
                    "unit type and cannot hold both" % (unit_type, sensor_name)
                )
                continue
            radars["%s|%s" % (unit_type, sensor_name)] = (unit_type, sensor_name, distance)
    return radars, missing


def collect_missiles(dump):
    """{name -> (display name, Range_max, H_max)} for every missile in the dump."""
    missiles = {}
    for name, path in sorted(index_files(dump, "_G/rockets").items()):
        text = read(path)
        range_max = number(text, "Range_max")
        # No reach stated, or stated as zero, is nothing to watch: a figure that is already zero
        # cannot move in a way that changes when a battery wakes. One entry is dropped this way at
        # the current pin -- the V-1 flying bomb -- and the floor below catches it if that ever
        # becomes many.
        if not range_max:
            continue
        missiles[name] = (string(text, "display_name") or name, range_max, number(text, "H_max"))
    return missiles


def lua_string(value):
    return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')


def render(ref, radars, missiles):
    out = [
        "--- Figures DCS states about the units Skynet models. GENERATED -- DO NOT EDIT BY HAND.",
        "--",
        "-- Written by `python build-tools/dcs-figures.py generate` from the DCS database dump at",
        "-- Quaggles/dcs-lua-datamine, commit %s. CI regenerates this and fails on any" % ref[:12],
        "-- difference, and a weekly workflow bumps the pin and opens a pull request -- whose diff is",
        "-- the point of this file. It is how anyone finds out that ED moved a figure: the SA-11's",
        "-- missile went from 35000 m to 46000 m at some point between December 2023 and September",
        "-- 2026, which changes how far out a Buk battery wakes in every mission, and nothing here",
        "-- noticed.",
        "--",
        "-- These are what the pinned dump says, not what the player's install says. A mission runs",
        "-- whatever DCS version it runs; this file is a record to compare against, not a promise.",
        "--",
        "-- `radars` is keyed by DCS unit type, taken from samTypesDB, and `detectionDistance` is the",
        "-- raw figure in the sensor's database entry. What the DCS API reports to Skynet is that",
        "-- figure scaled for the reference target's radar cross-section: detection range goes as the",
        "-- fourth root of that cross-section, and the reference is `referenceRcs` below, so the API",
        "-- answers `detectionDistance * referenceRcs^0.25`. DCS evaluates that in single precision;",
        "-- test/lua/test_dcs_figures.lua asserts it to a tolerance against two figures a real DCS run",
        "-- reported, because Lua is double precision.",
        "--",
        "-- `missiles` is keyed by DCS weapon name and holds every missile in the dump, not only the",
        "-- surface-to-air ones: the dump prunes the link between a launcher and its missile, so there",
        "-- is nothing to filter on that would not be a guess. `range` is `Range_max`, which is what",
        "-- SkynetIADSSAMLauncher:getRange() reports; `maxAltitude` is `H_max`, which is what",
        "-- getMaximumFiringAltitude() reports.",
        "",
        "return {",
        "\tdatamineRef = %s," % lua_string(ref),
        "\treferenceRcs = %s," % REFERENCE_RCS,
        "",
        "\tradars = {",
    ]
    for _, (unit_type, sensor_name, distance) in sorted(radars.items()):
        out.append(
            "\t\t[%s] = { sensor = %s, detectionDistance = %s },"
            % (lua_string(unit_type), lua_string(sensor_name), distance)
        )
    out += ["\t},", "", "\tmissiles = {"]
    for name, (display, range_max, alt_max) in sorted(missiles.items()):
        out.append(
            "\t\t[%s] = { displayName = %s, range = %s, maxAltitude = %s },"
            % (lua_string(name), lua_string(display), range_max, "nil" if alt_max is None else alt_max)
        )
    out += ["\t},", "}", ""]
    return "\n".join(out)


def generate(ref=DATAMINE_REF):
    import tempfile

    with tempfile.TemporaryDirectory() as dump:
        clone_datamine(dump, ref)
        radars, missing = collect_radars(dump)
        missiles = collect_missiles(dump)

    if missing:
        for problem in missing:
            print("  -", problem)
        raise SystemExit(
            "FAIL: %d radar(s) could not be resolved. Either samTypesDB names a type the dump does\n"
            "      not have, or the dump changed shape -- do not commit figures with holes in them." % len(missing)
        )
    # A floor, not a count: a regex that silently stops matching produces a plausible, empty file.
    if len(radars) < 25 or len(missiles) < 150:
        raise SystemExit(
            "FAIL: %d radars and %d missiles is far below what this dump holds; the parsing\n"
            "      probably stopped matching." % (len(radars), len(missiles))
        )
    return render(ref, radars, missiles), len(radars), len(missiles)


def bump(ref):
    """Rewrite DATAMINE_REF in this file. Answers whether it changed.

    Done here rather than with a `sed` in the workflow because a textual replacement that matches
    nothing exits zero: the pin would stay put while every later step reported success, and a robot
    with nothing to say is indistinguishable from one that has been silenced.
    """
    if not SAFE_REF.match(ref) or len(ref) != 40:
        raise SystemExit("FAIL: %r is not a 40-character commit sha" % ref)
    if ref == DATAMINE_REF:
        return False
    me = os.path.abspath(__file__)
    with open(me, encoding="utf-8") as handle:
        text = handle.read()
    needle = 'DATAMINE_REF = "%s"' % DATAMINE_REF
    if text.count(needle) != 1:
        raise SystemExit("FAIL: expected exactly one %s, found %d" % (needle, text.count(needle)))
    with open(me, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text.replace(needle, 'DATAMINE_REF = "%s"' % ref))
    print("pin: %s -> %s" % (DATAMINE_REF[:12], ref[:12]))
    return True


def main(argv):
    if len(argv) < 2 or argv[1] not in ("generate", "check", "bump"):
        print(__doc__)
        return 1

    if argv[1] == "bump":
        if len(argv) < 3:
            print("FAIL: bump needs a commit sha")
            return 1
        if not bump(argv[2]):
            print("pin already at %s; nothing to do" % DATAMINE_REF[:12])
            return 0
        print("now run `python build-tools/dcs-figures.py generate`")
        return 0

    rendered, radars, missiles = generate()
    target = os.path.join(ROOT, OUTPUT)

    if argv[1] == "generate":
        with open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(rendered)
        print("written: %s (%d radars, %d missiles, ref %s)" % (OUTPUT, radars, missiles, DATAMINE_REF[:12]))
        return 0

    if not os.path.isfile(target):
        print("FAIL: %s does not exist -- run `python build-tools/dcs-figures.py generate`" % OUTPUT)
        return 2
    # Line endings normalised: a Windows checkout with core.autocrlf=true holds CRLF, a CI runner
    # holds LF, and this compares content rather than checkouts.
    with open(target, "rb") as handle:
        committed = handle.read().replace(b"\r\n", b"\n")
    if committed != rendered.encode("utf-8"):
        print("FAIL: %s does not match the datamine at %s." % (OUTPUT, DATAMINE_REF[:12]))
        print("      Run `python build-tools/dcs-figures.py generate` and commit the result.")
        print("      If figures changed, that is the news -- read the diff before committing it.")
        return 2
    print("%s matches the datamine at %s (%d radars, %d missiles)" % (OUTPUT, DATAMINE_REF[:12], radars, missiles))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
