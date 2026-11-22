local ctx = ...

-- an SA-2 cannot engage a HARM, but its point defence can: it stays live on its track under one
ctx:add("SAM-SA2", "ZONE-SITE-1")
ctx:add("SAM-SA15", "ZONE-SITE-1-PD")
ctx:add("EW-1L13", "ZONE-EW-1")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA2")
	local pointDefence = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA15")
	site:addPointDefence(pointDefence)
	-- live once the waker is in its search radar's range, which Skynet reads as 80 km, past its
	-- missiles' 43 km: live on a real track, with no missile spent before the HARM
	site:setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
	site:setHARMDetectionChance(100)
	pointDefence:setHARMDetectionChance(100)
	-- the chances of every radar that sees the HARM combine, the EW radar's among them
	iads:getEarlyWarningRadarByUnitName(ctx.name .. "/EW-1L13-1"):setHARMDetectionChance(100)
end)
ctx.state.site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA2")
ctx.state.pointDefence = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA15")
ctx.state.watch = Hotload.load("insim-harm").watch(ctx, ctx.state.site, ctx.state.pointDefence)
