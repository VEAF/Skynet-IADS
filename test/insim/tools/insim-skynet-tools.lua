do

--[[
InsimSkynet -- helpers that know about Skynet, kept out of InsimTestTools so that file stays a
plain DCS toolbox usable by any scenario, Skynet-aware or not.

Everything here reads Skynet's own accessors rather than reimplementing its rules. The point is
to make a scenario able to assert WHY something happened -- at what range a site was allowed to
come up -- instead of only that it eventually did.
]]

InsimSkynet = {}

--- The three element kinds isTargetInRange consults. Within a kind, any one element in range
--- satisfies it; across kinds, all three must be satisfied. So the site's gate is the smallest
--- of the three kinds' best ranges.
local KINDS = {
  { name = "search", getter = "getSearchRadars" },
  { name = "tracking", getter = "getTrackingRadars" },
  { name = "launcher", getter = "getLaunchers" },
}

--- Skynet compares getMaxRangeFindingTarget() scaled by firingRangePercent, which
--- setGoLiveRangeInPercent lowers. Launchers inherit both from SkynetIADSSAMSearchRadar and
--- fill maximumRange from the missile's own rangeMaxAltMax, so one formula covers all three.
local function effectiveRange(element)
  local maxRange = element:getMaxRangeFindingTarget()
  if type(maxRange) ~= "number" then
    return nil
  end
  return maxRange / 100 * (element.firingRangePercent or 100)
end

--- The best range and closest distance within one kind, ignoring destroyed elements. Returns
--- nil range for an empty kind, which Skynet reads as satisfied rather than as a zero gate.
local function surveyKind(samSite, getter, target)
  local best, closest = nil, nil

  for _, element in ipairs(samSite[getter](samSite)) do
    if element:isExist() then
      local range = effectiveRange(element)
      if range and (not best or range > best) then
        best = range
      end
      local distance = element:getDistance(target)
      if distance and (not closest or distance < closest) then
        closest = distance
      end
    end
  end

  return best, closest
end

--- What range this SAM site is allowed to come live at, and where the target is now.
---
--- Returns { gate, gateKind, distance, inRange, kinds = { { kind, range, distance } } }. `gate`
--- is the distance at which Skynet will first consider the target engageable, so a site coming
--- up further out than that is Skynet ignoring its own rule.
function InsimSkynet.engagementReport(samSite, target)
  local killZone = SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_KILL_ZONE
  local searchOnly = samSite:getEngagementZone() ~= killZone

  local report = { kinds = {}, gate = nil, gateKind = nil, distance = nil }

  for _, kind in ipairs(KINDS) do
    -- Outside kill-zone mode Skynet treats tracking and launchers as always satisfied, so only
    -- the search radar gates and including the others would predict the wrong range.
    if not (searchOnly and kind.name ~= "search") then
      local range, distance = surveyKind(samSite, kind.getter, target)

      report.kinds[#report.kinds + 1] = { kind = kind.name, range = range, distance = distance }

      if range and (not report.gate or range < report.gate) then
        report.gate = range
        report.gateKind = kind.name
      end
      if distance and (not report.distance or distance < report.distance) then
        report.distance = distance
      end
    end
  end

  report.inRange = (report.gate ~= nil and report.distance ~= nil
    and report.distance <= report.gate)

  return report
end

--- One line for the run timeline: what gates this site, at what range, and where the target is
--- relative to it. Read before the target flies it is a prediction; read at the moment the site
--- goes live it is the measurement.
function InsimSkynet.describeEngagement(samSite, target)
  local report = InsimSkynet.engagementReport(samSite, target)

  if not report.gate or not report.distance then
    return string.format("%s: no gate could be computed (no surviving elements?)",
      samSite:getDCSName())
  end

  return string.format("%s: gate %.0f m (%s), target at %.0f m -- %s by %.0f m",
    samSite:getDCSName(), report.gate, report.gateKind, report.distance,
    report.inRange and "inside" or "outside",
    math.abs(report.gate - report.distance))
end

--- Skynet writes its own narration through its logger's printOutputToLog, as
--- env.info("SKYNET: ..."). That reaches dcs.log but not the run timeline, so it is absent from
--- last-run.lua and the archive. Pointing this instance's logger at log() puts "GOING LIVE" and
--- friends in the timeline, stamped and interleaved with the scenario's own lines.
---
--- The replacement carries the same text, so grepping dcs.log for "SKYNET:" still finds it. The
--- logger belongs to one SkynetIADS instance, so nothing global is touched and the patch dies
--- with the IADS in tearDown.
local function routeOutputToTimeline(iads, enabled)
  local logger = iads.logger
  if type(logger) ~= "table" then
    return
  end

  if enabled then
    if not logger.insimNativeOutput then
      logger.insimNativeOutput = logger.printOutputToLog
      logger.printOutputToLog = function(_, output)
        log("SKYNET: %s", tostring(output))
      end
    end
  elseif logger.insimNativeOutput then
    logger.printOutputToLog = logger.insimNativeOutput
    logger.insimNativeOutput = nil
  end
end

--- Turns on the Skynet debug output a scenario wants to see, and routes it into the timeline.
---
--- Two keys deliberately absent: noWorkingCommmandCenter and ewRadarNoConnection appear in
--- README_source.md but are read nowhere in the source, so setting them does nothing.
function InsimSkynet.networkDisplayState(iads, bDisplay)
  local iadsDebug = iads:getDebugSettings()

  iadsDebug.IADSStatus = bDisplay
  iadsDebug.radarWentDark = bDisplay
  iadsDebug.contacts = bDisplay
  iadsDebug.radarWentLive = bDisplay
  iadsDebug.samNoConnection = false
  iadsDebug.jammerProbability = false
  iadsDebug.addedEWRadar = false
  iadsDebug.hasNoPower = false
  iadsDebug.harmDefence = bDisplay
  iadsDebug.samSiteStatusEnvOutput = false
  iadsDebug.earlyWarningRadarStatusEnvOutput = false

  routeOutputToTimeline(iads, bDisplay)
end

end
