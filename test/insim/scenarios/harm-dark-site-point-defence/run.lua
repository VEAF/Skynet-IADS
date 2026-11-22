local ctx = ...
local H = Hotload.load("insim-harm")
local watch = ctx.state.watch

if
	not (
		watch:waitFor("activeEwr", { true }, 30)
		and watch:waitFor("activeSite", { false }, 30)
		and watch:waitFor("activePointDefence", { false }, 30)
	)
then
	ctx.invalid("the Dog Ear never went live, or the SA-2 or its point defence never went dark")
end
local harm = H.shoot(ctx, "EW-DOGEAR", "ZONE-SITE-1", 90)
return H.untilOver(ctx, watch, harm, { ctx.state.site }, 10)
