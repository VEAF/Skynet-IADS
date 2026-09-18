do

--[[
test/insim entry point. The mission's embedded bootstrap dofile's this; everything else is read
from disk on every run, so a scenario edit needs no mission restart and no Mission Editor.

Preflights the MissionScripting.lua sanitization edit first. DCS updates and repairs silently
revert that edit, so failing with an explicit message beats failing obscurely later.
]]

InsimInit = {}

local lastRun = nil         -- suite file of the most recent run, for "Re-run last"

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
    fail("re-apply the MissionScripting.lua edit -- missing: "
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
local function discoverScenarioFiles(repoPath)
  local dir = repoPath .. "/test/insim/scenarios"
  local names = {}

  -- The whole enumeration is protected, not just the lfs.dir call: LuaFileSystem builds differ
  -- over whether a missing directory raises when the iterator is created or on its first step.
  local listed = pcall(function()
    for entry in lfs.dir(dir) do
      if entry:match("^scenario_.+%.lua$") then
        names[#names + 1] = entry
      end
    end
  end)

  if not listed then
    return {}, dir
  end

  table.sort(names)
  return names, dir
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
  local ok, suites = pcall(loadSuites, repoPath, onlyFile)

  if not ok then
    fail("loading failed: " .. tostring(suites))
    return
  end

  if #suites == 0 then
    fail("no scenarios found")
    return
  end

  lastRun = onlyFile
  trigger.action.outText(string.format("skynet-insim: running %d suite(s)...", #suites), 10)

  InsimRunner.start(suites, function(results)
    InsimReport.emit(results, repoPath)
  end)
end

function InsimInit.start()
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
