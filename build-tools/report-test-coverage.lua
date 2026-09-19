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

local function fail(reason)
  io.stderr:write("report-test-coverage: " .. reason .. "\n")
  os.exit(2)
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

print("")
print(string.format(
  "test coverage: %.2f%%  (%d / %d lines)",
  total.percent, total.hits, total.hits + total.missed))
print("per-line detail: " .. reportFile)
