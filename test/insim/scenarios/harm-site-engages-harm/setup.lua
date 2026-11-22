local ctx = ...

-- An SA-10 can engage a HARM: with launchers and missiles for it, it stays live under one
-- (shallIgnoreHARMShutdown). Alone, so that nothing else takes the HARM down.
ctx:add("SAM-SA10", "ZONE-SITE-2")
ctx:add("EW-1L13", "ZONE-EW-1")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA10")
	-- live once the waker is in its search radar's range, stretched past its missiles: live on a real
	-- track, with no missile spent before the HARM. Skynet reads a search radar's range from
	-- getSensors(), and DCS answers 80,249 m for every ground radar (seen in DCS 2.9, 2026-11-22),
	-- short of the SA-10's 120 km: 200 % makes it 160 km
	site:setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
	site:setGoLiveRangeInPercent(200)
	site:setHARMDetectionChance(100)
	-- the chances of every radar that sees the HARM combine, the EW radar's among them
	iads:getEarlyWarningRadarByUnitName(ctx.name .. "/EW-1L13-1"):setHARMDetectionChance(100)
end)
local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA10")
ctx.state.site = site
ctx.state.watch = Hotload.load("insim-watch").start(ctx, {
	activeSite = function()
		return site:isActive()
	end,
	defending = function()
		return site:isDefendingHARM()
	end,
	harm = function()
		return site:getNumberOfObjectsItentifiedAsHARMS() > 0
	end,
}, 1)
