# Integrate the RP standalone test harness into VEAF/Skynet-IADS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the `regroupement-patrouille` standalone Lua test harness on a `VEAF/Skynet-IADS` branch that is a strict superset of both forks, with the harness green against MiST-free source and the `feature-inform-bomb-contact` feature merged in.

**Architecture:** One branch on the local VEAF clone. Squash-merge RP `master` (brings `test/lua/`, CI, two source fixes). Then repair the harness: the merged source calls `SkynetIADSUtils.*` instead of `mist.*`, so the loader must load the real `skynet-iads-utils.lua`, `dcs-stub.lua` must cover the DCS globals that module reaches (`coord`, `timer.scheduleFunction`), the M2 fake scheduler moves from `mist.*` onto a `SkynetIADSUtils.*` recorder, and `mist-stub.lua` is deleted. Then merge the bomb-contact feature, harden the build script, recompile, PR.

**Tech Stack:** Lua 5.1 (DCS runtime + `lua5.1` / "Lua for Windows" for the standalone suite), luaunit 3.4 (vendored), PowerShell 7 (`build-tools/build-compiled-script.ps1`), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-09-integrate-rp-harness-into-veaf-design.md` — read it alongside this plan.

## Global Constraints

- **Where the work happens:** local VEAF clone `D:\Projects\DcsLua\Skynet-IADS-VEAF`, branch `feat/integrate-rp-test-harness` (already cut from `origin/master` = `cde577d`, spec committed at `b904221`). `origin` → `VEAF/Skynet-IADS`, `rp` → `regroupement-patrouille/Skynet-IADS`. The RP clone `D:\Projects\DcsLua\Skynet-IADS` is **read-only** — never commit there.
- **Lua 5.1 only.** No `goto`, `//`, bitwise ops. `table.unpack`/`unpack` — use the `unpack or table.unpack` fallback pattern. `os` / `io` only in `test/lua/run.lua` and `test/lua/test_*.lua` — never in `dcs-stub.lua`, `dcs-fixtures.lua`, `skynet-loader.lua`.
- **Skynet source under `skynet-iads-source/*.lua` is loaded by the harness, not modified by it.** The only source that changes in this plan is whatever Task 6's merge carries. `build-tools/*` and `docs/*` are not "source".
- **Magic numbers in tests** are recomputed from code-defined fixtures with the arithmetic shown in a comment; adjust the fixture, not the assertion.
- **Commit trailer on every commit:** `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- **`// FGA`** trigram marks any customisation inside a vendored / third-party file (e.g. `test/lua/luaunit.lua`). Not needed for first-party files.
- **Interpreter:** locally `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua`; in CI `lua5.1 test/lua/run.lua`. The plan writes the command as `LUA test/lua/run.lua` — substitute your interpreter.
- **Out of scope** (do not touch): VEAF issue #3 (`harmSilenceID` cleanup), the demo-IADS-world fixture and the four DCS-only suites (`test-skynet-iads.lua`, `abstract-radar-element`, `early-warning-radar`, `red/blue-sam-sites-and-ew-radars`), standalone regression tests for the SAM-dark / bomb-contact fixes, version bump, luacheck/StyLua/luacov, `highdigitsams/`.

---

## File map

| File | Task | Responsibility after this plan |
|---|---|---|
| `test/lua/skynet-loader.lua` | 2 | loads `skynet-iads-source/*.lua` in build order — now including `skynet-iads-utils` first |
| `test/lua/dcs-stub.lua` | 2, 3 | fake DCS env: adds `coord`, a controllable `timer.scheduleFunction`, `dcsStub.fireDueTimers()`, `dcsStub.stubUtilsScheduler()`; drops the `mist.*` scheduler |
| `test/lua/test_dcs_stub.lua` | 2, 3 | tests for the above |
| `test/lua/mist-stub.lua` | 4 | **deleted** |
| `test/lua/test_mist_stub.lua` | 4 | **deleted**, replaced by `test_skynet_iads_utils.lua` |
| `test/lua/test_skynet_iads_utils.lua` | 4 | **new** — unit tests for the real `skynet-iads-source/skynet-iads-utils.lua` (math + scheduler) |
| `test/lua/test_skynet_iads_*.lua` (7 ported suites) | 4 | drop the `dofile(".../mist-stub.lua")` line; the contact suite also gains an explicit `loader.load("skynet-iads-utils")` |
| `test/lua/test_dcs_fixtures.lua` | 4 | drop the `dofile(".../mist-stub.lua")` line |
| `test/lua/test_skynet_iads_jammer.lua` | 3 | `setUp` calls `dcsStub.stubUtilsScheduler()` |
| `test/lua/README.md`, `contributing.md` | 5 | prose no longer references `mist-stub.lua` / a MiST dependency |
| `skynet-iads-source/README_source.md` | 5 | "load MIST" note softened (MiST no longer required by Skynet) |
| `build-tools/build-compiled-script.ps1` | 7 | guards the TOC step (VEAF #4) |
| `demo-missions/skynet-iads-compiled.lua` | 7 | regenerated |
| `docs/superpowers/plans/2026-09-09-integrate-rp-harness-into-veaf.md` | — | this plan |

---

## Task 1: Squash-merge RP `master`

**Files:**
- Modify (merge, working tree): the whole branch
- No test file of its own — the deliverable is "the branch now holds RP's tree; `test/lua` exists here"

**Interfaces:**
- Consumes: `rp/master` (`d94e8c8`), branch `feat/integrate-rp-test-harness` at `b904221`
- Produces: on the branch — `test/lua/` (18 files), `.github/workflows/lua-tests.yml`, `contributing.md` edits, `skynet-iads-source/skynet-iads-contact.lua` (WEAPON `getTypeName`, auto-merged), `skynet-iads-source/skynet-iads-supported-types.lua` (`Zeus`). `SkynetIADSUtils` is **not yet** wired into the loader — `LUA test/lua/run.lua` is expected to fail until Task 4.

- [ ] **Step 1: Confirm starting state**

```bash
cd /d/Projects/DcsLua/Skynet-IADS-VEAF
git branch --show-current      # feat/integrate-rp-test-harness
git log --oneline -1           # b904221 docs: design — integrate the RP standalone test harness into VEAF
git status --porcelain         # empty
git rev-parse rp/master        # d94e8c8979f2a50bc9b2acba4c8bac0b72094d3b
```

If `rp/master` is missing: `git remote add rp https://github.com/regroupement-patrouille/Skynet-IADS.git && git fetch rp`.

- [ ] **Step 2: Squash-merge**

```bash
git merge --squash rp/master
```

Expected output ends with `Automatic merge went well; stopped before committing as requested` and `Squash commit -- not updating HEAD`. Verify no conflicts:

```bash
git diff --name-only --diff-filter=U      # must be empty
git diff --cached --name-only | wc -l      # 22
```

If there is any conflict, stop — the spec's clean-merge assumption is broken; re-read both sides of the conflicting file before proceeding.

- [ ] **Step 3: Sanity-check the staged tree**

```bash
git diff --cached --stat | tail -5
test -f test/lua/run.lua && echo "test/lua present"
test -f skynet-iads-source/skynet-iads-utils.lua && echo "utils present (from VEAF base)"
grep -c "getCategory" skynet-iads-source/skynet-iads-contact.lua   # both forks' changes present
git grep -l "Zeus" skynet-iads-source/skynet-iads-supported-types.lua
```

- [ ] **Step 4: Commit the squash**

```bash
git commit -m "$(cat <<'EOF'
merge: squash the RP standalone Lua test harness (M1 + M2)

Squashes regroupement-patrouille/Skynet-IADS master (f18b919..d94e8c8)
onto this branch. Brings:

- test/lua/ — luaunit-on-plain-Lua harness + 8 ported unit-tests suites
- .github/workflows/lua-tests.yml — runs the standalone suite on push/PR
- contributing.md — documents the standalone suite
- skynet-iads-contact.lua — getTypeName returns the type for WEAPON
  contacts, not only UNIT (RP ef37ead), auto-merged with the MiST removal
- skynet-iads-supported-types.lua — 'Zues' -> 'Zeus' (RP d94e8c8)

Design rationale for the harness is in the squashed history's
docs/superpowers/specs/2026-09-03-standalone-lua-tests-design.md and
.../2026-09-06-standalone-lua-tests-m2-design.md (removed from RP master
in 35db8db as working docs).

The harness does not run green yet: the merged source calls
SkynetIADSUtils.* where RP's harness expected mist.*. Repaired in the
commits that follow, per
docs/superpowers/plans/2026-09-09-integrate-rp-harness-into-veaf.md.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
git log --oneline -3
```

- [ ] **Step 5: Record the expected-red baseline**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua ; echo "exit $LASTEXITCODE"
```

Expected: **FAIL**, several suites red (`attempt to index ... 'SkynetIADSUtils' (a nil value)` and similar). `test_harness_smoke`, `test_dcs_stub`, `test_mist_stub` should still pass. Note which suites fail — Task 4's gate is that they all pass again.

---

## Task 2: Load `skynet-iads-utils`, add the `coord` fake

**Files:**
- Modify: `test/lua/skynet-loader.lua` (the `ORDER` table)
- Modify: `test/lua/dcs-stub.lua` (add `coord`)
- Test: `test/lua/test_dcs_stub.lua` (new `coord` test), `test/lua/test_harness_smoke.lua` (already asserts `loadAll` works)

**Interfaces:**
- Consumes: `skynet-iads-source/skynet-iads-utils.lua` defines the global table `SkynetIADSUtils` with, among others, `SkynetIADSUtils.round(num, idp)`, `.get2DDist(p1,p2)`, `.get3DDist(p1,p2)`, `.metersToNM(m)`, `.metersToFeet(m)`, `.toDegree(rad)`, `.getHeading(unit, rawHeading)`, `.getNorthCorrection(point)`, `.random(a,b)`, `.scheduleFunction(fn,args,startTime,interval,stopTime)`, `.removeFunction(id)`, `.getUnitNames()`, `.getGroupNames()`. `getNorthCorrection` calls `coord.LOtoLL(vec3)` → `lat, lon` then `coord.LLtoLO(lat+1, lon)` → a point, and returns `atan2(north.z - vec3.z, north.x - vec3.x)`.
- Produces: after `loader.loadAll()` (or `loader.load("skynet-iads-utils")`), `SkynetIADSUtils` is populated; `coord` is a global whose fake makes `getNorthCorrection` return `0` for any point.

- [ ] **Step 1: Write the failing test — loader brings in SkynetIADSUtils**

In `test/lua/test_harness_smoke.lua`, add after `test_loader_loads_wrapper_and_contact`:

```lua
function TestHarnessSmoke:test_loader_loads_skynet_iads_utils()
  loader.load("skynet-iads-utils")
  luaunit.assertEquals(type(SkynetIADSUtils), "table")
  luaunit.assertEquals(type(SkynetIADSUtils.round), "function")
  luaunit.assertEquals(SkynetIADSUtils.round(2.5), 3)
end
```

- [ ] **Step 2: Run it — verify it fails**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_harness_smoke.lua
```

Expected: FAIL — `skynet-loader: cannot load 'skynet-iads-utils'` is NOT the error (the file exists); the failure is `type(SkynetIADSUtils)` is `"nil"` because the loader never loads it... actually `loader.load("skynet-iads-utils")` **will** work since the file exists on disk. The real failure mode: it passes here but `loadAll()` in other suites still doesn't include it. To be sure this step fails first, assert via `loadAll`:

```lua
function TestHarnessSmoke:test_loadAll_includes_utils()
  loader.reset()
  loader.loadAll()
  luaunit.assertEquals(type(SkynetIADSUtils), "table")
end
```

Run again — this FAILS because `skynet-iads-utils` is not in `ORDER`, so `loadAll` skips it and `SkynetIADSUtils` is `nil`.

- [ ] **Step 3: Add `skynet-iads-utils` to the loader ORDER**

In `test/lua/skynet-loader.lua`, the `ORDER` table currently starts:

```lua
local ORDER = {
  "skynet-iads-supported-types",
  "skynet-iads-logger",
  ...
```

Make `skynet-iads-utils` the first entry, matching `build-tools/build-compiled-script.ps1` (which concatenates `skynet-iads-utils.lua` before `skynet-iads-supported-types.lua`):

```lua
local ORDER = {
  "skynet-iads-utils",
  "skynet-iads-supported-types",
  "skynet-iads-logger",
  ...
```

- [ ] **Step 4: Run the smoke suite — verify it passes**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_harness_smoke.lua
```

Expected: PASS.

- [ ] **Step 5: Write the failing test — coord gives zero north correction**

In `test/lua/test_dcs_stub.lua`, add before `os.exit(...)`:

```lua
function TestDcsStub:test_coord_zero_north_correction()
  -- SkynetIADSUtils.getNorthCorrection does:
  --   lat, lon = coord.LOtoLL(p);  n = coord.LLtoLO(lat + 1, lon)
  --   return atan2(n.z - p.z, n.x - p.x)
  -- The standalone world has no theatre, so "one degree north" must lie purely
  -- along +x for the correction to be 0 (grid heading == true heading), which
  -- is what the old mist-stub did by dropping the term entirely.
  local p = { x = 1234, y = 0, z = -567 }
  local lat, lon = coord.LOtoLL(p)
  local n = coord.LLtoLO(lat + 1, lon)
  luaunit.assertAlmostEquals(n.z - p.z, 0, 1e-6)
  luaunit.assertEquals((n.x - p.x) > 0, true)
end
```

- [ ] **Step 6: Run it — verify it fails**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_dcs_stub.lua
```

Expected: FAIL — `attempt to index global 'coord' (a nil value)`.

- [ ] **Step 7: Add the `coord` fake to `dcs-stub.lua`**

In `test/lua/dcs-stub.lua`, next to the other enum/singleton globals (after the `land = { ... }` block is fine):

```lua
-- coord: map metres <-> lat/lon. The standalone world has no theatre; this is a
-- linear fake with north == +x, present only so
-- SkynetIADSUtils.getNorthCorrection evaluates to 0 (the old mist-stub dropped
-- the correction term outright — same net effect).
coord = {
  LOtoLL = function(vec3)
    return vec3.x / 111000, vec3.z / 111000 -- lat from +x, lon from +z
  end,
  LLtoLO = function(lat, lon)
    return { x = lat * 111000, y = 0, z = lon * 111000 }
  end,
}
```

- [ ] **Step 8: Run `test_dcs_stub.lua` — verify it passes**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_dcs_stub.lua
```

Expected: PASS (the pre-existing `mist.scheduleFunction` scheduler tests still pass — they are rewired in Task 3).

- [ ] **Step 9: Run the full suite — record progress**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua ; echo "exit $LASTEXITCODE"
```

Expected: the math-driven suites (`contact`, `abstract-dcs-object-wrapper`, `harm-detection`, `abstract-element`, `sam-site`, `moose-a2a-connector`, `dcs-fixtures`) now **pass** — the source's `SkynetIADSUtils.*` math calls resolve and `getMagneticHeading` gets a 0 correction. `jammer` still **fails** (scheduler: `SkynetIADSUtils.scheduleFunction` hits the real module, not the recorder `scheduledCount()` reads). `test_mist_stub` still passes. Note the remaining failures for Task 3 / 4.

- [ ] **Step 10: Commit**

```bash
git add test/lua/skynet-loader.lua test/lua/dcs-stub.lua test/lua/test_dcs_stub.lua test/lua/test_harness_smoke.lua
git commit -m "$(cat <<'EOF'
test(lua): load skynet-iads-utils in the loader, add a coord fake

The MiST removal made the source call SkynetIADSUtils.* for the
arithmetic and headings the harness previously satisfied with mist-stub.
Add skynet-iads-utils as the first loader entry (matching the compiled
build order) and a linear coord fake that zeroes getNorthCorrection, so
getMagneticHeading and the distance/rounding paths resolve against the
real module. mist-stub is still present; it is removed in a later commit.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Move the fake scheduler onto `SkynetIADSUtils`

**Files:**
- Modify: `test/lua/dcs-stub.lua` — replace the `mist.scheduleFunction`/`mist.removeFunction` fake with a controllable `timer.scheduleFunction` + `dcsStub.fireDueTimers()`, and add `dcsStub.stubUtilsScheduler()` + rework `dcsStub.scheduledCount()`
- Modify: `test/lua/test_dcs_stub.lua` — rewrite the two scheduler tests
- Modify: `test/lua/test_skynet_iads_jammer.lua` — `setUp` installs the recorder

**Interfaces:**
- Consumes: the real `SkynetIADSUtils.scheduleFunction(fn, args, startTime, interval, stopTime)` calls `timer.scheduleFunction(runScheduledTask, id, startTime)` internally and returns its own integer id; `SkynetIADSUtils.removeFunction(id)` returns `true` on a hit, `false` otherwise (booleans, unlike the M2 fake which returned the id / nil).
- Produces:
  - `timer.scheduleFunction(fn, arg, time)` → integer id; records `{fn, arg, time}`. `timer.removeFunction(id)` → drops it.
  - `dcsStub.fireDueTimers()` → runs every recorded task whose `time <= dcsStub.now()`, in id order; if the task's `fn(arg)` returns a number, re-records it at that time, else drops it. (Mirrors the DCS timer contract that `SkynetIADSUtils`' `runScheduledTask` relies on.)
  - `dcsStub.stubUtilsScheduler()` → overwrites `SkynetIADSUtils.scheduleFunction` / `.removeFunction` with no-fire recorders; must be called **after** `loader.loadAll()`, typically in a suite's `setUp` after `dcsStub.reset()`.
  - `dcsStub.scheduledCount()` → number of tasks held by the `stubUtilsScheduler` recorder; **asserts** if `stubUtilsScheduler()` was not installed.

- [ ] **Step 1: Write the failing test — controllable timer**

In `test/lua/test_dcs_stub.lua`, replace `test_scheduler_ids_and_removal` and `test_reset_clears_scheduler` with:

```lua
function TestDcsStub:test_timer_scheduleFunction_records_and_fires()
  local ran = {}
  local id = timer.scheduleFunction(function(arg) ran[#ran + 1] = arg; return nil end, "A", 10)
  luaunit.assertEquals(id, 1)
  dcsStub.setClock(5)
  dcsStub.fireDueTimers() -- nothing due yet
  luaunit.assertEquals(#ran, 0)
  dcsStub.setClock(10)
  dcsStub.fireDueTimers()
  luaunit.assertEquals(ran, { "A" })
  dcsStub.fireDueTimers() -- one-shot task is gone
  luaunit.assertEquals(#ran, 1)
end

function TestDcsStub:test_timer_scheduleFunction_reschedules_on_numeric_return()
  local n = 0
  timer.scheduleFunction(function() n = n + 1; return dcsStub.now() + 10 end, nil, 10)
  dcsStub.setClock(10); dcsStub.fireDueTimers()
  dcsStub.setClock(20); dcsStub.fireDueTimers()
  dcsStub.setClock(20); dcsStub.fireDueTimers() -- same tick, not due again
  luaunit.assertEquals(n, 2)
end

function TestDcsStub:test_reset_clears_timers()
  timer.scheduleFunction(function() end, nil, 1)
  dcsStub.reset()
  luaunit.assertEquals(timer.scheduleFunction(function() end, nil, 1), 1) -- id counter reset
end
```

- [ ] **Step 2: Run it — verify it fails**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_dcs_stub.lua
```

Expected: FAIL — `attempt to call field 'scheduleFunction' (a nil value)` (only `timer.getAbsTime` / `getTime` exist today).

- [ ] **Step 3: Implement the controllable timer in `dcs-stub.lua`**

Replace the current scheduler block (the `mist = mist or {}` / `mist.scheduleFunction` / `mist.removeFunction` section, ~lines 108-124) with:

```lua
-- Controllable timer. SkynetIADSUtils' scheduler runs on top of this; no task
-- fires until a test calls dcsStub.fireDueTimers(), matching what a synchronous
-- luaunit run sees. dcsStub.reset() clears it.
local timerTasks = {}
local nextTimerId = 0

function timer.scheduleFunction(fn, arg, time)
  nextTimerId = nextTimerId + 1
  timerTasks[nextTimerId] = { fn = fn, arg = arg, time = time }
  return nextTimerId
end
function timer.removeFunction(id)
  timerTasks[id] = nil
end
function dcsStub.fireDueTimers()
  local ids = {}
  for id in pairs(timerTasks) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local task = timerTasks[id]
    if task and task.time <= now then
      local nextTime = task.fn(task.arg)
      if type(nextTime) == "number" then
        task.time = nextTime
      else
        timerTasks[id] = nil
      end
    end
  end
end
```

Add `timerTasks = {}` and `nextTimerId = 0` resets inside `dcsStub.reset()` (alongside the existing `scheduled = {}` / `nextScheduleId = 0` lines — remove those two, they belonged to the deleted `mist` fake).

- [ ] **Step 4: Run it — verify it passes**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_dcs_stub.lua
```

Expected: PASS.

- [ ] **Step 5: Write the failing test — stubUtilsScheduler recorder**

Add to `test/lua/test_dcs_stub.lua` (this test loads the source, so it needs the loader — add the two `dofile`/loader lines at the top of the file if not present, mirroring `test_harness_smoke.lua`):

At the top, after `dofile(base .. "/dcs-stub.lua")`:

```lua
local loader = dofile(base .. "/skynet-loader.lua")
loader.load("skynet-iads-utils")
```

Then:

```lua
function TestDcsStub:test_stubUtilsScheduler_records_without_firing()
  dcsStub.stubUtilsScheduler()
  luaunit.assertEquals(dcsStub.scheduledCount(), 0)
  local fired = false
  local id = SkynetIADSUtils.scheduleFunction(function() fired = true end, {}, 1, 10)
  luaunit.assertEquals(dcsStub.scheduledCount(), 1)
  luaunit.assertEquals(fired, false) -- recorder never fires
  luaunit.assertEquals(SkynetIADSUtils.removeFunction(id), true)
  luaunit.assertEquals(SkynetIADSUtils.removeFunction(id), false)
  luaunit.assertEquals(dcsStub.scheduledCount(), 0)
end

function TestDcsStub:test_scheduledCount_asserts_without_recorder()
  -- fresh reset, recorder not installed
  luaunit.assertErrorMsgContains("stubUtilsScheduler", dcsStub.scheduledCount)
end
```

Note: `dcsStub.reset()` in `setUp` must clear the recorder so `test_scheduledCount_asserts_without_recorder` sees no recorder. Order the tests' expectations accordingly (luaunit runs alphabetically; `setUp` resets each time).

- [ ] **Step 6: Run it — verify it fails**

Expected: FAIL — `attempt to call field 'stubUtilsScheduler' (a nil value)`.

- [ ] **Step 7: Implement `stubUtilsScheduler` + `scheduledCount`**

In `test/lua/dcs-stub.lua`, add after the timer block:

```lua
-- A no-fire recorder for SkynetIADSUtils' scheduler. A ported suite that mocks
-- the whole SAM/radar/IADS surface and drives runCycle by hand installs this in
-- setUp (after loader.loadAll()) so "is anything still scheduled?" is a stable
-- count, not dependent on the real scheduler's re-arm timing.
local utilsSchedulerTasks = nil

function dcsStub.stubUtilsScheduler()
  utilsSchedulerTasks = {}
  local n = 0
  SkynetIADSUtils.scheduleFunction = function(fn, args)
    n = n + 1
    utilsSchedulerTasks[n] = { fn = fn, args = args }
    return n
  end
  SkynetIADSUtils.removeFunction = function(id)
    if id ~= nil and utilsSchedulerTasks[id] ~= nil then
      utilsSchedulerTasks[id] = nil
      return true
    end
    return false
  end
end

function dcsStub.scheduledCount()
  assert(utilsSchedulerTasks, "dcsStub.scheduledCount: call dcsStub.stubUtilsScheduler() first")
  local c = 0
  for _ in pairs(utilsSchedulerTasks) do c = c + 1 end
  return c
end
```

In `dcsStub.reset()`, add `utilsSchedulerTasks = nil`. Remove the old `function dcsStub.scheduledCount()` that counted `scheduled`.

- [ ] **Step 8: Run it — verify it passes**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_dcs_stub.lua
```

Expected: PASS.

- [ ] **Step 9: Wire the jammer suite**

In `test/lua/test_skynet_iads_jammer.lua`, `setUp` currently is:

```lua
function TestSkynetIADSJammer:setUp()
  dcsStub.reset()
  self.emitter = dcsStub.makeUnit({ name = "jammer-source", type = "F-16C", pos = { x = 0, y = 1000, z = 0 } })
  ...
```

Add the recorder right after `dcsStub.reset()`:

```lua
function TestSkynetIADSJammer:setUp()
  dcsStub.reset()
  dcsStub.stubUtilsScheduler()
  self.emitter = dcsStub.makeUnit({ name = "jammer-source", type = "F-16C", pos = { x = 0, y = 1000, z = 0 } })
  ...
```

`testDestroyEmitter` calls `self:tearDown()` then rebuilds — `tearDown` runs `self.jammer:masterArmSafe()`, which calls the recorder's `removeFunction`; fine. No other change: the `dcsStub.scheduledCount()` assertions on lines ~95-98 and ~124-129 now read the recorder.

- [ ] **Step 10: Run the jammer suite — verify it passes**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_skynet_iads_jammer.lua
```

Expected: PASS. If another ported suite now fails because a real `SkynetIADSUtils.scheduleFunction` call accumulates (e.g. a `scanForHarms` path), add `dcsStub.stubUtilsScheduler()` to that suite's `setUp` too — same one-line fix.

- [ ] **Step 11: Run the full suite**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua ; echo "exit $LASTEXITCODE"
```

Expected: everything green **except** `test_mist_stub` may still pass (it does — mist-stub still there). All the real suites pass. If `run.lua` is green here, Task 4 is cleanup + the new util suite.

- [ ] **Step 12: Commit**

```bash
git add test/lua/dcs-stub.lua test/lua/test_dcs_stub.lua test/lua/test_skynet_iads_jammer.lua
git commit -m "$(cat <<'EOF'
test(lua): run the fake scheduler through SkynetIADSUtils, not mist

dcs-stub now provides a controllable timer.scheduleFunction +
dcsStub.fireDueTimers() (so the real SkynetIADSUtils scheduler can be
unit-tested), and dcsStub.stubUtilsScheduler() — a no-fire recorder the
ported suites install in setUp so scheduledCount() stays stable. The
jammer suite uses the recorder. The old mist.scheduleFunction fake is
gone.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Delete `mist-stub.lua`, add `test_skynet_iads_utils.lua`

**Files:**
- Delete: `test/lua/mist-stub.lua`, `test/lua/test_mist_stub.lua`
- Create: `test/lua/test_skynet_iads_utils.lua`
- Modify: `test/lua/test_skynet_iads_contact.lua`, `test_skynet_iads_harm_detection.lua`, `test_skynet_iads_abstract_dcs_object_wrapper.lua`, `test_skynet_iads_abstract_element.lua`, `test_skynet_iads_sam_site.lua`, `test_skynet_moose_a2a_dispatcher_connector.lua`, `test_skynet_iads_jammer.lua`, `test_dcs_fixtures.lua` — drop the `dofile(".../mist-stub.lua")` line
- Modify: `test/lua/test_skynet_iads_contact.lua` — add `loader.load("skynet-iads-utils")` before the other `loader.load` calls (this suite loads specific modules, not `loadAll`)

**Interfaces:**
- Consumes: `SkynetIADSUtils` (real module, loaded via the loader), `dcsStub.stubUtilsScheduler()` / `dcsStub.fireDueTimers()` from Task 3
- Produces: `test_skynet_iads_utils.lua` covering the real module's math and scheduler; no file in `test/lua` references `mist` any more

- [ ] **Step 1: Create `test_skynet_iads_utils.lua` (failing — module behaviours)**

`test/lua/test_skynet_iads_utils.lua`:

```lua
--- Unit tests for skynet-iads-source/skynet-iads-utils.lua — the MiST-free
--- replacement for the ~13 helpers Skynet used to borrow from MiST. Replaces
--- the old test_mist_stub.lua (mist-stub.lua is deleted).
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.load("skynet-iads-utils")

TestSkynetIADSUtils = {}

function TestSkynetIADSUtils:setUp()
  dcsStub.reset()
end

-- ---- arithmetic (was test_mist_stub) --------------------------------

function TestSkynetIADSUtils:test_round()
  luaunit.assertEquals(SkynetIADSUtils.round(5015.0), 5015)
  luaunit.assertEquals(SkynetIADSUtils.round(2.4), 2)
  luaunit.assertEquals(SkynetIADSUtils.round(2.5), 3)
  luaunit.assertEquals(SkynetIADSUtils.round(1.2345, 2), 1.23)
end

function TestSkynetIADSUtils:test_conversions()
  luaunit.assertAlmostEquals(SkynetIADSUtils.toDegree(math.pi), 180, 1e-9)
  luaunit.assertAlmostEquals(SkynetIADSUtils.metersToNM(1852), 1, 1e-9)
  luaunit.assertAlmostEquals(SkynetIADSUtils.metersToFeet(0.3048), 1, 1e-9)
end

function TestSkynetIADSUtils:test_get2DDist_ignores_altitude()
  local a = { x = 0, y = 9999, z = 0 }
  local b = { x = 3, y = 0, z = 4 }
  luaunit.assertAlmostEquals(SkynetIADSUtils.get2DDist(a, b), 5, 1e-9)
end

function TestSkynetIADSUtils:test_get3DDist()
  luaunit.assertAlmostEquals(SkynetIADSUtils.get3DDist({ x = 0, y = 0, z = 0 }, { x = 3, y = 0, z = 4 }), 5, 1e-9)
  luaunit.assertAlmostEquals(SkynetIADSUtils.get3DDist({ x = 0, y = 0, z = 0 }, { x = 0, y = 12, z = 0 }), 12, 1e-9)
end

function TestSkynetIADSUtils:test_random_in_range()
  for _ = 1, 20 do
    local r = SkynetIADSUtils.random(3, 5)
    luaunit.assertEquals(r >= 3 and r <= 5, true)
  end
  luaunit.assertEquals(SkynetIADSUtils.random(1) >= 1, true)
end

-- ---- headings ------------------------------------------------------

function TestSkynetIADSUtils:test_getHeading_raw_wraps_into_0_2pi()
  local u = dcsStub.makeUnit({ heading = math.rad(347) })
  -- rawHeading = true skips the coord-based north correction
  luaunit.assertAlmostEquals(SkynetIADSUtils.getHeading(u, true), math.rad(347), 1e-6)
end

function TestSkynetIADSUtils:test_getHeading_nil_position()
  local nofix = { getPosition = function() return nil end }
  luaunit.assertNil(SkynetIADSUtils.getHeading(nofix))
end

function TestSkynetIADSUtils:test_getNorthCorrection_zero_with_coord_fake()
  luaunit.assertAlmostEquals(SkynetIADSUtils.getNorthCorrection({ x = 100, y = 0, z = 200 }), 0, 1e-6)
end

-- ---- scheduler ---------------------------------------------------

function TestSkynetIADSUtils:test_scheduleFunction_runs_once_via_timer()
  local ran = 0
  SkynetIADSUtils.scheduleFunction(function() ran = ran + 1 end, {}, 1)
  dcsStub.setClock(1)
  dcsStub.fireDueTimers()
  luaunit.assertEquals(ran, 1)
  dcsStub.setClock(100)
  dcsStub.fireDueTimers()
  luaunit.assertEquals(ran, 1) -- one-shot
end

function TestSkynetIADSUtils:test_scheduleFunction_repeats()
  local ran = 0
  SkynetIADSUtils.scheduleFunction(function() ran = ran + 1 end, {}, 1, 10)
  dcsStub.setClock(1);  dcsStub.fireDueTimers()
  dcsStub.setClock(11); dcsStub.fireDueTimers()
  dcsStub.setClock(21); dcsStub.fireDueTimers()
  luaunit.assertEquals(ran, 3)
end

function TestSkynetIADSUtils:test_scheduleFunction_clamps_past_start_time()
  -- a first run asked for a time already past must still happen (VEAF #5 /
  -- cde577d): the module arms it no earlier than now + MINIMUM_DELAY.
  local ran = false
  dcsStub.setClock(200)
  SkynetIADSUtils.scheduleFunction(function() ran = true end, {}, 1) -- start 1s, clock 200
  dcsStub.setClock(200.01)
  dcsStub.fireDueTimers()
  luaunit.assertEquals(ran, true)
end

function TestSkynetIADSUtils:test_repeating_task_that_throws_is_logged_and_keeps_going()
  local calls = 0
  SkynetIADSUtils.scheduleFunction(function()
    calls = calls + 1
    if calls == 1 then error("boom") end
  end, {}, 1, 10)
  dcsStub.setClock(1);  dcsStub.fireDueTimers() -- throws, caught
  dcsStub.setClock(11); dcsStub.fireDueTimers() -- still scheduled
  luaunit.assertEquals(calls, 2)
  local sawError = false
  for _, e in ipairs(dcsStub.logs) do
    if tostring(e.text):find("boom", 1, true) then sawError = true end
  end
  luaunit.assertEquals(sawError, true)
end

function TestSkynetIADSUtils:test_removeFunction_returns_boolean()
  local id = SkynetIADSUtils.scheduleFunction(function() end, {}, 1, 10)
  luaunit.assertEquals(SkynetIADSUtils.removeFunction(id), true)
  luaunit.assertEquals(SkynetIADSUtils.removeFunction(id), false)
  luaunit.assertEquals(SkynetIADSUtils.removeFunction(nil), false)
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run it — verify current failures**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_skynet_iads_utils.lua
```

Expected: mostly PASS already (the module is real and correct). The likely FAIL is `test_scheduleFunction_clamps_past_start_time` or the repeat tests **if** `dcsStub.fireDueTimers()` does not model re-arm the way `runScheduledTask` expects (it returns `timer.getTime() + repeatInterval`). Fix `fireDueTimers` (Task 3 Step 3) until these pass — this is the point of testing the real scheduler. Do not weaken the assertions.

- [ ] **Step 3: Delete the mist-stub files**

```bash
git rm test/lua/mist-stub.lua test/lua/test_mist_stub.lua
```

- [ ] **Step 4: Drop the `dofile(mist-stub)` lines**

In each of these files remove the single line `dofile(base .. "/mist-stub.lua")`:

- `test/lua/test_skynet_iads_contact.lua`
- `test/lua/test_skynet_iads_harm_detection.lua`
- `test/lua/test_skynet_iads_abstract_dcs_object_wrapper.lua`
- `test/lua/test_skynet_iads_abstract_element.lua`
- `test/lua/test_skynet_iads_sam_site.lua`
- `test/lua/test_skynet_moose_a2a_dispatcher_connector.lua`
- `test/lua/test_skynet_iads_jammer.lua`
- `test/lua/test_dcs_fixtures.lua`

In `test/lua/test_skynet_iads_contact.lua` only, add an explicit utils load — this suite loads named modules, not `loadAll`. The lines currently read:

```lua
local loader = dofile(base .. "/skynet-loader.lua")
loader.load("skynet-iads-abstract-dcs-object-wrapper")
loader.load("skynet-iads-contact")
```

Change to:

```lua
local loader = dofile(base .. "/skynet-loader.lua")
loader.load("skynet-iads-utils")
loader.load("skynet-iads-abstract-dcs-object-wrapper")
loader.load("skynet-iads-contact")
```

- [ ] **Step 5: Run the full suite — verify green**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua ; echo "exit $LASTEXITCODE"
```

Expected: **ALL SUITE(S) PASSED**, exit 0. `test_mist_stub` is gone; `test_skynet_iads_utils` is listed and green. This restores the Task 1 baseline to all-green.

- [ ] **Step 6: Grep-check no `mist` reference remains in the harness**

```bash
grep -rn "mist" test/lua/    # expect: no matches (or only an unrelated word in a comment — inspect each)
```

- [ ] **Step 7: Commit**

```bash
git add -A test/lua/
git commit -m "$(cat <<'EOF'
test(lua): replace mist-stub with tests against the real skynet-iads-utils

skynet-iads-utils.lua is the real module now, so mist-stub.lua only
duplicated it. Deleted it and test_mist_stub.lua; added
test_skynet_iads_utils.lua covering the module's arithmetic, headings
(via the coord fake), and the scheduler — one-shot, repeat, the
past-start-time clamp (VEAF #5), and the pcall guard on a throwing
repeating task. Dropped the dofile(mist-stub) line from the eight suites
that carried it; the contact suite now loads skynet-iads-utils
explicitly since it does not call loadAll.

Full standalone suite green.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Documentation

**Files:**
- Modify: `test/lua/README.md`, `contributing.md`, `skynet-iads-source/README_source.md`

**Interfaces:** none (docs only)

- [ ] **Step 1: `test/lua/README.md`**

Remove the `mist-stub.lua` row from the Files table. In the "Files" table add a row:

```
| `test_skynet_iads_utils.lua` | Unit tests for the real `skynet-iads-utils.lua` (math + scheduler) |
```

Anywhere the text says the source "calls `mist`" or tests need `mist-stub`, rewrite to: the source is MiST-free and calls `SkynetIADSUtils` (loaded first by `skynet-loader.lua`); `dcs-stub.lua` provides the DCS globals it reaches (`coord`, a controllable `timer.scheduleFunction`).

- [ ] **Step 2: `contributing.md`**

Around line 38, the instruction currently reads (paraphrased) "add a `test/lua/test_<module>.lua` that `dofile`s `luaunit.lua`, `dcs-stub.lua`, `mist-stub.lua`, loads the source module(s)...". Drop `mist-stub.lua` from that list.

- [ ] **Step 3: `skynet-iads-source/README_source.md`**

Find the line telling users to "load MIST and the compiled skynet code into a mission" (root `README.md` line ~245 is generated from here). Soften to note MiST is **no longer required by Skynet itself** — the compiled script is a drop-in — though the demo missions still bundle `mist_4_5_107.lua`. Do not regenerate `README.md` here (that happens in Task 7's build run).

- [ ] **Step 4: Commit**

```bash
git add test/lua/README.md contributing.md skynet-iads-source/README_source.md
git commit -m "$(cat <<'EOF'
docs: drop the MiST-dependency and mist-stub references

The source is MiST-free (skynet-iads-utils.lua); the standalone harness
loads the real module and no longer has a mist-stub. Update the test/lua
README, contributing.md, and the README source's "load MIST" note.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Merge `feature-inform-bomb-contact`

**Files:**
- Modify (merge): `skynet-iads-source/skynet-iads.lua`

**Interfaces:**
- Consumes: `origin/feature-inform-bomb-contact` (`ad60e92`) — one commit, based on the shared ancestor `62aab46`. Rewrites the per-contact category filter in `SkynetIADS.evaluateContacts` to use `Object.getCategory(contact:getDCSRepresentation())` and handle `Object.Category.WEAPON` (so a Phalanx is informed of inbound bombs).
- Produces: `evaluateContacts` on the branch has both the SAM-collection change (VEAF `3a94937`, top of the loop) and the category-filter change (`ad60e92`, per-contact test).

- [ ] **Step 1: Merge**

```bash
cd /d/Projects/DcsLua/Skynet-IADS-VEAF
git merge origin/feature-inform-bomb-contact -m "$(cat <<'EOF'
Merge feature-inform-bomb-contact: inform SAM sites of inbound weapons

evaluateContacts() classified a contact by description.category assuming
it was always a unit; a bomb (Weapon.Category.BOMB == Unit.Category.SHIP)
was therefore never handed to a SAM site, so a Phalanx sat idle while
bombs were inbound. Now the contact's Object.getCategory() decides
UNIT vs WEAPON first, and WEAPON contacts (minus SHELL/ROCKET) are
informed.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 2: Check for conflict**

```bash
git diff --name-only --diff-filter=U
```

Expected: empty. If `skynet-iads-source/skynet-iads.lua` conflicts, resolve by **keeping both** hunks:
- the top-of-loop change from `3a94937` — SAM sites added to `samSitesToTrigger` even when already active (no `isActive() == false` guard)
- the per-contact change from `ad60e92` — `Object.getCategory(...)` gate with the `objectCategory == Object.Category.WEAPON` branch
Then `git add skynet-iads-source/skynet-iads.lua && git commit --no-edit`.

- [ ] **Step 3: Run the standalone suite**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua ; echo "exit $LASTEXITCODE"
```

Expected: **ALL PASSED**, exit 0. The `evaluateContacts` orchestrator path is not covered by a ported suite (it is the deferred milestone), so this merge should not move the suite — a red result means the merge broke a module load; investigate before continuing.

- [ ] **Step 4: Eyeball the merged function**

```bash
git grep -n -A30 "function SkynetIADS.evaluateContacts" skynet-iads-source/skynet-iads.lua
```

Confirm both changes are present and the `SkynetIADSUtils.*` renames from `fe40c4a` are intact in the surrounding code (the merge base for this branch already had them).

---

## Task 7: Harden the build script, recompile, verify

**Files:**
- Modify: `build-tools/build-compiled-script.ps1`
- Modify (generated): `demo-missions/skynet-iads-compiled.lua`, `README.md`

**Interfaces:**
- Consumes: the finished source tree
- Produces: a regenerated compiled artefact containing the two RP source fixes and the bomb-contact change and **no `mist.` call**

- [ ] **Step 1: Add the TOC guard (VEAF #4)**

In `build-tools/build-compiled-script.ps1`, the README regeneration currently does:

```powershell
$toc = ./bin/gh-md-toc.exe --hide-footer ../skynet-iads-source/README_source.md
```

then unconditionally deletes and rewrites `../README.md`. Immediately after the `$toc = ...` line, insert:

```powershell
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($toc)) {
    Write-Error "Table of contents generation failed; leaving README.md untouched."
    return
}
```

- [ ] **Step 2: Parse-check every source file**

```bash
cd /d/Projects/DcsLua/Skynet-IADS-VEAF
for f in skynet-iads-source/*.lua skynet-iads-source/highdigitsams/*.lua; do
  & "C:\Program Files (x86)\Lua\5.1\luac.exe" -p "$f" || echo "PARSE FAIL: $f"
done
```

Expected: no `PARSE FAIL` lines. (If `luac.exe` is unavailable, `lua.exe -e "assert(loadfile[[$f]])"` per file.)

- [ ] **Step 3: Run the build script**

```powershell
cd D:\Projects\DcsLua\Skynet-IADS-VEAF\build-tools
pwsh -File ./build-compiled-script.ps1
```

- [ ] **Step 4: Verify the artefact**

```bash
cd /d/Projects/DcsLua/Skynet-IADS-VEAF
& "C:\Program Files (x86)\Lua\5.1\lua.exe" -e "assert(loadfile('demo-missions/skynet-iads-compiled.lua')); print('compiled parses')"
grep -nE "mist\.[a-zA-Z]" demo-missions/skynet-iads-compiled.lua        # expect: no matches
git diff --stat -- README.md                                            # expect: no change, or only intended TOC
```

If `README.md` shows a large deletion, the guard from Step 1 failed to fire — fix it, `git checkout -- README.md`, re-run the build.

- [ ] **Step 5: Diff the artefact against the previous one**

```bash
git diff -- demo-missions/skynet-iads-compiled.lua | grep -E "^[+-]" | grep -vE "^[+-]{3}" | head -80
```

Every change should trace to: the bomb-contact `evaluateContacts` rewrite, `getTypeName` WEAPON, `Zues`→`Zeus`, or the build banner/timestamp. Anything else — stop and investigate.

- [ ] **Step 6: Full standalone suite once more**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua ; echo "exit $LASTEXITCODE"
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add build-tools/build-compiled-script.ps1 demo-missions/skynet-iads-compiled.lua README.md
git commit -m "$(cat <<'EOF'
build: guard the TOC step (VEAF #4), recompile

gh-md-toc.exe failing left README.md with its table of contents replaced
by a blank line and the build still reporting success. Bail out instead
when $LASTEXITCODE is non-zero or $toc is empty.

Recompiled skynet-iads-compiled.lua: picks up the inform-of-bomb-contact
change in evaluateContacts, getTypeName for WEAPON contacts, and the
Zeus typo. No mist. call remains in the artefact.

Closes VEAF/Skynet-IADS#4

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Push and open the PR

**Files:** none

- [ ] **Step 1: Push the branch**

```bash
cd /d/Projects/DcsLua/Skynet-IADS-VEAF
git push -u origin feat/integrate-rp-test-harness
```

- [ ] **Step 2: Confirm CI ran**

Check the Actions tab for `VEAF/Skynet-IADS` — `.github/workflows/lua-tests.yml` should run on the branch push and pass (`lua5.1 test/lua/run.lua`, exit 0).

- [ ] **Step 3: Open the PR**

```bash
gh pr create --repo VEAF/Skynet-IADS --base master --head feat/integrate-rp-test-harness \
  --title "Integrate the RP standalone test harness; merge inform-of-bomb-contact" \
  --body "$(cat <<'EOF'
Consolidates `regroupement-patrouille/Skynet-IADS` into this repo, which
becomes the canonical line.

## What lands

- **`test/lua/` standalone Lua test harness** (RP M1 + M2, squashed) — luaunit
  on a plain Lua 5.1 interpreter, 8 ported unit-test suites, plus
  `.github/workflows/lua-tests.yml` running them on push/PR.
- **Harness repaired for the MiST-free source** — loads the real
  `skynet-iads-utils.lua`, `dcs-stub.lua` gained a `coord` fake and a
  controllable `timer.scheduleFunction`, the fake scheduler moved onto a
  `SkynetIADSUtils` recorder, `mist-stub.lua` deleted and replaced by
  `test_skynet_iads_utils.lua`.
- **`getTypeName` for WEAPON contacts** and the **`Zues`→`Zeus`** fix (RP).
- **`feature-inform-bomb-contact`** merged — SAM sites (Phalanx) are now
  informed of inbound weapons, not just aircraft.
- **Build script guarded** against the README-truncation failure — closes #4.
- Compiled artefact regenerated; no `mist.` call remains.

## Deferred (not in this PR)

- **#3** (`cleanUp()` leaves `harmSilenceID` stale) — real bug, untouched here.
- The demo-IADS-world fixture and the four DCS-only orchestrator suites
  (`test-skynet-iads`, `abstract-radar-element`, `early-warning-radar`,
  `red/blue-sam-sites-and-ew-radars`) — next milestone, with standalone
  regression tests for the SAM-dark fix and inform-of-bomb-contact.
  Interim coverage: VEAF's in-`.miz` `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage`.

Design + plan: `docs/superpowers/specs/2026-09-09-integrate-rp-harness-into-veaf-design.md`,
`docs/superpowers/plans/2026-09-09-integrate-rp-harness-into-veaf.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Post-merge follow-ups (for David / Flogas, not this session)**

Record in the PR description or a comment:
- archive `regroupement-patrouille/Skynet-IADS` (or convert to a pointer)
- close RP PR #4 with a note that `3a94937` landed here via the consolidation
- start `docs/superpowers/specs/2026-09-DD-demo-iads-world-fixture-design.md`

---

## Self-Review

**1. Spec coverage**

| Spec item | Task |
|---|---|
| Squash-merge RP `master` | 1 |
| Loader: add `skynet-iads-utils` | 2 |
| `dcs-stub`: `coord` for zero north-correction | 2 |
| `dcs-stub`: controllable `timer.scheduleFunction` | 3 |
| `dcs-stub`: scheduler moved off `mist.*` | 3 |
| `removeFunction` boolean return shape | 3 (recorder), 4 (real-module test) |
| Delete `mist-stub.lua` + repoint suites | 4 |
| `test_skynet_iads_utils.lua` (real module tests) | 4 |
| `contact` suite explicit `loader.load("skynet-iads-utils")` | 4 |
| Docs: README/contributing MiST references | 5 |
| Merge `feature-inform-bomb-contact` | 6 |
| Build-script TOC guard (VEAF #4) | 7 |
| Recompile + verify no `mist.` | 7 |
| PR into `VEAF/master`, defer #3 + fixture milestone | 8 |
| `coalition` fake | **deliberately omitted** — no ported suite reaches `getUnitNames`/`getGroupNames` (spec: "add only if a suite forces it"). Noted in Task 3 interfaces as a reactive add. |

No spec requirement is left without a task.

**2. Placeholder scan** — no "TBD"/"handle edge cases"/"similar to Task N". Every code step has literal code. Task 5 Step 3 is prose-only but it is a doc edit with the exact line identified, not code.

**3. Type consistency**
- `dcsStub.stubUtilsScheduler()` — defined Task 3 Step 7, consumed Task 3 Step 9, Task 4. Same name throughout.
- `dcsStub.scheduledCount()` — redefined in Task 3 Step 7 (asserts if no recorder); old definition removed same step. Consumers (jammer suite) unchanged because the call signature is identical.
- `dcsStub.fireDueTimers()` — defined Task 3 Step 3, consumed Task 3 Step 1/5 and Task 4 Step 1. Same name.
- `timer.scheduleFunction(fn, arg, time)` — the DCS 3-arg form; `SkynetIADSUtils.scheduleFunction(fn, args, startTime, interval, stopTime)` — the 5-arg module form. Distinct on purpose; the module calls the former internally.
- `SkynetIADSUtils.removeFunction` returns `true`/`false` — asserted consistently in Task 3 Step 5 and Task 4 Step 1.
- `coord.LOtoLL` returns `lat, lon` (two values); `coord.LLtoLO(lat, lon)` returns a `{x,y,z}` table — used consistently in Task 2 Steps 5 and 7.

**4. Ordering sanity** — the full-suite gate is: red after Task 1 (expected), math suites green after Task 2, jammer green after Task 3, **all green after Task 4**, still green after Tasks 6 and 7. Each task also has a local test gate before its commit.
