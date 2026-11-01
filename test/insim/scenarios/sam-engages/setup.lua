local ctx = ...

ctx:add("SAM-SA6", "ZONE-SITE-1")
ctx:add("EW-1L13", "ZONE-EW-1")
local iads = Hotload.load("insim-skynet").iads(ctx)
local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
if not site then
	ctx.invalid("the SA-6 is not in the network")
end
ctx.state.watch = Hotload.load("insim-watch").start(ctx, {
	active = function()
		return site:isActive()
	end,
	firing = function()
		return site:hasMissilesInFlight()
	end,
}, 1)
