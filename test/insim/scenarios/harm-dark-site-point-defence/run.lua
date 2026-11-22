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
-- Gone once its HARM is: at the end of its route, the shooter became a contact the network woke
-- the SA-2 for, invisible or not, and a site gone live releases its point defence without the fix.
-- Not before: a HARM goes with the aircraft that fired it.
Hotload.waitFor(function()
	return harm:isExist() == false
end, 180)
local shooter = Group.getByName(ctx.name .. "/SHOOTER")
if shooter then
	shooter:destroy()
end
return H.untilOver(watch, harm, { ctx.state.site }, 10)
