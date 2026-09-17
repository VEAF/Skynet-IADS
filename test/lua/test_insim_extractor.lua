--- Offline tests for test/insim/tools/extract-fixtures.lua. Input is a synthetic `mission`
--- table shaped exactly like the one inside a .miz, so no DCS and no .miz are needed.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/../insim/tools/insim-test-tools.lua")
dofile(base .. "/../insim/tools/extract-fixtures.lua")

TestInsimExtractor = {}

--- Three units 20m apart on the x (north) axis -- the shape real .miz group tables have.
local function sampleGroup()
  return {
    name = "SAM-Kub-1",
    task = "Ground Nothing",
    x = 25781.5,
    y = -239472.0,
    units = {
      { type = "Kub 1S91 str", name = "SAM-Kub-1-1", x = 25781.5, y = -239472.0,
        heading = 2.827, skill = "Excellent", playerCanDrive = false },
      { type = "Kub 2P25 ln", name = "SAM-Kub-1-2", x = 25761.5, y = -239472.0,
        heading = 2.827, skill = "Excellent", playerCanDrive = false },
      { type = "Kub 2P25 ln", name = "SAM-Kub-1-3", x = 25741.5, y = -239452.0,
        heading = 1.5, skill = "Average", playerCanDrive = false },
    },
  }
end

function TestInsimExtractor:testFirstUnitIsTheOrigin()
  local template = InsimExtractor.templateFromGroup(sampleGroup())
  luaunit.assertEquals(template.units[1].dx, 0)
  luaunit.assertEquals(template.units[1].dy, 0)
end

function TestInsimExtractor:testOffsetsAreRelativeToTheFirstUnit()
  local template = InsimExtractor.templateFromGroup(sampleGroup())
  -- unit 2: x 25761.5 - 25781.5 = -20 north; y unchanged
  luaunit.assertEquals(template.units[2].dx, -20)
  luaunit.assertEquals(template.units[2].dy, 0)
  -- unit 3: x -40 north, y -239452.0 - -239472.0 = +20 east
  luaunit.assertEquals(template.units[3].dx, -40)
  luaunit.assertEquals(template.units[3].dy, 20)
end

function TestInsimExtractor:testTemplateCarriesNoAbsoluteCoordinates()
  local template = InsimExtractor.templateFromGroup(sampleGroup())
  luaunit.assertNil(template.x)
  luaunit.assertNil(template.y)
  for _, unit in ipairs(template.units) do
    luaunit.assertNil(unit.x)
    luaunit.assertNil(unit.y)
    luaunit.assertNil(unit.name)  -- names are scoped per scenario at add time
  end
end

function TestInsimExtractor:testTemplateKeepsTypeHeadingAndSkill()
  local template = InsimExtractor.templateFromGroup(sampleGroup())
  luaunit.assertEquals(template.units[1].type, "Kub 1S91 str")
  luaunit.assertEquals(template.units[1].heading, 2.827)
  luaunit.assertEquals(template.units[1].skill, "Excellent")
  luaunit.assertEquals(template.units[3].skill, "Average")
  luaunit.assertEquals(template.task, "Ground Nothing")
end

function TestInsimExtractor:testStaticTemplateKeepsTypeCategoryAndHeading()
  local template = InsimExtractor.templateFromStatic({
    name = "Static MBT-1",
    x = 24985.4,
    y = -240039.7,
    units = { { type = "M-60", category = "Armor", heading = 4.468, name = "Static MBT-1-1" } },
  })
  luaunit.assertEquals(template.type, "M-60")
  luaunit.assertEquals(template.category, "Armor")
  luaunit.assertEquals(template.heading, 4.468)
  luaunit.assertNil(template.x)
end

function TestInsimExtractor:testGroupsFromMissionTableFindsByPrefixAcrossCountries()
  local mission = {
    coalition = {
      red = {
        country = {
          { name = "CJTF Red",
            vehicle = { group = { sampleGroup(), { name = "Convoy-1", units = {} } } } },
        },
      },
      blue = {
        country = {
          { name = "USA", vehicle = { group = { { name = "SAM-Blue-1", units = {} } } } },
        },
      },
    },
  }
  local found = InsimExtractor.groupsFromMissionTable(mission, "SAM-Kub")
  luaunit.assertEquals(#found, 1)
  luaunit.assertEquals(found[1].name, "SAM-Kub-1")
end

function TestInsimExtractor:testFixtureFileTextLoadsBackAsATableOfTemplates()
  local text = InsimExtractor.fixtureFileText({
    kub = InsimExtractor.templateFromGroup(sampleGroup()),
  })
  local chunk, err = loadstring(text)
  luaunit.assertNotNil(chunk, tostring(err) .. "\n" .. text)
  local fixtures = chunk()
  luaunit.assertEquals(fixtures.kub.units[2].dx, -20)
end

function TestInsimExtractor:testFixtureFileTextIsStableAcrossRuns()
  local group = sampleGroup()
  local first = InsimExtractor.fixtureFileText({ kub = InsimExtractor.templateFromGroup(group) })
  local second = InsimExtractor.fixtureFileText({ kub = InsimExtractor.templateFromGroup(group) })
  luaunit.assertEquals(first, second)
end

function TestInsimExtractor:testIsStaticGroupRecognisesAUnitCarryingACategory()
  luaunit.assertTrue(InsimExtractor.isStaticGroup({
    name = "Static MBT-1",
    units = { { type = "M-60", category = "Armor" } },
  }))
end

function TestInsimExtractor:testIsStaticGroupRejectsAVehicleGroup()
  luaunit.assertFalse(InsimExtractor.isStaticGroup(sampleGroup()))
end

function TestInsimExtractor:testIsStaticGroupRejectsAGroupWithNoUnits()
  luaunit.assertFalse(InsimExtractor.isStaticGroup({ name = "Empty", units = {} }))
  luaunit.assertFalse(InsimExtractor.isStaticGroup({ name = "Nil units" }))
end

os.exit(luaunit.LuaUnit.run())
