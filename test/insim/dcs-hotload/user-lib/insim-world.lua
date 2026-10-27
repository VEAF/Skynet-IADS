-- The world helpers of the in-sim test suite: points measured from a zone, aircraft spawned on a
-- route, and wrecks cleared. Ground fixtures come from the mission (`ctx:add`); aircraft are spawned
-- here, because their geometry is computed from where the scenario's sites stand.
local Wd = {}

local INVALID_MARK = Hotload.load("insim").INVALID_MARK

local function zoneOrInvalid(zoneName)
	local zone = trigger.misc.getZone(zoneName)
	if not zone then
		error(INVALID_MARK .. "no zone " .. zoneName .. " in the mission", 0)
	end
	return zone
end

-- The point `km` from the zone's centre on `bearingDegrees` (0 north, 90 east), in mission
-- coordinates: `x` north, `y` east.
function Wd.pointFrom(zoneName, bearingDegrees, km)
	local zone = zoneOrInvalid(zoneName)
	local bearing = math.rad(bearingDegrees)
	return {
		x = zone.point.x + km * 1000 * math.cos(bearing),
		y = zone.point.z + km * 1000 * math.sin(bearing),
	}
end

local function waypoint(point, spec, tasks)
	return {
		x = point.x,
		y = point.y,
		alt = spec.alt,
		alt_type = spec.altType or "BARO",
		type = "Turning Point",
		action = "Turning Point",
		speed = spec.speed,
		speed_locked = true,
		ETA = 0,
		ETA_locked = false,
		formation_template = "",
		task = { id = "ComboTask", params = { tasks = tasks } },
	}
end

-- What each flag does to the aircraft's controller. Each keeps the aircraft on the run the
-- scenario measures: one that dies, evades or attacks leaves it.
local FLAGS = {
	{
		name = "immortal",
		apply = function(controller)
			controller:setCommand({ id = "SetImmortal", params = { value = true } })
		end,
	},
	{
		name = "invisible",
		apply = function(controller)
			controller:setCommand({ id = "SetInvisible", params = { value = true } })
		end,
	},
	{
		name = "holdFire",
		apply = function(controller)
			controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD)
		end,
	},
	{
		name = "ignoreThreats",
		apply = function(controller)
			controller:setOption(AI.Option.Air.id.REACTION_ON_THREAT, AI.Option.Air.val.REACTION_ON_THREAT.NO_REACTION)
		end,
	},
}

-- Spawns one aircraft flying from `spec.from` to `spec.to`, named `<scenario>/<spec.name>`, and
-- hands it to `ctx:track` for cleanup. `spec`: name, type, country, from, to ({x, y}), alt (m),
-- altType ("BARO" by default), speed (m/s), payload, task (default "Nothing"), waypointTasks (the
-- second waypoint's), via (an optional second waypoint), and the flags immortal, invisible,
-- holdFire, ignoreThreats.
function Wd.spawnAircraft(ctx, spec)
	assert(spec.payload, "spawnAircraft: a payload is required")
	local scoped = ctx.name .. "/" .. spec.name
	-- A task on an air-started group's first waypoint is ignored, and one on a later waypoint starts
	-- when the aircraft reaches it: `via`, a point just after the start, carries it from the outset.
	local route = { waypoint(spec.from, spec, {}) }
	if spec.via then
		route[2] = waypoint(spec.via, spec, spec.waypointTasks or {})
		route[3] = waypoint(spec.to, spec, {})
	else
		route[2] = waypoint(spec.to, spec, spec.waypointTasks or {})
	end
	local group = {
		name = scoped,
		task = spec.task or "Nothing",
		taskSelected = true,
		hidden = false,
		uncontrolled = false,
		start_time = 0,
		route = { points = route },
		units = {
			{
				name = scoped .. "-1",
				type = spec.type,
				skill = "Excellent",
				x = spec.from.x,
				y = spec.from.y,
				alt = spec.alt,
				alt_type = spec.altType or "BARO",
				speed = spec.speed,
				heading = math.atan2(spec.to.y - spec.from.y, spec.to.x - spec.from.x),
				payload = spec.payload,
				callsign = { [1] = 1, [2] = 1, [3] = 1, name = "Enfield11" },
			},
		},
	}
	local object = coalition.addGroup(spec.country, Group.Category.AIRPLANE, group)
	if object == nil then
		ctx.invalid(scoped .. " did not spawn")
	end
	ctx:track(object)
	local controller = object:getController()
	for _, flag in ipairs(FLAGS) do
		if spec[flag.name] then
			local ok, message = pcall(flag.apply, controller)
			if not ok then
				ctx.invalid(scoped .. ": could not set " .. flag.name .. ": " .. tostring(message))
			end
		end
	end
	return object
end

-- The waypoint task attacking `groupName` with `weaponType`, a number from the Mission Editor's
-- weaponTable (MissionEditor/modules/me_action_db.lua): 32768 anti-radiation, 14 guided bombs,
-- 240 iron bombs, 1835008 standard air-to-surface missiles. Goes on a `via` point.
function Wd.attackTask(groupName, weaponType)
	local group = Group.getByName(groupName)
	if not group then
		error(INVALID_MARK .. "no group " .. groupName .. " to attack", 0)
	end
	return {
		id = "AttackGroup",
		number = 1,
		enabled = true,
		auto = false,
		params = {
			groupId = group:getID(),
			weaponType = weaponType,
			expend = "All",
			attackQtyLimit = false,
			attackQty = 1,
			groupAttack = false,
			altitudeEnabled = false,
			directionEnabled = false,
			direction = 0,
		},
	}
end

-- How many of `shots` (from recordShots) the unit named `initiator` fired.
function Wd.fired(shots, initiator)
	local count = 0
	for _, shot in ipairs(shots) do
		if shot.initiator == initiator then
			count = count + 1
		end
	end
	return count
end

-- Every shot fired from now until cleanup, as `{ initiator = <unit name>, weapon = <type name> }`,
-- in the table returned. What tells "the site did not react" from "nothing was fired at it".
function Wd.recordShots(ctx)
	local shots = {}
	local handler = {}
	function handler:onEvent(event)
		if event.id == world.event.S_EVENT_SHOT and event.initiator and event.weapon then
			shots[#shots + 1] = { initiator = event.initiator:getName(), weapon = event.weapon:getTypeName() }
		end
	end
	ctx:onCleanup(function()
		world.removeEventHandler(handler)
	end)
	local ok, message = Hotload.callOnMain(function()
		world.addEventHandler(handler)
	end)
	if not ok then
		error(message, 0)
	end
	return shots
end

-- Removes the debris inside the zone, measured from the ground under its centre. Returns how many
-- objects went.
function Wd.clearWrecks(zoneName)
	local zone = zoneOrInvalid(zoneName)
	local point = { x = zone.point.x, y = land.getHeight({ x = zone.point.x, y = zone.point.z }), z = zone.point.z }
	return world.removeJunk({ id = world.VolumeType.SPHERE, params = { point = point, radius = zone.radius } })
end

return Wd
