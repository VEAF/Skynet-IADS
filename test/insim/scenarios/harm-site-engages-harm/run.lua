local ctx = ...
local H = Hotload.load("insim-harm")
local Wd = Hotload.load("insim-world")
local watch = ctx.state.watch

local shots = Wd.recordShots(ctx)
-- 140 km: inside the SA-10's search radar (S-300PS 64H6E sr, 160 km) and the 1L13 (300 km), beyond
-- its missiles (S-300PS 5P85C ln, ThreatRange 120 km). DCS unit database, _G/db/Units/Cars/Car/.
-- North-west, over the steppe towards the Sea of Azov: away from the mountains, and from the
-- shooter's line from the east.
H.wake(ctx, "ZONE-SITE-2", 315, 140)
if not watch:waitFor("activeSite", { false, true }, 300) then
	ctx.invalid("the network never woke the SA-10")
end
Hotload.wait(20)
if H.firedBy(shots, ctx.name .. "/SAM-SA10-") > 0 then
	ctx.invalid("the SA-10 fired at the waker")
end
local harm = H.shoot(ctx, "SAM-SA10", "ZONE-SITE-2", 90)
return H.untilOver(ctx, watch, harm, { ctx.state.site }, 10)
