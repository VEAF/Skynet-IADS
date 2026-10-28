local ctx = ...
local Wd = Hotload.load("insim-world")

-- Ported from the legacy run 2 of unit-tests/last-line-of-defence/. The A-50's detection range is
-- 204.5 km, read in game, and a sweep rebuilds only for an element that has moved more than 10 NM
-- (18.5 km) since its last rebuild. So the AWACS starts at 190 km, inside its range and therefore
-- the battery's parent, and flies straight away: it crosses its range at 204.5 km and the movement
-- threshold at 208.6 km, and the next sweep must hand the battery back. East, over land: west of
-- the site the same distance is off the map.
ctx:add("SAM-SA6", "ZONE-SITE-1")
Wd.spawnAircraft(ctx, {
	name = "EW-AWACS",
	type = "A-50",
	country = country.id.RUSSIA,
	from = Wd.pointFrom("ZONE-SITE-1", 90, 190),
	to = Wd.pointFrom("ZONE-SITE-1", 90, 290),
	alt = 8000,
	speed = 220,
	task = "AWACS",
	payload = { fuel = 60000, flare = 0, chaff = 0, gun = 0, pylons = {} },
})
local iads = Hotload.load("insim-skynet").iads(ctx)
local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
if not site then
	ctx.invalid("the SA-6 is not in the network")
end
ctx.state.watch = Hotload.load("insim-watch").start(ctx, {
	autonomous = function()
		return site:getAutonomousState()
	end,
}, 1)
