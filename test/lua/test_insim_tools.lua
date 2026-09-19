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

function TestInsimTools:testSerializeRoundTripsComputedDoublesNeedingSeventeenDigits()
  -- These fail to round-trip under %.14g, so this test falsifies a truncating format.
  local value = { third = 1 / 3, pi = math.pi, ratio = 10 / 7 }
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
