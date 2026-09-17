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

os.exit(luaunit.LuaUnit.run())
