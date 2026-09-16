# Design: `test/insim/` — a live-DCS test tier

Status: **design approved**; the wreck-clearing question that previously gated it was answered
empirically on 2026-09-16. Remaining items are implementation-time verification, not design forks.

Supersedes [2026-09-14-insim-test-tier-design.md](2026-09-14-insim-test-tier-design.md).
Related: [docs/evolutions.md](../../evolutions.md) "Smoke tests".

## Problem

Skynet-IADS has two test tiers:

| Tier | Runs where | Job |
|---|---|---|
| `test/lua/` | plain Lua 5.1, no DCS | logic: state machines, math, branching |
| `unit-tests/*.miz` | inside DCS, launched by hand, results read from `dcs.log` | functional/smoke, but mocks `getDCSRepresentation()` and similar — it does not exercise real radar geometry, terrain, or emission state |

Recent changes (HARM-silence cleanup, the `ad60e92` weapon-contact widening, the SAM-goes-dark
fix) shipped without ever running against a live DCS mission. The existing DCS-tier tests do
not close that gap: they mock away the exact behavior that needs checking.

Three structural frictions make the legacy tier unpleasant enough that it gets skipped:

- **Everything is embedded in the `.miz`.** `unit-tests/skynet-unit-tests.miz` carries 17
  `a_do_script_file` actions whose targets are copies baked into `l10n/DEFAULT/` at save time.
  Editing a test on disk changes nothing until the mission is re-saved in the Mission Editor.
- **The Skynet build inside the mission is a snapshot.** The `.miz` embeds its own
  `skynet-iads-compiled.lua`. A green run can mean last month's code was green.
- **Results are read by grepping `dcs.log`.**

## Goals

- A third durable tier, `test/insim/`, for behavior that needs a real simulator: radar
  detection, terrain, coalition data, genuine emission-state changes.
- A fast edit→run loop. Editing a scenario and re-running it must not require restarting the
  mission or opening the Mission Editor.
- Scenarios must be able to wait for simulated time to pass, because that is what the
  motivating behaviors require.
- Always runs against current source, never a stale build.
- Minimal in-repo tooling: no new external dependency, no binary/ABI risk, no mist.

## Non-goals

- **Unattended operation.** The tester launches DCS and triggers runs by hand. This is a
  deliberate reversal of the superseded spec, and it removes that spec's entire highest-risk
  area: dedicated-server mode, `serverSettings.lua` (which would have overwritten the user's
  real server config), `pause_without_clients`, and autologin are all gone.
- **A command/response IPC channel.** No polling loop, no command file, no response-file
  write/read race. The mission reads from disk; nothing writes into the mission.
- **CI integration.** Running DCS needs a licensed, GPU-capable machine. Separate decision.
- **Migrating `unit-tests/*.miz`.** It stays as the fallback. The long-term intent is for
  `test/insim/` to replace and extend it, scoped incrementally, file by file. Not this work.
- **Writing a backlog of regression scenarios.** This work delivers the tier plus one real
  scenario that proves it.
- **Using or vendoring mist.** See "No mist".

## Architecture

### Shape

Three artifacts: one touched occasionally, the rest constantly.

```
skynet-insim.miz            authored in the Mission Editor, extended only when a new
  ├─ Caucasus map           fixture asset type is needed              (binary, committed)
  ├─ one playable aircraft slot
  ├─ late-activated fixture assets, placed at correct coordinates
  └─ MISSION START trigger → ~15-line inline bootstrap
                              └─ dofile(<repo>/test/insim/runner/init.lua)

test/insim/**               everything real, plain text, re-read from disk on every run
skynet-iads-source/**       loaded fresh from disk on every run — never a stale build
```

The mission is Caucasus, not Persian Gulf: it is the free map, so the tier is runnable by any
contributor and by a future CI machine. The legacy `.miz` and both demo missions are Persian
Gulf; this tier deliberately diverges.

### Repo path resolution

The bootstrap embedded in the `.miz` must not contain a machine-specific path, so that the same
committed mission works against any checkout. It reads the path at runtime from a config file
whose location it derives itself:

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

`Saved Games\DCS\Config\` is where DCS keeps per-machine config, and — unlike the
`MissionScripting.lua` edit below — it survives DCS updates. No environment variables, no
machine-wide settings.

This makes `lfs` load-bearing, so it joins `io` and `os` as a hard requirement of the
sanitization edit.

### Run loop: hot reload from the F10 menu

Launch `skynet-insim.miz` in the normal DCS client, take the aircraft slot, then
**F10 → Skynet Tests → Run all / Re-run last / Run one suite**.

Every invocation re-`dofile`s Skynet source *and* scenario files from disk. Edit a scenario in
an editor, press F10, see the result. No mission restart, no Mission Editor, no alt-tab.

Consequence accepted: `missionCommands.addCommand` requires a player in a slot, so the mission
needs a playable aircraft and the tester must occupy it. Skynet already uses `missionCommands`
for its own radio menu (`skynet-iads-source/skynet-iads.lua:613`), so this is idiomatic here.

Source loading reuses `test/lua/skynet-loader.lua` verbatim — it is already mist-free, already
resolves its root from configuration rather than a hardcoded path, and already exposes
`reset()` for reloading. Load order therefore has one source of truth shared by both tiers.

### Async model: coroutines, not luaunit's run loop

Every motivating scenario needs simulated time to pass. A mission script cannot block — that
would freeze the sim thread — and luaunit's `run()` is synchronous. So the runner replaces
luaunit's run loop while keeping its assertions.

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
`pcall`. Assertion failures surface as `false, message` from `resume`. This is why luaunit's
assertions can be kept unchanged: they only call `error()`. It also means the design has no
dependency on yielding across a `pcall` boundary — a LuaJIT-only capability that stock Lua 5.1
lacks.

Every wait is bounded, and each test additionally carries an overall budget, so a hung test
fails rather than wedging the mission.

### Fixtures: authored in the editor, stored as text, spawned at runtime

Authoring and runtime are separated.

```
Mission Editor (occasionally, by hand)
  place typical assets at correct Caucasus coordinates, tick Late Activation
  save skynet-insim.miz

Offline extractor (test/insim/tools/extract-fixtures.lua, plain Lua 5.1, no DCS)
  read that .miz's `mission` file  →  test/insim/fixtures/generated/*.lua  (committed, diffable)

Runtime (every F10 run)
  setUp spawns from the generated table  →  fresh units
```

The Mission Editor is the source of truth for placement: hand-authoring coordinates is
error-prone and loses the map as a browsable view of the fixture world. A `.miz`'s `mission`
file is plain Lua, so extraction runs offline on the same Lua 5.1 interpreter `test/lua`
already uses — no in-sim step, no mist, no Mission Editor session needed to extract.

Fixtures are stored as **templates plus a placement** rather than as absolute positions: unit
types, counts, headings and offsets relative to the site origin are map-independent and
reusable, while only the anchor coordinate is Caucasus-specific. A real unit entry is small —
seven keys, matching the tables in the existing `.miz`:

```lua
{ type = "Kub 1S91 str", dx = 0, dz = 0, heading = 2.827, skill = "Excellent" }
```

The extractor computes `dx`/`dz` relative to each site's first unit, so the compositions Skynet
was actually built against can be harvested out of `unit-tests/skynet-unit-tests.miz` (Persian
Gulf) and re-anchored on Caucasus.

The late-activated units inside `skynet-insim.miz` never activate during a run. They exist to
be read by the extractor and to give a map view of the fixture world.

### Isolation: removeJunk for the dead, same-name replacement for the living

Measured in DCS on 2026-09-16 with a throwaway F10 probe
(`GroundStrikeSandboxSyria/Scripts/FgInsimProbe.lua`, DCS API only, no MOOSE). Groups and
statics behaved identically on all three points:

| Action | Result |
|---|---|
| Spawn same name over a **live** group/static | Replaced, as documented |
| Spawn same name over an **exploded** group/static | **Neither replaced nor despawned** — the wreck survives |
| `world.removeJunk` over the zone | Clears the wrecks |

So neither mechanism alone is sufficient, and the model uses both. The background that led here:

- `skynet-iads-source/skynet-iads-utils.lua:238-242` — `coalition.getGroups` hands back groups
  that have been destroyed, and asking one for its units *raises*, aborting the enclosing
  `pairs` loop. An `isExist()` guard exists specifically for this.
- `skynet-iads-source/skynet-iads-abstract-radar-element.lua:754` — "there are cases when a
  destroyed object is still visible as a target to the radar".
- mist, ~9,000 lines and the de-facto standard for a decade, contains **zero** `destroy()`
  calls. Its entire respawn/teleport/clone machinery routes through a single
  `coalition.addGroup`. The idiomatic reset in DCS is re-adding a group under the same name.

Removal *is* possible for live objects — `Object.destroy()` "physically removes it from the
game world without creating an event", and MOOSE's `GROUP:Destroy()` builds on it. The
long-standing limitation is that it stops working once a unit is destroyed and burning
(MOOSE issue #695, closed as a DCS bug). So despawn is exactly backwards for this tier: it
works on the units we do not need to clear and fails on the ones we do.

Same-name replacement, by contrast, is **documented API behavior**, not merely mist
convention. ED's `coalition.addGroup` documentation states: "If the group or any unit within
shares a name of an existing group or unit, the existing group or unit will be destroyed when
the new group is created."

The cycle, therefore:

```
setUp     world.removeJunk(sphere around this scenario's anchor)   -- clears wrecks from last run
          coalition.addGroup(scoped name)                          -- replaces any live leftovers
tearDown  Object.destroy() on each tracked group still alive       -- clean, leaves no wreck
          iads:deactivate()
```

- Each scenario spawns under deterministic, test-scoped names
  (`insim_TestSamGoesDark_SAM-1`) at its own well-separated anchor coordinate. The unique
  prefix keeps Skynet's prefix-based discovery honest; the separated anchor gives `removeJunk`
  a volume that cannot touch another scenario's fixtures.
- `removeJunk` runs in `setUp` rather than `tearDown` deliberately: it then also covers runs
  that crashed, were interrupted mid-scenario, or were re-triggered from F10 before finishing —
  cases a `tearDown` never reaches.
- `tearDown` destroys what is still alive because that path is reliable for live units and
  keeps the world from accumulating. Anything killed during the test is left to the next
  `setUp`'s `removeJunk`.
- The hard reset is a mission restart, occasionally needed after a long session — an accepted
  cost of the manual-launch model.

Spawned units fire `S_EVENT_BIRTH`, which Skynet already handles
(`skynet-iads-source/skynet-iads.lua:31`, currently a log line). Benign, but on the path.

### No mist

Skynet source contains **zero** mist references; mist is purely test-harness, and `test/lua`
has already dropped its mist stub. This tier starts mist-free, consistent with that direction.

What mist would have provided is small and gets written here instead. Crucially it is
**rewritten, not copied**: the mist copy in the legacy `.miz` carries no license header at all
(authors Speed and Grimes, `mrSkortch/MissionScriptingTools`), while this repo is Apache 2.0.
What is taken from mist is knowledge — that the reset primitive is re-adding under the same
name, and how country/category enums resolve — not implementation. Functions are written fresh
against the documented DCS API and sized for this tier's needs. Anything genuinely mist-derived
in structure carries a provenance comment marked `-- FGA`, per the repo convention for
third-party-derived code.

### Results

The same data, three outputs:

- **On screen** via `trigger.action.outText` — pass/fail without leaving the sim. The primary
  readout.
- **`dcs.log`** via `env.info`, prefixed `SKYNET_INSIM`, for failure detail and context.
- **`test/insim/results/last-run.lua`** — machine-readable, gitignored.

A terminal reader with an exit code is roughly 40 lines and is explicitly *not* built now. The
results file is the contract that makes it trivial whenever CI or a top-level "run everything"
script wants it.

### Setup cost

`Scripts/MissionScripting.lua` sanitizes `io`, `os` and `lfs` out of the mission environment.
Unlocking all three is required — disk loading is the entire design — and is the same one-time
edit MOOSE/MIST/CTLD-class frameworks have long needed. It is install-wide, affects every
mission on that install including multiplayer integrity checks, and is the user's explicit
choice.

**DCS updates and repairs silently revert this edit.** The bootstrap therefore preflights `io`,
`os` and `lfs`, and when they are missing it puts an explicit "re-apply the MissionScripting.lua
edit" message on screen rather than failing obscurely. `test/insim/README.md` documents the
edit, the revert path, the multiplayer consequence, and the
`Saved Games/DCS/Config/skynet-insim.lua` config file.

## Layout

```
test/insim/
  runner/init.lua               entry point: preflight, load source, build F10 menu
  runner/runner.lua             coroutine scheduler, result collection
  runner/wait.lua               waitFor / waitSeconds
  runner/report.lua             outText + env.info + results file
  tools/insim-test-tools.lua    toolbox: pure-Lua helpers (deepCopy, serialize) and
                                DCS-world helpers (spawnOrReplace, name scoping)
  tools/extract-fixtures.lua    offline entry point, plain Lua 5.1, no DCS API
  fixtures/generated/*.lua      extracted templates (committed)
  fixtures/placements.lua       Caucasus anchor coordinates, one region per scenario
  scenarios/scenario_*.lua      suites: luaunit assertions, coroutine bodies
  results/                      gitignored
  README.md
  skynet-insim.miz              Caucasus, playable slot, bootstrap, late-activated fixtures
```

`insim-test-tools.lua` holds the helpers this tier needs that neither Skynet source nor luaunit
provides. Scope rules, so it does not become a junk drawer: nothing Skynet-specific (that
belongs in scenarios or fixtures); check `SkynetIADSUtils` before adding any math, since
`test/lua` already covers it; split into focused files past roughly 300 lines.
`extract-fixtures.lua` is separate because it runs under a different interpreter outside DCS —
an environment boundary, not a filing preference.

## Deliverable

The tier, plus **one real time-dependent scenario**: spawn an EWR, a red SAM site and a moving
aircraft; wait for genuine radar detection; assert that the IADS reacts.

A synchronous placeholder ("assert `Group.getByName` returns a unit") is explicitly rejected as
the proof: it would exercise none of the spawning, coroutine-waiting, timeout or isolation
machinery, leaving all of it unproven until the first real scenario.

## Open questions

The wreck-clearing question that previously gated this spec was **answered empirically on
2026-09-16** (see "Isolation"): same-name spawn does not clear wrecks, `world.removeJunk` does,
and the design uses both. The remaining items are verification steps for the implementation,
not design forks.

1. **Spawn fidelity.** Does a group spawned from an extracted table behave identically to its
   editor-placed original as far as Skynet can tell: types resolve, radar emits, detection
   works, `coldAtStart` honored? First implementation step. If some asset class fails, that
   asset falls back to a late-activated editor-placed group and its scenarios accept one
   destructive run per mission session — a per-asset escape hatch, not a redesign.
2. **Stale listings.** Does a wreck leave an entry behind in `coalition.getGroups()`, and does
   `removeJunk` clear that entry or only the visual debris? Skynet's `forEachLiveGroup`
   guard already tolerates the raise either way, but prefix-based discovery counts could be
   affected. Cheap to measure with the same probe.
3. **`removeJunk` stability.** It has a history of client CTDs a few seconds after removing
   nearby destroyed units, with a fix referenced around December 2024. Confirmed working in
   single player on the current version; the multiplayer blast radius is nil for this tier.

## Risks for the implementation plan

- `lfs.writedir()` availability in the mission environment post-unsanitize. Verify first: it is
  the only path-resolution mechanism, the environment-variable fallback having been dropped by
  choice.
- `coalition.addGroup` country and category enum correctness for these ground groups.
- Detection timing is genuinely non-deterministic. Timeouts are generous by policy, and any
  scenario needing tight timing is the wrong scenario for this tier.
- Whether group tables extracted from the Persian Gulf `.miz` re-anchor onto Caucasus cleanly,
  or need per-site coordinate fixups.
- Accumulated wrecks across a long session polluting detection despite separated coordinates.
