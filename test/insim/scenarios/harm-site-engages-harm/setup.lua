local ctx = ...

-- An SA-10 can engage a HARM: with launchers and missiles for it, it stays live under one
-- (shallIgnoreHARMShutdown). Alone, so that nothing else takes the HARM down.
ctx:add("SAM-SA10", "ZONE-SITE-2")
ctx:add("EW-1L13", "ZONE-EW-1")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA10")
	-- live once the waker is in its search radar's range, stretched past its missiles: live on a real
	-- track, with no missile spent before the HARM. Skynet reads the SA-10's search range as 80.2 km
	-- (measured in the mission, DCS 2.9), short of the 120 km its missiles reach: 200 % makes it 160 km
	site:setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
	site:setGoLiveRangeInPercent(200)
	site:setHARMDetectionChance(100)
	-- the chances of every radar that sees the HARM combine, the EW radar's among them
	iads:getEarlyWarningRadarByUnitName(ctx.name .. "/EW-1L13-1"):setHARMDetectionChance(100)
end)
ctx.state.site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA10")
ctx.state.watch = Hotload.load("insim-harm").watch(ctx, ctx.state.site)
