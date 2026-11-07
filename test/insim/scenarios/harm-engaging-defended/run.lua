local ctx = ...
local H = Hotload.load("insim-harm")
local site = ctx.state.site
local watch = ctx.state.watch
local siteUnits = ctx.name .. "/SAM-SA2-"

local shots, _, harm = H.attackOnceEngaged(ctx, "SAM-SA2", "ZONE-SITE-1")
Hotload.waitFor(function()
	return site:getNumberOfObjectsItentifiedAsHARMS() > 0
end, 120)
local firedBeforeHarm = H.firedBy(shots, siteUnits)
-- the HARM's flight, to its end: shot down, on the ground, or flown on past the site and out
if not Hotload.waitFor(function()
	return harm:isExist() == false
end, 300) then
	ctx.invalid("the HARM never ended")
end
-- the attacker is immortal, so the site goes on firing until it runs out of missiles, and goes
-- dark then as it would under a HARM
if site:hasRemainingAmmo() == false then
	ctx.invalid("the SA-2 ran out of missiles before the HARM's end")
end
local result = watch:report()
result.siteShotsAfterHarm = H.firedBy(shots, siteUnits) - firedBeforeHarm
-- the minute the HARM is remembered after it, at the end of which the point defence stands down.
-- The attacker circles above the point defence's reach, so it cannot hold the point defence live
watch:waitFor("pointDefence", { false, true, false }, 120)
result.pointDefence = watch:sequence("pointDefence")
result.pointDefenceShots = H.firedBy(shots, ctx.name .. "/SAM-SA15-")
return result
