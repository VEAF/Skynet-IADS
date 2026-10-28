local ctx = ...

ctx:add("SAM-SA6", "ZONE-SITE-1")
local power = ctx:add("POWER", "ZONE-INFRA-1")
local iads = Hotload.load("insim-skynet").iads(ctx, function(iads)
	local site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
	site:addPowerSource(power)
	-- live with no target in sight, so that going dark can only be the power's doing
	site:setActAsEW(true)
end)
ctx.state.iads = iads
ctx.state.power = power
ctx.state.site = iads:getSAMSiteByGroupName(ctx.name .. "/SAM-SA6")
