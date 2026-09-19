--- Reports how much of skynet-iads-source/ the standalone suite executed.
---
--- Beware the word: in Skynet, "coverage" is what an early warning radar does to a SAM
--- site (CONTEXT.md). This reports *test* coverage and nothing else.
---
--- It reads the stats the suite merged into luacov.stats.out; it does not run anything.
--- Usage, from the repository root:
---   SKYNET_TEST_COVERAGE=1 lua5.1 test/lua/run.lua
---   lua5.1 build-tools/report-test-coverage.lua
---
--- What is measured, and what is left out, lives in .luacov beside this repository's root.
--- The lowest figure accepted is in build-tools/test-coverage-floor.txt.
---
--- Exit codes, kept apart on purpose: 1 means the suite covers less than the floor, 2 means
--- the measurement did not happen at all. A luacov that installed badly must not look like a
--- drop in test coverage.

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."

local function fail(reason)
  io.stderr:write("report-test-coverage: " .. reason .. "\n")
  os.exit(2)
end

local function readFloor()
  local path = base .. "/test-coverage-floor.txt"
  local file = io.open(path, "r")
  if not file then
    fail("cannot read the floor from " .. path)
  end
  local value
  for line in file:lines() do
    local entry = line:match("^%s*(.-)%s*$")
    if entry ~= "" and entry:sub(1, 1) ~= "#" then
      value = tonumber(entry)
      if not value then
        file:close()
        fail(path .. " holds '" .. entry .. "', which is not a number")
      end
      break
    end
  end
  file:close()
  if not value then
    fail(path .. " holds no figure")
  end
  -- A percentage outside these bounds is a typo, and the two directions fail differently: 700
  -- is a gate nothing can ever pass, -5 is a gate that passes everything and says nothing.
  if value <= 0 or value > 100 then
    fail(path .. " holds " .. value .. ", which is not a percentage between 0 and 100")
  end
  return value
end

local ok, runner = pcall(require, "luacov.runner")
if not ok then
  fail("luacov is not installed for this interpreter.\n"
    .. "  Linux/CI: luarocks --lua-version=5.1 install luacov\n"
    .. "  Windows:  it ships with Lua for Windows, so check you are running its lua.exe")
end

local config = runner.load_config()
local statsFile = config.statsfile
local reportFile = config.reportfile

local stats = io.open(statsFile, "r")
if not stats then
  fail("no " .. statsFile .. " in " .. (os.getenv("PWD") or "the working directory") .. ".\n"
    .. "  Run the suite first: SKYNET_TEST_COVERAGE=1 lua5.1 test/lua/run.lua")
end
stats:close()

-- Read before reporting: a floor file nobody can parse is a broken gate, and should say so
-- straight away rather than after a page of figures it is about to refuse to judge.
local floor = readFloor()

require("luacov.reporter").report()

local report = io.open(reportFile, "r")
if not report then
  fail("luacov produced no " .. reportFile)
end

-- The reporter's own summary is the source of the figures: re-deriving them from the stats
-- would mean re-implementing its idea of which lines are code, and disagreeing with it silently.
local rows, total = {}, nil
local inSummary = false
for line in report:lines() do
  if line:match("^Summary") then
    inSummary = true
  elseif inSummary then
    local name, hits, missed, percent = line:match("^(%S.-%.lua)%s+(%d+)%s+(%d+)%s+([%d%.]+)%%")
    if name then
      rows[#rows + 1] = {
        name = name:match("([^\\/]+)$"),
        hits = tonumber(hits),
        missed = tonumber(missed),
        percent = tonumber(percent),
      }
    else
      local tHits, tMissed, tPercent = line:match("^Total%s+(%d+)%s+(%d+)%s+([%d%.]+)%%")
      if tHits then
        total = { hits = tonumber(tHits), missed = tonumber(tMissed), percent = tonumber(tPercent) }
      end
    end
  end
end
report:close()

if not total then
  fail(reportFile .. " has no summary — the suite may have run without SKYNET_TEST_COVERAGE=1")
end

-- A summary that measured nothing is not 0% test coverage, it is a broken measurement: an
-- include pattern that stopped matching, or a run from the wrong directory. Reporting it as a
-- number would be a green job carrying a figure nobody can act on.
if total.hits + total.missed == 0 then
  fail("the summary measured no lines at all — check .luacov's include patterns still match "
    .. "skynet-iads-source, and that both commands ran from the repository root")
end

-- Worst first: the file to look at is the one holding the most unexecuted lines, which is not
-- the one with the lowest percentage.
table.sort(rows, function(a, b)
  if a.missed ~= b.missed then
    return a.missed > b.missed
  end
  return a.name < b.name
end)

local widest = 0
for _, row in ipairs(rows) do
  widest = math.max(widest, #row.name)
end

for _, row in ipairs(rows) do
  print(string.format(
    "%-" .. widest .. "s  %5d hit  %4d missed  %6.2f%%",
    row.name, row.hits, row.missed, row.percent))
end

local measured = total.hits + total.missed
-- The verdict is decided on whole lines, not on the percentage: that figure is rounded to two
-- decimals for reading, and a gate must not turn on a rounding nobody can see.
local required = math.ceil(floor / 100 * measured)

print("")
print(string.format(
  "test coverage: %.2f%%  (%d / %d lines)",
  total.percent, total.hits, measured))
print("per-line detail: " .. reportFile)
print("")

if total.hits < required then
  -- On stdout, not stderr: the verdict is part of the report, and CI shows the report to the
  -- reviewer. stderr is kept for the cases where the measurement itself did not happen.
  print(string.format(
    "FAIL: below the floor of %g%% (%d lines) — %d lines short.",
    floor, required, required - total.hits))
  print("The per-file table above says where. A drop is not always a lost test: deleting")
  print("covered code, or adding a file nothing exercises, moves the number too.")
  os.exit(1)
end

print(string.format("PASS: at or above the floor of %g%% (%d lines).", floor, required))

-- The floor is meant to follow the work up, in the pull request that earned it. Said here
-- rather than enforced: a change that improves test coverage must not fail for improving it.
local reachable = math.floor(total.hits / measured * 100)
if reachable > floor then
  print(string.format(
    "NOTE: build-tools/test-coverage-floor.txt can be raised from %g to %d.",
    floor, reachable))
end
