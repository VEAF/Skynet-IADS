local ctx = ...
local H = Hotload.load("insim-harm")
local watch = ctx.state.watch

local shots = H.attackOnceEngaged(ctx, "SAM-SA2", "ZONE-SITE-1")
-- live to engage, silent under the HARM, and back up once the silence is over, to engage the
-- attacker again: it circles inside the kill zone
watch:waitFor("active", { false, true, false, true }, 300)
local result = watch:report()
result.siteShots = H.firedBy(shots, ctx.name .. "/SAM-SA2-")
return result
