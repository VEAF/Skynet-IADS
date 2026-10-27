local ctx = ...

ctx:add("SAM-TORM2", "ZONE-SITE-1") -- engages bombs and missiles
ctx:add("SAM-SA10", "ZONE-SITE-2") -- engages missiles only
ctx:add("SAM-SA6", "ZONE-SITE-3") -- engages neither
-- 2 km away: the munition campaign's EW radar reported every munition from there within 1 s; a 1L13
-- 35 km away reported none
ctx:add("EW-55G6", "ZONE-EW-2")
local sites = {}
ctx.state.iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	-- The attacker flies over the sites, and the last line of defence wakes a dark site for any
	-- hostile aircraft near it, seen or not: it would wake them all, munition or none.
	iads:setLastLineOfDefence(false)
	for _, role in ipairs({ "SAM-TORM2", "SAM-SA10", "SAM-SA6" }) do
		local name = ctx.name .. "/" .. role
		sites[role] = iads:getSAMSiteByGroupName(name)
		-- immortal, as the feature's own measurement had them: a site destroyed cannot go dark again
		local controller = Group.getByName(name):getController()
		controller:setCommand({ id = "SetImmortal", params = { value = true } })
		-- dispersal moves units after nearby impacts, and the site out of its zone
		controller:setOption(AI.Option.Ground.id.DISPERSE_ON_ATTACK, 0)
	end
end)
ctx.state.sites = sites
