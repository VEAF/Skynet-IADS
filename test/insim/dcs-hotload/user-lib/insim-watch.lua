-- The watch of the in-sim test suite. A scenario that judges a transition — a site lit then dark
-- again — cannot read it from the state at the end, where "dark" is both the pass and a site that
-- never lit. The watch samples probes on a timer and keeps each value a probe goes through.
local W = {}

local Watch = {}
Watch.__index = Watch

local function startsWith(values, expected)
	if #values < #expected then
		return false
	end
	for i = 1, #expected do
		if values[i] ~= expected[i] then
			return false
		end
	end
	return true
end

local function copy(values)
	local result = {}
	for i = 1, #values do
		result[i] = values[i]
	end
	return result
end

-- `probes` is `{ name = function() return value end }`, sampled every `interval` seconds (default
-- 1). A probe that raises is recorded as "error: <message>" and a nil answer as "nil": the
-- timer would otherwise stop at the first error, and the run go blind looking like a run where
-- nothing happened.
function W.start(ctx, probes, interval)
	interval = interval or 1
	local watch = setmetatable({ values = {} }, Watch)
	for name in pairs(probes) do
		watch.values[name] = {}
	end
	local function sample()
		for name, probe in pairs(probes) do
			local ok, value = pcall(probe)
			if not ok then
				value = "error: " .. tostring(value)
			elseif value == nil then
				value = "nil"
			end
			local values = watch.values[name]
			if #values == 0 or values[#values] ~= value then
				values[#values + 1] = value
			end
		end
	end
	local id
	ctx:onCleanup(function()
		if id then
			timer.removeFunction(id)
			id = nil
		end
	end)
	local ok, message = Hotload.callOnMain(function()
		id = timer.scheduleFunction(function()
			sample()
			return timer.getTime() + interval
		end, nil, timer.getTime() + interval)
	end)
	if not ok then
		error(message, 0)
	end
	return watch
end

-- The values `name` went through, in order.
function Watch:sequence(name)
	return copy(self.values[name])
end

-- Waits until the values of `name` start with `expected`; false after `timeout` seconds.
function Watch:waitFor(name, expected, timeout)
	return Hotload.waitFor(function()
		return startsWith(self.values[name], expected)
	end, timeout)
end

-- Every sequence, for a run to return.
function Watch:report()
	local report = {}
	for name, values in pairs(self.values) do
		report[name] = copy(values)
	end
	return report
end

return W
