local ctx = ...
local H = Hotload.load("insim-harm")
local watch = ctx.state.watch

if not watch:waitFor("activeSite", { true }, 30) then
	ctx.invalid("the SA-6 never went live")
end
local harm = H.shoot(ctx, "SAM-SA6", "ZONE-SITE-1", 90)
return H.untilOver(ctx, watch, harm, { ctx.state.site }, 10)
