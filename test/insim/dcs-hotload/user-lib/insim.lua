-- The mission-side layer of the in-sim test suite. Each mailbox command of the driver calls one
-- function of it: `phase` runs one phase file of a scenario, `cleanup` removes what the scenario
-- added, `status` answers the driver's probe. The scenario's context (`ctx`) lives in InsimState
-- between commands, which is why that global is guarded: a reload of this file must not wipe it.
InsimState = InsimState or { contexts = {} }

local I = {}

I.INVALID_MARK = "INSIM-INVALID: "

-- The sides of env.mission.coalition, and the group categories a country can hold, with the
-- Group.Category each is added under (a static is added by another call).
local SIDES = { "red", "blue", "neutrals" }
local CATEGORIES = { "plane", "helicopter", "vehicle", "ship", "static" }
local GROUP_CATEGORY = {
	plane = "AIRPLANE",
	helicopter = "HELICOPTER",
	vehicle = "GROUND",
	ship = "SHIP",
}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function fileExists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

-- The fixture group named `fixtureName` in the mission, with the country that holds it and the
-- category it was found under.
local function findFixture(fixtureName)
	for _, side in ipairs(SIDES) do
		local coalitionTable = env.mission.coalition[side]
		for _, country in ipairs(coalitionTable and coalitionTable.country or {}) do
			for _, category in ipairs(CATEGORIES) do
				for _, group in ipairs(country[category] and country[category].group or {}) do
					if group.name == fixtureName then
						return group, country.id, category
					end
				end
			end
		end
	end
end

local Context = {}
Context.__index = Context

function Context:add(role)
	local fixtureName = "FIXTURE-" .. self.name .. "-" .. role
	local fixture, countryId, category = findFixture(fixtureName)
	if not fixture then
		error("no fixture " .. fixtureName .. " in the mission")
	end
	local group = deepCopy(fixture)
	local scoped = self.name .. "/" .. role
	group.name = scoped
	group.lateActivation = false
	group.groupId = nil
	for k, unit in ipairs(group.units) do
		unit.name = scoped .. "-" .. k
		unit.unitId = nil
	end
	local object
	if category == "static" then
		-- A static is its group's only unit, and takes the group's name.
		group.units[1].name = scoped
		object = coalition.addStaticObject(countryId, group.units[1])
	else
		object = coalition.addGroup(countryId, Group.Category[GROUP_CATEGORY[category]], group)
	end
	table.insert(self.added, object)
	return object
end

function Context:onCleanup(fn)
	table.insert(self.cleanups, fn)
end

local function newContext(name, mission)
	local ctx = setmetatable({
		name = name,
		mission = mission,
		state = {},
		added = {},
		cleanups = {},
	}, Context)
	function ctx.invalid(reason)
		error(I.INVALID_MARK .. reason, 0)
	end
	return ctx
end

function I.status()
	return { mission = env.getValueDictByKey(env.mission.sortie), time = timer.getTime() }
end

function I.scenariosDir()
	return InsimState.scenariosDir or (Hotload.root .. "/../scenarios")
end

function I.phase(name, phase)
	local dir = I.scenariosDir() .. "/" .. name
	if phase == "setup" then
		local mission = assert(loadfile(dir .. "/scenario.lua"))()
		InsimState.contexts[name] = newContext(name, mission)
	end
	local ctx = InsimState.contexts[name]
	if not ctx then
		error("no context for " .. name .. ": setup did not run", 0)
	end
	local path = dir .. "/" .. phase .. ".lua"
	if phase == "teardown" and not fileExists(path) then
		return nil
	end
	return assert(loadfile(path))(ctx)
end

function I.cleanup(name)
	local ctx = InsimState.contexts[name]
	if not ctx then
		return { destroyed = 0, cleanups = 0 }
	end
	InsimState.contexts[name] = nil
	local destroyed = 0
	for _, object in ipairs(ctx.added) do
		if object:isExist() then
			object:destroy()
			destroyed = destroyed + 1
		end
	end
	local failures = {}
	for i = #ctx.cleanups, 1, -1 do
		local ok, message = Hotload.callOnMain(ctx.cleanups[i])
		if not ok then
			table.insert(failures, tostring(message))
		end
	end
	if #failures > 0 then
		error(table.concat(failures, "; "), 0)
	end
	return { destroyed = destroyed, cleanups = #ctx.cleanups }
end

return I
