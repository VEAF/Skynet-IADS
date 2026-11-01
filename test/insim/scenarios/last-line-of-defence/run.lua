local ctx = ...
local Wd = Hotload.load("insim-world")
local site, watch = ctx.state.site, ctx.state.watch

-- The geometry the check rests on, read from the running mission: the EW radar covers the site, the
-- site is dark, and its radius is inside its own firing range (or a woken site refuses the contact).
if not watch:waitFor("active", { false }, 30) then
	ctx.invalid("the SA-6 was never dark")
end
if #site:getParentRadars() ~= 1 then
	ctx.invalid("the SA-6 has " .. #site:getParentRadars() .. " parent radars, not the far EW radar alone")
end
local radius = site:getLastLineOfDefenceRadius()
local range = site:getLaunchers()[1]:getRange()
if radius >= range then
	ctx.invalid(string.format("the radius, %.0f m, is not inside the firing range, %.0f m", radius, range))
end

-- From 40 km south of the site to 40 km north, at 150 m above the ground and 200 m/s: under the EW
-- radar's horizon, across the radius in about two minutes, and out of it again, which is the half
-- that proves the persistence expires. Told to do nothing, hold fire, ignore threats, and immortal:
-- an intruder that attacks, evades or dies leaves its run.
local centre = site:getElementPosition()
Wd.spawnAircraft(ctx, {
	name = "INTRUDER",
	type = "A-10A",
	country = country.id.USA,
	from = { x = centre.x - 40000, y = centre.z },
	to = { x = centre.x + 40000, y = centre.z },
	alt = 150,
	altType = "RADIO",
	speed = 200,
	payload = { fuel = 5000, flare = 120, chaff = 240, gun = 100, pylons = {} },
	immortal = true,
	holdFire = true,
	ignoreThreats = true,
})
watch:waitFor("active", { false, true, false }, 600)
-- Watched on for a while after the first match: the sequence must still be exactly this once the
-- site has had time to flap or wake again, which a snapshot at the match could not show.
Hotload.wait(30)
local report = watch:report()
report.radius = radius
return report
