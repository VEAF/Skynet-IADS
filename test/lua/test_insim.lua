--- insim.lua: the mission-side test layer of the in-sim suite (test/insim/). It runs in DCS under
--- dcs-hotload; here hotload, the mission table and the coalition are stubbed, and the scenarios
--- are the tiny ones in insim-fixtures/.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")

local fixtures = base .. "/insim-fixtures"

Hotload = {
	root = fixtures .. "/dcs-hotload",
	load = function(name)
		return dofile(base .. "/../insim/dcs-hotload/user-lib/" .. name .. ".lua")
	end,
	callOnMain = function(fn)
		return pcall(fn)
	end,
	log = function() end,
}

local I = Hotload.load("insim")

local addedGroups, addedStatics, destroyedNames

-- What coalition.addGroup / addStaticObject hand back: an object that is registered in the stub
-- world and remembers its destruction.
local function recorded(name)
	local object = { alive = true }
	function object:isExist()
		return self.alive
	end
	function object:destroy()
		self.alive = false
		table.insert(destroyedNames, name)
	end
	dcsStub.world[name] = object
	return object
end

local function missionTable()
	return {
		sortie = "DictKey_sortie_5",
		coalition = {
			red = {
				country = {
					{
						id = 0,
						vehicle = {
							group = {
								{
									name = "FIXTURE-adds-SAM",
									groupId = 12,
									lateActivation = true,
									units = {
										{ name = "FIXTURE-adds-SAM-1", unitId = 31, type = "S-300PS 64H6E sr" },
										{ name = "FIXTURE-adds-SAM-2", unitId = 32, type = "S-300PS 40B6M tr" },
									},
								},
							},
						},
					},
					{
						id = 2,
						static = {
							group = {
								{
									name = "FIXTURE-cleans-DEPOT",
									groupId = 13,
									units = { { name = "FIXTURE-cleans-DEPOT", unitId = 33, type = "Fuel tank" } },
								},
							},
						},
					},
				},
			},
			blue = {
				country = {
					{
						id = 1,
						vehicle = {
							group = {
								{ name = "FIXTURE-cleans-SAM", groupId = 14, units = { { name = "u", unitId = 34 } } },
							},
						},
					},
				},
			},
		},
	}
end

TestInsim = {}

function TestInsim:setUp()
	dcsStub.reset()
	dcsStub.setClock(500)
	addedGroups, addedStatics, destroyedNames = {}, {}, {}
	InsimState.contexts = {}
	InsimState.scenariosDir = fixtures .. "/scenarios"
	env.mission = missionTable()
	env.getValueDictByKey = function(key)
		return key == "DictKey_sortie_5" and "insim01" or key
	end
	coalition.addGroup = function(countryId, category, groupTable)
		groupTable.countryId, groupTable.category = countryId, category
		table.insert(addedGroups, groupTable)
		return recorded(groupTable.name)
	end
	coalition.addStaticObject = function(countryId, staticTable)
		staticTable.countryId = countryId
		table.insert(addedStatics, staticTable)
		return recorded(staticTable.name)
	end
end

function TestInsim:testStatePassesFromSetupToRun()
	I.phase("carry", "setup")
	luaunit.assertEquals(I.phase("carry", "run"), 7)
end

function TestInsim:testContextCarriesNameAndScenarioTable()
	I.phase("carry", "setup")
	local ctx = InsimState.contexts.carry
	luaunit.assertEquals(ctx.name, "carry")
	luaunit.assertEquals(ctx.mission.mission, "insim01")
	luaunit.assertEquals(ctx.state.v, 7)
end

function TestInsim:testTeardownReceivesTheContext()
	I.phase("carry", "setup")
	luaunit.assertEquals(I.phase("carry", "teardown"), "carry")
end

function TestInsim:testMissingTeardownReturnsNil()
	pcall(I.phase, "invalid", "setup") -- raises: the context exists all the same
	luaunit.assertNil(I.phase("invalid", "teardown"))
end

function TestInsim:testRunWithoutSetupRaises()
	luaunit.assertErrorMsgContains("setup did not run", I.phase, "carry", "run")
end

function TestInsim:testTeardownWithoutSetupRaises()
	luaunit.assertErrorMsgContains("setup did not run", I.phase, "carry", "teardown")
end

function TestInsim:testSetupReplacesAnOlderContext()
	I.phase("carry", "setup")
	local first = InsimState.contexts.carry
	I.phase("carry", "setup")
	luaunit.assertNotIs(InsimState.contexts.carry, first)
end

function TestInsim:testInvalidRaisesTheMark()
	local _, err = pcall(I.phase, "invalid", "setup")
	luaunit.assertEquals(err, "INSIM-INVALID: no SAM")
end

function TestInsim:testAddCopiesTheFixtureUnderTheScenarioName()
	I.phase("adds", "setup")
	local g = addedGroups[1]
	luaunit.assertEquals(g.name, "adds/SAM")
	luaunit.assertEquals(g.units[1].name, "adds/SAM-1")
	luaunit.assertEquals(g.units[2].name, "adds/SAM-2")
	luaunit.assertEquals(g.lateActivation, false)
	luaunit.assertNil(g.groupId)
	luaunit.assertNil(g.units[1].unitId)
	luaunit.assertEquals(g.countryId, 0)
	luaunit.assertEquals(g.category, Group.Category.GROUND)
end

function TestInsim:testAddLeavesTheMissionTableUntouched()
	I.phase("adds", "setup")
	local fixture = env.mission.coalition.red.country[1].vehicle.group[1]
	luaunit.assertEquals(fixture.name, "FIXTURE-adds-SAM")
	luaunit.assertEquals(fixture.groupId, 12)
	luaunit.assertEquals(fixture.units[1].unitId, 31)
end

function TestInsim:testAddFindsAFixtureOnAnotherSide()
	I.phase("cleans", "setup")
	luaunit.assertEquals(addedGroups[1].name, "cleans/SAM")
	luaunit.assertEquals(addedGroups[1].countryId, 1)
end

function TestInsim:testAddStaticUsesTheUnitTable()
	I.phase("cleans", "setup")
	local s = addedStatics[1]
	luaunit.assertEquals(s.name, "cleans/DEPOT")
	luaunit.assertEquals(s.type, "Fuel tank")
	luaunit.assertNil(s.unitId)
	luaunit.assertEquals(s.countryId, 2)
end

function TestInsim:testMissingFixtureRaises()
	luaunit.assertErrorMsgContains("no fixture FIXTURE-missing-NOPE in the mission", I.phase, "missing", "setup")
end

function TestInsim:testCleanupDestroysThenCallsCleanupsInReverse()
	I.phase("cleans", "setup")
	local order = InsimState.contexts.cleans.state.order
	local r = I.cleanup("cleans")
	luaunit.assertEquals(r, { destroyed = 2, cleanups = 2 })
	luaunit.assertEquals(order, { "B", "A" })
	luaunit.assertEquals(destroyedNames, { "cleans/SAM", "cleans/DEPOT" })
	luaunit.assertNil(InsimState.contexts.cleans)
end

function TestInsim:testCleanupSkipsWhatIsAlreadyGone()
	I.phase("cleans", "setup")
	dcsStub.world["cleans/SAM"].alive = false
	luaunit.assertEquals(I.cleanup("cleans").destroyed, 1)
end

function TestInsim:testCleanupRunsAllThenRaisesTheFailures()
	I.phase("cleanfail", "setup")
	local order = InsimState.contexts.cleanfail.state.order
	-- registered A (raises) then B: B runs first, then A raises
	local ok, err = pcall(I.cleanup, "cleanfail")
	luaunit.assertFalse(ok)
	luaunit.assertStrContains(err, "a broke")
	luaunit.assertEquals(order, { "B" })
	luaunit.assertNil(InsimState.contexts.cleanfail)
end

function TestInsim:testCleanupWithoutContextIsEmpty()
	luaunit.assertEquals(I.cleanup("nothing"), { destroyed = 0, cleanups = 0 })
end

function TestInsim:testStatusNamesTheMission()
	luaunit.assertEquals(I.status().mission, "insim01")
	luaunit.assertEquals(I.status().time, 500)
end

function TestInsim:testScenariosDirDefaultsBesideHotload()
	InsimState.scenariosDir = nil
	luaunit.assertEquals(I.scenariosDir(), Hotload.root .. "/../scenarios")
end

os.exit(luaunit.LuaUnit.run())
