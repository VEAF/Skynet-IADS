local ctx = ...
local Wd = Hotload.load("insim-world")
local watch = ctx.state.watch

local liveFirst = watch:waitFor("active", { true }, 30)
Wd.spawnAircraft(ctx, {
	name = "TARGET",
	type = "F-16C_50",
	country = country.id.USA,
	from = Wd.pointFrom("ZONE-SITE-1", 0, 30),
	to = Wd.pointFrom("ZONE-SITE-1", 180, 30),
	alt = 3000,
	speed = 250,
	payload = { pylons = {}, fuel = 1500, flare = 0, chaff = 0, gun = 100 },
	holdFire = true,
	ignoreThreats = true,
})
Hotload.waitFor(function()
	for _, value in ipairs(watch:sequence("firing")) do
		if value == true then
			return true
		end
	end
	return false
end, 240)
local report = watch:report()
report.liveFirst = liveFirst
return report
