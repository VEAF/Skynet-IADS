# In-sim tests

Scenarios that run inside a live DCS mission, for behaviour that needs a real simulator: radar
detection, terrain, coalition data, genuine emission-state changes. For fast logic tests with no
DCS, see `test/lua/`.

Design: [docs/superpowers/specs/2026-09-15-insim-test-tier-design.md](../../docs/superpowers/specs/2026-09-15-insim-test-tier-design.md)

## One-time setup

**1. Unlock the mission scripting environment.** Comment out the sanitization block in
`<DCS install>/Scripts/MissionScripting.lua`:

```lua
do
	--sanitizeModule('os')
	--sanitizeModule('io')
	--sanitizeModule('lfs')
	--_G['require'] = nil
	--_G['loadlib'] = nil
	--_G['package'] = nil
end
```

This is the same edit MOOSE, MIST and CTLD have always needed. Be aware:

- It is **install-wide**, not scoped to this mission.
- It affects **multiplayer integrity checks**.
- **DCS updates and repairs silently revert it.** When that happens the mission puts
  "re-apply the MissionScripting.lua edit" on screen rather than failing obscurely.

To revert: restore the file, or run a DCS repair.

**2. Point the mission at your checkout.** Create
`%USERPROFILE%\Saved Games\DCS\Config\skynet-insim.lua` containing one line:

```lua
return [[D:\Projects\DcsLua\Skynet-IADS]]
```

Saved Games survives DCS updates, and keeping the path here rather than in the `.miz` means the
committed mission works against anyone's checkout.

**3. Make mission diffs readable** (optional, recommended). A `.miz` is a zip whose `mission`
entry is plain Lua. `.gitattributes` already declares the driver; enable it once per clone:

```bash
git config diff.miz.textconv "unzip -p"
```

`git diff test/insim/skynet-insim.miz` then shows the mission text — units, coordinates, zones
and triggers — instead of "binary files differ".

## Running

1. Launch `test/insim/skynet-insim.miz` in DCS.
2. Take the **Neutral Game Master** slot — the map view shows added fixtures, wrecks and unit
   positions while a scenario runs. Neutral so it sees both coalitions.
3. **F10 → Skynet Tests → Run all**.

Each test result appears on screen as it happens, so a long scenario shows progress rather than
a silent screen. The full picture lands in three places:

```
dcs.log                                     every line, tagged SKYNET_INSIM, written live
test/insim/results/last-run.lua             the run that just finished
test/insim/results/archive/<stamp>-PASS.lua the same run, kept
```

Both files hold the same thing: counts, every test with its **duration** and — when it failed —
the **phase** that raised, plus the run's whole timeline. Durations are the number to read on a
green run: 41.3 s of a 450 s budget and 448 s of it are both "pass" and mean very different
things.

Nothing is ever overwritten but `last-run.lua`, so the archive is the history of every run you
have made. It is gitignored and each file is a few KB; delete the directory whenever you like.

Every run re-reads Skynet source and scenario files from disk, so **editing a scenario and
pressing F10 again is the whole edit→run loop** — no mission restart, no Mission Editor.

Two things that do need a restart:

- A **newly added** scenario file does not appear under "Run one suite", which is built once at
  mission start. "Run all" re-discovers, so only the per-suite menu is stale.
- A long session accumulates wrecks outside any arena zone. Restarting is the hard reset.

## Fixtures

Fixtures are the late-activated groups in `skynet-insim.miz`. There is no fixture file and
nothing to generate: a scenario reads a group's own definition out of `env.mission` — the whole
mission table, which DCS exposes to any mission script — and adds it.

```lua
InsimTestTools.addFromMission("SKY-Z01-SA6-01")     -- ground/static, exactly as placed
```

**Only `SKY-` groups are fixtures.** A scenario may add or destroy those and nothing else, so
anything you do not prefix — a playable slot, an observer, scenery, a group half-built in the
editor — is protected by default. Forgetting to mark something makes it safer, not more
exposed. Within the prefix, names are free-form; the one rule is that they match the `.miz`
exactly, case included. A mismatch says `missionGroupData: no group named '...'`.

A group with a `Client` or `Player` unit is **never** a fixture, whatever it is named. That is
the second, independent guard: a naming convention cannot catch a slot that accidentally got the
prefix, and the cost of that mistake is a player thrown back to the slot screen mid-flight.
`addFromMission` refuses such a group outright, and `destroyAllFixtures()` skips it.

The scheme in use keys ground fixtures to their arena and leaves air assets free:

```
SKY-Z01              the arena zone (must be CIRCULAR — see below)
SKY-Z01-EWR-01       ground, inside that zone
SKY-Z01-SA6-01       ground, inside that zone
SKY-AIR-F18-01       air, parked anywhere — belongs to no zone
```

When picking prefixes, keep the ones you hand to Skynet's `addSAMSitesByPrefix` and
`addEarlyWarningRadarsByPrefix` **disjoint**. They match on a raw string prefix, so `SKY-Z01`
would sweep up the EWR and the SAM together.

### Adding a ground fixture

Place it in the Mission Editor, inside its arena zone, tick **Late Activation**, save. It is
added exactly where you put it, so position it for the test — an EWR needs line of sight to
where the target will fly, and a valley between them fails the scenario for reasons that have
nothing to do with Skynet.

### Adding an air fixture

An aircraft parked in the editor is useless without a route, and a route authored in the editor
is wrong the moment a scenario wants different geometry. So an air fixture supplies **airframes
only** — type, count, skill, country — and the scenario supplies everything else:

```lua
local ewr = InsimTestTools.missionGroupData("SKY-Z01-EWR-01")

InsimTestTools.addAirFromMission("SKY-AIR-F18-01", {
  from     = InsimTestTools.offsetFrom(ewr, 270, 60000),  -- 60 km due west of the EWR
  to       = InsimTestTools.offsetFrom(ewr, 90,  20000),  -- flying through, 20 km past
  altitude = 6000,                                        -- metres, BARO
  speed    = 200,                                         -- METRES PER SECOND (~390 kt)
})
```

Author it as an **In Air** start with a **single** turning point, task **Nothing**, parked
anywhere. Its own coordinates, altitude and waypoint are ignored. Not a ramp or runway start: a
ground start carries an `airdromeId` on its first waypoint, which is meaningless once the group
is placed somewhere else.

Because the scenario owns the geometry, one airframe template can serve several scenarios.

`speed` is metres per second, as the mission table stores it. Writing `400` meaning knots gives
you 778 kt and it will not be rejected.

### Playable slots

Slots are what make a human observation possible — sitting in a cockpit to watch an RWR is the
only way to settle some questions the tier cannot assert. Add as many as you need; the rules
above mean a scenario will never despawn one.

Two things a scenario cannot do for you: the aircraft has to be somewhere useful when the event
happens, and nothing in `results/last-run.lua` will record what you saw. Automation for the
setup, eyes for the verdict.

### Arena zones

Draw the zone as a **circle**. `removeJunkInZone` reads its radius, and a quad-point zone can
report 0. Size it to cover the ground fixtures plus where their debris will scatter, and keep
scenarios far enough apart that one arena never reaches another's fixtures.

## Writing a scenario

A scenario file returns `{ name = ..., suite = ... }`. The suite is luaunit-shaped —
`setUp`, `tearDown`, and `test*` functions — but the runner, not luaunit, drives it, so test
bodies may wait for sim time:

```lua
waitFor(function() return sam:isActive() end, 60)   -- yields until true, fails after 60s
waitSeconds(30)                                     -- yields for 30 sim-seconds
log("target airborne %d km out at %d m", 60, 6000)  -- one timeline line, formatted
```

`log` is a global like the waits. The runner already records the skeleton — run start, each
test, every wait and how long it really took, each result — so `log` is for the part only the
scenario knows: what was placed where, and what just happened. Lines are stamped with seconds
since the run began and tagged with the scenario name:

```
t=   0.4 [Detection] SKY-AIR-F18-01 airborne 60 km out on bearing 270, 6000 m, 200 m/s
t=   0.4 waitFor(450s) started
t=  41.7 waitFor satisfied after 41.3s
t=  41.8 PASS Detection.testSAMGoesLiveWhenTheEWRDetectsATarget (41.5s)
```

Do not call `log` from a `waitFor` predicate — predicates run on every tick, ten times a second.

Every wait is bounded and each test has an overall budget (`InsimRunner.DEFAULT_BUDGET`, or
`budgetSeconds` on the suite), so a hung test fails rather than wedging the mission. A test that
never yields at all is the exception — nothing can interrupt that.

Timeouts should be generous. Live detection timing is not deterministic, and a scenario that
needs tight timing is the wrong scenario for this tier.

### Asserting on DCS rather than on Skynet

`SkynetIADSAbstractRadarElement:isActive()` returns `self.aiState` — Skynet's own bookkeeping.
Asserting on it proves the IADS decided something, not that the sim did it. `radarState` asks
DCS:

```lua
luaunit.assertFalse(InsimTestTools.radarState(SAM).emitting,
  "DCS reports the SAM is emitting, though Skynet believes it is dark")
```

**A turning antenna is not evidence.** `goDark()` calls `enableEmission(false)`, which stops the
radar emitting but leaves the unit alive and animated; `setOnOff(false)` is used only when a
site is silenced against a HARM. Expect the model to keep rotating on a dark site.

`Unit:getRadar()` returns false both for a unit with no radar and for one whose radar is off, so
read the aggregate (`emitting`, `emitters`), not a single unit. And keep a **positive control**
in the scenario — something that should be emitting, asserted alongside the thing that should
not. `scenario_detection.lua` uses the EWR, which Skynet brings live on add: if the sim reports
even that one as dark, `getRadar()` does not mean what the other assertions assume.

### Isolation

```
setUp     removeJunkInZone(ZONE)        -- clear wrecks from the last run
          addFromMission(...)           -- replaces anything still live
tearDown  destroyIfLive(...)            -- leaves no wreck behind
          iads:deactivate()
          world.removeEventHandler(iads) -- deactivate() does not; they pile up across re-runs
```

Measured DCS behaviour, which is why it is shaped this way:

| Operation | Result |
|---|---|
| **add** over a **live** entity | Replaced |
| **add** over an **exploded** entity | New one is whole and live; the wreck remains beside it |
| **destroy** a **live** entity | Removed cleanly, no wreck |
| **destroy** an **exploded** entity | No effect |
| `removeJunk` over a volume | Clears wrecks |

So `add` alone cannot reset a scenario — wrecks are `removeJunk`'s job, and it runs in `setUp`
rather than `tearDown` so it also covers runs that crashed or were re-triggered mid-scenario.

### Helpers

All on the global `InsimTestTools`:

| | |
|---|---|
| `missionGroupData(name)` | → `data, countryId, kind` — the editor's own table, deep-copied |
| `addFromMission(name)` | ground or static, exactly as placed |
| `addAirFromMission(name, {from, to, altitude, speed})` | airframes from the editor, geometry from you |
| `offsetFrom(origin, bearingDeg, metres)` | bearing clockwise from north |
| `bearingBetween(from, to)` | radians, clockwise from north |
| `destroyIfLive(name)` | live entities only |
| `removeJunkInZone(zoneName)` / `removeJunkAround(anchor, radius)` | clear wrecks |
| `radarState(name)` / `describeRadarState(name)` | what **DCS** says the group's radars are doing |
| `skynetNetworkDisplayState(iads, on)` | Skynet's debug output, routed into the timeline |

And two globals that are not on it: `waitFor` / `waitSeconds` (above) and `log`.

Skynet-aware helpers live on `InsimSkynet`, in `tools/insim-skynet-tools.lua`, so the toolbox
above stays usable by a scenario that never loads Skynet:

| | |
|---|---|
| `engagementReport(samSite, targetUnit)` | → `{ gate, gateKind, distance, inRange, kinds }` |
| `describeEngagement(samSite, targetUnit)` | the same as one timeline line |
| `networkDisplayState(iads, on)` | Skynet's debug output, routed into the timeline |

`engagementReport` answers *why* a site came up when it did. Skynet's `isTargetInRange` needs
the search radar **and** tracking radar **and** launcher all in range, and within each kind any
one element suffices — so the gate is the smallest of the three kinds' best ranges, usually the
launcher's missile range. Log it before the target flies and it is a prediction; read it when
the site goes live and it is the measurement.

Coordinates are mission-table throughout: **`x` is north, `y` is east**. (`Vec3` differs — there
`y` is altitude and `z` is east. `getPosition()` differs again — its `.x`/`.y`/`.z` are
orientation unit vectors, not coordinates at all.)

## Troubleshooting

Read the `dcs.log` lines tagged `SKYNET_INSIM` first, then look at the Game Master map.

| Symptom | Likely cause |
|---|---|
| `re-apply the MissionScripting.lua edit` | A DCS update reverted setup step 1 |
| A message naming `Config/skynet-insim.lua` | Setup step 2 is missing or returns the wrong path |
| `no scenarios in <dir>` | Expected before the first scenario exists; otherwise check the path it names |
| `missionGroupData: no group named '...'` | The group is missing or misspelled in the `.miz`. Case matters |
| A group is added but Skynet finds 0 of them | Prefix mismatch in `addSAMSitesByPrefix` / `addEarlyWarningRadarsByPrefix` |
| Fixtures appear in the wrong place | Axis confusion — `y` is east, not altitude and not north |
| An aircraft spawns but never flies | Check `speed` and `alt` reached the units; suspect the group task before the route |
| An aircraft flies the wrong way | Re-read the `atan2` argument order in `bearingBetween` |
| A rerun shows wrecks | The arena zone is too small, or it is a quad reporting radius 0 |
| A test passed but you do not trust it | Read its `duration` in `last-run.lua` against its timeout, and the timeline around it |
| `a run is already in progress` that never clears | A run raised before its guard was released. Restart the mission and report it |

## Checking the mission itself

Everything about fixtures rests on `env.mission` being populated and shaped as expected. Confirm
it once, before debugging a scenario against an unverified assumption. Add a **MISSION START →
DO SCRIPT** action containing the probe below, run the mission, then read the on-screen text or
grep `dcs.log` for `SKYNET_PROBE`. Remove the action afterwards.

It needs no `io`/`os`/`lfs`, so it works even if setup step 1 has not been applied.

```lua
do
  local PREFIX = "SKY"
  local ZONE   = "SKY-Z01"

  local function say(text)
    env.info("SKYNET_PROBE: " .. text)
    trigger.action.outText(text, 60)
  end

  if type(env.mission) ~= "table" then
    say("env.mission is NOT available (got " .. type(env.mission) .. ")")
    return
  end

  local lines = { "env.mission OK | theatre=" .. tostring(env.mission.theatre) }

  for sideName, side in pairs(env.mission.coalition or {}) do
    for _, country in pairs(side.country or {}) do
      for _, kind in ipairs({ "vehicle", "static", "plane", "helicopter" }) do
        for _, g in pairs((country[kind] or {}).group or {}) do
          if type(g.name) == "string" and g.name:sub(1, #PREFIX) == PREFIX then
            lines[#lines + 1] = string.format(
              "%s | %s | %s | country=%s id=%s | units=%d | x=%.0f y=%.0f",
              g.name, kind, sideName, tostring(country.name), tostring(country.id),
              #(g.units or {}), g.x or 0, g.y or 0)
          end
        end
      end
    end
  end

  local ok, zone = pcall(trigger.misc.getZone, ZONE)
  if ok and zone then
    lines[#lines + 1] = string.format("zone %s | radius=%.0f | x=%.0f z=%.0f",
      ZONE, zone.radius or -1, zone.point.x, zone.point.z)
  else
    lines[#lines + 1] = "zone " .. ZONE .. " NOT found (" .. tostring(zone) .. ")"
  end

  say(table.concat(lines, "\n"))
end
```

What each line tells you:

| Output | Means |
|---|---|
| `env.mission is NOT available` | Stop — nothing in the fixture design works. Everything downstream assumes this table |
| ground fixtures listed under `vehicle`, the air one under `plane` | `missionGroupData` will find them. Any other category and it raises "no group named…" |
| `id=` on each country | What `coalition.addGroup` receives. A wrong one adds to the wrong coalition **silently** — the nastiest failure in the set |
| `units=` | Catches an empty group before `addAirFromMission` does |
| `radius=` a real number | The zone is circular. `0` means you drew a quad — redraw it |
