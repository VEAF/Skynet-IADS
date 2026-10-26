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
-- second waypoint's), and the flags immortal, invisible, holdFire, ignoreThreats.
function Wd.spawnAircraft(ctx, spec)
	assert(spec.payload, "spawnAircraft: a payload is required")
	local scoped = ctx.name .. "/" .. spec.name
	local group = {
		name = scoped,
		task = spec.task or "Nothing",
		taskSelected = true,
		hidden = false,
		uncontrolled = false,
		start_time = 0,
		route = {
			points = { waypoint(spec.from, spec, {}), waypoint(spec.to, spec, spec.waypointTasks or {}) },
		},
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

-- Removes the debris inside the zone, measured from the ground under its centre. Returns how many
-- objects went.
function Wd.clearWrecks(zoneName)
	local zone = zoneOrInvalid(zoneName)
	local point = { x = zone.point.x, y = land.getHeight({ x = zone.point.x, y = zone.point.z }), z = zone.point.z }
	return world.removeJunk({ id = world.VolumeType.SPHERE, params = { point = point, radius = zone.radius } })
end

return Wd
