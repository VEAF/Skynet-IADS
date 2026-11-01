local ctx = ...
local Wd = Hotload.load("insim-world")

-- A network of its own per case, named after it, deactivated by cleanup whatever happens.
local function network(case, build)
	local ok, iads = Hotload.callOnMain(function()
		return SkynetIADS:create(ctx.name .. "-" .. case)
	end)
	if not ok then
		error(iads, 0)
	end
	ctx:onCleanup(function()
		iads:deactivate()
	end)
	local built, message = Hotload.callOnMain(function()
		build(iads)
		iads:activate()
	end)
	if not built then
		error(message, 0)
	end
	return iads
end

local function destroy(case, object, power)
	Hotload.callOnMain(function()
		trigger.action.explosion(object:getPosition().p, power)
	end)
	if not Hotload.waitFor(function()
		return not object:isExist()
	end, 15) then
		ctx.invalid(case .. ": the target survived the explosion")
	end
end

local function held(site)
	return Hotload.waitFor(function()
		return site:getAutonomousState() == false
	end, 20)
end

local function autonomous(element)
	return Hotload.waitFor(function()
		return element:getAutonomousState() == true
	end, 30)
end

-- One SA-6 under one EW radar, both copied fresh for the case; `extra(iads, site, radar)` wires
-- what the case destroys.
local function case(name, extra)
	local group = ctx:add("SAM-SA6", "ZONE-SITE-1", "SAM-" .. name)
	local radarGroup = ctx:add("EW-1L13", "ZONE-EW-1", "EW-" .. name)
	local samName, ewName = ctx.name .. "/SAM-" .. name, ctx.name .. "/EW-" .. name .. "-1"
	local site, radar
	local iads = network(name, function(iads)
		iads:addEarlyWarningRadar(ewName)
		iads:addSAMSite(samName)
		site = iads:getSAMSiteByGroupName(samName)
		radar = iads:getEarlyWarningRadarByUnitName(ewName)
		extra(iads, site, radar)
	end)
	return iads, site, radar, group, radarGroup
end

local function finish(iads, objects)
	Hotload.callOnMain(function()
		iads:deactivate()
		for _, object in ipairs(objects) do
			if object:isExist() then
				object:destroy()
			end
		end
	end)
	Wd.clearWrecks("ZONE-AREA")
end

local results = {}

-- 1. a SAM site's connection node
do
	local node = ctx:add("NODE", "ZONE-INFRA-2", "NODE-C1")
	local iads, site, _, g1, g2 = case("C1", function(_, site)
		site:addConnectionNode(node)
	end)
	local before = held(site)
	destroy("C1", node, 500)
	results.samConnectionNode = { held = before, autonomous = autonomous(site) }
	finish(iads, { g1, g2 })
end

-- 2. an EW radar's connection node, 3. an EW radar's power source
for _, c in ipairs({
	{ "C2", "NODE", "addConnectionNode", "ewConnectionNode" },
	{ "C3", "POWER", "addPowerSource", "ewPowerSource" },
}) do
	local thing = ctx:add(c[2], "ZONE-INFRA-EW", c[2] .. "-" .. c[1])
	local iads, site, _, g1, g2 = case(c[1], function(_, _, radar)
		radar[c[3]](radar, thing)
	end)
	local before = held(site)
	destroy(c[1], thing, 500)
	results[c[4]] = { held = before, autonomous = autonomous(site) }
	finish(iads, { g1, g2 })
end

-- 4. the EW radar itself
do
	local iads, site, radar, g1, g2 = case("C4", function() end)
	local before = held(site)
	destroy("C4", radar:getDCSRepresentation(), 500)
	results.ewDestroyed = { held = before, autonomous = autonomous(site) }
	finish(iads, { g1, g2 })
end

-- 5. a command centre, 6. its power source, 7. its connection node
for _, c in ipairs({
	{ "C5", nil, "commandCentre" },
	{ "C6", "POWER", "commandCentrePower", "addPowerSource" },
	{ "C7", "NODE", "commandCentreNode", "addConnectionNode" },
}) do
	local centre = ctx:add("CC", "ZONE-CC", "CC-" .. c[1])
	local thing = c[2] and ctx:add(c[2], "ZONE-INFRA-1", c[2] .. "-" .. c[1])
	local iads, site, radar, g1, g2 = case(c[1], function(iads)
		local cc = iads:addCommandCenter(centre)
		if thing then
			cc[c[4]](cc, thing)
		end
	end)
	local before = held(site) and iads:isCommandCenterUsable()
	destroy(c[1], thing or centre, 5000)
	local unusable = Hotload.waitFor(function()
		return not iads:isCommandCenterUsable()
	end, 30)
	results[c[3]] = { held = before, autonomous = unusable and autonomous(site) and autonomous(radar) }
	finish(iads, { g1, g2, centre })
end

return results
