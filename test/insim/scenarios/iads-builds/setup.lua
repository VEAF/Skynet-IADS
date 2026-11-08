local ctx = ...
local Wd = Hotload.load("insim-world")

ctx:add("SAM-SA6")
ctx:add("EW")
ctx:add("SAM-SA10", "ZONE-SITE-2")
ctx:add("SAM-SA8", "ZONE-SITE-1-PD")
-- under the prefix, neither a site: a group that is no SAM, and a static
ctx:add("SAM-NOTSAM", "ZONE-SITE-3")
ctx:add("SAM-STATIC", "ZONE-INFRA-1")
ctx:add("EW-1L13", "ZONE-INFRA-EW")
Wd.spawnAircraft(ctx, {
	name = "EW-AWACS",
	type = "A-50",
	country = country.id.RUSSIA,
	from = Wd.pointFrom("ZONE-SITE-1", 270, 40),
	to = Wd.pointFrom("ZONE-SITE-1", 270, 140),
	alt = 8000,
	speed = 220,
	task = "AWACS",
	payload = { fuel = 60000, flare = 0, chaff = 0, gun = 0, pylons = {} },
})
ctx.state.iads = Hotload.load("insim-skynet").iads(ctx)
