local ctx = ...
local iads, power, site = ctx.state.iads, ctx.state.power, ctx.state.site

if not Hotload.waitFor(function()
	return site:isActive()
end, 30) then
	ctx.invalid("the SA-6 never went live")
end
Hotload.callOnMain(function()
	trigger.action.explosion(power:getPosition().p, 100)
end)
if not Hotload.waitFor(function()
	return not power:isExist()
end, 30) then
	ctx.invalid("the power source survived the explosion")
end
-- No event is faked: the site goes dark only if DCS's S_EVENT_DEAD reaches Skynet.
local dark = Hotload.waitFor(function()
	return not site:isActive()
end, 30)
return {
	powerLost = not site:hasWorkingPowerSource(),
	dark = dark,
	usable = #iads:getUsableSAMSites(),
}
