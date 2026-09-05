do

--[[
SkynetIADSUtils -- the handful of helpers Skynet used to borrow from MiST.

Skynet called 13 MiST functions across 31 call sites. None of them needed MiST's databases,
its event system or its spawning: they were arithmetic, a repeating scheduler, and two ways
of listing what the mission contains. Carrying a 9800-line dependency for that made Skynet
refuse to start in any mission that does not inject MiST.

These are deliberately kept free of any outside dependency, so Skynet stays a drop-in script.
Behaviour is reproduced from MiST 4.5.107 rather than reinvented; where this file departs from
it, the reason is written at the call site.
]]

SkynetIADSUtils = {}

-- Lua 5.1 in DCS; the fallbacks keep the file loadable under a newer interpreter (unit tests).
local unpack = unpack or table.unpack
local maxn = table.maxn or function(t)
	local n = 0
	for k in pairs(t) do
		if type(k) == "number" and k > n then n = k end
	end
	return n
end

-- Arithmetic ---------------------------------------------------------------------------------

--- Rounds to the given number of decimals (0 when omitted).
function SkynetIADSUtils.round(num, idp)
	local mult = 10 ^ (idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

function SkynetIADSUtils.metersToNM(meters)
	return meters / 1852
end

function SkynetIADSUtils.metersToFeet(meters)
	return meters / 0.3048
end

function SkynetIADSUtils.toDegree(angle)
	return angle * 180 / math.pi
end

--- Turns a mission-table point into a runtime vec3.
-- A vec2 carries the easting in y, a vec3 carries the altitude there and the easting in z.
-- Getting this backwards raises no error, it only misplaces the point, which is why every
-- distance below goes through here first.
function SkynetIADSUtils.makeVec3(vec, y)
	if not vec.z then
		if vec.alt and not y then
			y = vec.alt
		elseif not y then
			y = 0
		end
		return { x = vec.x, y = y, z = vec.y }
	end
	return { x = vec.x, y = vec.y, z = vec.z }
end

local function magnitude(vec)
	return (vec.x ^ 2 + vec.y ^ 2 + vec.z ^ 2) ^ 0.5
end

--- Ground distance in metres, altitude ignored.
function SkynetIADSUtils.get2DDist(point1, point2)
	local p1 = SkynetIADSUtils.makeVec3(point1)
	local p2 = SkynetIADSUtils.makeVec3(point2)
	return magnitude({ x = p1.x - p2.x, y = 0, z = p1.z - p2.z })
end

--- Slant distance in metres.
function SkynetIADSUtils.get3DDist(point1, point2)
	return magnitude({ x = point1.x - point2.x, y = point1.y - point2.y, z = point1.z - point2.z })
end

-- Headings -----------------------------------------------------------------------------------

--- The angle between the map grid and true north at that point.
-- DCS grids are not aligned on true north, and the error grows with distance from the map
-- origin, so a bearing meant for a pilot has to carry this correction.
function SkynetIADSUtils.getNorthCorrection(point)
	local vec3 = SkynetIADSUtils.makeVec3(point)
	local lat, lon = coord.LOtoLL(vec3)
	local northPosit = coord.LLtoLO(lat + 1, lon)
	return math.atan2(northPosit.z - vec3.z, northPosit.x - vec3.x)
end

--- Direction of a vector, in radians in [0, 2*pi). Corrected to true north when a reference
-- point is supplied.
function SkynetIADSUtils.getDir(vec, point)
	local dir = math.atan2(vec.z, vec.x)
	if point then
		dir = dir + SkynetIADSUtils.getNorthCorrection(point)
	end
	if dir < 0 then
		dir = dir + 2 * math.pi
	end
	return dir
end

--- Heading from one point to another, in radians.
function SkynetIADSUtils.getHeadingPoints(point1, point2, north)
	local p1 = SkynetIADSUtils.makeVec3(point1)
	local p2 = SkynetIADSUtils.makeVec3(point2)
	local delta = { x = p2.x - p1.x, y = p2.y - p1.y, z = p2.z - p1.z }
	if north then
		return SkynetIADSUtils.getDir(delta, p1)
	end
	return SkynetIADSUtils.getDir(delta)
end

--- Heading a unit is facing, in radians in [0, 2*pi), corrected to true north unless asked raw.
-- Returns nil for a unit with no position, as MiST did: the caller decides what that means.
function SkynetIADSUtils.getHeading(unit, rawHeading)
	local unitPosition = unit:getPosition()
	if not unitPosition then
		return nil
	end
	local heading = math.atan2(unitPosition.x.z, unitPosition.x.x)
	if not rawHeading then
		heading = heading + SkynetIADSUtils.getNorthCorrection(unitPosition.p)
	end
	if heading < 0 then
		heading = heading + 2 * math.pi
	end
	return heading
end

--- A random integer in [firstNum, secondNum], or in [1, firstNum] when called with one argument.
-- MiST built a table of at least 50 candidates and drew from it ten times over; that changes
-- nothing about the distribution, so this calls math.random directly.
function SkynetIADSUtils.random(firstNum, secondNum)
	if not secondNum then
		return math.random(1, firstNum)
	end
	return math.random(firstNum, secondNum)
end

-- Scheduler ----------------------------------------------------------------------------------

local scheduledTasks = {}
local lastTaskId = 0

--- Smallest delay this module will ever hand to the native timer, in seconds.
--
-- MiST's task list was walked by a loop re-armed every 0.01 s that ran anything whose time had
-- come **or gone**, so a task asked for a moment already past simply ran on the next tick. One
-- native timer.scheduleFunction per task carries no such promise, and Skynet leans on it hard:
-- SkynetIADS:activate, SkynetIADS:scanForHarms and SkynetIADSJammer:masterArmOn all pass a
-- hardcoded startTime of 1 -- one second of mission time. Only goSilentToEvadeHARM passes an
-- absolute future time.
--
-- Measured 2026-09-03 on a Persian Gulf mission whose IADS initialised at 18:29:48, some three
-- minutes in: evaluateContacts never ran once. Every SAM stayed dark (the IADS darkens a site's
-- radar when it registers it, and only re-enables it from that cycle), the status page stayed
-- blank (printSystemStatus is the last statement of evaluateContacts), and dcs.log carried no
-- Skynet error at all -- the signature of a lost task rather than a crash. This floor is what
-- keeps those three hardcoded call sites equivalent to what they got under MiST.
local MINIMUM_DELAY = 0.01

--- Runs one scheduled task and answers when it should run next, or nil to stop.
local function runScheduledTask(id)
	local task = scheduledTasks[id]
	if not task then
		return nil -- removed while it was pending
	end
	if task.stopTime and timer.getTime() >= task.stopTime then
		scheduledTasks[id] = nil
		return nil
	end

	-- Guarded exactly as MiST guarded it: a repeating task that throws is logged and keeps its
	-- place. An IADS whose contact evaluation dies on one bad contact must not go deaf for the
	-- rest of the mission.
	local ok, err = pcall(task.fn, unpack(task.args, 1, maxn(task.args)))
	if not ok then
		env.info("SkynetIADS: error in scheduled function: " .. tostring(err))
	end

	if not task.repeatInterval then
		scheduledTasks[id] = nil
		return nil
	end
	if not scheduledTasks[id] then
		return nil -- the task removed itself while running
	end
	return timer.getTime() + task.repeatInterval
end

--- Schedules a function, and answers an id that removeFunction accepts.
-- @param fn function to run
-- @param args table of arguments passed to it, or nil
-- @param startTime seconds since mission start at which to run it first; a time already past
--        means the next tick
-- @param repeatInterval seconds between runs, or nil to run once
-- @param stopTime seconds since mission start after which it stops repeating, or nil
function SkynetIADSUtils.scheduleFunction(fn, args, startTime, repeatInterval, stopTime)
	assert(type(fn) == "function", "scheduleFunction: argument 1 must be a function, got " .. type(fn))
	assert(type(args) == "table" or args == nil, "scheduleFunction: argument 2 must be a table or nil")
	assert(type(startTime) == "number", "scheduleFunction: argument 3 must be a number")
	assert(
		type(repeatInterval) == "number" or repeatInterval == nil,
		"scheduleFunction: argument 4 must be a number or nil"
	)
	assert(type(stopTime) == "number" or stopTime == nil, "scheduleFunction: argument 5 must be a number or nil")

	lastTaskId = lastTaskId + 1
	local id = lastTaskId
	scheduledTasks[id] = { fn = fn, args = args or {}, repeatInterval = repeatInterval, stopTime = stopTime }
	-- A first run due now, or overdue, is armed for the next tick instead -- see MINIMUM_DELAY.
	-- Only the first run is clamped: repetition is re-armed from timer.getTime() inside
	-- runScheduledTask, so it is future by construction, and stopTime is a comparison, not a delay.
	local earliest = timer.getTime() + MINIMUM_DELAY
	if startTime < earliest then
		startTime = earliest
	end
	timer.scheduleFunction(runScheduledTask, id, startTime)
	return id
end

--- Cancels a scheduled function. Answers whether there was one to cancel.
-- Safe to call with nil, which happens whenever Skynet stops something it never started.
function SkynetIADSUtils.removeFunction(id)
	if id == nil or scheduledTasks[id] == nil then
		return false
	end
	scheduledTasks[id] = nil
	return true
end

-- Listing what the mission holds -------------------------------------------------------------

--- Runs `visit` on every group DCS still considers alive, in every coalition.
--
-- The isExist check is the reason this is a function rather than two copied loops.
-- `coalition.getGroups` can hand back a group that has been destroyed, and asking such a group for
-- its units raises. Inside a `pairs` loop that error does not skip one group -- it aborts the whole
-- listing, so a single wreck on the map would silently truncate prefix-based discovery and the sites
-- after it would never join the IADS. MiST never met this because it read its own database.
local function forEachLiveGroup(visit)
	for _, coalitionId in pairs(coalition.side) do
		local groups = coalition.getGroups(coalitionId)
		if groups then
			for _, group in pairs(groups) do
				if group and (not group.isExist or group:isExist()) then
					visit(group)
				end
			end
		end
	end
end

--- Every group name currently in the mission, whatever its coalition or category.
-- MiST answered from a database it refreshed every two seconds; this asks DCS directly, which
-- costs nothing here because Skynet calls it only when adding sites by prefix.
--
-- The two differ on paper: MiST's database was built from the mission file and so also held
-- groups that are not in the game yet (late activation) or no longer are. Skynet discarded
-- those itself right after, with Group.getByName and isActive, so the visible behaviour is the
-- same -- and a group spawned at runtime, which MiST's database only knew after its next
-- refresh, is now visible immediately.
function SkynetIADSUtils.getGroupNames()
	local names = {}
	forEachLiveGroup(function(group)
		local name = group:getName()
		if name then
			names[name] = true
		end
	end)
	return names
end

--- Every unit name currently in the mission. See getGroupNames for how this differs from the
-- database MiST kept.
function SkynetIADSUtils.getUnitNames()
	local names = {}
	forEachLiveGroup(function(group)
		for _, unit in pairs(group:getUnits() or {}) do
			local name = unit:getName()
			if name then
				names[name] = true
			end
		end
	end)
	return names
end

end
