--- Offline tests for test/insim/tools/insim-skynet-tools.lua.
---
--- The Skynet objects here are fakes, deliberately. What is under test is our own arithmetic --
--- which element gates a site going live, and at what distance -- not Skynet's range model,
--- which test/lua's own Skynet suites cover against the real classes.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/../insim/runner/log.lua")
dofile(base .. "/../insim/tools/insim-skynet-tools.lua")

-- Skynet's own constant, which the real source defines; the helper reads it to confirm the site
-- is in the default kill-zone mode before predicting anything.
SkynetIADSAbstractRadarElement = { GO_LIVE_WHEN_IN_KILL_ZONE = 1, GO_LIVE_WHEN_IN_SEARCH_RANGE = 2 }

TestInsimSkynet = {}

function TestInsimSkynet:setUp()
  dcsStub.reset()
  dcsStub.setClock(0)
  InsimLog.reset()
end

--- One radar or launcher: the four calls the report makes on it.
local function element(maxRange, distance, options)
  options = options or {}
  return {
    firingRangePercent = options.percent or 100,
    isExist = function() return options.exists ~= false end,
    getMaxRangeFindingTarget = function() return maxRange end,
    getDistance = function() return distance end,
    getTypeName = function() return options.type or "some-element" end,
  }
end

--- A SAM site whose three kinds gate at the given ranges. The launcher is normally the binding
--- one, which is the case the scenario cares about.
local function samSite(spec)
  return {
    searchRadars = spec.search or { element(100000, spec.distance, { type = "Kub 1S91 str" }) },
    trackingRadars = spec.tracking or { element(90000, spec.distance) },
    launchers = spec.launchers or { element(24000, spec.distance, { type = "Kub 2P25 ln" }) },
    getSearchRadars = function(self) return self.searchRadars end,
    getTrackingRadars = function(self) return self.trackingRadars end,
    getLaunchers = function(self) return self.launchers end,
    getEngagementZone = function() return spec.zone or 1 end,
    getDCSName = function() return spec.name or "SKY-Z01-SA6-01" end,
  }
end

function TestInsimSkynet:testTheGateIsTheSmallestOfTheThreeKinds()
  -- isTargetInRange needs search AND tracking AND launcher, so the shortest-ranged kind decides
  -- when the site may come up.
  local report = InsimSkynet.engagementReport(samSite({ distance = 30000 }), {})

  luaunit.assertEquals(report.gate, 24000)
  luaunit.assertEquals(report.gateKind, "launcher")
end

function TestInsimSkynet:testTheGateUsesTheLongestRangedElementWithinAKind()
  -- Within one kind any single element in range is enough, so the best of them decides.
  local report = InsimSkynet.engagementReport(samSite({
    distance = 30000,
    launchers = { element(24000, 30000), element(40000, 30000) },
  }), {})

  luaunit.assertEquals(report.gate, 40000)
end

function TestInsimSkynet:testAnEmptyKindDoesNotGateAnything()
  -- Skynet reads an empty kind as satisfied (#self.launchers == 0), so it must not pull the
  -- predicted gate down to zero.
  local report = InsimSkynet.engagementReport(samSite({ distance = 30000, launchers = {} }), {})

  luaunit.assertEquals(report.gate, 90000)
  luaunit.assertEquals(report.gateKind, "tracking")
end

function TestInsimSkynet:testADestroyedElementIsNotCounted()
  local report = InsimSkynet.engagementReport(samSite({
    distance = 30000,
    launchers = { element(40000, 30000, { exists = false }), element(24000, 30000) },
  }), {})

  luaunit.assertEquals(report.gate, 24000)
end

function TestInsimSkynet:testTheGateHonoursAReducedFiringRangePercent()
  -- setGoLiveRangeInPercent(50) halves the effective range Skynet compares against.
  local report = InsimSkynet.engagementReport(samSite({
    distance = 30000,
    launchers = { element(24000, 30000, { percent = 50 }) },
  }), {})

  luaunit.assertEquals(report.gate, 12000)
end

function TestInsimSkynet:testTheReportCarriesTheCurrentDistanceAndWhetherItIsInside()
  local outside = InsimSkynet.engagementReport(samSite({ distance = 30000 }), {})
  luaunit.assertEquals(outside.distance, 30000)
  luaunit.assertFalse(outside.inRange)

  local inside = InsimSkynet.engagementReport(samSite({ distance = 20000 }), {})
  luaunit.assertTrue(inside.inRange)
end

function TestInsimSkynet:testASiteInSearchRangeModeIsGatedOnlyByItsSearchRadar()
  local report = InsimSkynet.engagementReport(samSite({ distance = 30000, zone = 2 }), {})

  luaunit.assertEquals(report.gate, 100000)
  luaunit.assertEquals(report.gateKind, "search")
end

function TestInsimSkynet:testDescribeEngagementNamesTheGateAndTheMargin()
  local text = InsimSkynet.describeEngagement(samSite({ distance = 20000 }), {})

  luaunit.assertStrContains(text, "24000")
  luaunit.assertStrContains(text, "20000")
  luaunit.assertStrContains(text, "launcher")
end

--- Stands in for a SkynetIADS: only the two members networkDisplayState touches. The
--- behaviour under test is our wiring, not Skynet's.
local function fakeIads()
  local settings = {}
  return {
    logger = { printOutputToLog = function(_, text) settings.lastNative = text end },
    getDebugSettings = function() return settings end,
  }, settings
end

function TestInsimSkynet:testSkynetOutputIsRoutedIntoTheRunTimeline()
  local captured = {}
  local previousLog = log
  log = function(format, ...) captured[#captured + 1] = string.format(format, ...) end

  local iads = fakeIads()
  InsimSkynet.networkDisplayState(iads, true)
  iads.logger:printOutputToLog("GOING LIVE: SAM SITE SKY-Z01-SA6-01")

  log = previousLog
  luaunit.assertEquals(#captured, 1)
  luaunit.assertStrContains(captured[1], "GOING LIVE: SAM SITE SKY-Z01-SA6-01")
end

function TestInsimSkynet:testTurningTheDisplayOffPutsSkynetsOwnLoggerBack()
  local captured = {}
  local previousLog = log
  log = function(format, ...) captured[#captured + 1] = string.format(format, ...) end

  local iads, settings = fakeIads()
  InsimSkynet.networkDisplayState(iads, true)
  InsimSkynet.networkDisplayState(iads, false)
  iads.logger:printOutputToLog("GOING DARK: SAM SITE")

  log = previousLog
  luaunit.assertEquals(#captured, 0, "the timeline should no longer be receiving Skynet output")
  luaunit.assertEquals(settings.lastNative, "GOING DARK: SAM SITE")
end

function TestInsimSkynet:testTheDisplayFlagsSkynetActuallyReadsAreSet()
  local iads, settings = fakeIads()

  InsimSkynet.networkDisplayState(iads, true)

  -- goDark() reads radarWentDark and goLive() reads radarWentLive; the logger's own
  -- samWentDark default is vestigial and read by nothing.
  luaunit.assertTrue(settings.radarWentDark)
  luaunit.assertTrue(settings.radarWentLive)
end

os.exit(luaunit.LuaUnit.run())
