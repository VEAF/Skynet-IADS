--- insim-world.lua: the world helpers of the in-sim suite (test/insim/) — points from a zone,
--- aircraft spawned on a route, wrecks cleared. It runs in DCS under dcs-hotload; here hotload,
--- the zones, the spawn and the controller are stubbed.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/../lua/dcs-stub.lua")

Hotload = {
	load = function(name)
		return dofile(base .. "/../insim/dcs-hotload/user-lib/" .. name .. ".lua")
	end,
	callOnMain = function(fn)
		return pcall(fn)
	end,
}

local Wd = Hotload.load("insim-world")

local spawned, controllerCalls, junkVolume, failingCall

local function fakeContext(name)
	local ctx = { name = name, tracked = {} }
	function ctx:track(object)
		table.insert(self.tracked, object)
		return object
	end
	function ctx.invalid(reason)
		error("INSIM-INVALID: " .. reason, 0)
	end
	return ctx
end

local function spec(extra)
	local s = {
		name = "TARGET",
		type = "F-16C_50",
		country = 2,
		from = { x = 0, y = 0 },
		to = { x = 40000, y = 0 },
		alt = 3000,
		speed = 250,
		payload = { pylons = {}, fuel = 3000 },
	}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

TestInsimWorld = {}

function TestInsimWorld:setUp()
	dcsStub.reset()
	spawned, controllerCalls, junkVolume, failingCall = nil, {}, nil, nil
	trigger.misc = {
		getZone = function(name)
			if name == "ZONE-A" then
				return { point = { x = 1000, y = 0, z = 2000 }, radius = 300 }
			end
		end,
	}
	-- the shared stub has no reaction-on-threat option; its values matter only as they are passed on
	AI.Option.Air.id.REACTION_ON_THREAT = 1
	AI.Option.Air.val.REACTION_ON_THREAT = { NO_REACTION = 0 }
	land.getHeight = function()
		return 55
	end
	world.VolumeType = { SPHERE = 2 }
	world.removeJunk = function(volume)
		junkVolume = volume
		return 3
	end
	local controller = {}
	function controller:setOption(id, value)
		if failingCall == "option" then
			error("refused")
		end
		table.insert(controllerCalls, { "option", id, value })
	end
	function controller:setCommand(command)
		if failingCall == command.id then
			error("refused")
		end
		table.insert(controllerCalls, { "command", command.id, command.params.value })
	end
	coalition.addGroup = function(countryId, category, groupTable)
		spawned = { countryId = countryId, category = category, group = groupTable }
		return {
			getController = function()
				return controller
			end,
		}
	end
end

function TestInsimWorld:testPointFromNorth()
	luaunit.assertEquals(Wd.pointFrom("ZONE-A", 0, 10), { x = 11000, y = 2000 })
end

function TestInsimWorld:testPointFromEast()
	local p = Wd.pointFrom("ZONE-A", 90, 10)
	luaunit.assertAlmostEquals(p.x, 1000, 1e-6)
	luaunit.assertAlmostEquals(p.y, 12000, 1e-6)
end

function TestInsimWorld:testPointFromAMissingZoneIsInvalid()
	local _, err = pcall(Wd.pointFrom, "ZONE-NOPE", 0, 1)
	luaunit.assertStrContains(err, "INSIM-INVALID: no zone ZONE-NOPE in the mission")
end

function TestInsimWorld:testSpawnBuildsAScopedGroupOnTwoWaypoints()
	local ctx = fakeContext("s")
	local group = Wd.spawnAircraft(ctx, spec({ waypointTasks = { { id = "AttackGroup" } } }))
	local g = spawned.group
	luaunit.assertEquals(spawned.category, Group.Category.AIRPLANE)
	luaunit.assertEquals(spawned.countryId, 2)
	luaunit.assertEquals(g.name, "s/TARGET")
	luaunit.assertEquals(g.task, "Nothing")
	luaunit.assertEquals(g.units[1].name, "s/TARGET-1")
	luaunit.assertEquals(g.units[1].type, "F-16C_50")
	luaunit.assertEquals({ g.units[1].x, g.units[1].y, g.units[1].alt }, { 0, 0, 3000 })
	luaunit.assertEquals(g.units[1].payload, { pylons = {}, fuel = 3000 })
	luaunit.assertEquals(#g.route.points, 2)
	luaunit.assertEquals({ g.route.points[2].x, g.route.points[2].y }, { 40000, 0 })
	luaunit.assertEquals(g.route.points[2].task.params.tasks, { { id = "AttackGroup" } })
	luaunit.assertEquals(g.route.points[1].task.params.tasks, {})
	luaunit.assertIs(ctx.tracked[1], group)
end

function TestInsimWorld:testAViaPointCarriesTheTasksJustAfterTheStart()
	Wd.spawnAircraft(fakeContext("s"), spec({ via = { x = 2000, y = 0 }, waypointTasks = { { id = "AttackGroup" } } }))
	local points = spawned.group.route.points
	luaunit.assertEquals(#points, 3)
	luaunit.assertEquals({ points[2].x, points[2].y }, { 2000, 0 })
	luaunit.assertEquals(points[2].task.params.tasks, { { id = "AttackGroup" } })
	luaunit.assertEquals({ points[3].x, points[3].y }, { 40000, 0 })
	luaunit.assertEquals(points[3].task.params.tasks, {})
end

function TestInsimWorld:testSpawnHeadsForItsSecondWaypoint()
	Wd.spawnAircraft(fakeContext("s"), spec({ to = { x = 0, y = 40000 } }))
	luaunit.assertAlmostEquals(spawned.group.units[1].heading, math.pi / 2, 1e-6)
end

function TestInsimWorld:testSpawnAppliesEachFlag()
	Wd.spawnAircraft(
		fakeContext("s"),
		spec({ immortal = true, invisible = true, holdFire = true, ignoreThreats = true })
	)
	luaunit.assertEquals(controllerCalls, {
		{ "command", "SetImmortal", true },
		{ "command", "SetInvisible", true },
		{ "option", AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD },
		{ "option", AI.Option.Air.id.REACTION_ON_THREAT, AI.Option.Air.val.REACTION_ON_THREAT.NO_REACTION },
	})
end

function TestInsimWorld:testAFlagThatFailsIsInvalid()
	failingCall = "SetInvisible"
	local _, err = pcall(Wd.spawnAircraft, fakeContext("s"), spec({ invisible = true }))
	luaunit.assertStrContains(err, "INSIM-INVALID: s/TARGET: could not set invisible")
end

function TestInsimWorld:testASpawnReturningNilIsInvalid()
	coalition.addGroup = function()
		return nil
	end
	local _, err = pcall(Wd.spawnAircraft, fakeContext("s"), spec())
	luaunit.assertStrContains(err, "INSIM-INVALID: s/TARGET did not spawn")
end

function TestInsimWorld:testSpawnWithoutAPayloadIsRefused()
	local s = spec()
	s.payload = nil
	luaunit.assertErrorMsgContains("payload", Wd.spawnAircraft, fakeContext("s"), s)
end

local function namedObject(name)
	return {
		getName = function()
			return name
		end,
		getTypeName = function()
			return name
		end,
	}
end

function TestInsimWorld:testRecordShotsKeepsWhoFiredWhatUntilCleanup()
	local handlers = {}
	world.addEventHandler = function(h)
		handlers[h] = true
	end
	world.removeEventHandler = function(h)
		handlers[h] = nil
	end
	local cleanups = {}
	local ctx = fakeContext("s")
	function ctx:onCleanup(fn)
		table.insert(cleanups, fn)
	end
	local shots = Wd.recordShots(ctx)
	local handler = next(handlers)
	handler:onEvent({
		id = world.event.S_EVENT_SHOT,
		initiator = namedObject("s/ATTACKER-1"),
		weapon = namedObject("AGM_88"),
	})
	handler:onEvent({ id = world.event.S_EVENT_DEAD, initiator = namedObject("x") })
	luaunit.assertEquals(shots, { { initiator = "s/ATTACKER-1", weapon = "AGM_88" } })
	cleanups[1]()
	luaunit.assertNil(next(handlers))
end

function TestInsimWorld:testAttackTaskTargetsTheGroupWithTheWeapon()
	Group.getByName = function(name)
		return name == "s/SAM-SA6" and {
			getID = function()
				return 42
			end,
		} or nil
	end
	local task = Wd.attackTask("s/SAM-SA6", 32768)
	luaunit.assertEquals(task.id, "AttackGroup")
	luaunit.assertEquals(task.params.groupId, 42)
	luaunit.assertEquals(task.params.weaponType, 32768)
	luaunit.assertEquals(task.params.expend, "All")
end

function TestInsimWorld:testAttackTaskOnAMissingGroupIsInvalid()
	Group.getByName = function()
		return nil
	end
	local _, err = pcall(Wd.attackTask, "s/NOPE", 14)
	luaunit.assertStrContains(err, "INSIM-INVALID: no group s/NOPE to attack")
end

function TestInsimWorld:testFiredCountsTheShotsOfOneAircraft()
	local shots = {
		{ initiator = "s/ATTACKER-1", weapon = "AGM_88" },
		{ initiator = "s/SAM-SA6-2", weapon = "SA3M9M" },
		{ initiator = "s/ATTACKER-1", weapon = "AGM_88" },
	}
	luaunit.assertEquals(Wd.fired(shots, "s/ATTACKER-1"), 2)
	luaunit.assertEquals(Wd.fired(shots, "s/OTHER-1"), 0)
end

function TestInsimWorld:testClearWrecksSweepsTheZoneOnTheGround()
	luaunit.assertEquals(Wd.clearWrecks("ZONE-A"), 3)
	luaunit.assertEquals(junkVolume, {
		id = world.VolumeType.SPHERE,
		params = { point = { x = 1000, y = 55, z = 2000 }, radius = 300 },
	})
end

os.exit(luaunit.LuaUnit.run())
