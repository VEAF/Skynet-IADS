local ctx = ...

ctx:add("SAM-SA6", "ZONE-SITE-1")
ctx:add("SAM-SA15", "ZONE-SITE-1-PD")
-- an EW radar holds both, so the point defence is dark until the site needs it
ctx:add("EW-1L13", "ZONE-EW-1")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
	local pointDefence = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA15")
	site:addPointDefence(pointDefence)
	site:setHARMDetectionChance(100)
	pointDefence:setHARMDetectionChance(100)
	site:setActAsEW(true)
end)
local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
local pointDefence = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA15")
ctx.state.watch = Hotload.load("insim-watch").start(ctx, {
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
