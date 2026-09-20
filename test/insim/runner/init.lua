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

--- The sanitization edit unlocks io, os, lfs and require together. lfs is load-bearing -- it is
--- how the repo path is found at all -- and luaunit calls require at its very first line, so a
--- half-applied edit is worth naming here rather than surfacing as a load error from a vendored
--- file.
local function preflight()
  local missing = {}
  if not io then missing[#missing + 1] = "io" end
  if not os then missing[#missing + 1] = "os" end
  if not lfs then missing[#missing + 1] = "lfs" end
  if not require then missing[#missing + 1] = "require" end

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
    fail("a run is already in progress")
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

  -- InsimRunner.plan asserts more strictly than loadSuites does, so a malformed scenario can
  -- raise here, after the flag is set. Releasing it on failure keeps a bad scenario file from
  -- wedging the menu until the mission is restarted.
  local started, err = pcall(InsimRunner.start, suites, function(results)
    running = false
    InsimReport.emit(results, repoPath)
  end)

  if not started then
    running = false
    fail("could not start the run: " .. tostring(err))
  end
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
