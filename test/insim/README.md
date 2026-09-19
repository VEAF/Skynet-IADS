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

Results appear on screen, in `dcs.log` tagged `SKYNET_INSIM`, and in
`test/insim/results/last-run.lua`.

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

**Names are free-form.** This mission exists only to be tested against, so every group in it is
a fixture and nothing needs distinguishing from anything else. The one rule is that the names in
a scenario's Lua match the `.miz` exactly, case included. A mismatch says
`missionGroupData: no group named '...'`.

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
```

Every wait is bounded and each test has an overall budget (`InsimRunner.DEFAULT_BUDGET`, or
`budgetSeconds` on the suite), so a hung test fails rather than wedging the mission. A test that
never yields at all is the exception — nothing can interrupt that.

Timeouts should be generous. Live detection timing is not deterministic, and a scenario that
needs tight timing is the wrong scenario for this tier.

### Isolation

```
setUp     removeJunkInZone(ZONE)        -- clear wrecks from the last run
          addFromMission(...)           -- replaces anything still live
tearDown  destroyIfLive(...)            -- leaves no wreck behind
          iads:deactivate()
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
| `a run is already in progress` that never clears | A run raised before its guard was released. Restart the mission and report it |

To check the mission itself rather than a scenario, add a **MISSION START → DO SCRIPT** action
that prints what `env.mission` actually contains — group names, their category, country id, unit
counts and zone radii. The probe is in the implementation plan under Task 9. It needs no
`io`/`os`/`lfs`, so it works even if setup step 1 has not been applied.
