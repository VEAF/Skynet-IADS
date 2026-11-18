local ctx = ...

-- A dark site emits nothing, so no HARM can be fired at it: the HARM is fired at the SA-6, live as
-- an EW, and flies over the SA-2, 2.5 km east of it, on its way in from the east.
ctx:add("SAM-SA6", "ZONE-SITE-1")
-- An SA-2, because it cannot engage a HARM: a site that can, an SA-10, is woken by the network to
-- shoot at the HARM, and a site gone live releases its point defence without the fix.
ctx:add("SAM-SA2", "ZONE-SITE-2")
ctx:add("SAM-SA15", "ZONE-SITE-1-PD")
-- an EW radar holds the SA-2 and its point defence dark: the attacker is invisible, so neither ever
-- has a target
ctx:add("EW-1L13", "ZONE-EW-1")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	local target = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
	local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA2")
	local pointDefence = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA15")
	site:addPointDefence(pointDefence)
	target:setHARMDetectionChance(100)
	site:setHARMDetectionChance(100)
	pointDefence:setHARMDetectionChance(100)
	target:setActAsEW(true)
end)
local target = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA2")
local pointDefence = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA15")
ctx.state.watch = Hotload.load("insim-watch").start(ctx, {
	target = function()
		return target:isActive()
	end,
	site = function()
		return site:isActive()
	end,
	pointDefence = function()
		return pointDefence:isActive()
	end,
	harm = function()
		return site:getNumberOfObjectsItentifiedAsHARMS() > 0
	end,
}, 1)
