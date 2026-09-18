# `test/insim/` Live-DCS Test Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a third test tier that runs luaunit-style scenarios inside a live DCS mission,
hot-reloaded from disk via an F10 menu, and prove it with one scenario that waits for real radar
detection.

**Architecture:** A near-empty Caucasus mission embeds a ~15-line bootstrap that `dofile`s a
runner from the repo. The runner loads Skynet source fresh from disk on every run, then drives
each test as a coroutine resumed on a `timer.scheduleFunction` tick, so tests can wait for
simulated time to pass. Fixtures are authored in the Mission Editor, extracted offline to
diffable Lua, and added at runtime under test-scoped names.

**Tech Stack:** Lua 5.1 (DCS ships LuaJIT; `test/lua` runs stock 5.1 — code must work on both),
luaunit 3.4 assertions only, stock DCS scripting API, no mist, no MOOSE, no external process.

**Spec:** [docs/superpowers/specs/2026-09-15-insim-test-tier-design.md](../specs/2026-09-15-insim-test-tier-design.md)

## Global Constraints

- **Lua 5.1, no modules.** Skynet source files declare globals inside `do ... end` blocks and
  are loaded with `loadfile`. No `require`, no `package`. DCS nils `require` and `package`.
- **Never `pcall` inside a test coroutine.** Stock Lua 5.1 cannot yield across a `pcall`
  boundary; LuaJIT can. Code must work on both, so the runner catches failures via
  `coroutine.resume`, never `pcall`.
- **No mist, no MOOSE.** Write helpers fresh against the documented DCS API. Where behaviour is
  deliberately equivalent to or divergent from mist, say so at the call site, as
  `SkynetIADSUtils` does. No `-- FGA` markers: nothing is vendored.
- **Axis conventions** (mixing these up silently misplaces units):
  - `Vec3` world position — `x` north, `y` **altitude**, `z` east
  - `Vec2` and mission-file unit tables — `x` north, `y` **east**
  - `getPosition().x/.y/.z` — forward/up/right **orientation unit vectors**, not coordinates;
    position is in `.p`. Heading is `math.atan2(pos.x.z, pos.x.x)`.
- **Terminology**, used exactly: **add** (`coalition.addGroup` / `addStaticObject`), **destroy**
  (`Object.destroy()`, live entities only), **explode** (in-game destruction; leaves a wreck).
- **Terrain is Caucasus.** Fixture anchors are Caucasus-specific.
- **Existing suite must stay green.** `test/lua/run.lua` passes after every task.

## Executor and verification legend

Each task is annotated. Routing rule: a task goes to a subagent only if its verification can be
run by that subagent.

| Executor | Meaning |
|---|---|
| **Sonnet** | Dispatch to a Sonnet subagent; it can verify its own work |
| **Opus** | Subtle enough to warrant the stronger model, but still self-verifying |
| **human-in-DCS** | Blocks on the user running DCS. Not a delegable task — do not hand to any subagent |

| Verification | Command |
|---|---|
| **test/lua green** | `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua` |
| **lua5.1** | Same runner; the new suite is discovered automatically as `test/lua/test_*.lua` |
| **needs DCS** | Launch `skynet-insim.miz`, take the GM slot, use the F10 menu, read the result |

Tasks 1–6 are fully offline-testable. Tasks 7–11 need DCS.

**The code in Tasks 2–6 has been run.** Each implementation was executed against its own test
suite on `lua5.1` before this plan was written, so the expected test counts below are measured,
not estimated: Task 2 → 8, Task 3 → 8, Task 4 → 8, Task 5 → 21 cumulative, Task 6 → 27
cumulative. If a task's count comes out lower, something was mistranscribed.

## File structure

| File | Responsibility |
|---|---|
| `test/common/skynet-loader.lua` | Moved from `test/lua/`. Dependency-ordered source loading; gains `setRoot()` |
| `test/common/luaunit.lua` | Moved from `test/lua/`. Assertions for both tiers |
| `test/insim/tools/insim-test-tools.lua` | Pure-Lua helpers (`deepCopy`, `serialize`) + DCS-world helpers (`addOrReplace`, `removeJunkAround`, `scopedName`) |
| `test/insim/tools/extract-fixtures.lua` | Offline entry point: `.miz` `mission` table → fixture templates |
| `test/insim/runner/wait.lua` | `waitFor` / `waitSeconds` coroutine primitives |
| `test/insim/runner/runner.lua` | Coroutine phase scheduler, timeouts, result collection |
| `test/insim/runner/report.lua` | Result formatting → `outText`, `env.info`, results file |
| `test/insim/runner/init.lua` | Preflight, source loading, suite discovery, F10 menu |
| `test/insim/fixtures/placements.lua` | Caucasus anchors, one per scenario |
| `test/insim/fixtures/generated/*.lua` | Extractor output (committed) |
| `test/insim/scenarios/scenario_detection.lua` | The proving scenario |
| `test/insim/README.md` | MissionScripting edit, revert path, config file, how to run |
| `test/lua/test_insim_tools.lua` | Offline tests for the pure-Lua tool helpers |
| `test/lua/test_insim_extractor.lua` | Offline tests for the extractor |
| `test/lua/test_insim_runner.lua` | Offline tests for wait/runner/report against `dcs-stub` |

Offline tests for `test/insim` code live in `test/lua/` deliberately: `test/lua/run.lua`
discovers `test_*.lua` in its own directory, so putting them there gets this tier's
offline-testable code into the existing suite with no second runner.

---

### Task 1: Move shared assets to `test/common/`

**Executor:** Sonnet · **Verification:** test/lua green

**Files:**
- Create: `test/common/` (move target)
- Move: `test/lua/luaunit.lua` → `test/common/luaunit.lua`
- Move: `test/lua/skynet-loader.lua` → `test/common/skynet-loader.lua`
- Modify: `test/common/skynet-loader.lua` (add `setRoot`)
- Modify: 12 files in `test/lua/` — `test_dcs_fixtures.lua`, `test_dcs_stub.lua`,
  `test_harness_smoke.lua`, `test_skynet_iads.lua`,
  `test_skynet_iads_abstract_dcs_object_wrapper.lua`, `test_skynet_iads_abstract_element.lua`,
  `test_skynet_iads_contact.lua`, `test_skynet_iads_harm_detection.lua`,
  `test_skynet_iads_jammer.lua`, `test_skynet_iads_sam_site.lua`,
  `test_skynet_iads_utils.lua`, `test_skynet_moose_a2a_dispatcher_connector.lua`
- Modify: `test/lua/README.md`
- Test: `test/lua/test_harness_smoke.lua` (existing, proves the move)

**Interfaces:**
- Consumes: nothing
- Produces: `test/common/skynet-loader.lua` returning a table `M` with
  `M.load(name)`, `M.loadAll()`, `M.reset()`, `M.setRoot(absolutePath)`, `M.ORDER`
  (array of 19 source basenames). `test/common/luaunit.lua` returning the luaunit 3.4 module.

- [ ] **Step 1: Move both files with git**

```bash
mkdir -p test/common
git mv test/lua/luaunit.lua test/common/luaunit.lua
git mv test/lua/skynet-loader.lua test/common/skynet-loader.lua
```

- [ ] **Step 2: Run the suite to see it fail**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua`
Expected: every suite FAILS — `dofile` cannot find `luaunit.lua`.

- [ ] **Step 3: Repoint all 12 suites**

Each of the 12 files has exactly these two lines (the leading variable differs between
`luaunit = ` and `local loader = `; the `dofile` argument is identical in shape):

```lua
luaunit = dofile(base .. "/luaunit.lua")
local loader = dofile(base .. "/skynet-loader.lua")
```

Change them to:

```lua
luaunit = dofile(base .. "/../common/luaunit.lua")
local loader = dofile(base .. "/../common/skynet-loader.lua")
```

Apply with sed across the directory:

```bash
sed -i 's|dofile(base \.\. "/luaunit\.lua")|dofile(base .. "/../common/luaunit.lua")|; s|dofile(base \.\. "/skynet-loader\.lua")|dofile(base .. "/../common/skynet-loader.lua")|' test/lua/test_*.lua
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua`
Expected: `ALL N SUITE(S) PASSED`

This is the whole verification for the move. `skynet-loader.lua`'s default root
(`base .. "/../../skynet-iads-source"`) needs no change: `test/common/` is the same depth as
`test/lua/`.

- [ ] **Step 5: Commit the move**

```bash
git add test/common test/lua
git commit -m "refactor: move luaunit and skynet-loader to test/common/

Both are needed by test/lua and the incoming test/insim tier and belong to
neither. The loader's dependency order in particular needs one source of truth
rather than a copy per tier."
```

- [ ] **Step 6: Write the failing test for `setRoot`**

Add to `test/lua/test_harness_smoke.lua`, after the existing tests:

```lua
function TestHarnessSmoke:testSetRootOverridesTheDefaultSourceDirectory()
  local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
  local fresh = dofile(base .. "/../common/skynet-loader.lua")
  fresh.setRoot(base .. "/no-such-directory")
  local ok, err = pcall(fresh.load, "skynet-iads-utils")
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "no-such-directory")
end

function TestHarnessSmoke:testSetRootAcceptsATrailingSeparator()
  local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
  local fresh = dofile(base .. "/../common/skynet-loader.lua")
  fresh.setRoot(base .. "/../../skynet-iads-source/")
  fresh.load("skynet-iads-utils")
  luaunit.assertNotNil(SkynetIADSUtils)
end
```

- [ ] **Step 7: Run it to verify it fails**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_harness_smoke.lua`
Expected: FAIL — `attempt to call field 'setRoot' (a nil value)`

- [ ] **Step 8: Implement `setRoot`**

In `test/common/skynet-loader.lua`, the root is currently a load-time local:

```lua
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "./"
local src = (os.getenv("SKYNET_SRC") or (base .. "/../../skynet-iads-source")) .. "/"
```

Replace those two lines with:

```lua
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "./"
local src = (os.getenv("SKYNET_SRC") or (base .. "/../../skynet-iads-source")) .. "/"

--- Overrides where source files are read from. The in-sim runner calls this with the repo
--- path its bootstrap already resolved, so it does not depend on debug.getinfo or an
--- environment variable inside the DCS mission environment.
local function setRoot(path)
  assert(type(path) == "string", "skynet-loader.setRoot: path must be a string")
  src = path:gsub("[\\/]*$", "") .. "/"
end
```

Then in the `M` table section, expose it:

```lua
local M = { _loaded = {}, ORDER = ORDER, setRoot = setRoot }
```

`M.load` already reads `src` at call time, so no other change is needed.

- [ ] **Step 9: Run the test to verify it passes**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_harness_smoke.lua`
Expected: PASS

- [ ] **Step 10: Update `test/lua/README.md`**

In the `## Files` table, remove the `luaunit.lua` and `skynet-loader.lua` rows and add a line
above the table:

```markdown
`luaunit.lua` and `skynet-loader.lua` now live in `test/common/`, shared with `test/insim/`.
```

- [ ] **Step 11: Run the full suite and commit**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
git add test/common test/lua
git commit -m "feat: add skynet-loader.setRoot for in-sim source loading"
```

---

### Task 2: Pure-Lua tool helpers — `deepCopy` and `serialize`

**Executor:** Sonnet · **Verification:** lua5.1

**Files:**
- Create: `test/insim/tools/insim-test-tools.lua`
- Create: `test/lua/test_insim_tools.lua`

**Interfaces:**
- Consumes: `test/common/luaunit.lua`
- Produces: global table `InsimTestTools` with
  - `InsimTestTools.deepCopy(value)` → deep copy of tables, values otherwise
  - `InsimTestTools.serialize(value)` → Lua source string that `loadstring` evaluates back to
    an equal value. Emits `[key] = value` form, sorted by key so output is diffable.

The file declares a global inside a `do ... end` block, matching Skynet source convention, and
is loaded with `dofile`. Later tasks add DCS-world helpers to the same file (Task 7).

- [ ] **Step 1: Write the failing tests**

Create `test/lua/test_insim_tools.lua`:

```lua
--- Offline tests for the pure-Lua half of test/insim/tools/insim-test-tools.lua.
--- The DCS-world half (addOrReplace, removeJunkAround) is not tested here: it needs a sim.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/../insim/tools/insim-test-tools.lua")

TestInsimTools = {}

function TestInsimTools:testDeepCopyProducesAnIndependentTable()
  local original = { a = 1, nested = { b = 2 } }
  local copy = InsimTestTools.deepCopy(original)
  copy.nested.b = 99
  luaunit.assertEquals(original.nested.b, 2)
  luaunit.assertEquals(copy.nested.b, 99)
end

function TestInsimTools:testDeepCopyPassesScalarsThrough()
  luaunit.assertEquals(InsimTestTools.deepCopy(5), 5)
  luaunit.assertEquals(InsimTestTools.deepCopy("x"), "x")
  luaunit.assertEquals(InsimTestTools.deepCopy(nil), nil)
end

function TestInsimTools:testDeepCopyHandlesArrays()
  local copy = InsimTestTools.deepCopy({ 10, 20, 30 })
  luaunit.assertEquals(#copy, 3)
  luaunit.assertEquals(copy[2], 20)
end

local function roundTrip(value)
  local text = InsimTestTools.serialize(value)
  local chunk, err = loadstring("return " .. text)
  luaunit.assertNotNil(chunk, "serialize produced unloadable source: " .. tostring(err)
    .. "\n" .. text)
  return chunk()
end

function TestInsimTools:testSerializeRoundTripsAFixtureTable()
  local fixture = {
    name = "SAM-1",
    units = {
      { type = "Kub 1S91 str", dx = 0, dy = 0, heading = 2.827, skill = "Excellent" },
      { type = "Kub 2P25 ln", dx = 40, dy = -20, heading = 2.827, skill = "Excellent" },
    },
  }
  luaunit.assertEquals(roundTrip(fixture), fixture)
end

function TestInsimTools:testSerializeEscapesQuotesAndBackslashes()
  local value = { text = 'a "quoted" \\ backslash' }
  luaunit.assertEquals(roundTrip(value), value)
end

function TestInsimTools:testSerializeRoundTripsBooleansAndNegativeNumbers()
  local value = { flag = false, other = true, x = -239471.99699379 }
  luaunit.assertEquals(roundTrip(value), value)
end

function TestInsimTools:testSerializeSortsKeysSoOutputIsStable()
  local first = InsimTestTools.serialize({ b = 1, a = 2, c = 3 })
  local second = InsimTestTools.serialize({ c = 3, a = 2, b = 1 })
  luaunit.assertEquals(first, second)
  luaunit.assertTrue(first:find('%["a"%]') < first:find('%["b"%]'))
end

function TestInsimTools:testSerializeRoundTripsNumericKeys()
  local value = { [1] = "one", [2] = "two" }
  luaunit.assertEquals(roundTrip(value), value)
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run it to verify it fails**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_tools.lua`
Expected: FAIL — cannot open `../insim/tools/insim-test-tools.lua`

- [ ] **Step 3: Implement the helpers**

Create `test/insim/tools/insim-test-tools.lua`:

```lua
do

--[[
InsimTestTools -- helpers the test/insim tier needs that neither Skynet source nor luaunit
provides.

Two halves, deliberately in one file while it stays small:
  * pure Lua      -- deepCopy, serialize. Usable in-sim and offline, and unit-tested offline
                     by test/lua/test_insim_tools.lua.
  * DCS-world     -- addOrReplace, removeJunkAround, scopedName. Need a running sim.

Scope rules: nothing Skynet-specific (that belongs in scenarios or fixtures); check
SkynetIADSUtils before adding arithmetic, since test/lua already covers it; split this file
once it passes roughly 300 lines.
]]

InsimTestTools = {}

--- Pure Lua ----------------------------------------------------------------------------------

function InsimTestTools.deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[InsimTestTools.deepCopy(k)] = InsimTestTools.deepCopy(v)
  end
  return copy
end

local function serializeScalar(value)
  local kind = type(value)
  if kind == "string" then
    return string.format("%q", value)
  end
  if kind == "number" then
    -- A double needs 17 significant digits to be recovered exactly; %g strips trailing
    -- zeros, so clean values stay short.
    return string.format("%.17g", value)
  end
  if kind == "boolean" then
    return tostring(value)
  end
  error("InsimTestTools.serialize: cannot serialize a " .. kind)
end

--- Sorted so the same table always produces the same text: fixture files are committed, and a
--- diff that reorders on every regeneration is useless.
local function sortedKeys(tbl)
  local numbers, strings = {}, {}
  for k in pairs(tbl) do
    if type(k) == "number" then
      numbers[#numbers + 1] = k
    elseif type(k) == "string" then
      strings[#strings + 1] = k
    else
      error("InsimTestTools.serialize: cannot serialize a " .. type(k) .. " key")
    end
  end
  table.sort(numbers)
  table.sort(strings)
  for _, k in ipairs(strings) do
    numbers[#numbers + 1] = k
  end
  return numbers
end

function InsimTestTools.serialize(value, indent)
  if type(value) ~= "table" then
    return serializeScalar(value)
  end
  indent = indent or ""
  local inner = indent .. "  "
  local parts = {}
  for _, key in ipairs(sortedKeys(value)) do
    parts[#parts + 1] = string.format("%s[%s] = %s",
      inner, serializeScalar(key), InsimTestTools.serialize(value[key], inner))
  end
  if #parts == 0 then
    return "{}"
  end
  return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end

end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_tools.lua`
Expected: PASS, 8 tests

- [ ] **Step 5: Run the full suite and commit**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
git add test/insim/tools/insim-test-tools.lua test/lua/test_insim_tools.lua
git commit -m "feat: add deepCopy and stable serialize for insim fixtures"
```

---

### Task 3: Offline fixture extractor

**Executor:** Sonnet · **Verification:** lua5.1

**Files:**
- Create: `test/insim/tools/extract-fixtures.lua`
- Create: `test/lua/test_insim_extractor.lua`

**Interfaces:**
- Consumes: `InsimTestTools.serialize` and `InsimTestTools.deepCopy` from Task 2
- Produces: global table `InsimExtractor` with
  - `InsimExtractor.templateFromGroup(groupTable)` → `{ name = <string>, task = <string>,
    units = { { type=, dx=, dy=, heading=, skill= }, ... } }` — `dx`/`dy` are mission-table
    (Vec2) offsets from the group's first unit
  - `InsimExtractor.templateFromStatic(staticTable)` → `{ name=, type=, category=, heading= }`
  - `InsimExtractor.fixtureFileText(templatesByName)` → full Lua file text, `return`ing a table
  - `InsimExtractor.groupsFromMissionTable(mission, prefix)` → array of matching group tables

The extractor reads a `mission` table, not a `.miz`. Unzipping is a separate manual step
(documented in Task 9's README), which keeps the extractor pure and testable.

- [ ] **Step 1: Write the failing tests**

Create `test/lua/test_insim_extractor.lua`:

```lua
--- Offline tests for test/insim/tools/extract-fixtures.lua. Input is a synthetic `mission`
--- table shaped exactly like the one inside a .miz, so no DCS and no .miz are needed.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/../insim/tools/insim-test-tools.lua")
dofile(base .. "/../insim/tools/extract-fixtures.lua")

TestInsimExtractor = {}

--- Three units 20m apart on the x (north) axis -- the shape real .miz group tables have.
local function sampleGroup()
  return {
    name = "SAM-Kub-1",
    task = "Ground Nothing",
    x = 25781.5,
    y = -239472.0,
    units = {
      { type = "Kub 1S91 str", name = "SAM-Kub-1-1", x = 25781.5, y = -239472.0,
        heading = 2.827, skill = "Excellent", playerCanDrive = false },
      { type = "Kub 2P25 ln", name = "SAM-Kub-1-2", x = 25761.5, y = -239472.0,
        heading = 2.827, skill = "Excellent", playerCanDrive = false },
      { type = "Kub 2P25 ln", name = "SAM-Kub-1-3", x = 25741.5, y = -239452.0,
        heading = 1.5, skill = "Average", playerCanDrive = false },
    },
  }
end

function TestInsimExtractor:testFirstUnitIsTheOrigin()
  local template = InsimExtractor.templateFromGroup(sampleGroup())
  luaunit.assertEquals(template.units[1].dx, 0)
  luaunit.assertEquals(template.units[1].dy, 0)
end

function TestInsimExtractor:testOffsetsAreRelativeToTheFirstUnit()
  local template = InsimExtractor.templateFromGroup(sampleGroup())
  -- unit 2: x 25761.5 - 25781.5 = -20 north; y unchanged
  luaunit.assertEquals(template.units[2].dx, -20)
  luaunit.assertEquals(template.units[2].dy, 0)
  -- unit 3: x -40 north, y -239452.0 - -239472.0 = +20 east
  luaunit.assertEquals(template.units[3].dx, -40)
  luaunit.assertEquals(template.units[3].dy, 20)
end

function TestInsimExtractor:testTemplateCarriesNoAbsoluteCoordinates()
  local template = InsimExtractor.templateFromGroup(sampleGroup())
  luaunit.assertNil(template.x)
  luaunit.assertNil(template.y)
  for _, unit in ipairs(template.units) do
    luaunit.assertNil(unit.x)
    luaunit.assertNil(unit.y)
    luaunit.assertNil(unit.name)  -- names are scoped per scenario at add time
  end
end

function TestInsimExtractor:testTemplateKeepsTypeHeadingAndSkill()
  local template = InsimExtractor.templateFromGroup(sampleGroup())
  luaunit.assertEquals(template.units[1].type, "Kub 1S91 str")
  luaunit.assertEquals(template.units[1].heading, 2.827)
  luaunit.assertEquals(template.units[1].skill, "Excellent")
  luaunit.assertEquals(template.units[3].skill, "Average")
  luaunit.assertEquals(template.task, "Ground Nothing")
end

function TestInsimExtractor:testStaticTemplateKeepsTypeCategoryAndHeading()
  local template = InsimExtractor.templateFromStatic({
    name = "Static MBT-1",
    x = 24985.4,
    y = -240039.7,
    units = { { type = "M-60", category = "Armor", heading = 4.468, name = "Static MBT-1-1" } },
  })
  luaunit.assertEquals(template.type, "M-60")
  luaunit.assertEquals(template.category, "Armor")
  luaunit.assertEquals(template.heading, 4.468)
  luaunit.assertNil(template.x)
end

function TestInsimExtractor:testGroupsFromMissionTableFindsByPrefixAcrossCountries()
  local mission = {
    coalition = {
      red = {
        country = {
          { name = "CJTF Red",
            vehicle = { group = { sampleGroup(), { name = "Convoy-1", units = {} } } } },
        },
      },
      blue = {
        country = {
          { name = "USA", vehicle = { group = { { name = "SAM-Blue-1", units = {} } } } },
        },
      },
    },
  }
  local found = InsimExtractor.groupsFromMissionTable(mission, "SAM-Kub")
  luaunit.assertEquals(#found, 1)
  luaunit.assertEquals(found[1].name, "SAM-Kub-1")
end

function TestInsimExtractor:testFixtureFileTextLoadsBackAsATableOfTemplates()
  local text = InsimExtractor.fixtureFileText({
    kub = InsimExtractor.templateFromGroup(sampleGroup()),
  })
  local chunk, err = loadstring(text)
  luaunit.assertNotNil(chunk, tostring(err) .. "\n" .. text)
  local fixtures = chunk()
  luaunit.assertEquals(fixtures.kub.units[2].dx, -20)
end

function TestInsimExtractor:testFixtureFileTextIsStableAcrossRuns()
  local group = sampleGroup()
  local first = InsimExtractor.fixtureFileText({ kub = InsimExtractor.templateFromGroup(group) })
  local second = InsimExtractor.fixtureFileText({ kub = InsimExtractor.templateFromGroup(group) })
  luaunit.assertEquals(first, second)
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run it to verify it fails**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_extractor.lua`
Expected: FAIL — cannot open `extract-fixtures.lua`

- [ ] **Step 3: Implement the extractor**

Create `test/insim/tools/extract-fixtures.lua`:

```lua
do

--[[
InsimExtractor -- turns the `mission` table inside a .miz into fixture templates.

Runs OUTSIDE DCS, on the same stock Lua 5.1 that test/lua uses. It never touches the DCS API,
which is what makes it unit-testable.

Templates are position-independent: unit types, headings, skills and offsets from the group's
first unit. Absolute coordinates live in fixtures/placements.lua instead, so a composition can
be re-anchored anywhere. Offsets are mission-table (Vec2) values: dx is NORTH, dy is EAST.

Usage:
  unzip -o mission.miz mission          -- by hand; see test/insim/README.md
  lua5.1 extract-fixtures.lua mission SAM-Kub > fixtures/generated/sam-kub.lua
]]

InsimExtractor = {}

--- One group table -> a position-independent template.
function InsimExtractor.templateFromGroup(group)
  assert(type(group) == "table", "templateFromGroup: group must be a table")
  assert(type(group.units) == "table" and group.units[1],
    "templateFromGroup: group '" .. tostring(group.name) .. "' has no units")

  local origin = group.units[1]
  local template = { name = group.name, task = group.task, units = {} }

  for i, unit in ipairs(group.units) do
    template.units[i] = {
      type = unit.type,
      dx = unit.x - origin.x,
      dy = unit.y - origin.y,
      heading = unit.heading,
      skill = unit.skill,
    }
  end

  return template
end

--- One static group table -> a template. Statics are a single unit carrying a category.
function InsimExtractor.templateFromStatic(staticGroup)
  assert(type(staticGroup) == "table", "templateFromStatic: argument must be a table")
  local unit = staticGroup.units and staticGroup.units[1]
  assert(unit, "templateFromStatic: '" .. tostring(staticGroup.name) .. "' has no unit")
  return {
    name = staticGroup.name,
    type = unit.type,
    category = unit.category,
    heading = unit.heading,
  }
end

--- Every vehicle/static group whose name starts with `prefix`, in any coalition or country.
function InsimExtractor.groupsFromMissionTable(mission, prefix)
  assert(type(mission) == "table", "groupsFromMissionTable: mission must be a table")
  assert(type(prefix) == "string", "groupsFromMissionTable: prefix must be a string")

  local found = {}
  local coalitions = mission.coalition or {}

  for _, coalition in pairs(coalitions) do
    for _, country in pairs(coalition.country or {}) do
      for _, category in pairs({ country.vehicle, country.static }) do
        for _, group in pairs((category or {}).group or {}) do
          if type(group.name) == "string" and group.name:sub(1, #prefix) == prefix then
            found[#found + 1] = group
          end
        end
      end
    end
  end

  table.sort(found, function(a, b) return a.name < b.name end)
  return found
end

--- Distinguishes a static group from a vehicle group. Mission files mark statics by carrying a
--- `category` on the unit ("Armor", "Fortifications", ...); vehicle and aircraft units never
--- do. Measured across two independent missions in this project: 156 static units carry
--- `category`, zero vehicle or plane units do.
function InsimExtractor.isStaticGroup(group)
  local unit = type(group) == "table" and group.units and group.units[1]
  return unit ~= nil and unit.category ~= nil
end

--- A committed fixture file: a Lua chunk returning { <key> = <template>, ... }.
function InsimExtractor.fixtureFileText(templatesByName)
  local lines = {
    "--- GENERATED by test/insim/tools/extract-fixtures.lua -- do not edit by hand.",
    "--- Offsets are mission-table (Vec2): dx is NORTH, dy is EAST.",
    "return " .. InsimTestTools.serialize(templatesByName),
    "",
  }
  return table.concat(lines, "\n")
end

end

--- Command-line entry point. Silent when dofile'd by a test (arg is nil then).
if arg and arg[0] and arg[0]:find("extract%-fixtures") and arg[1] then
  local missionPath, prefix = arg[1], arg[2]
  assert(prefix, "usage: lua5.1 extract-fixtures.lua <mission-file> <group-name-prefix>")

  local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
  dofile(base .. "/insim-test-tools.lua")

  local chunk = assert(loadfile(missionPath))
  -- A .miz's `mission` file is a Lua chunk assigning the global `mission`.
  chunk()
  assert(type(mission) == "table", "no global `mission` table after loading " .. missionPath)

  local templates = {}
  for _, group in ipairs(InsimExtractor.groupsFromMissionTable(mission, prefix)) do
    local isStatic = InsimExtractor.isStaticGroup(group)
    templates[group.name] = isStatic
      and InsimExtractor.templateFromStatic(group)
      or InsimExtractor.templateFromGroup(group)
  end

  io.write(InsimExtractor.fixtureFileText(templates))
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_extractor.lua`
Expected: PASS, 8 tests

- [ ] **Step 5: Run the full suite and commit**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
git add test/insim/tools/extract-fixtures.lua test/lua/test_insim_extractor.lua
git commit -m "feat: add offline .miz fixture extractor

Reads a mission table and emits position-independent templates, so fixture
compositions are authored in the Mission Editor but stored as diffable Lua."
```

---

### Task 4: `wait.lua` — coroutine wait primitives

**Executor:** Opus · **Verification:** lua5.1 (against `dcs-stub`)

**Files:**
- Create: `test/insim/runner/wait.lua`
- Create: `test/lua/test_insim_runner.lua` (grows in Task 5 and Task 6)

**Interfaces:**
- Consumes: `timer.getTime()` from the DCS API (stubbed offline by `test/lua/dcs-stub.lua`)
- Produces: globals `waitFor(predicate, timeoutSec)` and `waitSeconds(seconds)`, plus
  `InsimWait.describe(yielded)` for the runner's diagnostics. Both primitives
  `coroutine.yield` a descriptor table and raise on a `false` resume:
  - `waitFor` yields `{ kind = "waitFor", predicate = <fn>, timeout = <number> }`
  - `waitSeconds` yields `{ kind = "waitSeconds", timeout = <number> }`

  The runner resumes with `true` when satisfied and `false` when the deadline passed; the
  primitive turns `false` into an `error()`, so a timeout fails the test exactly like an
  assertion.

**Why this shape:** the primitives never call `pcall`, because stock Lua 5.1 cannot yield
across a `pcall` boundary. Failure propagation is `coroutine.resume`'s job — see the Global
Constraints.

- [ ] **Step 1: Write the failing tests**

Create `test/lua/test_insim_runner.lua`:

```lua
--- Offline tests for the test/insim runner, driven against dcs-stub's controllable clock and
--- timer. This is the whole reason the runner is testable outside DCS: dcsStub.advanceClock and
--- dcsStub.fireDueTimers reproduce timer.getTime and timer.scheduleFunction's re-arm contract.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/../insim/runner/wait.lua")

TestInsimWait = {}

function TestInsimWait:setUp()
  dcsStub.reset()
  dcsStub.setClock(100)
end

--- Drives a coroutine the way the runner will: resume, inspect the yield, decide.
local function resumeUntilBlocked(co)
  local ok, yielded = coroutine.resume(co)
  luaunit.assertTrue(ok, tostring(yielded))
  return yielded
end

function TestInsimWait:testWaitForYieldsADescriptorCarryingThePredicateAndTimeout()
  local called = false
  local co = coroutine.create(function()
    waitFor(function() called = true; return true end, 60)
  end)
  local yielded = resumeUntilBlocked(co)
  luaunit.assertEquals(yielded.kind, "waitFor")
  luaunit.assertEquals(yielded.timeout, 60)
  luaunit.assertIsFunction(yielded.predicate)
  luaunit.assertFalse(called, "the primitive must not evaluate the predicate itself")
end

function TestInsimWait:testWaitForReturnsNormallyWhenResumedWithTrue()
  local reached = false
  local co = coroutine.create(function()
    waitFor(function() return true end, 60)
    reached = true
  end)
  resumeUntilBlocked(co)
  local ok, err = coroutine.resume(co, true)
  luaunit.assertTrue(ok, tostring(err))
  luaunit.assertTrue(reached)
  luaunit.assertEquals(coroutine.status(co), "dead")
end

function TestInsimWait:testWaitForRaisesWhenResumedWithFalse()
  local co = coroutine.create(function()
    waitFor(function() return false end, 45)
  end)
  resumeUntilBlocked(co)
  local ok, err = coroutine.resume(co, false)
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "45")
  luaunit.assertStrContains(tostring(err), "timed out")
end

function TestInsimWait:testWaitForRejectsABadTimeout()
  local co = coroutine.create(function() waitFor(function() return true end, nil) end)
  local ok, err = coroutine.resume(co)
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "timeout")
end

function TestInsimWait:testWaitForRejectsANonFunctionPredicate()
  local co = coroutine.create(function() waitFor("not a function", 10) end)
  local ok, err = coroutine.resume(co)
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "predicate")
end

function TestInsimWait:testWaitSecondsYieldsADeadlineOnlyDescriptor()
  local co = coroutine.create(function() waitSeconds(30) end)
  local yielded = resumeUntilBlocked(co)
  luaunit.assertEquals(yielded.kind, "waitSeconds")
  luaunit.assertEquals(yielded.timeout, 30)
  luaunit.assertNil(yielded.predicate)
end

function TestInsimWait:testWaitSecondsReturnsNormallyOnResume()
  local reached = false
  local co = coroutine.create(function() waitSeconds(30); reached = true end)
  resumeUntilBlocked(co)
  luaunit.assertTrue(coroutine.resume(co, true))
  luaunit.assertTrue(reached)
end

function TestInsimWait:testDescribeNamesTheWaitForAFailureMessage()
  luaunit.assertStrContains(
    InsimWait.describe({ kind = "waitSeconds", timeout = 30 }), "waitSeconds")
  luaunit.assertStrContains(
    InsimWait.describe({ kind = "waitFor", timeout = 60 }), "waitFor")
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 2: Run it to verify it fails**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_runner.lua`
Expected: FAIL — cannot open `../insim/runner/wait.lua`

- [ ] **Step 3: Implement the primitives**

Create `test/insim/runner/wait.lua`:

```lua
do

--[[
Wait primitives for test/insim scenarios.

A scenario body runs as a coroutine. It cannot block -- that would freeze the sim thread -- so
waiting means yielding a descriptor and letting the runner decide when to resume.

Deliberately free of pcall: stock Lua 5.1 cannot yield across a pcall boundary (LuaJIT can, and
DCS ships LuaJIT, but test/lua runs stock 5.1 and this code must pass there too). Failures
propagate through coroutine.resume, which is itself a protected call.
]]

InsimWait = {}

--- Yields until `predicate` returns true, or fails the test when `timeoutSec` sim-seconds pass.
--- The predicate is evaluated by the runner on its tick, never here.
function waitFor(predicate, timeoutSec)
  assert(type(predicate) == "function", "waitFor: predicate must be a function")
  assert(type(timeoutSec) == "number" and timeoutSec > 0,
    "waitFor: timeout must be a positive number of seconds")

  local satisfied = coroutine.yield({
    kind = "waitFor",
    predicate = predicate,
    timeout = timeoutSec,
  })

  if not satisfied then
    error(string.format("waitFor timed out after %gs", timeoutSec), 2)
  end
end

--- Yields for a fixed number of sim-seconds. Never fails on its own.
function waitSeconds(seconds)
  assert(type(seconds) == "number" and seconds > 0,
    "waitSeconds: seconds must be a positive number")

  coroutine.yield({ kind = "waitSeconds", timeout = seconds })
end

--- Human-readable name for a pending wait, used when a test blows its overall budget and the
--- runner has to say what it was waiting on.
function InsimWait.describe(yielded)
  if type(yielded) ~= "table" or not yielded.kind then
    return "an unrecognised yield"
  end
  return string.format("%s(%gs)", yielded.kind, yielded.timeout or 0)
end

end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_runner.lua`
Expected: PASS, 8 tests

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
git add test/insim/runner/wait.lua test/lua/test_insim_runner.lua
git commit -m "feat: add waitFor and waitSeconds coroutine primitives

Yield a descriptor rather than blocking, and turn a false resume into an error
so a timeout fails a test like an assertion. No pcall: stock Lua 5.1 cannot
yield across one."
```

---

### Task 5: `runner.lua` — phase scheduler and result collection

**Executor:** Opus · **Verification:** lua5.1 (against `dcs-stub`)

**Files:**
- Create: `test/insim/runner/runner.lua`
- Modify: `test/lua/test_insim_runner.lua` (append a second suite)

**Interfaces:**
- Consumes: `waitFor` / `waitSeconds` / `InsimWait.describe` (Task 4); `timer.getTime`,
  `timer.scheduleFunction` from the DCS API
- Produces: global `InsimRunner` with
  - `InsimRunner.plan(suites)` → an opaque run state. `suites` is an array of
    `{ name = <string>, suite = <table> }`; test functions are the suite's keys matching
    `^test`, run in sorted order. `setUp`/`tearDown` are optional.
  - `InsimRunner.step(state)` → `true` while work remains, `false` when the run is complete.
    Each call is one tick: it resumes at most one coroutine per phase.
  - `InsimRunner.results(state)` → `{ passed = <n>, failed = <n>, suites = { { name = <string>,
    tests = { { name = <string>, status = "pass"|"fail", message = <string|nil> } } } } }`
  - `InsimRunner.TICK` = `0.1` (sim-seconds between ticks)
  - `InsimRunner.DEFAULT_BUDGET` = `600` (sim-seconds per test before it is abandoned)
  - `InsimRunner.start(suites, onComplete)` → arms a `timer.scheduleFunction` tick that calls
    `step` until done, then `onComplete(results)`

**Design note — three coroutines per test, not one.** `setUp`, the test body and `tearDown` each
get their own coroutine, resumed in sequence. That is what lets `tearDown` still run after the
test body raises: the runner learns of the failure from `coroutine.resume` and moves to the next
phase. Wrapping the body in `pcall` inside one coroutine would be the obvious alternative and is
forbidden by the Global Constraints.

- [ ] **Step 1: Write the failing tests**

Append to `test/lua/test_insim_runner.lua`, above the final `os.exit(...)` line, and add
`dofile(base .. "/../insim/runner/runner.lua")` next to the existing `wait.lua` dofile at the
top of the file:

```lua
TestInsimRunner = {}

function TestInsimRunner:setUp()
  dcsStub.reset()
  dcsStub.setClock(100)
end

--- Runs a plan to completion, advancing the clock a tick at a time. Returns the results.
local function runToCompletion(suites, maxTicks)
  local state = InsimRunner.plan(suites)
  local ticks = 0
  while InsimRunner.step(state) do
    ticks = ticks + 1
    luaunit.assertTrue(ticks < (maxTicks or 100000), "run did not terminate")
    dcsStub.advanceClock(InsimRunner.TICK)
  end
  return InsimRunner.results(state)
end

function TestInsimRunner:testASynchronousPassingTestIsReportedAsPassed()
  local results = runToCompletion({
    { name = "Sync", suite = { testOk = function() end } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertEquals(results.failed, 0)
  luaunit.assertEquals(results.suites[1].tests[1].name, "testOk")
  luaunit.assertEquals(results.suites[1].tests[1].status, "pass")
end

function TestInsimRunner:testAFailedAssertionIsReportedWithItsMessage()
  local results = runToCompletion({
    { name = "Failing", suite = { testBad = function() error("boom") end } },
  })
  luaunit.assertEquals(results.passed, 0)
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertEquals(results.suites[1].tests[1].status, "fail")
  luaunit.assertStrContains(results.suites[1].tests[1].message, "boom")
end

function TestInsimRunner:testLuaunitAssertionsWorkUnchangedInsideACoroutine()
  local results = runToCompletion({
    { name = "Asserting", suite = {
        testPasses = function() luaunit.assertEquals(1, 1) end,
        testFails = function() luaunit.assertEquals(1, 2) end,
      } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertEquals(results.failed, 1)
end

function TestInsimRunner:testOnlyKeysStartingWithTestAreRun()
  local ran = {}
  runToCompletion({
    { name = "Selective", suite = {
        testOne = function() ran[#ran + 1] = "one" end,
        helper = function() ran[#ran + 1] = "helper" end,
      } },
  })
  luaunit.assertEquals(ran, { "one" })
end

function TestInsimRunner:testSetUpAndTearDownRunAroundEachTest()
  local order = {}
  runToCompletion({
    { name = "Lifecycle", suite = {
        setUp = function() order[#order + 1] = "setUp" end,
        tearDown = function() order[#order + 1] = "tearDown" end,
        testA = function() order[#order + 1] = "A" end,
        testB = function() order[#order + 1] = "B" end,
      } },
  })
  luaunit.assertEquals(order,
    { "setUp", "A", "tearDown", "setUp", "B", "tearDown" })
end

function TestInsimRunner:testTearDownStillRunsAfterTheTestBodyRaises()
  local torn = false
  local results = runToCompletion({
    { name = "Cleanup", suite = {
        tearDown = function() torn = true end,
        testRaises = function() error("nope") end,
      } },
  })
  luaunit.assertTrue(torn, "tearDown must run even when the body failed")
  luaunit.assertEquals(results.failed, 1)
end

function TestInsimRunner:testAFailingSetUpFailsTheTestAndSkipsTheBody()
  local bodyRan = false
  local results = runToCompletion({
    { name = "BadSetUp", suite = {
        setUp = function() error("setup exploded") end,
        testNeverRuns = function() bodyRan = true end,
      } },
  })
  luaunit.assertFalse(bodyRan)
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "setup exploded")
end

function TestInsimRunner:testWaitForResumesOnceThePredicateHolds()
  local flipAt = 100 + 5
  local results = runToCompletion({
    { name = "Waiting", suite = {
        testWaits = function()
          waitFor(function() return timer.getTime() >= flipAt end, 60)
        end,
      } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertTrue(timer.getTime() >= flipAt)
end

function TestInsimRunner:testWaitForFailsTheTestWhenItsTimeoutPasses()
  local results = runToCompletion({
    { name = "TimingOut", suite = {
        testNeverSatisfied = function() waitFor(function() return false end, 10) end,
      } },
  })
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "timed out")
end

function TestInsimRunner:testWaitSecondsElapsesRoughlyTheRequestedSimTime()
  local started = timer.getTime()
  local finished
  local results = runToCompletion({
    { name = "Sleeping", suite = {
        testSleeps = function() waitSeconds(8); finished = timer.getTime() end,
      } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertTrue(finished - started >= 8,
    "expected at least 8s of sim time, got " .. tostring(finished - started))
end

function TestInsimRunner:testTheOverallBudgetAbandonsATestThatNeverFinishes()
  local results = runToCompletion({
    { name = "Runaway", suite = {
        testLoopsForever = function()
          while true do
            waitFor(function() return false end, InsimRunner.DEFAULT_BUDGET * 2)
          end
        end,
      } },
  })
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "budget")
end

function TestInsimRunner:testOneFailureDoesNotStopLaterTestsOrSuites()
  local results = runToCompletion({
    { name = "First", suite = { testBoom = function() error("x") end } },
    { name = "Second", suite = { testFine = function() end } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertEquals(#results.suites, 2)
  luaunit.assertEquals(results.suites[2].tests[1].status, "pass")
end

function TestInsimRunner:testStartArmsARepeatingTickAndCallsBackOnCompletion()
  local seen
  InsimRunner.start({ { name = "Async", suite = { testOk = function() end } } },
    function(results) seen = results end)
  for _ = 1, 20 do
    dcsStub.fireDueTimers()
    dcsStub.advanceClock(InsimRunner.TICK)
  end
  luaunit.assertNotNil(seen, "onComplete was never called")
  luaunit.assertEquals(seen.passed, 1)
end

function TestInsimRunner:testARaisingPredicateFailsOnlyThatTestAndRunsItsTearDown()
  local torn = false
  local results = runToCompletion({
    { name = "RaisingPredicate", suite = {
        tearDown = function() torn = true end,
        testPredicateRaises = function()
          waitFor(function() error("attempt to index a destroyed unit") end, 60)
        end,
      } },
    { name = "Later", suite = { testStillRuns = function() end } },
  })
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "predicate raised")
  luaunit.assertStrContains(results.suites[1].tests[1].message, "destroyed unit")
  luaunit.assertTrue(torn, "tearDown must still run after a predicate raises")
  luaunit.assertEquals(results.suites[2].tests[1].status, "pass")
end

function TestInsimRunner:testAMalformedYieldFailsOnlyThatTest()
  local results = runToCompletion({
    { name = "BadYield", suite = {
        testYieldsGarbage = function() coroutine.yield("not a descriptor") end,
      } },
    { name = "Later", suite = { testStillRuns = function() end } },
  })
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "not a wait descriptor")
end

function TestInsimRunner:testASetUpPredicateRaiseSkipsTheBodyButStillRunsTearDown()
  local bodyRan, torn = false, false
  local results = runToCompletion({
    { name = "SetUpPredicateRaises", suite = {
        setUp = function()
          waitFor(function() error("unit already destroyed") end, 60)
        end,
        tearDown = function() torn = true end,
        testNeverRuns = function() bodyRan = true end,
      } },
  })
  luaunit.assertFalse(bodyRan, "a setUp that failed must not be followed by the body")
  luaunit.assertTrue(torn, "tearDown must still run after a failed setUp")
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "predicate raised")
end

function TestInsimRunner:testASetUpMalformedYieldSkipsTheBodyButStillRunsTearDown()
  local bodyRan, torn = false, false
  local results = runToCompletion({
    { name = "SetUpYieldsGarbage", suite = {
        setUp = function() coroutine.yield("not a descriptor") end,
        tearDown = function() torn = true end,
        testNeverRuns = function() bodyRan = true end,
      } },
  })
  luaunit.assertFalse(bodyRan, "a setUp that failed must not be followed by the body")
  luaunit.assertTrue(torn, "tearDown must still run after a failed setUp")
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "not a wait descriptor")
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_runner.lua`
Expected: FAIL — cannot open `../insim/runner/runner.lua`

- [ ] **Step 3: Implement the runner**

Create `test/insim/runner/runner.lua`:

```lua
do

--[[
InsimRunner -- drives test/insim scenarios inside a live mission.

Replaces luaunit's run loop while keeping its assertions. The reason is timing: live DCS
behaviour needs simulated seconds to pass, a mission script may not block, and luaunit's run()
is synchronous.

Each test is three coroutines -- setUp, body, tearDown -- resumed in sequence on a tick. Three
rather than one so that tearDown still runs when the body raises: the runner hears about the
failure from coroutine.resume and simply moves to the next phase. Wrapping the body in pcall
inside a single coroutine would be the obvious alternative, and it cannot work here, because
stock Lua 5.1 cannot yield across a pcall boundary.

coroutine.resume IS the protected call. There is no pcall anywhere in this file.

The budget bounds COOPERATIVE hangs only. A test that never yields at all (`while true do end`)
never returns control to the runner, so nothing here can stop it.
]]

InsimRunner = {}

InsimRunner.TICK = 0.1            -- sim-seconds between ticks
InsimRunner.DEFAULT_BUDGET = 600  -- sim-seconds one test may take before being abandoned

local function sortedTestNames(suite)
  local names = {}
  for key, value in pairs(suite) do
    if type(key) == "string" and key:match("^test") and type(value) == "function" then
      names[#names + 1] = key
    end
  end
  table.sort(names)
  return names
end

--- Flattens the suites into a queue of pending tests, so stepping never has to nest loops.
function InsimRunner.plan(suites)
  assert(type(suites) == "table", "InsimRunner.plan: suites must be an array")

  local state = { queue = {}, index = 1, phase = nil, results = { passed = 0, failed = 0,
    suites = {} } }

  for _, entry in ipairs(suites) do
    assert(type(entry.name) == "string", "InsimRunner.plan: every suite needs a name")
    assert(type(entry.suite) == "table", "InsimRunner.plan: every suite needs a suite table")

    local record = { name = entry.name, tests = {} }
    state.results.suites[#state.results.suites + 1] = record

    for _, testName in ipairs(sortedTestNames(entry.suite)) do
      state.queue[#state.queue + 1] = {
        suite = entry.suite,
        suiteName = entry.name,
        testName = testName,
        record = record,
      }
    end
  end

  return state
end

local function recordOutcome(state, item, message)
  local outcome = { name = item.testName, status = message and "fail" or "pass",
    message = message }
  item.record.tests[#item.record.tests + 1] = outcome
  if message then
    state.results.failed = state.results.failed + 1
  else
    state.results.passed = state.results.passed + 1
  end
end

--- Phases are attempted in order. A phase with no function is skipped; a failed setUp skips the
--- body but never the tearDown.
local PHASES = { "setUp", "body", "tearDown" }

local function phaseFunction(item, phaseName)
  if phaseName == "body" then
    return item.suite[item.testName]
  end
  return item.suite[phaseName]
end

local function beginPhase(state, item, phaseIndex)
  local phaseName = PHASES[phaseIndex]
  local fn = phaseFunction(item, phaseName)

  if not fn then
    return nil
  end

  return {
    name = phaseName,
    index = phaseIndex,
    co = coroutine.create(function() fn(item.suite) end),
    deadline = nil,
    pending = nil,
  }
end

--- Advances to the next phase that actually has a function, or finishes the test.
local function advancePhase(state, item, fromIndex)
  for next = fromIndex + 1, #PHASES do
    if item.failedSetUp and PHASES[next] == "body" then
      -- skipped deliberately
    else
      local phase = beginPhase(state, item, next)
      if phase then
        return phase
      end
    end
  end
  return nil
end

local function finishTest(state)
  local item = state.queue[state.index]
  recordOutcome(state, item, item.failure)
  state.index = state.index + 1
  state.phase = nil
end

--- Records a failure for the current test, then moves to the next phase. Every failure path
--- goes through here on purpose: a setUp that fails must skip the body, and that flag was
--- forgotten in two separate branches before this helper existed.
local function failPhase(state, item, phase, message)
  item.failure = item.failure or message
  if phase.name == "setUp" then
    item.failedSetUp = true
  end
  state.phase = advancePhase(state, item, phase.index)
  if not state.phase then
    finishTest(state)
  end
  return state.queue[state.index] ~= nil
end

--- One tick. Returns true while the run has more to do.
function InsimRunner.step(state)
  local item = state.queue[state.index]
  if not item then
    return false
  end

  if not state.started then
    state.started = true
  end

  if not state.phase then
    item.startedAt = timer.getTime()
    item.budget = item.suite.budgetSeconds or InsimRunner.DEFAULT_BUDGET
    state.phase = beginPhase(state, item, 1) or advancePhase(state, item, 1)
    if not state.phase then
      finishTest(state)
      return state.queue[state.index] ~= nil
    end
  end

  local phase = state.phase
  local now = timer.getTime()

  -- Overall budget. Checked before resuming so an abandoned coroutine is never touched again.
  if now - item.startedAt > item.budget then
    item.failure = item.failure or string.format(
      "%s exceeded its %gs budget while blocked on %s",
      item.testName, item.budget, InsimWait.describe(phase.pending))
    finishTest(state)
    return state.queue[state.index] ~= nil
  end

  local resumeValue = nil

  if phase.pending then
    local satisfied = false
    if phase.pending.kind == "waitFor" then
      -- The predicate runs here, on the runner's tick, never inside the test coroutine. It is
      -- arbitrary test code and it CAN raise: querying a DCS object destroyed mid-test raises,
      -- which is precisely what a scenario predicate does. Running it in its own coroutine keeps
      -- that raise from escaping the timer callback and killing the run silently, and keeps this
      -- file pcall-free, since resume is itself the protected call.
      local probe = coroutine.create(phase.pending.predicate)
      local ok, value = coroutine.resume(probe)

      local predicateFailure
      if not ok then
        predicateFailure = "waitFor predicate raised: " .. tostring(value)
      elseif coroutine.status(probe) ~= "dead" then
        predicateFailure = "waitFor predicate yielded; a predicate must not wait"
      end

      if predicateFailure then
        return failPhase(state, item, phase, predicateFailure)
      end

      satisfied = value and true or false
    end

    if satisfied then
      resumeValue = true
    elseif now >= phase.deadline then
      resumeValue = (phase.pending.kind == "waitSeconds")
    else
      return true  -- still waiting; nothing to do this tick
    end
  end

  local ok, yielded = coroutine.resume(phase.co, resumeValue)

  if not ok then
    -- A raise from any phase fails the test. setUp additionally skips the body.
    return failPhase(state, item, phase, tostring(yielded))
  end

  if coroutine.status(phase.co) == "dead" then
    state.phase = advancePhase(state, item, phase.index)
    if not state.phase then
      finishTest(state)
    end
    return state.queue[state.index] ~= nil
  end

  -- Still alive, so it yielded a wait descriptor.
  if type(yielded) ~= "table" or not yielded.timeout then
    return failPhase(state, item, phase, item.testName ..
      ": a test coroutine yielded something that is not a wait descriptor")
  end
  phase.pending = yielded
  phase.deadline = now + yielded.timeout

  return true
end

function InsimRunner.results(state)
  return state.results
end

--- Arms a repeating tick that steps the run to completion, then hands the results to
--- `onComplete`. Returning a time from a timer.scheduleFunction callback re-arms it, which is
--- the DCS contract dcs-stub also implements.
function InsimRunner.start(suites, onComplete)
  local state = InsimRunner.plan(suites)

  local function tick()
    if InsimRunner.step(state) then
      return timer.getTime() + InsimRunner.TICK
    end
    onComplete(InsimRunner.results(state))
    return nil
  end

  return timer.scheduleFunction(tick, nil, timer.getTime() + InsimRunner.TICK)
end

end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_runner.lua`
Expected: PASS, 21 tests (8 from Task 4, 13 here)

- [ ] **Step 5: Run the full suite and commit**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
git add test/insim/runner/runner.lua test/lua/test_insim_runner.lua
git commit -m "feat: add the insim coroutine runner

Three coroutines per test -- setUp, body, tearDown -- resumed in sequence, so
tearDown still runs when the body raises and no pcall is needed anywhere.
Bounded waits plus a per-test budget mean a hung test fails instead of wedging
the mission."
```

---

### Task 6: `report.lua` — three outputs from one result set

**Executor:** Sonnet · **Verification:** lua5.1

**Files:**
- Create: `test/insim/runner/report.lua`
- Modify: `test/lua/dcs-stub.lua` (capture `outText` instead of discarding it)
- Modify: `test/lua/test_insim_runner.lua` (append a third suite)

**Interfaces:**
- Consumes: `InsimRunner.results(state)` shape (Task 5); `InsimTestTools.serialize` (Task 2)
- Produces: global `InsimReport` with
  - `InsimReport.summaryText(results)` → short multi-line string for the screen
  - `InsimReport.detailLines(results)` → array of strings for `env.info`
  - `InsimReport.resultsFileText(results)` → Lua chunk text `return`ing the results table
  - `InsimReport.emit(results, repoPath)` → calls `trigger.action.outText`, `env.info` per
    line, and writes `<repoPath>/test/insim/results/last-run.lua` when `io` is available

- [ ] **Step 1: Make the stub capture `outText`**

In `test/lua/dcs-stub.lua`, replace:

```lua
trigger = { action = { outText = function() end, explosion = function() end } }
```

with:

```lua
-- outText is captured, not discarded: test/insim's reporter puts its primary readout there.
dcsStub.outTexts = {}
trigger = { action = {
  outText = function(text, duration)
    dcsStub.outTexts[#dcsStub.outTexts + 1] = { text = text, duration = duration }
  end,
  explosion = function() end,
} }
```

and add `dcsStub.outTexts = {}` to the body of `dcsStub.reset()`.

- [ ] **Step 2: Write the failing tests**

Append to `test/lua/test_insim_runner.lua`, above the final `os.exit(...)`, and add
`dofile(base .. "/../insim/tools/insim-test-tools.lua")` and
`dofile(base .. "/../insim/runner/report.lua")` to the dofiles at the top:

```lua
TestInsimReport = {}

function TestInsimReport:setUp()
  dcsStub.reset()
  dcsStub.setClock(100)
  self.results = {
    passed = 2,
    failed = 1,
    suites = {
      { name = "Detection", tests = {
          { name = "testDetects", status = "pass" },
          { name = "testGoesDark", status = "fail", message = "waitFor timed out after 60s" },
        } },
      { name = "Power", tests = { { name = "testLosesPower", status = "pass" } } },
    },
  }
end

function TestInsimReport:testSummaryLeadsWithTheCountsAndNamesFailures()
  local text = InsimReport.summaryText(self.results)
  luaunit.assertStrContains(text, "2 passed")
  luaunit.assertStrContains(text, "1 failed")
  luaunit.assertStrContains(text, "testGoesDark")
end

function TestInsimReport:testSummaryOfAGreenRunSaysSo()
  local text = InsimReport.summaryText({ passed = 3, failed = 0, suites = {} })
  luaunit.assertStrContains(text, "3 passed")
  luaunit.assertStrContains(text, "ALL PASSED")
end

function TestInsimReport:testDetailLinesIncludeEveryTestAndEachFailureMessage()
  local lines = table.concat(InsimReport.detailLines(self.results), "\n")
  luaunit.assertStrContains(lines, "Detection")
  luaunit.assertStrContains(lines, "testDetects")
  luaunit.assertStrContains(lines, "testLosesPower")
  luaunit.assertStrContains(lines, "waitFor timed out after 60s")
end

function TestInsimReport:testDetailLinesAreTaggedForLogGrepping()
  for _, line in ipairs(InsimReport.detailLines(self.results)) do
    luaunit.assertStrContains(line, "SKYNET_INSIM")
  end
end

function TestInsimReport:testResultsFileTextLoadsBackAsTheSameCounts()
  local chunk, err = loadstring(InsimReport.resultsFileText(self.results))
  luaunit.assertNotNil(chunk, tostring(err))
  local loaded = chunk()
  luaunit.assertEquals(loaded.passed, 2)
  luaunit.assertEquals(loaded.failed, 1)
  luaunit.assertEquals(loaded.suites[1].tests[2].message, "waitFor timed out after 60s")
end

function TestInsimReport:testEmitPutsTheSummaryOnScreenAndDetailInTheLog()
  InsimReport.emit(self.results, nil)
  luaunit.assertEquals(#dcsStub.outTexts, 1)
  luaunit.assertStrContains(dcsStub.outTexts[1].text, "1 failed")
  luaunit.assertTrue(dcsStub.outTexts[1].duration > 0)

  local logged = {}
  for _, entry in ipairs(dcsStub.logs) do
    logged[#logged + 1] = entry.text
  end
  luaunit.assertStrContains(table.concat(logged, "\n"), "SKYNET_INSIM")
end

function TestInsimReport:testEmitStillReportsWhenTheResultsFileCannotBeWritten()
  -- A path whose directory does not exist, which is the state of a fresh checkout: the results
  -- directory is created by nothing until the first successful write.
  InsimReport.emit(self.results, "Z:/no/such/repo/for/skynet/insim")

  luaunit.assertEquals(#dcsStub.outTexts, 1, "the screen summary must still appear")
  luaunit.assertStrContains(dcsStub.outTexts[1].text, "1 failed")

  local logged = {}
  for _, entry in ipairs(dcsStub.logs) do
    logged[#logged + 1] = entry.text
  end
  local allLogged = table.concat(logged, "\n")
  luaunit.assertStrContains(allLogged, "SKYNET_INSIM")
  luaunit.assertStrContains(allLogged, "cannot write")
end

os.exit(luaunit.LuaUnit.run())
```

- [ ] **Step 3: Run it to verify it fails**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_runner.lua`
Expected: FAIL — cannot open `../insim/runner/report.lua`

- [ ] **Step 4: Implement the reporter**

Create `test/insim/runner/report.lua`:

```lua
do

--[[
InsimReport -- one result set, three outputs.

  * on screen via trigger.action.outText -- the primary readout, so a tester never alt-tabs
  * dcs.log via env.info, tagged SKYNET_INSIM -- failure detail and context
  * test/insim/results/last-run.lua -- machine-readable, gitignored

No reader for the results file is built: the file is the contract that makes one trivial later.
]]

InsimReport = {}

local TAG = "SKYNET_INSIM"
local SCREEN_SECONDS = 30

function InsimReport.summaryText(results)
  local lines = { string.format("Skynet insim: %d passed, %d failed",
    results.passed, results.failed) }

  if results.failed == 0 then
    lines[#lines + 1] = "ALL PASSED"
    return table.concat(lines, "\n")
  end

  for _, suite in ipairs(results.suites or {}) do
    for _, test in ipairs(suite.tests or {}) do
      if test.status == "fail" then
        lines[#lines + 1] = string.format("  FAIL %s.%s", suite.name, test.name)
      end
    end
  end

  return table.concat(lines, "\n")
end

function InsimReport.detailLines(results)
  local lines = { string.format("%s: %d passed, %d failed",
    TAG, results.passed, results.failed) }

  for _, suite in ipairs(results.suites or {}) do
    for _, test in ipairs(suite.tests or {}) do
      lines[#lines + 1] = string.format("%s: %s %s.%s",
        TAG, test.status == "pass" and "PASS" or "FAIL", suite.name, test.name)
      if test.message then
        lines[#lines + 1] = string.format("%s:   %s", TAG, test.message)
      end
    end
  end

  return lines
end

function InsimReport.resultsFileText(results)
  return "--- GENERATED by test/insim. Overwritten on every run.\nreturn "
    .. InsimTestTools.serialize(results) .. "\n"
end

--- Writes all three. `repoPath` nil (or io unavailable) skips the file and still reports.
function InsimReport.emit(results, repoPath)
  trigger.action.outText(InsimReport.summaryText(results), SCREEN_SECONDS)

  for _, line in ipairs(InsimReport.detailLines(results)) do
    env.info(line)
  end

  if not repoPath or not io then
    return
  end

  local path = repoPath .. "/test/insim/results/last-run.lua"
  local handle, err = io.open(path, "w")
  if not handle then
    env.info(string.format("%s: cannot write %s (%s)", TAG, path, tostring(err)))
    return
  end
  handle:write(InsimReport.resultsFileText(results))
  handle:close()
end

end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\test_insim_runner.lua`
Expected: PASS, 27 tests

- [ ] **Step 6: Run the full suite and commit**

The results file this task's reporter writes (`test/insim/results/last-run.lua`) is
machine-generated and must not be committed, so the `.gitignore` entry for it is added here
(originally slated for Task 9, moved up since Task 6 is what makes the file real):

The *directory* must exist in a fresh checkout, though, or the very first in-sim run logs
`cannot write ...last-run.lua` even when every test passed. So track the directory and ignore
its contents, rather than ignoring the directory itself.

Create an empty `test/insim/results/.gitkeep`, and append to `.gitignore`:

```
/test/insim/results/*
!/test/insim/results/.gitkeep
```

Confirm both halves hold (`check-ignore` exits 0 when a path is ignored, 1 when it is not; omit
`-v`, which also prints negation rules and muddies the exit code):

```bash
git check-ignore test/insim/results/last-run.lua   # exits 0 -- ignored
git check-ignore test/insim/results/.gitkeep       # exits 1 -- tracked
```

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
git add test/insim/runner/report.lua test/lua/dcs-stub.lua test/lua/test_insim_runner.lua .gitignore test/insim/results/.gitkeep
git commit -m "feat: add insim result reporting to screen, log and file"
```

---

### Task 7: DCS-world helpers — `addOrReplace`, `removeJunkAround`, `scopedName`

**Executor:** Opus · **Verification:** needs DCS (Task 9 must land first to run it)

**Files:**
- Modify: `test/insim/tools/insim-test-tools.lua` (append the DCS-world half)

**Interfaces:**
- Consumes: `InsimTestTools.deepCopy` (Task 2); DCS `coalition`, `country`, `Group`,
  `StaticObject`, `world`, `land`, `trigger` APIs
- Produces:
  - `InsimTestTools.scopedName(scenarioName, fixtureName)` → `"insim_<scenario>_<fixture>"`
  - `InsimTestTools.addGroupFromTemplate(template, name, anchor, countryId)` → the added group's
    name. `anchor` is `{ x = <north>, y = <east> }` in mission-table coordinates.
  - `InsimTestTools.addStaticFromTemplate(template, name, anchor, countryId)` → the added
    static's name
  - `InsimTestTools.destroyIfLive(name)` → `true` if something was destroyed
  - `InsimTestTools.removeJunkAround(anchor, radius)` → number of wrecks cleared

**Cannot be unit-tested offline.** Every function here is a thin wrapper over a DCS API call
with no logic worth stubbing; the risk is in whether DCS accepts the tables, which only DCS can
answer. Task 11's scenario is its real test.

- [ ] **Step 1: Append the DCS-world half**

Add to `test/insim/tools/insim-test-tools.lua`, inside the existing `do ... end` block, after
the pure-Lua section:

```lua
--- DCS world ---------------------------------------------------------------------------------
--- Everything below needs a running sim. See test/insim/README.md for how to exercise it.

--- Test-scoped names keep one scenario's fixtures from colliding with another's, and give
--- Skynet's prefix discovery a prefix that cannot match a neighbour's leftovers.
function InsimTestTools.scopedName(scenarioName, fixtureName)
  assert(type(scenarioName) == "string" and type(fixtureName) == "string",
    "scopedName: both arguments must be strings")
  return string.format("insim_%s_%s", scenarioName, fixtureName)
end

--- Adds a group from a template at `anchor`. Re-adding the same name replaces a LIVE group;
--- a wreck is not replaced, which is why setUp calls removeJunkAround first.
--- anchor/dx/dy are mission-table coordinates: x is NORTH, y is EAST.
function InsimTestTools.addGroupFromTemplate(template, name, anchor, countryId)
  assert(type(template) == "table" and template.units and template.units[1],
    "addGroupFromTemplate: template has no units")
  assert(type(name) == "string", "addGroupFromTemplate: name must be a string")
  assert(type(anchor) == "table" and anchor.x and anchor.y,
    "addGroupFromTemplate: anchor needs x (north) and y (east)")

  local groupData = {
    name = name,
    task = template.task or "Ground Nothing",
    units = {},
    route = { points = {} },
  }

  for i, unit in ipairs(template.units) do
    groupData.units[i] = {
      name = string.format("%s-%d", name, i),
      type = unit.type,
      x = anchor.x + (unit.dx or 0),
      y = anchor.y + (unit.dy or 0),
      heading = unit.heading or 0,
      skill = unit.skill or "Average",
      playerCanDrive = false,
    }
  end

  coalition.addGroup(countryId, Group.Category.GROUND, groupData)
  return name
end

function InsimTestTools.addStaticFromTemplate(template, name, anchor, countryId)
  assert(type(template) == "table" and template.type, "addStaticFromTemplate: bad template")
  assert(template.category,
    "addStaticFromTemplate: template has no category -- is this a group template?")
  assert(type(name) == "string", "addStaticFromTemplate: name must be a string")
  assert(type(anchor) == "table" and anchor.x and anchor.y,
    "addStaticFromTemplate: anchor needs x (north) and y (east)")

  coalition.addStaticObject(countryId, {
    name = name,
    type = template.type,
    category = template.category,
    x = anchor.x,
    y = anchor.y,
    heading = template.heading or 0,
    dead = false,
  })
  return name
end

--- Destroys a group or static if it is still live. Has no effect on a wreck -- that is what
--- removeJunkAround is for.
function InsimTestTools.destroyIfLive(name)
  local group = Group.getByName(name)
  if group and group:isExist() then
    group:destroy()
    return true
  end

  local static = StaticObject.getByName(name)
  if static and static:isExist() then
    static:destroy()
    return true
  end

  return false
end

--- Clears wrecks in a sphere around `anchor`. Returns how many objects DCS removed.
--- `radius` is measured from the anchor, so it must cover the whole composition footprint plus
--- debris scatter, not just the anchor point.
--- The sphere is centred at terrain height so it covers ground clutter regardless of elevation.
function InsimTestTools.removeJunkAround(anchor, radius)
  assert(type(anchor) == "table" and anchor.x and anchor.y,
    "removeJunkAround: anchor needs x (north) and y (east)")
  assert(type(radius) == "number" and radius > 0, "removeJunkAround: radius must be positive")

  -- land.getHeight takes a Vec2 {x = north, y = east}; world volumes take a Vec3
  -- {x = north, y = altitude, z = east}.
  local point = {
    x = anchor.x,
    y = land.getHeight({ x = anchor.x, y = anchor.y }),
    z = anchor.y,
  }

  local cleared = world.removeJunk({
    id = world.VolumeType.SPHERE,
    params = { point = point, radius = radius },
  })

  -- Documented as a count, but `or 0` alone would pass a boolean straight through to a caller
  -- that is about to do arithmetic on it.
  return type(cleared) == "number" and cleared or 0
end
```

- [ ] **Step 2: Confirm the offline suite still passes**

The pure-Lua tests must be unaffected — nothing above runs at load time.

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua`
Expected: `ALL N SUITE(S) PASSED`

- [ ] **Step 3: Commit**

```bash
git add test/insim/tools/insim-test-tools.lua
git commit -m "feat: add insim DCS-world helpers

addOrReplace semantics, name scoping and wreck clearing. Thin wrappers over the
DCS API; Task 11's scenario is their real test."
```

---

### Task 8: `init.lua` — preflight, source loading, F10 menu

**Executor:** Opus · **Verification:** needs DCS (Task 9 must land first)

**Files:**
- Create: `test/insim/runner/init.lua`

**Interfaces:**
- Consumes: everything from Tasks 2–7; `lfs.writedir()`, `missionCommands`, `dofile`
- Produces: the entry point the mission bootstrap calls. Builds
  **F10 → Skynet Tests → Run all / Re-run last / Run one suite**, and defines global
  `InsimInit.repoPath` for the reporter and loader.

Every run re-`dofile`s Skynet source and scenario files, so editing a scenario and pressing F10
picks up the change with no mission restart.

- [ ] **Step 1: Write the entry point**

Create `test/insim/runner/init.lua`:

```lua
do

--[[
test/insim entry point. The mission's embedded bootstrap dofile's this; everything else is read
from disk on every run, so a scenario edit needs no mission restart and no Mission Editor.

Preflights the MissionScripting.lua sanitization edit first. DCS updates and repairs silently
revert that edit, so failing with an explicit message beats failing obscurely later.
]]

InsimInit = {}

local lastRun = nil         -- suite file of the most recent run, for "Re-run last"
local running = false       -- guards against a second run being started over a live one

local function fail(message)
  if trigger and trigger.action then
    trigger.action.outText("skynet-insim: " .. message, 60)
  end
  if env then
    env.info("SKYNET_INSIM: " .. message)
  end
end

--- The sanitization edit unlocks io, os and lfs together. lfs is load-bearing: it is how the
--- repo path is found at all.
local function preflight()
  local missing = {}
  if not io then missing[#missing + 1] = "io" end
  if not os then missing[#missing + 1] = "os" end
  if not lfs then missing[#missing + 1] = "lfs" end

  if #missing > 0 then
    fail("re-apply the edit in <DCS install>\\Scripts\\MissionScripting.lua -- missing: "
      .. table.concat(missing, ", ") .. ". A DCS update reverts it.")
    return false
  end

  return true
end

local function resolveRepoPath()
  local configPath = lfs.writedir() .. "Config/skynet-insim.lua"
  local chunk = loadfile(configPath)
  if not chunk then
    fail("create " .. configPath .. " containing: return [[<path to the repo>]]")
    return nil
  end

  local ok, path = pcall(chunk)
  if not ok or type(path) ~= "string" then
    fail(configPath .. " must return the repo path as a string")
    return nil
  end

  return (path:gsub("[\\/]*$", ""))
end

--- Scenario files are discovered by listing the directory, so adding one needs no registration.
--- The directory is legitimately absent until the first scenario exists, and lfs.dir raises on
--- a missing path. Menu building calls this outside any pcall, so absence must read as "none".
--- Returns names, dir, err -- the error is kept rather than swallowed so a caller can tell
--- "nobody has written a scenario yet" apart from "that directory cannot be read".
local function discoverScenarioFiles(repoPath)
  local dir = repoPath .. "/test/insim/scenarios"
  local names = {}

  -- The whole enumeration is protected, not just the lfs.dir call: LuaFileSystem builds differ
  -- over whether a missing directory raises when the iterator is created or on its first step.
  local listed, err = pcall(function()
    for entry in lfs.dir(dir) do
      if entry:match("^scenario_.+%.lua$") then
        names[#names + 1] = entry
      end
    end
  end)

  if not listed then
    return {}, dir, err
  end

  table.sort(names)
  return names, dir, nil
end

--- Re-reads Skynet source and every scenario file, then returns the suite list the runner takes.
local function loadSuites(repoPath, onlyFile)
  local loader = dofile(repoPath .. "/test/common/skynet-loader.lua")
  loader.setRoot(repoPath .. "/skynet-iads-source")
  loader.reset()
  loader.loadAll()

  luaunit = dofile(repoPath .. "/test/common/luaunit.lua")
  dofile(repoPath .. "/test/insim/tools/insim-test-tools.lua")
  dofile(repoPath .. "/test/insim/runner/wait.lua")
  dofile(repoPath .. "/test/insim/runner/runner.lua")
  dofile(repoPath .. "/test/insim/runner/report.lua")

  local files, dir = discoverScenarioFiles(repoPath)
  local suites = {}

  for _, file in ipairs(files) do
    if not onlyFile or file == onlyFile then
      -- A scenario file returns { name = <string>, suite = <table> }.
      local entry = dofile(dir .. "/" .. file)
      assert(type(entry) == "table" and entry.name and entry.suite,
        file .. ": a scenario must return { name = ..., suite = ... }")
      suites[#suites + 1] = entry
    end
  end

  return suites
end

local function run(onlyFile)
  local repoPath = InsimInit.repoPath

  -- A second run would re-dofile runner.lua and the Skynet source underneath the first run's
  -- live coroutines, arm a second scheduled tick, and race to overwrite last-run.lua. An
  -- impatient double-press is likely, and the result would read as flaky tests.
  if running then
    trigger.action.outText("skynet-insim: a run is already in progress", 10)
    return
  end

  local ok, suites = pcall(loadSuites, repoPath, onlyFile)

  if not ok then
    fail("loading failed: " .. tostring(suites))
    return
  end

  if #suites == 0 then
    local _, dir, err = discoverScenarioFiles(repoPath)
    if err then
      fail("cannot read " .. dir .. " -- " .. tostring(err))
    else
      fail("no scenarios in " .. dir .. " -- add scenario_<name>.lua there")
    end
    return
  end

  lastRun = onlyFile
  trigger.action.outText(string.format("skynet-insim: running %d suite(s)...", #suites), 10)

  running = true
  InsimRunner.start(suites, function(results)
    running = false
    InsimReport.emit(results, repoPath)
  end)
end

function InsimInit.start()
  if InsimInit.repoPath then
    return   -- already bootstrapped; a second dofile must not build a second menu
  end

  if not preflight() then
    return
  end

  local repoPath = resolveRepoPath()
  if not repoPath then
    return
  end
  InsimInit.repoPath = repoPath

  local menu = missionCommands.addSubMenu("Skynet Tests")
  missionCommands.addCommand("Run all", menu, function() run(nil) end)
  missionCommands.addCommand("Re-run last", menu, function() run(lastRun) end)

  local suiteMenu = missionCommands.addSubMenu("Run one suite", menu)
  local files = discoverScenarioFiles(repoPath)
  for _, file in ipairs(files) do
    local label = file:gsub("^scenario_", ""):gsub("%.lua$", "")
    missionCommands.addCommand(label, suiteMenu, function() run(file) end)
  end

  env.info(string.format("SKYNET_INSIM: menu ready, %d scenario file(s), repo %s",
    #files, repoPath))
end

end

InsimInit.start()
```

- [ ] **Step 2: Confirm the offline suite is unaffected and commit**

Run: `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua`
Expected: `ALL N SUITE(S) PASSED`

```bash
git add test/insim/runner/init.lua
git commit -m "feat: add the insim entry point, preflight and F10 menu"
```

---

### Task 9: The mission, the config file and the README

**Executor:** human-in-DCS · **Verification:** needs DCS

**Not delegable.** This task is authored in the DCS Mission Editor and verified by launching
DCS. A subagent cannot do any of it. Everything before this task is testable offline;
everything after it depends on this being done.

**Files:**
- Create: `test/insim/skynet-insim.miz` (Mission Editor)
- Create: `%USERPROFILE%\Saved Games\DCS\Config\skynet-insim.lua` (one line, not in the repo)
- Create: `test/insim/README.md`
- Create: `test/insim/fixtures/placements.lua`
- Modify: `.gitignore`

- [ ] **Step 1: Unlock the mission scripting environment**

Edit `<DCS install>/Scripts/MissionScripting.lua` and comment out the sanitization block:

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

This is install-wide and affects multiplayer integrity checks. **DCS updates and repairs revert
it** — the runner's preflight will say so explicitly when that happens.

- [ ] **Step 2: Write the config file**

Create `%USERPROFILE%\Saved Games\DCS\Config\skynet-insim.lua`:

```lua
return [[D:\Projects\DcsLua\Skynet-IADS]]
```

- [ ] **Step 3: Author the mission**

In the Mission Editor:
1. New mission, **Caucasus**.
2. Add one **Neutral Game Master** slot (neutral so it sees both coalitions).
3. Place the fixture assets the first scenario needs, all **Late Activation**:
   - a red **1L13 EWR** group, named `FIXTURE-EWR`
   - a red **SA-6 Kub** site (`Kub 1S91 str` + 2× `Kub 2P25 ln`), named `FIXTURE-SAM-Kub`
   These are read by the extractor and give a map view of the fixture world; a normal run never
   activates them.
4. Add a trigger: **MISSION START**, no condition, action **DO SCRIPT**, with exactly:

```lua
local cfg = loadfile(lfs.writedir() .. "Config/skynet-insim.lua")
local repo = cfg and cfg()
if not repo then
  trigger.action.outText("skynet-insim: create Saved Games/DCS/Config/skynet-insim.lua", 60)
  return
end
dofile(repo .. "/test/insim/runner/init.lua")
```

5. Save as `test/insim/skynet-insim.miz`.

- [ ] **Step 4: Record the anchors**

Read each fixture's coordinates off the Mission Editor (F10 map, unit properties) and create
`test/insim/fixtures/placements.lua`:

```lua
--- Caucasus anchors, one well-separated region per scenario.
--- Mission-table coordinates: x is NORTH, y is EAST.
--- Separation matters: setUp clears wrecks in a sphere around its own anchor, and that sphere
--- must not reach another scenario's fixtures.
return {
  detection = {
    radius = 3000,                    -- the removeJunk sphere for this scenario
    ewr = { x = 0, y = 0 },           -- REPLACE with the real Caucasus coordinates
    sam = { x = 0, y = 0 },           -- REPLACE
    target = { x = 0, y = 0 },        -- REPLACE: aircraft start point, ~40km from the EWR
  },
}
```

- [ ] **Step 5: Verify the preflight and menu**

Launch `skynet-insim.miz`, take the Game Master slot, open **F10**.
Expected: a **Skynet Tests** menu with **Run all**, **Re-run last** and **Run one suite**.
`dcs.log` contains `SKYNET_INSIM: menu ready`.

If instead the screen says "re-apply the MissionScripting.lua edit", Step 1 did not take.
If it names the config file, Step 2 did not take.

- [ ] **Step 7: Write the README**

Create `test/insim/README.md`:

````markdown
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

## Running

1. Launch `test/insim/skynet-insim.miz` in DCS.
2. Take the **Neutral Game Master** slot — the map view shows added fixtures, wrecks and unit
   positions while a scenario runs.
3. **F10 → Skynet Tests → Run all**.

Results appear on screen, in `dcs.log` tagged `SKYNET_INSIM`, and in
`test/insim/results/last-run.lua`.

Every run re-reads Skynet source and scenario files from disk, so **editing a scenario and
pressing F10 again is the whole edit→run loop** — no mission restart, no Mission Editor.

If the world gets cluttered after a long session, restart the mission. That is the hard reset.

## Writing a scenario

A scenario file returns `{ name = ..., suite = ... }`. The suite is luaunit-shaped —
`setUp`, `tearDown`, and `test*` functions — but the runner, not luaunit, drives it, so test
bodies may wait for sim time:

```lua
waitFor(function() return sam:isActive() end, 60)   -- yields until true, fails after 60s
waitSeconds(30)                                     -- yields for 30 sim-seconds
```

Every wait is bounded and each test has an overall budget (`InsimRunner.DEFAULT_BUDGET`, or
`budgetSeconds` on the suite), so a hung test fails rather than wedging the mission.

Isolation, per the design:

- `setUp` clears wrecks around the scenario's anchor, then adds fixtures under scoped names.
- `tearDown` destroys what is still live and deactivates the IADS.
- Adding a name that is already live replaces it; a wreck is not replaced, which is why
  `removeJunkAround` runs in `setUp`.

## Regenerating fixtures

Fixtures are authored in the Mission Editor and stored as position-independent Lua. To
regenerate after changing the mission:

```bash
cd test/insim
unzip -o skynet-insim.miz mission
lua5.1 tools/extract-fixtures.lua mission FIXTURE- > fixtures/generated/fixtures.lua
rm mission
```

Anchors live separately in `fixtures/placements.lua` — templates carry only composition
(types, headings, skills, and offsets from the first unit), so one template can be re-anchored
anywhere.
````

- [ ] **Step 8: Commit**

```bash
git add test/insim/skynet-insim.miz test/insim/README.md test/insim/fixtures/placements.lua .gitignore
git commit -m "feat: add the insim test mission, setup docs and Caucasus anchors"
```

---

### Task 10: Generate the fixture file from the real mission

**Executor:** Sonnet (after the human step) · **Verification:** lua5.1

**Files:**
- Create: `test/insim/fixtures/generated/fixtures.lua`

**Interfaces:**
- Consumes: `InsimExtractor` (Task 3) and `test/insim/skynet-insim.miz` (Task 9)
- Produces: `test/insim/fixtures/generated/fixtures.lua` returning
  `{ ["FIXTURE-EWR"] = <template>, ["FIXTURE-SAM-Kub"] = <template> }`

- [ ] **Step 1: Extract**

```bash
cd test/insim
unzip -o skynet-insim.miz mission
lua5.1 tools/extract-fixtures.lua mission FIXTURE- > fixtures/generated/fixtures.lua
rm mission
```

- [ ] **Step 2: Check the output by eye**

Open `fixtures/generated/fixtures.lua`. Expected: two templates; the EWR has one unit with
`dx = 0, dy = 0`; the Kub site has three units whose `dx`/`dy` are small (tens of metres) and
whose first unit is at the origin. **No absolute coordinates and no `name` keys on units.**

If absolute coordinates appear, the extractor regressed — Task 3's
`testTemplateCarriesNoAbsoluteCoordinates` covers exactly that; run it.

- [ ] **Step 3: Confirm it loads and commit**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" -e "local f = assert(loadfile('test/insim/fixtures/generated/fixtures.lua'))() ; print('templates:', (next(f) and 'ok' or 'EMPTY'))"
git add test/insim/fixtures/generated/fixtures.lua
git commit -m "feat: add extracted Caucasus fixture templates"
```

---

### Task 11: The proving scenario — real radar detection

**Executor:** Opus, verified human-in-DCS · **Verification:** needs DCS

**Files:**
- Create: `test/insim/scenarios/scenario_detection.lua`

**Interfaces:**
- Consumes: `InsimTestTools` (Tasks 2, 7), `waitFor`/`waitSeconds` (Task 4),
  `fixtures/generated/fixtures.lua` (Task 10), `fixtures/placements.lua` (Task 9),
  `SkynetIADS` from the loaded source
- Produces: a scenario file returning `{ name = "Detection", suite = <table> }`

This is the deliverable that proves the tier: it adds fixtures, waits for genuine DCS radar
detection, and asserts the IADS reacts. A synchronous placeholder would exercise none of the
adding, waiting, timeout or isolation machinery.

- [ ] **Step 1: Write the scenario**

Create `test/insim/scenarios/scenario_detection.lua`:

```lua
--- Proves the tier end to end: real DCS radar detection driving real Skynet state.
---
--- Deliberately time-dependent. Detection is not instant and not deterministic, so every wait
--- is generous; a scenario needing tight timing is the wrong scenario for this tier.

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
local fixtures = assert(loadfile(base .. "/../fixtures/generated/fixtures.lua"))()
local placements = assert(loadfile(base .. "/../fixtures/placements.lua"))()

local SCENARIO = "Detection"
local PLACEMENT = placements.detection
local RED = country.id.CJTF_RED

local TestDetection = {}

local function scoped(name)
  return InsimTestTools.scopedName(SCENARIO, name)
end

function TestDetection:setUp()
  -- Clear wrecks from any previous run first: adding a name replaces a LIVE entity, but not a
  -- wreck. This also covers runs that crashed or were re-triggered mid-scenario.
  InsimTestTools.removeJunkAround(PLACEMENT.ewr, PLACEMENT.radius)
  InsimTestTools.removeJunkAround(PLACEMENT.sam, PLACEMENT.radius)

  self.ewrName = InsimTestTools.addGroupFromTemplate(
    fixtures["FIXTURE-EWR"], scoped("EWR"), PLACEMENT.ewr, RED)
  self.samName = InsimTestTools.addGroupFromTemplate(
    fixtures["FIXTURE-SAM-Kub"], scoped("SAM"), PLACEMENT.sam, RED)

  self.iads = SkynetIADS:create(scoped("iads"))
  self.iads:addEarlyWarningRadarsByPrefix(scoped("EWR"))
  self.iads:addSAMSitesByPrefix(scoped("SAM"))
  self.iads:activate()

  self.tracked = { self.ewrName, self.samName }
end

function TestDetection:tearDown()
  if self.iads then
    self.iads:deactivate()
  end
  for _, name in ipairs(self.tracked or {}) do
    InsimTestTools.destroyIfLive(name)
  end
end

--- The fixtures exist and Skynet found them. Synchronous, and the cheapest failure to diagnose
--- if the whole thing is broken.
function TestDetection:testFixturesAreAddedAndJoinTheIADS()
  luaunit.assertNotNil(Group.getByName(self.ewrName), "EWR group was not added")
  luaunit.assertNotNil(Group.getByName(self.samName), "SAM group was not added")
  luaunit.assertEquals(#self.iads:getEarlyWarningRadars(), 1)
  luaunit.assertEquals(#self.iads:getSAMSites(), 1)
end

--- The time-dependent one. The SAM starts dark; a live EWR detecting the target is what brings
--- it up, and that takes simulated seconds.
function TestDetection:testSAMGoesLiveWhenTheEWRDetectsATarget()
  local sam = self.iads:getSAMSiteByGroupName(self.samName)
  luaunit.assertNotNil(sam, "the SAM site did not join the IADS")
  luaunit.assertFalse(sam:isActive(), "the SAM should start dark")

  local target = InsimTestTools.addGroupFromTemplate(
    { task = "Ground Nothing", units = { { type = "M-1 Abrams", dx = 0, dy = 0 } } },
    scoped("TARGET"), PLACEMENT.target, country.id.USA)
  self.tracked[#self.tracked + 1] = target

  -- Detection, then the IADS's own evaluation cycle, then the SAM coming up.
  waitFor(function() return sam:isActive() end, 300)
  luaunit.assertTrue(sam:isActive())
end

return { name = SCENARIO, suite = TestDetection }
```

- [ ] **Step 2: Run it in DCS**

Launch `skynet-insim.miz`, take the Game Master slot, **F10 → Skynet Tests → Run all**.
Expected on screen: `Skynet insim: 2 passed, 0 failed` and `ALL PASSED`.

- [ ] **Step 3: Diagnose from the map if it fails**

This is why Game Master is the recommended slot. Read `dcs-log` lines tagged `SKYNET_INSIM`
first, then check on the map:

| Symptom | Likely cause |
|---|---|
| `EWR group was not added` | Enum or template problem — verification item 3. Check `country.id.CJTF_RED` and `Group.Category.GROUND`, and that the template's unit `type` strings match the Mission Editor's |
| Fixtures appear in the wrong place, or in the sea | Axis convention — `dy` is **east**, not north or altitude. Check `placements.lua` against the Mission Editor coordinates |
| Groups added but `getEarlyWarningRadars()` is 0 | Prefix mismatch: `addEarlyWarningRadarsByPrefix` must match the scoped name `insim_Detection_EWR` |
| `waitFor timed out` on the SAM going live | Target too far for detection, or the SAM has no line of sight. Move `PLACEMENT.target` closer, or raise the timeout — but confirm on the map that the EWR really sees it first |
| Fixtures land whole but a rerun shows wrecks | `removeJunkAround` radius too small, or the anchor is wrong |

- [ ] **Step 4: Verify the re-run loop**

Change a timeout in the scenario file, save, and press **F10 → Skynet Tests → Run all** again
**without restarting the mission**. Expected: the new value takes effect, and fixtures are whole
again rather than duplicated or wrecked. That single check exercises hot reload, same-name
replacement and wreck clearing together.

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
git add test/insim/scenarios/scenario_detection.lua
git commit -m "feat: add the insim detection scenario

Adds an EWR, a SAM site and a target, waits for genuine DCS radar detection, and
asserts the IADS brings the site live. Proves adding, coroutine waiting,
timeouts, isolation and reporting in one scenario."
```

---

## Verification items carried from the spec

These are checked as a side effect of the tasks above, not as separate work. Record what each
one turns out to be — several are questions about DCS, not about this code.

| Item | Settled by |
|---|---|
| Fixture fidelity — does an added group behave like its editor-placed original? | Task 11 Step 2. If an asset class fails, fall back to activating the late-activated editor group for it |
| `lfs.writedir()` availability post-unsanitize | Task 9 Step 5 — the menu appearing at all proves it |
| `coalition.addGroup` country/category enum correctness | Task 11 Step 2, first test |
| Re-anchoring Persian Gulf compositions onto Caucasus | Not exercised: Task 9 authors fixtures directly on Caucasus. Harvesting the legacy `.miz` is later work |
| `removeJunk` stability (client CTD history) | Task 11 Step 4 — if DCS dies seconds after a rerun, that is the known bug |
| Partially exploded groups | Not exercised by this plan. The first scenario that explodes a fixture mid-test will hit it |

## Self-review

**Spec coverage.** Shape → Task 9; repo path resolution → Tasks 8, 9; run loop and F10 menu →
Task 8; async model → Tasks 4, 5; fixtures and the extractor → Tasks 3, 9, 10; axis conventions
→ Global Constraints, Tasks 3, 7; isolation → Tasks 7, 11; no mist → Global Constraints, honoured
throughout; results → Task 6; setup cost → Task 9; layout → the file structure table;
`test/common/` → Task 1; deliverable → Task 11.

**Gap found and closed:** the spec's layout lists `runner/init.lua` as doing "suite discovery",
which nothing else specified. Task 8 defines it: `lfs.dir` over `scenarios/scenario_*.lua`, each
file returning `{ name, suite }`. That contract is now stated in Task 8's interfaces and used by
Task 11.

**Type consistency.** `InsimRunner.results` shape is produced in Task 5 and consumed in Task 6;
`{ name, suite }` is produced in Task 11 and consumed in Task 8; templates are produced in Task 3
and consumed in Task 7; `anchor` is `{ x = north, y = east }` in Tasks 7, 9 and 11;
`InsimTestTools.scopedName` is defined in Task 7 and used in Task 11. `isActive()` is the real
emission accessor — `isRadarEmitting()` does not exist in the source.
