local ctx = ...
local Wd = Hotload.load("insim-world")
local watch = ctx.state.watch

local HARM = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}" -- AGM-88C, F-16C bl.52d stations 3 and 8

-- Invisible, so that only the HARM is ever a contact; immortal, so that its run ends with a shot.
-- From the east, so that the HARM passes over the SA-2 on its way to the SA-6.
local function attack()
	local shots = Wd.recordShots(ctx)
	Wd.spawnAircraft(ctx, {
		name = "ATTACKER",
		type = "F-16C bl.52d",
		country = country.id.USA,
		from = Wd.pointFrom("ZONE-SITE-1", 90, 80),
		via = Wd.pointFrom("ZONE-SITE-1", 90, 77),
		to = Wd.pointFrom("ZONE-SITE-1", 90, 10),
		alt = 6000,
		speed = 250,
		task = "SEAD",
		payload = {
			-- one HARM for the SA-15's one launcher: with more, the SA-2 goes silent too
			pylons = { [3] = { CLSID = HARM } },
			fuel = 3000,
			flare = 0,
			chaff = 0,
			gun = 100,
		},
		immortal = true,
		invisible = true,
		ignoreThreats = true,
		waypointTasks = { Wd.attackTask(ctx.name .. "/SAM-SA6", 32768) }, -- anti-radiation
	})
	return shots
end

if
	not (
		watch:waitFor("target", { true }, 30)
		and watch:waitFor("site", { false }, 30)
		and watch:waitFor("pointDefence", { false }, 30)
	)
then
	ctx.invalid("the SA-6 never went live, or the SA-2 or its point defence never went dark")
end
local shots = attack()
if not Hotload.waitFor(function()
	return Wd.fired(shots, ctx.name .. "/ATTACKER-1") > 0
end, 120) then
	ctx.invalid("the attacker never fired")
end
-- Gone once its HARM is: at the end of its route, the attacker became a contact the network woke
-- the SA-2 for, invisible or not, and a site gone live releases its point defence without the fix.
-- Not before: a HARM goes with the aircraft that fired it.
Hotload.waitFor(function()
	return shots[1].object:isExist() == false
end, 120)
local attacker = Group.getByName(ctx.name .. "/ATTACKER")
if attacker then
	attacker:destroy()
end
-- the HARM's flight, then objectsIdentifiedAsHarmsMaxTargetAge (60 s) for the SA-2 to forget it
watch:waitFor("pointDefence", { false, true, false }, 300)
return watch:report()
