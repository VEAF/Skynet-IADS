local ctx = ...
local H = Hotload.load("insim-harm")
local Wd = Hotload.load("insim-world")
local watch = ctx.state.watch

local shots = Wd.recordShots(ctx)
-- 140 km: inside the SA-10's go-live range (160 km, see setup) and the 1L13's detection (300 km),
-- beyond its missiles (S-300PS 5P85C ln, ThreatRange 120 km, _G/db/Units/Cars/Car/ in the DCS unit
-- database).
-- North-west, over the steppe towards the Sea of Azov, away from the mountains.
H.wake(ctx, "ZONE-SITE-2", 315, 140)
if not watch:waitFor("activeSite", { false, true }, 300) then
	ctx.invalid("the network never woke the SA-10")
end
Hotload.wait(20)
if H.firedBy(shots, ctx.name .. "/SAM-SA10-") > 0 then
	ctx.invalid("the SA-10 fired at the waker")
end
-- From the waker's side, as a SEAD flight comes in with the aircraft a site tracks: the SA-10's
-- tracking radar is turned to the waker, and a HARM from elsewhere lies outside its sector, so the
-- SA-10 never engages it (seen from the east, DCS 2.9, 2026-11-22). The shooter's run, 80 to 10 km
-- out, stays clear of the waker's orbit at 140 km.
local harm = H.shoot(ctx, "SAM-SA10", "ZONE-SITE-2", 315)
local result = H.untilOver(ctx, watch, harm, { ctx.state.site }, 10)
-- measured, not judged: whether the DCS AI engages the HARM is its own business
result.siteShots = H.firedBy(shots, ctx.name .. "/SAM-SA10-")
return result
