-- The HARM attack of the harm-engaging-* scenarios: a visible, immortal F-16 flies straight at a
-- site with its weapons held, fires its HARM only once the site has fired at it, so that the HARM
-- arrives on a site that is engaging, and then circles where it is.
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
