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

--- The target's leg, as a bearing and distance from the EWR. Both ends are chosen so the
--- aircraft is outside detection range at spawn and flies into it, and so the leg outlasts the
--- test -- AI behaviour at a final waypoint is its own rabbit hole.
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
  self.iads:addEarlyWarningRadarsByPrefix(EWR)
  self.iads:addSAMSitesByPrefix(SAM)
  self.iads:activate()
end

function TestDetection:tearDown()
  if self.iads then
    self.iads:deactivate()
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
end

--- The time-dependent one. The SAM starts dark; a live EWR detecting the target is what brings
--- it up, and that takes simulated seconds.
function TestDetection:testSAMGoesLiveWhenTheEWRDetectsATarget()
  local sam = self.iads:getSAMSiteByGroupName(SAM)
  luaunit.assertNotNil(sam, "the SAM site did not join the IADS")
  luaunit.assertFalse(sam:isActive(), "the SAM should start dark")

  -- The editor group supplies only the airframe. Its leg is computed from the EWR, so the
  -- geometry lives here rather than in the Mission Editor where it would be invisible.
  local ewr = InsimTestTools.missionGroupData(EWR)
  InsimTestTools.addAirFromMission(TARGET, {
    from = InsimTestTools.offsetFrom(ewr, INBOUND_BEARING, START_RANGE),
    to = InsimTestTools.offsetFrom(ewr, INBOUND_BEARING - 180, END_RANGE),
    altitude = TARGET_ALTITUDE,
    speed = TARGET_SPEED,
  })

  -- Detection, then the IADS's own evaluation cycle, then the SAM coming up.
  waitFor(function() return sam:isActive() end, 300)
  luaunit.assertTrue(sam:isActive())
end

return { name = SCENARIO, suite = TestDetection }
