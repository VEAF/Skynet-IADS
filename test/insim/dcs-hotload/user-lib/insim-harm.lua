-- What the harm-* scenarios share: the probes they watch, the shooter that fires the HARM, the waker
-- that gives the network a target to wake a site for, and the rule for when a scenario has watched
-- long enough.
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

-- Starts the watch every harm-* scenario reads (`activeSite`, `defending`, `harm` on the judged site;
-- `activePointDefence` and `pointDefenceLatched` when `pointDefence` is given), sampled every second,
-- plus the probes in `more`, a table as insim-watch takes it. Returns the watch.
function H.watch(ctx, site, pointDefence, more)
	local probes = {
		activeSite = function()
			return site:isActive()
		end,
		defending = function()
			return site:isDefendingHARM()
		end,
		harm = function()
			return site:getNumberOfObjectsItentifiedAsHARMS() > 0
		end,
	}
	if pointDefence then
		probes.activePointDefence = function()
			return pointDefence:isActive()
		end
		probes.pointDefenceLatched = function()
			return pointDefence:getIsPointDefending()
		end
	end
	for name, probe in pairs(more or {}) do
		probes[name] = probe
	end
	return Hotload.load("insim-watch").start(ctx, probes, 1)
end

-- Fires one HARM at the group `<scenario>/<targetRole>`, standing on `zone`, from `bearing` (degrees,
-- 0 north): an F-16 spawned 80 km out flies in and fires on the way. Invisible, so that only its HARM
-- is ever a contact; immortal, so that its run ends with a shot. Returns the HARM, a weapon object
-- whose `isExist()` tells when it has ended. The phase ends as `invalid` if it never fires.
--
-- The target is made immortal first. What a scenario judges is Skynet's reaction to the HARM, not
-- whether the DCS AI shoots it down: it often does not, and a HARM that kills a search radar sends
-- the site dark for a reason that is not Skynet's (seen with an SA-10, DCS 2.9, 2026-11-22).
function H.shoot(ctx, targetRole, zone, bearing)
	local target = ctx.name .. "/" .. targetRole
	local group = Group.getByName(target)
	if not group then
		ctx.invalid("no group " .. target .. " to shoot at")
	end
	group:getController():setCommand({ id = "SetImmortal", params = { value = true } })
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
		waypointTasks = { Wd.attackTask(target, 32768) }, -- anti-radiation
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

-- Gives the network a target to wake the site `<scenario>/<siteRole>` for: a visible, immortal F-16
-- with nothing to fire, which flies in on `bearing` from `zone` and circles `km` from the zone's
-- centre. Spawned farther out, so that it never comes closer than its orbit. A site set to go live in
-- its search range, with the orbit beyond its missiles' reach, is then live on a real track without
-- firing a missile. Waits for `watch`'s `activeSite` to go `{false, true}`, then 20 s more, and ends
-- the phase as `invalid` if the site never woke or fired: a site that fired at the waker may have
-- no missile left for the HARM. Returns every shot fired from the waker's spawn on.
function H.wake(ctx, watch, siteRole, zone, bearing, km)
	local shots = Wd.recordShots(ctx)
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
	if not watch:waitFor("activeSite", { false, true }, 300) then
		ctx.invalid("the network never woke " .. siteRole .. " for the waker")
	end
	Hotload.wait(20)
	if H.firedBy(shots, ctx.name .. "/" .. siteRole .. "-") > 0 then
		ctx.invalid(siteRole .. " fired at the waker")
	end
	return shots
end

-- Watches on until the engagement is over, and returns the watch's report: the HARM has ended
-- (shot down, on the ground, or flown past), every one of `sites` has forgotten it and is out of
-- any silence, every point defence among them has gone dark again once released, and `settle`
-- seconds more have passed for a late flip to show. A check made before
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
			-- released with the last HARM, it goes dark on the network's next cycle
			if site:getIsAPointDefence() and site:isActive() then
				return false
			end
		end
		return true
	end, 180)
	Hotload.wait(settle)
	return watch:report()
end

return H
