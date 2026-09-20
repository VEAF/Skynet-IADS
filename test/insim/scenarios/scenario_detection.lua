--- Proves the tier end to end: real DCS radar detection driving real Skynet state.
---
--- Deliberately time-dependent. Detection is not instant and not deterministic, so every wait
--- is generous; a scenario needing tight timing is the wrong scenario for this tier.
---
--- Fixtures are the late-activated groups of the same names in skynet-insim.miz. Nothing here
--- knows where they are: position lives in the Mission Editor and nowhere else.

local SCENARIO = "Detection"
local ZONE = "SKY-Z01"
local EWR = "SKY-Z01-EWR-01"
local SAM = "SKY-Z01-SA6-01"
local TARGET = "SKY-AIR-F18-01"

--- The target's leg, as a bearing and distance from the EWR. The EWR sees the target almost
--- immediately -- a 1L13 reaches well past the 60 km start -- so the wait is really for the
--- target to close into the SAM's kill zone, which is what brings the site live. Both ends are
--- also chosen so the leg outlasts the test: AI behaviour at a final waypoint is its own rabbit
--- hole.
local INBOUND_BEARING = 270      -- degrees, clockwise from north: due west of the EWR
local START_RANGE = 60000        -- metres out
local END_RANGE = 20000          -- metres past, on the far side
local TARGET_ALTITUDE = 6000     -- metres, BARO
local TARGET_SPEED = 200         -- metres per second (about 390 kt)

local TestDetection = {}

function TestDetection:setUp()
  -- Clear the whole arena first. Re-adding replaces a LIVE group but does NOT clear a wreck, so
  -- anything a previous run destroyed is still lying there.
  InsimTestTools.removeJunkInZone(ZONE)

  InsimTestTools.addFromMission(EWR)
  InsimTestTools.addFromMission(SAM)

  self.iads = SkynetIADS:create("insim_" .. SCENARIO)
  InsimTestTools.skynetNetworkDisplayState(self.iads, true)

  self.iads:addEarlyWarningRadarsByPrefix(EWR)
  self.iads:addSAMSitesByPrefix(SAM)
  self.iads:activate()

  log("arena %s cleared, %s and %s added, IADS active", ZONE, EWR, SAM)
end

function TestDetection:tearDown()
  if self.iads then
    self.iads:deactivate()
    -- SkynetIADS:create registers a world event handler that deactivate() does not remove, so
    -- a scenario that builds a fresh IADS per test has to take it out itself or they pile up
    -- across re-runs.
    world.removeEventHandler(self.iads)
    self.iads = nil
  end
  for _, name in ipairs({ EWR, SAM, TARGET }) do
    InsimTestTools.destroyIfLive(name)
  end
end

--- The fixtures exist and Skynet found them. Synchronous, and the cheapest failure to diagnose
--- if everything is broken.
function TestDetection:testFixturesAreAddedAndJoinTheIADS()
  luaunit.assertNotNil(Group.getByName(EWR), "the EWR group was not added")
  luaunit.assertNotNil(Group.getByName(SAM), "the SAM group was not added")
  luaunit.assertEquals(#self.iads:getEarlyWarningRadars(), 1)
  luaunit.assertEquals(#self.iads:getSAMSites(), 1)

  log("DCS: %s", InsimTestTools.describeRadarState(EWR))
  log("DCS: %s", InsimTestTools.describeRadarState(SAM))

  -- The positive control for every DCS-side radar check in this file. Skynet brings an EWR live
  -- when it is added and leaves it there, so if the sim reports even this one as not emitting,
  -- getRadar() does not mean what the SAM assertions below assume and they prove nothing.
  luaunit.assertTrue(InsimTestTools.radarState(EWR).emitting,
    "DCS reports the EWR is not emitting, though Skynet brings it live on add")
end

--- The time-dependent one. The SAM starts dark; a live EWR detecting the target is what brings
--- it up, and that takes simulated seconds.
function TestDetection:testSAMGoesLiveWhenTheEWRDetectsATarget()
  local sam = self.iads:getSAMSiteByGroupName(SAM)
  luaunit.assertNotNil(sam, "the SAM site did not join the IADS")
  luaunit.assertFalse(sam:isActive(), "the SAM should start dark")

  -- isActive() is Skynet's own aiState flag. This is the sim's answer, and the two are not the
  -- same claim: goDark() calls enableEmission(false), which stops emission but leaves the unit
  -- alive with its antenna still turning. A rotating radar proves nothing either way.
  log("DCS: %s", InsimTestTools.describeRadarState(SAM))
  luaunit.assertFalse(InsimTestTools.radarState(SAM).emitting,
    "DCS reports the SAM is emitting, though Skynet believes it is dark")

  -- The editor group supplies only the airframe. Its leg is computed from the EWR, so the
  -- geometry lives here rather than in the Mission Editor where it would be invisible.
  local ewr = InsimTestTools.missionGroupData(EWR)
  InsimTestTools.addAirFromMission(TARGET, {
    from = InsimTestTools.offsetFrom(ewr, INBOUND_BEARING, START_RANGE),
    to = InsimTestTools.offsetFrom(ewr, INBOUND_BEARING - 180, END_RANGE),
    altitude = TARGET_ALTITUDE,
    speed = TARGET_SPEED,
  })

  log("%s airborne %.0f km out on bearing %d, %d m, %d m/s -- SAM is dark",
    TARGET, START_RANGE / 1000, INBOUND_BEARING, TARGET_ALTITUDE, TARGET_SPEED)

  -- Detection, then the IADS's own evaluation cycle, then the SAM coming up.
  waitFor(function() return sam:isActive() end, 450)
  luaunit.assertTrue(sam:isActive())

  log("%s went live -- DCS: %s", SAM, InsimTestTools.describeRadarState(SAM))

  -- And the sim agrees. goLive() calls enableEmission(true) before it sets aiState, so this
  -- should already hold; the wait only tolerates the sim applying it a tick late.
  waitFor(function() return InsimTestTools.radarState(SAM).emitting end, 30)
end

return { name = SCENARIO, suite = TestDetection }
