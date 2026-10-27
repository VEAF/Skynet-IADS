--- insim.lua: the mission-side test layer of the in-sim suite (test/insim/). It runs in DCS under
--- dcs-hotload; here hotload, the mission table and the coalition are stubbed, and the scenarios
--- are the tiny ones in insim-fixtures/.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/../lua/dcs-stub.lua")

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
									name = "FIXTURE-SAM-X",
									groupId = 15,
									lateActivation = true,
									units = {
										{ name = "FIXTURE-SAM-X-1", unitId = 35, x = 100, y = 200 },
										{ name = "FIXTURE-SAM-X-2", unitId = 36, x = 160, y = 200 },
									},
									route = { points = { { x = 100, y = 200 } } },
								},
								{
									name = "FIXTURE-SAM",
									groupId = 16,
									units = { { name = "FIXTURE-SAM-1", unitId = 37 } },
								},
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
	trigger.misc = {
		getZone = function(name)
			if name == "ZONE-A" then
				return { point = { x = 1100, y = 0, z = 5200 }, radius = 300 }
			end
		end,
	}
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
	luaunit.assertEquals(ctx.mission, "insim01")
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

function TestInsim:testSetupCleansUpAnOlderContext()
	I.phase("cleans", "setup")
	local first = InsimState.contexts.cleans
	I.phase("cleans", "setup")
	luaunit.assertNotIs(InsimState.contexts.cleans, first)
	luaunit.assertEquals(first.state.order, { "B", "A" })
	luaunit.assertEquals(destroyedNames, { "cleans/SAM", "cleans/DEPOT" })
end

-- Runs fn as hotload runs a command: in a coroutine, with Hotload.callOnMain a yield the runner
-- answers. Lua 5.1 cannot yield across pcall, so code that wraps callOnMain in pcall raises here as
-- it does in DCS.
local function asHotloadRun(fn, ...)
	local saved = Hotload.callOnMain
	Hotload.callOnMain = function(f)
		return coroutine.yield({ kind = "main", fn = f })
	end
	local co = coroutine.create(fn)
	local results = { coroutine.resume(co, ...) }
	while coroutine.status(co) ~= "dead" do
		results = { coroutine.resume(co, pcall(results[2].fn)) }
	end
	Hotload.callOnMain = saved
	return unpack(results)
end

function TestInsim:testSetupCleansUpAnOlderContextInAHotloadRun()
	asHotloadRun(I.phase, "cleans", "setup")
	local first = InsimState.contexts.cleans
	local ok, err = asHotloadRun(I.phase, "cleans", "setup")
	luaunit.assertTrue(ok, tostring(err))
	luaunit.assertEquals(first.state.order, { "B", "A" })
end

function TestInsim:testSetupRefusesAnOlderContextItCannotClean()
	I.phase("cleanfail", "setup")
	luaunit.assertErrorMsgContains("an older run of cleanfail could not be cleaned up", I.phase, "cleanfail", "setup")
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
	local fixture = env.mission.coalition.red.country[1].vehicle.group[3]
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

function TestInsim:testMissingFixtureIsInvalid()
	local _, err = pcall(I.phase, "missing", "setup")
	luaunit.assertStrContains(err, "INSIM-INVALID: no fixture FIXTURE-missing-NOPE")
end

function TestInsim:testSpawnReturningNilIsInvalid()
	coalition.addGroup = function()
		return nil
	end
	local _, err = pcall(I.phase, "adds", "setup")
	luaunit.assertStrContains(err, "INSIM-INVALID: FIXTURE-adds-SAM did not spawn")
end

function TestInsim:testAddPrefersTheScenarioFixture()
	I.phase("adds", "setup")
	luaunit.assertEquals(addedGroups[1].units[1].type, "S-300PS 64H6E sr")
end

function TestInsim:testAddFallsBackToTheCatalogue()
	I.phase("catalogue", "setup")
	luaunit.assertEquals(addedGroups[1].name, "catalogue/SAM-X")
	luaunit.assertEquals(addedGroups[1].units[2].name, "catalogue/SAM-X-2")
	luaunit.assertEquals(addedGroups[1].units[1].x, 100)
end

function TestInsim:testAddIntoAZoneMovesUnitsAndRoute()
	I.phase("zoned", "setup")
	local g = addedGroups[1]
	luaunit.assertEquals({ g.units[1].x, g.units[1].y }, { 1100, 5200 })
	luaunit.assertEquals({ g.units[2].x, g.units[2].y }, { 1160, 5200 })
	luaunit.assertEquals({ g.route.points[1].x, g.route.points[1].y }, { 1100, 5200 })
	local fixture = env.mission.coalition.red.country[1].vehicle.group[1]
	luaunit.assertEquals({ fixture.units[1].x, fixture.route.points[1].x }, { 100, 100 })
end

function TestInsim:testAddNamesTheCopyWhenAsked()
	I.phase("renamed", "setup")
	local g = addedGroups[1]
	luaunit.assertEquals(g.name, "renamed/SAM-B")
	luaunit.assertEquals(g.units[1].name, "renamed/SAM-B-1")
	luaunit.assertEquals({ g.units[1].x, g.units[1].y }, { 1100, 5200 })
end

function TestInsim:testAddIntoAMissingZoneIsInvalid()
	local _, err = pcall(I.phase, "zonemissing", "setup")
	luaunit.assertStrContains(err, "INSIM-INVALID: no zone ZONE-NOPE in the mission")
end

function TestInsim:testMissingInBothPlacesNamesBoth()
	local _, err = pcall(I.phase, "missing", "setup")
	luaunit.assertStrContains(err, "INSIM-INVALID: no fixture FIXTURE-missing-NOPE or FIXTURE-NOPE in the mission")
end

function TestInsim:testTrackedObjectsAreDestroyedOnCleanup()
	I.phase("tracks", "setup")
	local state = InsimState.contexts.tracks.state
	luaunit.assertIs(state.returned, state.object)
	luaunit.assertEquals(I.cleanup("tracks").destroyed, 1)
	luaunit.assertFalse(state.object.alive)
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
