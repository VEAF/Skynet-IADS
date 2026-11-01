local ctx = ...

-- Ported from run 1 of the legacy unit-tests/last-line-of-defence/: a dark SA-6 held by a 55G6 so
-- far away that it covers the site on Skynet's flat 2D geometry while seeing nothing of an aircraft
-- low over the terrain. Fly under the EW radar's horizon and only the last line of defence reacts.
ctx:add("SAM-SA6")
ctx:add("EW-far")
local iads = Hotload.load("insim-skynet").iads(ctx)
local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
if not site then
	ctx.invalid("the SA-6 is not in the network")
end
ctx.state.site = site
ctx.state.watch = Hotload.load("insim-watch").start(ctx, {
	active = function()
		return site:isActive()
	end,
}, 1)
