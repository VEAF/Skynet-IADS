--- Offline tests for the pure-Lua half of test/insim/tools/insim-test-tools.lua, plus
--- radarState, whose iteration is stub-testable even though what DCS means by getRadar() is
--- not. The rest of the DCS-world half (addFromMission, removeJunkAround) needs a sim.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
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

function TestInsimTools:testSerializeRoundTripsComputedDoublesNeedingSeventeenDigits()
  -- These fail to round-trip under %.14g, so this test falsifies a truncating format.
  local value = { third = 1 / 3, pi = math.pi, ratio = 10 / 7 }
  luaunit.assertEquals(roundTrip(value), value)
end

function TestInsimTools:testSerializeWritesTheShortestFormThatStillRoundTrips()
  -- %.17g renders 41.3 as 41.299999999999997. Durations and log timings land in last-run.lua
  -- for a human to read, so the serializer must prefer the short form WHEN it is exact.
  local text = InsimTestTools.serialize({ duration = 41.3 })
  luaunit.assertStrContains(text, "41.3")
  luaunit.assertNotStrContains(text, "41.2999")
  luaunit.assertEquals(roundTrip({ duration = 41.3 }), { duration = 41.3 })
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

--- radarState asks DCS what a group's radars are doing, which is a different question from what
--- Skynet believes: goDark() calls enableEmission(false), which stops emission but leaves the
--- unit alive and its antenna turning, so the model tells you nothing.
local function samGroup(name, spec)
  dcsStub.reset()
  local group = dcsStub.makeGroup({
    name = name,
    units = {
      { name = name .. "-str", type = "Kub 1S91 str", radar = spec.searchRadarOn,
        radarTarget = spec.tracking },
      { name = name .. "-ln-1", type = "Kub 2P25 ln" },
      { name = name .. "-ln-2", type = "Kub 2P25 ln", exists = spec.secondLauncherAlive },
    },
  })
  return group
end

function TestInsimTools:testRadarStateReportsNothingEmittingWhenTheSiteIsDark()
  samGroup("SAM-DARK", { searchRadarOn = false })

  local state = InsimTestTools.radarState("SAM-DARK")

  luaunit.assertFalse(state.emitting)
  luaunit.assertEquals(state.emitters, 0)
end

function TestInsimTools:testRadarStateReportsEmittingWhenAnyUnitHasItsRadarOn()
  samGroup("SAM-LIVE", { searchRadarOn = true })

  local state = InsimTestTools.radarState("SAM-LIVE")

  luaunit.assertTrue(state.emitting)
  luaunit.assertEquals(state.emitters, 1)
end

function TestInsimTools:testRadarStateListsEveryLivingUnitItAsked()
  samGroup("SAM-COUNT", { searchRadarOn = true, secondLauncherAlive = false })

  local state = InsimTestTools.radarState("SAM-COUNT")

  -- The destroyed launcher is not reported: getRadar on a dead unit is meaningless.
  luaunit.assertEquals(#state.units, 2)
  luaunit.assertEquals(state.units[1].name, "SAM-COUNT-str")
  luaunit.assertTrue(state.units[1].emitting)
  luaunit.assertFalse(state.units[2].emitting)
end

function TestInsimTools:testRadarStateRaisesForAGroupThatIsNotThere()
  dcsStub.reset()
  -- Returning "not emitting" for a missing group would let a dark assertion pass for entirely
  -- the wrong reason.
  local ok, err = pcall(InsimTestTools.radarState, "SAM-GONE")
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "SAM-GONE")
end

function TestInsimTools:testDescribeRadarStateNamesTheEmittingUnit()
  samGroup("SAM-DESC", { searchRadarOn = true })

  local text = InsimTestTools.describeRadarState("SAM-DESC")

  luaunit.assertStrContains(text, "SAM-DESC")
  luaunit.assertStrContains(text, "emitting")
  luaunit.assertStrContains(text, "Kub 1S91 str")
end

function TestInsimTools:testDescribeRadarStateSaysDarkWhenNothingEmits()
  samGroup("SAM-QUIET", { searchRadarOn = false })

  luaunit.assertStrContains(InsimTestTools.describeRadarState("SAM-QUIET"), "dark")
end

--- A mission table holding fixtures, a playable slot, and a group that is neither.
local function missionWith(groups)
  env.mission = { coalition = { blue = { country = { { id = 2, name = "USA", plane = {
    group = groups } } } } } }
end

local function playableGroup(name)
  return { name = name, units = { { name = name .. "-1", skill = "Client" } } }
end

local function fixtureGroup(name)
  return { name = name, units = { { name = name .. "-1", skill = "Excellent" } } }
end

function TestInsimTools:testFixtureNamesAreOnlyThoseCarryingThePrefix()
  missionWith({
    fixtureGroup("SKY-Z01-SA6-01"),
    fixtureGroup("SKY-AIR-F18-01"),
    fixtureGroup("SCENERY-FARM-01"),
  })

  local names = InsimTestTools.missionFixtureNames()

  table.sort(names)
  luaunit.assertEquals(names, { "SKY-AIR-F18-01", "SKY-Z01-SA6-01" })
end

function TestInsimTools:testAPlayableGroupIsNeverAFixtureEvenWithThePrefix()
  -- The mistake a naming convention cannot catch: a slot that happens to carry the prefix.
  missionWith({ fixtureGroup("SKY-Z01-SA6-01"), playableGroup("SKY-SLOT-GM-01") })

  luaunit.assertEquals(InsimTestTools.missionFixtureNames(), { "SKY-Z01-SA6-01" })
end

function TestInsimTools:testAGroupWithAPlayerUnitIsProtectedToo()
  missionWith({ { name = "SKY-SLOT-01", units = {
    { name = "a", skill = "Excellent" }, { name = "b", skill = "Player" } } } })

  luaunit.assertEquals(#InsimTestTools.missionFixtureNames(), 0)
end

function TestInsimTools:testAddFromMissionRefusesAPlayableGroup()
  missionWith({ playableGroup("SKY-SLOT-GM-01") })

  local ok, err = pcall(InsimTestTools.addFromMission, "SKY-SLOT-GM-01")

  luaunit.assertFalse(ok, "adding over a slot would throw the player out of their aircraft")
  luaunit.assertStrContains(tostring(err), "playable")
end

function TestInsimTools:testAddAirFromMissionRefusesAPlayableGroup()
  missionWith({ playableGroup("SKY-SLOT-GM-01") })

  local ok, err = pcall(InsimTestTools.addAirFromMission, "SKY-SLOT-GM-01",
    { from = { x = 0, y = 0 }, to = { x = 1000, y = 0 }, altitude = 3000, speed = 150 })

  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "playable")
end

function TestInsimTools:testDestroyAllFixturesLeavesPlayableSlotsAlone()
  missionWith({ fixtureGroup("SKY-Z01-SA6-01"), playableGroup("SKY-SLOT-GM-01") })
  dcsStub.reset()
  dcsStub.makeGroup({ name = "SKY-Z01-SA6-01", units = { { name = "SKY-Z01-SA6-01-1" } } })
  dcsStub.makeGroup({ name = "SKY-SLOT-GM-01", units = { { name = "SKY-SLOT-GM-01-1" } } })

  local destroyed = InsimTestTools.destroyAllFixtures()

  luaunit.assertEquals(destroyed, { "SKY-Z01-SA6-01" })
  luaunit.assertNotNil(Group.getByName("SKY-SLOT-GM-01"), "the slot was despawned")
end

function TestInsimTools:testOffsetFromGoesNorthOnBearingZero()
  local p = InsimTestTools.offsetFrom({ x = 1000, y = 2000 }, 0, 500)
  luaunit.assertAlmostEquals(p.x, 1500, 1e-6)   -- north is x
  luaunit.assertAlmostEquals(p.y, 2000, 1e-6)
end

function TestInsimTools:testOffsetFromGoesEastOnBearingNinety()
  local p = InsimTestTools.offsetFrom({ x = 1000, y = 2000 }, 90, 500)
  luaunit.assertAlmostEquals(p.x, 1000, 1e-6)
  luaunit.assertAlmostEquals(p.y, 2500, 1e-6)   -- east is y
end

function TestInsimTools:testOffsetFromGoesSouthAndWest()
  local south = InsimTestTools.offsetFrom({ x = 0, y = 0 }, 180, 100)
  luaunit.assertAlmostEquals(south.x, -100, 1e-6)
  luaunit.assertAlmostEquals(south.y, 0, 1e-6)

  local west = InsimTestTools.offsetFrom({ x = 0, y = 0 }, 270, 100)
  luaunit.assertAlmostEquals(west.x, 0, 1e-6)
  luaunit.assertAlmostEquals(west.y, -100, 1e-6)
end

function TestInsimTools:testOffsetFromHandlesADiagonalBearing()
  local p = InsimTestTools.offsetFrom({ x = 0, y = 0 }, 45, 1000)
  local leg = 1000 * math.sqrt(2) / 2
  luaunit.assertAlmostEquals(p.x, leg, 1e-6)
  luaunit.assertAlmostEquals(p.y, leg, 1e-6)
end

function TestInsimTools:testOffsetFromDoesNotMutateItsOrigin()
  local origin = { x = 10, y = 20 }
  InsimTestTools.offsetFrom(origin, 90, 500)
  luaunit.assertEquals(origin, { x = 10, y = 20 })
end

function TestInsimTools:testBearingBetweenReadsTheCardinalDirections()
  local origin = { x = 0, y = 0 }
  -- Radians clockwise from north, normalised to [0, 2pi): north 0, east pi/2, south pi, west 3pi/2.
  luaunit.assertAlmostEquals(
    InsimTestTools.bearingBetween(origin, { x = 100, y = 0 }), 0, 1e-9)
  luaunit.assertAlmostEquals(
    InsimTestTools.bearingBetween(origin, { x = 0, y = 100 }), math.pi / 2, 1e-9)
  luaunit.assertAlmostEquals(
    InsimTestTools.bearingBetween(origin, { x = -100, y = 0 }), math.pi, 1e-9)
  luaunit.assertAlmostEquals(
    InsimTestTools.bearingBetween(origin, { x = 0, y = -100 }), 3 * math.pi / 2, 1e-9)
end

function TestInsimTools:testBearingBetweenHandlesADiagonalAndAnOffsetOrigin()
  local bearing = InsimTestTools.bearingBetween({ x = 500, y = 500 }, { x = 600, y = 600 })
  luaunit.assertAlmostEquals(bearing, math.pi / 4, 1e-9)
end

function TestInsimTools:testBearingBetweenIsTheInverseOfOffsetFrom()
  local from = { x = -12000, y = 8000 }
  for _, degrees in ipairs({ 0, 37, 90, 155, 180, 233, 270, 341 }) do
    local to = InsimTestTools.offsetFrom(from, degrees, 4000)
    luaunit.assertAlmostEquals(math.deg(InsimTestTools.bearingBetween(from, to)), degrees, 1e-6)
  end
end

function TestInsimTools:testBearingBetweenTreatsIdenticalPointsAsNorth()
  luaunit.assertAlmostEquals(
    InsimTestTools.bearingBetween({ x = 7, y = 9 }, { x = 7, y = 9 }), 0, 1e-9)
end

os.exit(luaunit.LuaUnit.run())
