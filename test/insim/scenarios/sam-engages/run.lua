local ctx = ...
local Wd = Hotload.load("insim-world")
local watch = ctx.state.watch

if not watch:waitFor("active", { false }, 30) then
	ctx.invalid("the SA-6 was never dark before the target came")
end
-- Not immortal: shot down, it leaves the network's picture, and the site has to go dark again.
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
watch:waitFor("active", { false, true, false }, 300)
-- Watched on for a while after the first match: the sequence must still be exactly this once the
-- site has had time to flap or wake again, which a snapshot at the match could not show.
Hotload.wait(30)
return watch:report()
