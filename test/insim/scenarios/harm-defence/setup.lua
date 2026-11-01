local ctx = ...

ctx:add("SAM-SA6", "ZONE-SITE-1")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
	site:setHARMDetectionChance(100)
	-- emitting, so the HARM has something to guide on; an SA-6 cannot engage a HARM, so it goes dark
	site:setActAsEW(true)
end)
local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
ctx.state.watch = Hotload.load("insim-watch").start(ctx, {
	active = function()
		return site:isActive()
	end,
	harm = function()
		return site:getNumberOfObjectsItentifiedAsHARMS() > 0
	end,
}, 1)
