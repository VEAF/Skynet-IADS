local ctx = ...

-- A dark site emits nothing, so no HARM can be fired at it: the HARM is fired at the Dog Ear, the
-- network's EW radar, and flies over the SA-2, 2.5 km east of it, on its way in from the east. A Dog
-- Ear, because the AI fires a HARM at it: the 1L13 and the 55G6 carry no RADAR_BAND*_FOR_ARM.
ctx:add("EW-DOGEAR", "ZONE-SITE-1")
-- An SA-2, because it cannot engage a HARM: a site that can, an SA-10, is woken by the network to
-- shoot at the HARM, and a site gone live releases its point defence without the fix.
ctx:add("SAM-SA2", "ZONE-SITE-2")
ctx:add("SAM-SA15", "ZONE-SITE-1-PD")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	local ewr = iads:getEarlyWarningRadarByUnitName(ctx.name .. "/EW-DOGEAR-1")
	local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA2")
	local pointDefence = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA15")
	site:addPointDefence(pointDefence)
	ewr:setHARMDetectionChance(100)
	site:setHARMDetectionChance(100)
	pointDefence:setHARMDetectionChance(100)
end)
local ewr = iads:getEarlyWarningRadarByUnitName(ctx.name .. "/EW-DOGEAR-1")
ctx.state.site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA2")
local pointDefence = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA15")
ctx.state.watch = Hotload.load("insim-harm").watch(ctx, ctx.state.site, pointDefence, {
	activeEwr = function()
		return ewr:isActive()
	end,
})
