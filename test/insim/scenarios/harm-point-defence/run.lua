local ctx = ...
local Wd = Hotload.load("insim-world")
local watch = ctx.state.watch

local HARM = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}" -- AGM-88C, F-16C bl.52d stations 3 and 8

-- Invisible, so that only the HARM is ever a contact; immortal, so that its run ends with a shot.
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
			-- one HARM for the SA-15's one launcher: with more, the site goes dark (shallIgnoreHARMShutdown)
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

local function firedOrInvalid(shots)
	if Wd.fired(shots, ctx.name .. "/ATTACKER-1") == 0 then
		ctx.invalid("the attacker never fired")
	end
end

if not (watch:waitFor("site", { true }, 30) and watch:waitFor("pointDefence", { false }, 30)) then
	ctx.invalid("the SA-6 never went live, or its point defence never went dark")
end
local shots = attack()
watch:waitFor("pointDefence", { false, true, false }, 390)
firedOrInvalid(shots)
return watch:report()
