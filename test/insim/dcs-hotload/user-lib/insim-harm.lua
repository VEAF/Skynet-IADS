-- What the harm-* scenarios share: the shooter that fires the HARM, the waker that gives the network
-- a target to wake a site for, and the rule for when a scenario has watched long enough.
local Wd = Hotload.load("insim-world")

local H = {}

local HARM = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}" -- AGM-88C, F-16C bl.52d stations 3 and 8
-- above a point defence's reach: the SA-15's missile tops out at 6,000 m (DCS 2.9), the SA-2's at 25,000
local ALTITUDE = 8000
local SPEED = 250

-- How many of `shots` (from recordShots) the units whose name starts with `prefix` fired.
function H.firedBy(shots, prefix)
	local count = 0
	for _, shot in ipairs(shots) do
		if string.sub(shot.initiator, 1, #prefix) == prefix then
			count = count + 1
		end
	end
	return count
end

-- Fires one HARM at the group `<scenario>/<targetRole>`, standing on `zone`, from `bearing` (degrees,
-- 0 north): an F-16 spawned 80 km out flies in and fires on the way. Invisible, so that only its HARM
-- is ever a contact; immortal, so that its run ends with a shot. Returns the HARM, a weapon object
-- whose `isExist()` tells when it has ended. The phase ends as `invalid` if it never fires.
function H.shoot(ctx, targetRole, zone, bearing)
	local shots = Wd.recordShots(ctx)
	Wd.spawnAircraft(ctx, {
		name = "SHOOTER",
		type = "F-16C bl.52d",
		country = country.id.USA,
		from = Wd.pointFrom(zone, bearing, 80),
		via = Wd.pointFrom(zone, bearing, 77),
		to = Wd.pointFrom(zone, bearing, 10),
		alt = 6000,
		speed = SPEED,
		task = "SEAD",
		payload = {
			-- one HARM: one is what a point defence's one launcher can take (shallIgnoreHARMShutdown)
			pylons = { [3] = { CLSID = HARM } },
			fuel = 3000,
			flare = 0,
			chaff = 0,
			gun = 100,
		},
		immortal = true,
		invisible = true,
		ignoreThreats = true,
		waypointTasks = { Wd.attackTask(ctx.name .. "/" .. targetRole, 32768) }, -- anti-radiation
	})
	local shooter = ctx.name .. "/SHOOTER-1"
	if not Hotload.waitFor(function()
		return Wd.fired(shots, shooter) > 0
	end, 180) then
		ctx.invalid("the shooter never fired")
	end
	for _, shot in ipairs(shots) do
		if shot.initiator == shooter then
			return shot.object
		end
	end
end

-- Gives the network a target to wake a site for: a visible, immortal F-16 with nothing to fire,
-- which flies in on `bearing` from `zone` and circles `km` from the zone's centre. Spawned farther
-- out, so that it never comes closer than its orbit. A site set to go live in its search range, with
-- the orbit beyond its missiles' reach, is then live on a real track without firing a missile.
function H.wake(ctx, zone, bearing, km)
	local orbit = Wd.pointFrom(zone, bearing, km)
	local waker = Wd.spawnAircraft(ctx, {
		name = "WAKER",
		type = "F-16C bl.52d",
		country = country.id.USA,
		from = Wd.pointFrom(zone, bearing, km + 15),
		to = orbit,
		alt = ALTITUDE,
		speed = SPEED,
		payload = { pylons = {}, fuel = 3000, flare = 0, chaff = 0, gun = 0 },
		immortal = true,
		holdFire = true,
		ignoreThreats = true,
	})
	local ok, message = Hotload.callOnMain(function()
		waker:getController():setTask({
			id = "Orbit",
			params = {
				pattern = "Circle",
				point = { x = orbit.x, y = orbit.y },
				speed = SPEED,
				altitude = ALTITUDE,
			},
		})
	end)
	if not ok then
		error(message, 0)
	end
end

-- Watches on until the engagement is over, and returns the watch's report: the HARM has ended
-- (shot down, on the ground, or flown past), every one of `sites` has forgotten it and is out of
-- any silence, and `settle` seconds more have passed for a late flip to show. A check made before
-- then cannot see a site that holds for a while and flaps afterwards. Each wait is bounded; one that
-- times out is a measurement, and the report says what went on.
--
-- The shooter goes once its HARM has: at the end of its route it becomes a contact the network wakes
-- sites for, invisible or not, which would show as a flip the HARM did not cause. Not before: a HARM
-- goes with the aircraft that fired it.
function H.untilOver(ctx, watch, harm, sites, settle)
	Hotload.waitFor(function()
		return harm:isExist() == false
	end, 180)
	local shooter = Group.getByName(ctx.name .. "/SHOOTER")
	if shooter then
		shooter:destroy()
	end
	Hotload.waitFor(function()
		for _, site in ipairs(sites) do
			if site:getNumberOfObjectsItentifiedAsHARMS() > 0 or site:isDefendingHARM() then
				return false
			end
		end
		return true
	end, 180)
	Hotload.wait(settle)
	return watch:report()
end

local function onAttacker(attacker, fn)
	local ok, message = Hotload.callOnMain(function()
		fn(attacker:getController())
	end)
	if not ok then
		error(message, 0)
	end
end

-- Attacks the group `<scenario>/<siteRole>`, standing on `zone`. Returns every shot fired from the
-- spawn on (recordShots), the attacker, and its HARM. The phase ends as `invalid` when the site
-- never fires at the attacker, or the attacker never fires its HARM.
function H.attackOnceEngaged(ctx, siteRole, zone)
	local site = ctx.name .. "/" .. siteRole
	local shots = Wd.recordShots(ctx)
	local hold = Wd.pointFrom(zone, 0, 20)
	local attacker = Wd.spawnAircraft(ctx, {
		name = "ATTACKER",
		type = "F-16C bl.52d",
		country = country.id.USA,
		-- from the north, straight at the site: inside an SA-2's kill zone a minute after the spawn,
		-- and the route ends outside the reach of a point defence beside the site, which would
		-- otherwise engage the attacker itself. Not from the east: the HARM's line would run on to
		-- the scenarios' EW radar, west of the site, which would take it for a HARM aimed at itself,
		-- go silent, and leave the site without a designation
		from = Wd.pointFrom(zone, 0, 55),
		to = hold,
		alt = ALTITUDE,
		speed = SPEED,
		task = "SEAD",
		payload = {
			-- one HARM for an SA-15's one launcher: with more, the site goes dark (shallIgnoreHARMShutdown)
			pylons = { [3] = { CLSID = HARM } },
			fuel = 3000,
			flare = 0,
			chaff = 0,
			gun = 100,
		},
		immortal = true,
		holdFire = true,
		ignoreThreats = true,
	})
	if not Hotload.waitFor(function()
		return H.firedBy(shots, site .. "-") > 0
	end, 300) then
		ctx.invalid(site .. " never fired at the attacker")
	end
	local attack = Wd.attackTask(site, 32768) -- anti-radiation
	onAttacker(attacker, function(controller)
		controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.OPEN_FIRE)
		controller:pushTask({ id = attack.id, params = attack.params })
	end)
	local attackerUnit = attacker:getName() .. "-1"
	if not Hotload.waitFor(function()
		return Wd.fired(shots, attackerUnit) > 0
	end, 180) then
		ctx.invalid("the attacker never fired its HARM")
	end
	local harm
	for _, shot in ipairs(shots) do
		if shot.initiator == attackerUnit then
			harm = shot.object
		end
	end
	-- the HARM away, it circles the route's end: inside the site's kill zone, so that the site still
	-- has it to engage, rather than wherever it fired from, which can lie at the zone's edge
	onAttacker(attacker, function(controller)
		controller:setTask({
			id = "Orbit",
			params = {
				pattern = "Circle",
				point = { x = hold.x, y = hold.y },
				speed = SPEED,
				altitude = ALTITUDE,
			},
		})
	end)
	return shots, attacker, harm
end

return H
