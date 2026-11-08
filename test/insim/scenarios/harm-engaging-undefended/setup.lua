local ctx = ...

-- an SA-2 cannot engage a HARM: with no point defence, it goes dark under one
ctx:add("SAM-SA2", "ZONE-SITE-1")
ctx:add("EW-1L13", "ZONE-EW-1")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA2"):setHARMDetectionChance(100)
	-- the chances of every radar that sees the HARM combine, the EW radar's among them
	iads:getEarlyWarningRadarByUnitName(ctx.name .. "/EW-1L13-1"):setHARMDetectionChance(100)
end)
local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA2")
ctx.state.site = site
ctx.state.watch = Hotload.load("insim-watch").start(ctx, {
	active = function()
		return site:isActive()
	end,
	harm = function()
		return site:getNumberOfObjectsItentifiedAsHARMS() > 0
	end,
	defending = function()
		return site:isDefendingHARM()
	end,
}, 1)
