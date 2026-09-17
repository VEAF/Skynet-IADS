# Design: `test/insim/` — a live-DCS test tier

Status: **approved**, ready for an implementation plan.

Supersedes [2026-09-14-insim-test-tier-design.md](2026-09-14-insim-test-tier-design.md).
Deferred ideas this design deliberately leaves out are tracked in
[docs/evolutions.md](../../evolutions.md), "In-sim test tier".

## Problem

Skynet-IADS has two test tiers:

| Tier | Runs where | Job |
|---|---|---|
| `test/lua/` | plain Lua 5.1, no DCS | logic: state machines, math, branching |
| `unit-tests/*.miz` | inside DCS, launched by hand, results read from `dcs.log` | functional/smoke, but mocks `getDCSRepresentation()` and similar — it does not exercise real radar geometry, terrain, or emission state |

Recent changes (HARM-silence cleanup, the `ad60e92` weapon-contact widening, the SAM-goes-dark
fix) shipped without ever running against a live DCS mission, and the DCS-tier tests do not
close that gap: they mock away the exact behavior that needs checking.

Three frictions make that tier unpleasant enough to skip:

- **Everything is embedded in the `.miz`.** `unit-tests/skynet-unit-tests.miz` carries 17
  `a_do_script_file` actions whose targets are copies baked into `l10n/DEFAULT/` at save time.
  Editing a test on disk changes nothing until the mission is re-saved in the Mission Editor.
- **The Skynet build inside the mission is a snapshot.** The `.miz` embeds its own
  `skynet-iads-compiled.lua`. A green run can mean last month's code was green.
- **Results are read by grepping `dcs.log`.**

## Goals

- A third durable tier, `test/insim/`, for behavior that needs a real simulator: radar
  detection, terrain, coalition data, genuine emission-state changes.
- A fast edit→run loop: re-running an edited scenario must not require restarting the mission
  or opening the Mission Editor.
- Scenarios can wait for simulated time to pass, because the motivating behaviors require it.
- Always runs against current source, never a stale build.
- Minimal in-repo tooling: no new external dependency, no binary/ABI risk, no mist.

## Non-goals

- **Unattended operation.** The tester launches DCS and triggers runs by hand.
- **Any external process driving the run.** No command file, no response file, no handshake.
  The mission reads scenarios from disk and is triggered from inside the sim.
- **CI integration.** Running DCS needs a licensed, GPU-capable machine.
- **Migrating `unit-tests/*.miz`,** which stays as the fallback.
- **Writing a backlog of regression scenarios.** This work delivers the tier plus one real
  scenario that proves it.
- **Using or vendoring mist.**

## Architecture

### Shape

```
skynet-insim.miz            authored in the Mission Editor, extended only when a new
  ├─ Caucasus map           fixture asset type is needed              (binary, committed)
  ├─ one Neutral Game Master slot
  ├─ late-activated fixture assets, placed at correct coordinates
  └─ MISSION START trigger → ~15-line inline bootstrap
                              └─ dofile(<repo>/test/insim/runner/init.lua)

test/insim/**               everything real, plain text, re-read from disk on every run
skynet-iads-source/**       loaded fresh from disk on every run — never a stale build
```

Caucasus, not Persian Gulf: it is the free map, so the tier is runnable by any contributor and
by a future CI machine. The legacy `.miz` and both demo missions are Persian Gulf; this tier
deliberately diverges.

### Repo path resolution

The bootstrap must not contain a machine-specific path, so the committed mission works against
any checkout. It reads the path at runtime from a config file whose location it derives itself:

```lua
-- embedded bootstrap — no path baked into the .miz
local cfg = loadfile(lfs.writedir() .. "Config/skynet-insim.lua")
local repo = cfg and cfg()   -- that file is one line: return [[D:\Projects\DcsLua\Skynet-IADS]]
if not repo then
  trigger.action.outText("skynet-insim: create Saved Games/DCS/Config/skynet-insim.lua", 60)
  return
end
dofile(repo .. "/test/insim/runner/init.lua")
```

`Saved Games\DCS\Config\` is where DCS keeps per-machine config and — unlike the
`MissionScripting.lua` edit below — it survives DCS updates. No environment variables, no
machine-wide settings.

This makes `lfs` load-bearing: it joins `io` and `os` as a hard requirement of the
sanitization edit.

### Run loop: hot reload from the F10 menu

Launch `skynet-insim.miz` in the normal DCS client, take a slot, then
**F10 → Skynet Tests → Run all / Re-run last / Run one suite**. Every invocation re-`dofile`s
Skynet source *and* scenario files from disk: edit a scenario, press F10, see the result.

The menu is built at mission start with the **global** `missionCommands.addCommand`, not the
group- or coalition-scoped variants, so it reaches whichever slot the tester occupies. Skynet
already uses `missionCommands` for its own radio menu
(`skynet-iads-source/skynet-iads.lua:613`).

**The mission carries a single Neutral Game Master slot.** Neutral rather than
red or blue because a neutral Game Master sees both coalitions, which a scenario adding red
sites against a blue target needs.

One slot, not several, keeps the mission simple. Nothing about the design depends on the slot
type — the menu is global and the runner is indifferent — so further slots can be added later
for in-cockpit observation without disturbing anything
(see [docs/evolutions.md](../../evolutions.md)). No scenario requires the tester to fly: target
aircraft are added by the scenario itself, and the Combined Arms map view is the useful
vantage point for debugging a detection test.

### Shared test assets: `test/common/`

Two files are needed by both `test/lua/` and `test/insim/`, and neither belongs to either tier:

| File | Why shared |
|---|---|
| `skynet-loader.lua` | Loads `skynet-iads-source/*.lua` in dependency order. That order must have one source of truth, not a copy per tier. Already mist-free and already exposes `reset()` for reloading |
| `luaunit.lua` | Both tiers assert with it — `test/insim/` keeps luaunit's assertions even though it replaces its run loop |

Both move to `test/common/`, and `test/lua/`'s suites update their `dofile` paths accordingly.
The legacy `unit-tests/luaunit.lua` is left alone: it is a different vintage and is embedded in
its `.miz` regardless.

The loader's default root resolution still works from the new location — its relative
`../../skynet-iads-source` is the same depth from `test/common/` as from `test/lua/`. It gains
one addition: an explicit root setter, so the in-sim runner can pass the repo path the
bootstrap has already resolved rather than falling back on `debug.getinfo` inside the mission
environment. `test/lua/` keeps the relative default and is otherwise unchanged.

Moving these is a small, targeted refactor of `test/lua/`, included here because this work is
what makes them shared.

### Async model: coroutines, not luaunit's run loop

Every motivating scenario needs simulated time to pass. A mission script cannot block — that
would freeze the sim thread — and luaunit's `run()` is synchronous. The runner therefore
replaces luaunit's run loop while keeping its assertions.

Each test runs as a **coroutine**, resumed by the runner on a `timer.scheduleFunction` tick.
`waitFor(predicate, timeoutSec)` and `waitSeconds(n)` yield until satisfied or until a deadline
computed from `timer.getTime()` passes; a blown deadline raises, failing the test exactly like
a failed assertion.

```lua
function TestSamGoesDark:testGoesDarkUnderHarm()
  local sam = self.iads:getSAMSiteByGroupName(self:scoped("SAM-1"))
  waitFor(function() return sam:isRadarEmitting() end, 60)
  fireHarmAt(sam)
  waitFor(function() return not sam:isRadarEmitting() end, 60)
  waitFor(function() return sam:isRadarEmitting() end, 300)   -- comes back up
end
```

`coroutine.resume` is itself a protected call, so the runner never wraps test bodies in
`pcall`; assertion failures surface as `false, message` from `resume`. That is what lets
luaunit's assertions stay unchanged — they only call `error()` — and it removes any dependency
on yielding across a `pcall` boundary, which LuaJIT allows but stock Lua 5.1 does not.

Every wait is bounded, and each test carries an overall budget, so a hung test fails rather
than wedging the mission.

### Fixtures: authored in the editor, stored as text, added at runtime

```
Mission Editor (occasionally, by hand)
  place assets at correct Caucasus coordinates, tick Late Activation, save skynet-insim.miz

Offline extractor (test/insim/tools/extract-fixtures.lua, plain Lua 5.1, no DCS)
  read that .miz's `mission` file  →  test/insim/fixtures/generated/*.lua  (committed, diffable)

Runtime (every F10 run)
  setUp adds from the generated table  →  fresh units
```

The Mission Editor is the source of truth for placement: hand-authoring coordinates is
error-prone and loses the map as a browsable view of the fixture world. A `.miz`'s `mission`
file is plain Lua, so extraction runs offline on the same Lua 5.1 interpreter `test/lua`
already uses — no in-sim step, no mist, no Mission Editor session needed to extract.

Fixtures are stored as **templates plus a placement**: unit types, counts, headings and offsets
relative to the site origin are map-independent and reusable, while only the anchor coordinate
is Caucasus-specific. A unit entry is seven keys, matching the tables in the existing `.miz`:

```lua
{ type = "Kub 1S91 str", dx = 0, dy = 0, heading = 2.827, skill = "Excellent" }
```

The extractor computes `dx`/`dy` relative to each site's first unit, so the compositions Skynet
was built against can be harvested out of `unit-tests/skynet-unit-tests.miz` (Persian Gulf) and
re-anchored on Caucasus.

**Axis conventions.** Three different things in DCS are spelled `x`/`y`/`z`, and mixing them up
silently produces units in the wrong place or facing the wrong way:

| | `x` | `y` | `z` |
|---|---|---|---|
| `Vec3` — world position | north | **altitude** | east |
| `Vec2` — and mission-file unit tables | north | **east** | — |
| `getPosition()` `.x`/`.y`/`.z` | forward | up | right |

`Vec2.x == Vec3.x`, `Vec2.y == Vec3.z`. Fixture offsets are Vec2/mission-table, so `dy` is an
**east** offset, not altitude and not north. `getPosition()`'s `.x`/`.y`/`.z` are orientation
*unit vectors*, not coordinates at all — position lives in its `.p`. Heading comes from the
forward vector, `math.atan2(pos.x.z, pos.x.x)`; the mission file stores `heading` directly as a
scalar, so the extractor needs no such conversion, but the fixture-fidelity check does if it
compares an added unit's live facing against its editor-placed original.

The late-activated units in `skynet-insim.miz` are not activated by a normal run: they exist to
be read by the extractor and to give a map view of the fixture world. The one exception is an
asset class that fails the fixture-fidelity check below, which falls back to being activated
directly.

### Isolation: removeJunk for the exploded, re-add for the live

Three distinct operations, kept distinct throughout this document:

| Term | Means |
|---|---|
| **add** | create a group or static — `coalition.addGroup`, `coalition.addStaticObject` |
| **destroy** | remove a live group or static through the API — `Object.destroy()` |
| **explode** | in-game destruction, by weapons or `trigger.action.explosion`; leaves a wreck |

How DCS responds to each:

| Operation | Result |
|---|---|
| **add** with the name of a **live** entity | The live one is destroyed; the new one takes its place |
| **add** with the name of an **exploded** entity | The new one is added whole and live; the wreck remains beside it |
| **destroy** a **live** entity | Removed cleanly, no wreck |
| **destroy** an **exploded** entity | No effect; the wreck remains |
| `removeJunk` over a volume | Clears wrecks |

Neither operation resets a scenario on its own: `destroy` acts only on what is still live, and
`add` replaces only what is still live. Wrecks are `removeJunk`'s job.

What an **exploded** entity leaves behind differs by kind, which decides how much the leftovers
matter:

| After exploding | Group | Static |
|---|---|---|
| `getByName` | **nil** | found |
| `isExist()` | n/a | **false** |
| entries in `coalition.getGroups` | **0** | n/a |

An exploded group leaves **no logical trace**, so `removeJunk` clears *physical debris* rather
than stale listings, and prefix-based discovery cannot pick up dead sites. The standing reason
to clear debris anyway is `skynet-iads-abstract-radar-element.lua:754`: "there are cases when a
destroyed object is still visible as a target to the radar".

An exploded static is the opposite — its handle survives, reporting `isExist() == false` — and
that suits Skynet. `SkynetIADSAbstractElement:genericCheckOneObjectIsAlive` holds stored
references to power sources and connection nodes, typically statics, and calls `isExist()` on
each; had statics vanished the way groups do, those references would go stale and raise.

The cycle:

```
setUp     removeJunk(sphere around this scenario's anchor)   -- clear wrecks from the last run
          add each fixture under its scoped name             -- replaces any live leftovers
tearDown  destroy each tracked entity still live             -- leaves no wreck behind
          iads:deactivate()
```

- Fixtures are added under deterministic, test-scoped names (`insim_TestSamGoesDark_SAM-1`) at
  the scenario's own well-separated anchor. The anchor gives `removeJunk` a volume that cannot
  touch another scenario's fixtures; the scoped name means re-adding replaces that scenario's
  own live leftovers and nothing else.
- `removeJunk` runs in `setUp`, not `tearDown`, so it also covers runs that crashed, were
  interrupted, or were re-triggered from F10 before finishing — cases a `tearDown` never reaches.
- `tearDown` destroys what is still live, which keeps the world from accumulating. Anything
  that exploded during the test is left to the next `setUp`.
- The hard reset is a mission restart, occasionally needed after a long session.

Added units fire `S_EVENT_BIRTH`, which Skynet already handles
(`skynet-iads-source/skynet-iads.lua:31`, currently a log line). Benign, but on the path.

### No mist

Skynet source contains **zero** mist references; mist is purely test-harness, and `test/lua`
has already dropped its mist stub. Nothing is vendored here.

The handful of things mist would have provided — adding a group, a table serializer, a deep
copy — are written fresh against the documented DCS API and sized for this tier's needs. mist
is inspiration, not a source: what it supplies is knowledge, such as re-adding under the same
name being the reset primitive, and how country and category enums resolve.

This follows the precedent `SkynetIADSUtils` already set when it replaced Skynet's 13 mist
calls: reproduce the behaviour, and where the implementation departs from what mist did, say so
at the call site. Those comments carry engineering information — what the behaviour is
equivalent to, and where it deliberately is not — rather than attribution.

### Results

The same data, three outputs:

- **On screen** via `trigger.action.outText` — the primary readout, pass/fail without leaving
  the sim.
- **`dcs.log`** via `env.info`, prefixed `SKYNET_INSIM`, for failure detail and context.
- **`test/insim/results/last-run.lua`** — machine-readable, gitignored. No reader is built now;
  the file is the contract that makes one trivial later.

### Setup cost

`Scripts/MissionScripting.lua` sanitizes `io`, `os` and `lfs` out of the mission environment.
Unlocking all three is required — disk loading is the entire design — and is the same one-time
edit MOOSE/MIST/CTLD-class frameworks have long needed. It is install-wide, affects every
mission on that install including multiplayer integrity checks, and is the user's explicit
choice.

**DCS updates and repairs silently revert this edit.** The bootstrap preflights `io`, `os` and
`lfs` and, when they are missing, puts an explicit "re-apply the MissionScripting.lua edit"
message on screen rather than failing obscurely. `test/insim/README.md` documents the edit, the
revert path, the multiplayer consequence, and the config file.

## Layout

```
test/common/                    shared by both Lua tiers (moved out of test/lua/)
  skynet-loader.lua             dependency-ordered source loading, one source of truth
  luaunit.lua                   vendored luaunit 3.4

test/insim/
  runner/init.lua               entry point: preflight, load source, build F10 menu
  runner/runner.lua             coroutine scheduler, result collection
  runner/wait.lua               waitFor / waitSeconds
  runner/report.lua             outText + env.info + results file
  tools/insim-test-tools.lua    toolbox: pure-Lua helpers (deepCopy, serialize) and
                                DCS-world helpers (addOrReplace, name scoping)
  tools/extract-fixtures.lua    offline entry point, plain Lua 5.1, no DCS API
  fixtures/generated/*.lua      extracted templates (committed)
  fixtures/placements.lua       Caucasus anchor coordinates, one region per scenario
  scenarios/scenario_*.lua      suites: luaunit assertions, coroutine bodies
  results/                      gitignored
  README.md
  skynet-insim.miz              Caucasus, Neutral GM slot, bootstrap, late-activated fixtures
```

`insim-test-tools.lua` holds helpers this tier needs that neither Skynet source nor luaunit
provides. Scope rules, so it does not become a junk drawer: nothing Skynet-specific (that
belongs in scenarios or fixtures); check `SkynetIADSUtils` before adding math, since `test/lua`
already covers it; split past roughly 300 lines. `extract-fixtures.lua` is separate because it
runs under a different interpreter outside DCS — an environment boundary, not a filing
preference.

## Deliverable

The tier, plus **one real time-dependent scenario**: add an EWR, a red SAM site and a moving
aircraft; wait for genuine radar detection; assert that the IADS reacts.

A synchronous placeholder ("assert `Group.getByName` returns a unit") is rejected as the proof:
it would exercise none of the adding, coroutine-waiting, timeout or isolation machinery.

## To verify during implementation

None of these are design forks; each has a known fallback.

1. **Fixture fidelity** — first step. Does a group added from an extracted table behave
   identically to its editor-placed original as far as Skynet can tell: types resolve, radar
   emits, detection works, `coldAtStart` honored? If an asset class fails, it falls back to a
   late-activated editor-placed group and its scenarios accept one destructive run per mission
   session.
2. **`lfs.writedir()` availability** in the mission environment post-unsanitize. It is the only
   path-resolution mechanism, the environment-variable fallback having been dropped by choice.
3. **`coalition.addGroup` country and category enum correctness** for these ground groups.
4. **Re-anchoring** — whether group tables extracted from the Persian Gulf `.miz` land cleanly
   on Caucasus or need per-site coordinate fixups.
5. **`removeJunk` stability.** It has a history of client CTDs a few seconds after clearing
   nearby wrecks, with a fix referenced around December 2024. Working in single player; the
   multiplayer blast radius is nil for this tier.
6. **Partially exploded groups.** Behaviour is known for groups whose units have *all*
   exploded. A group with some units live and some exploded is the case `forEachLiveGroup`
   guards, and the state a mid-scenario assertion will most often observe.
7. **Detection timing** is non-deterministic. Timeouts are generous by policy; any scenario
   needing tight timing is the wrong scenario for this tier.
