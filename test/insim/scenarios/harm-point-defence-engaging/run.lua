local ctx = ...
local H = Hotload.load("insim-harm")
local watch = ctx.state.watch

-- 75 km: inside the SA-2's go-live range (107 km, see setup) and the 1L13's detection, beyond its
-- missiles (S_75M_Volhov, ThreatRange 43 km) and far beyond the SA-15's (Tor 9A331, 12 km). DCS unit
-- database, _G/db/Units/Cars/Car/. North-west, over the steppe, away from the mountains.
local shots = H.wake(ctx, watch, "SAM-SA2", "ZONE-SITE-1", 315, 75)
-- From the waker's side, as a SEAD flight comes in with the aircraft a site tracks. The shooter
-- crosses the waker's orbit 2,000 m below it.
local harm = H.shoot(ctx, "SAM-SA2", "ZONE-SITE-1", 315)
local result = H.untilOver(ctx, watch, harm, { ctx.state.site, ctx.state.pointDefence }, 10)
-- measured, not judged: whether the DCS AI engages the HARM is its own business
result.pointDefenceShots = H.firedBy(shots, ctx.name .. "/SAM-SA15-")
return result
