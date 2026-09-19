--- In-sim check for the last line of defense and the coverage refresh.
--
-- This is the scenario FEAT-LAST-LINE-OF-DEFENSE asks for: a SAM site held dark by the network,
-- and an early warning radar placed so far away that it covers the site on Skynet's flat 2D
-- geometry while seeing nothing at all of an aircraft on the deck. It is the shape of the report
-- this whole lot came from — fly under the EWR's horizon and no battery reacts.
--
-- Everything the check needs is driven from outside through VEAF's dcs-bridge, so nobody has to
-- fly: SKYNET_TEST.launchIntruder() puts an aircraft on a run across the site, and
-- SKYNET_TEST.status() prints what the network is doing. The mission carries no player task.
--
-- The check must be able to fail BOTH ways:
--   * the site lights up when the intruder crosses its last-line-of-defense radius, and
--   * it falls silent once the persistence has run out after the intruder leaves.
-- A run that only ever shows one of the two proves nothing.

do
	SKYNET_TEST = {}

	SKYNET_TEST.SAM_PREFIX = "TEST-SAM"
	SKYNET_TEST.EW_PREFIX = "TEST-EW"
	SKYNET_TEST.SAM_GROUP = "TEST-SAM-SA-6"
	SKYNET_TEST.EW_UNIT = "TEST-EW-far"
	SKYNET_TEST.INTRUDER_GROUP = "TEST-INTRUDER"

	local function log(message)
		env.info("SKYNET-TEST: " .. message)
		trigger.action.outText("SKYNET-TEST: " .. message, 15)
	end

	--- Strips the demo mission back to the two groups this check needs.
	--
	-- This mission is a copy of skynet-test-persian-gulf.miz, which carries a full demo IADS: an
	-- SA-10, a jammer, a blue network. None of it belongs in a measurement, and an SA-10 would
	-- shoot the intruder down two hundred kilometres before it reached the site under test. Rather
	-- than hand-editing the mission tables, the scenario removes at startup everything it did not
	-- put there.
	local function stripEverythingButTheTest()
		local removed = 0
		local categories =
			{ Group.Category.AIRPLANE, Group.Category.HELICOPTER, Group.Category.GROUND, Group.Category.SHIP }
		for _, coalitionID in pairs(coalition.side) do
			for i = 1, #categories do
				local groups = coalition.getGroups(coalitionID, categories[i]) or {}
				for _, group in pairs(groups) do
					if group and group:isExist() then
						local name = group:getName()
						if string.sub(name, 1, 5) ~= "TEST-" then
							group:destroy()
							removed = removed + 1
						end
					end
				end
			end
		end
		return removed
	end

	--- The two elements under test, looked up once the network is built.
	function SKYNET_TEST.samSite()
		return SKYNET_TEST.iads:getSAMSiteByGroupName(SKYNET_TEST.SAM_GROUP)
	end

	function SKYNET_TEST.ewRadar()
		return SKYNET_TEST.iads:getEarlyWarningRadarByUnitName(SKYNET_TEST.EW_UNIT)
	end

	--- The geometry the check rests on, read back from the running mission rather than assumed.
	--
	-- Three numbers decide whether this scenario can prove anything at all: the EWR has to cover
	-- the site (so the network holds it dark), the site's radius has to be smaller than its own
	-- firing range (or a woken site refuses the contact on its go-live constraints), and the
	-- intruder has to fly well below the EWR's horizon.
	function SKYNET_TEST.geometry()
		local samSite = SKYNET_TEST.samSite()
		local ewRadar = SKYNET_TEST.ewRadar()
		if samSite == nil or ewRadar == nil then
			return "geometry: the site or the radar is missing -- check the group names in the mission"
		end
		local samPosition = samSite:getElementPosition()
		local ewPosition = ewRadar:getElementPosition()
		--a position is nil when the DCS units are gone: the group failed to spawn, or it has been
		--destroyed. That is the case this line exists to explain, so it must not raise on it
		if samPosition == nil or ewPosition == nil then
			return string.format(
				"geometry: no position for %s -- its DCS units do not exist (spawned in water? destroyed?)",
				samPosition == nil and "the site" or "the EWR"
			)
		end
		local separation = samSite:getDistanceToUnit(samPosition, ewPosition)
		local parents = samSite:getParentRadars()
		return string.format(
			"geometry: EWR is %.1f km from the site | EWR detection range %.1f km | site radius %.1f km | site has %d parent radar(s) | ground under site=%s, under EWR=%s",
			separation / 1000,
			ewRadar:getMaxDetectionRange() / 1000,
			samSite:getLastLineOfDefenceRadius() / 1000,
			#parents,
			SKYNET_TEST.surfaceUnder(samPosition),
			SKYNET_TEST.surfaceUnder(ewPosition)
		)
	end

	--- What the two groups are standing on.
	--
	-- Their positions were derived from groups the demo mission already had, so the terrain is
	-- known good -- but they were nudged a couple of kilometres to avoid spawning on top of them,
	-- and a couple of kilometres on this map can be water. Reported rather than assumed: a battery
	-- in the sea explains an otherwise baffling run in one line.
	function SKYNET_TEST.surfaceUnder(position)
		if position == nil then
			return "unknown"
		end
		local names = { [1] = "land", [2] = "shallow water", [3] = "water", [4] = "road", [5] = "runway" }
		local surface = land.getSurfaceType({ x = position.x, y = position.z })
		return names[surface] or ("type " .. tostring(surface))
	end

	--- One line per element, plus where the intruder is. This is what a run is read from.
	function SKYNET_TEST.status()
		local lines = { string.format("t=%.0fs", timer.getTime()) }
		local samSite = SKYNET_TEST.samSite()
		if samSite then
			--nil once the battery's DCS units are gone. Unguarded it raises, and this function is
			--the body of the scheduled watch: DCS would drop the schedule and the run would go
			--blind from that second on, looking exactly like a run where nothing happened
			local samPosition = samSite:getElementPosition()
			local distance = "no intruder"
			local intruder = SKYNET_TEST.intruderUnit()
			if samPosition == nil then
				distance = "site has no position (destroyed?)"
			elseif intruder then
				distance =
					string.format("%.2f km", samSite:getDistanceToUnit(samPosition, intruder:getPosition().p) / 1000)
			end
			table.insert(
				lines,
				string.format(
					"SAM %s: ACTIVE=%s AUTONOMOUS=%s targetsInRange=%s freshReport=%s radius=%.1fkm intruderAt=%s",
					samSite:getDCSName(),
					tostring(samSite:isActive()),
					tostring(samSite:getAutonomousState()),
					tostring(samSite:hasTargetsInRange()),
					tostring(samSite:hasFreshReportedContact()),
					samSite:getLastLineOfDefenceRadius() / 1000,
					distance
				)
			)
		end
		local ewRadar = SKYNET_TEST.ewRadar()
		if ewRadar then
			table.insert(
				lines,
				string.format(
					"EWR %s: ACTIVE=%s covers %d site(s)",
					ewRadar:getDCSName(),
					tostring(ewRadar:isActive()),
					#ewRadar:getChildRadars()
				)
			)
		end
		return table.concat(lines, "\n")
	end

	function SKYNET_TEST.intruderUnit()
		local group = Group.getByName(SKYNET_TEST.INTRUDER_GROUP)
		if group == nil or group:isExist() == false then
			return nil
		end
		local units = group:getUnits()
		if units == nil or units[1] == nil or units[1]:isExist() == false then
			return nil
		end
		return units[1]
	end

	--- Puts a hostile aircraft on a straight run across the site, low enough to stay unseen.
	--
	-- approachKm is where the run starts and ends, measured from the site along the north/south
	-- axis, and altitudeMeters is AGL. The defaults fly from 40 km south to 40 km north at 150 m,
	-- which crosses a 10-15 km radius in about two minutes at 200 m/s and leaves it cleanly --
	-- the departure is the half of the check that proves the persistence expires.
	--
	-- 150 m rather than the deck: at 106 km the aircraft stays under a ground radar's horizon up to
	-- roughly 400 m, so there is no need to spend the margin on flying an AI into a ridge. Anything
	-- below ~400 m keeps the premise of the scenario.
	--
	-- The aircraft is told to do nothing, to hold fire and to ignore threats, and it is set
	-- immortal. All four are properties of the measurement, not of the feature: an intruder that
	-- attacks the battery, evades its missiles or dies leaves its run, and a run off its track
	-- measures neither the radius nor the persistence.
	function SKYNET_TEST.launchIntruder(approachKm, altitudeMeters, speedMS)
		approachKm = approachKm or 40
		altitudeMeters = altitudeMeters or 150
		speedMS = speedMS or 200

		local samSite = SKYNET_TEST.samSite()
		if samSite == nil then
			return "no SAM site under test; nothing to fly at"
		end
		SKYNET_TEST.removeIntruder()

		local center = samSite:getElementPosition()
		local approach = approachKm * 1000
		--x is north on a DCS map, z is east; the mission tables call that second axis y
		local start = { x = center.x - approach, y = center.z }
		local finish = { x = center.x + approach, y = center.z }

		local function waypoint(point)
			return {
				["x"] = point.x,
				["y"] = point.y,
				["alt"] = altitudeMeters,
				["alt_type"] = "RADIO",
				["type"] = "Turning Point",
				["action"] = "Turning Point",
				["speed"] = speedMS,
				["speed_locked"] = true,
				["ETA"] = 0,
				["ETA_locked"] = false,
				["formation_template"] = "",
				["task"] = { ["id"] = "ComboTask", ["params"] = { ["tasks"] = {} } },
			}
		end

		local groupData = {
			["name"] = SKYNET_TEST.INTRUDER_GROUP,
			--"Nothing", not "CAS": a CAS flight engages targets of opportunity, and the nearest one
			--is the battery whose behaviour is being measured
			["task"] = "Nothing",
			["taskSelected"] = true,
			["visible"] = false,
			["hidden"] = false,
			["uncontrolled"] = false,
			["start_time"] = 0,
			["route"] = { ["points"] = { waypoint(start), waypoint(finish) } },
			["units"] = {
				{
					["name"] = SKYNET_TEST.INTRUDER_GROUP .. "-1",
					["type"] = "A-10A",
					["skill"] = "Excellent",
					["x"] = start.x,
					["y"] = start.y,
					["alt"] = altitudeMeters,
					["alt_type"] = "RADIO",
					["speed"] = speedMS,
					["heading"] = 0,
					["payload"] = { ["fuel"] = 5000, ["flare"] = 120, ["chaff"] = 240, ["gun"] = 100, ["pylons"] = {} },
					["callsign"] = { [1] = 1, [2] = 1, [3] = 1, ["name"] = "Enfield11" },
				},
			},
		}

		--USA, the blue side: Skynet's coalition filter is what decides this aircraft is hostile
		local group = coalition.addGroup(country.id.USA, Group.Category.AIRPLANE, groupData)
		if group == nil then
			return "the intruder did not spawn"
		end
		log(
			string.format(
				"intruder away: %.0f km south of the site, %.0f m AGL, %.0f m/s [%s]",
				approachKm,
				altitudeMeters,
				speedMS,
				table.concat(SKYNET_TEST.pinTheIntruderToItsTrack(group), ", ")
			)
		)
		return SKYNET_TEST.status()
	end

	--- Keeps the intruder flying the straight line the measurement assumes.
	--
	-- Two controller options and one command, each reported rather than swallowed: a scenario whose
	-- aircraft quietly kept its default rules of engagement would produce a run that looks valid
	-- and measures something else.
	function SKYNET_TEST.pinTheIntruderToItsTrack(group)
		local controller = group:getController()
		local settings = {
			{
				name = "hold fire",
				apply = function()
					controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD)
				end,
			},
			{
				name = "ignore threats",
				apply = function()
					controller:setOption(
						AI.Option.Air.id.REACTION_ON_THREAT,
						AI.Option.Air.val.REACTION_ON_THREAT.NO_REACTION
					)
				end,
			},
			{
				--a woken SA-6 fires; an intruder that dies cannot demonstrate the persistence expiring
				name = "immortal",
				apply = function()
					controller:setCommand({ id = "SetImmortal", params = { value = true } })
				end,
			},
		}
		local applied = {}
		for i = 1, #settings do
			local ok, err = pcall(settings[i].apply)
			if ok then
				table.insert(applied, settings[i].name)
			else
				log("could not set '" .. settings[i].name .. "' on the intruder: " .. tostring(err))
			end
		end
		return applied
	end

	--- Writes the status line into dcs.log every few seconds, so the run can be read back afterwards.
	--
	-- The two moments that matter -- the site lighting up as the intruder crosses the radius, and
	-- falling silent once the persistence expires -- are seconds wide. Polling them from outside
	-- would miss one; the log does not.
	function SKYNET_TEST.startWatch(intervalSeconds)
		intervalSeconds = intervalSeconds or 5
		SKYNET_TEST.stopWatch()
		SKYNET_TEST.watchID = timer.scheduleFunction(function(_, time)
			env.info("SKYNET-TEST-WATCH:\n" .. SKYNET_TEST.status())
			return time + intervalSeconds
		end, nil, timer.getTime() + intervalSeconds)
		return "watch started, every " .. intervalSeconds .. "s"
	end

	function SKYNET_TEST.stopWatch()
		if SKYNET_TEST.watchID then
			timer.removeFunction(SKYNET_TEST.watchID)
			SKYNET_TEST.watchID = nil
			return "watch stopped"
		end
		return "no watch running"
	end

	function SKYNET_TEST.removeIntruder()
		local group = Group.getByName(SKYNET_TEST.INTRUDER_GROUP)
		if group and group:isExist() then
			group:destroy()
			return "intruder removed"
		end
		return "no intruder to remove"
	end

	-- Build ---------------------------------------------------------------------------------------

	local removed = stripEverythingButTheTest()

	SKYNET_TEST.iads = SkynetIADS:create("LAST-LINE-OF-DEFENCE-TEST")

	local iadsDebug = SKYNET_TEST.iads:getDebugSettings()
	iadsDebug.IADSStatus = true
	iadsDebug.radarWentDark = true
	iadsDebug.radarWentLive = true
	iadsDebug.contacts = true
	iadsDebug.samSiteStatusEnvOutput = true
	iadsDebug.earlyWarningRadarStatusEnvOutput = true

	SKYNET_TEST.iads:addEarlyWarningRadarsByPrefix(SKYNET_TEST.EW_PREFIX)
	SKYNET_TEST.iads:addSAMSitesByPrefix(SKYNET_TEST.SAM_PREFIX)
	--the site must be one the network holds dark: that is the whole premise of the report
	SKYNET_TEST.iads:activate()

	log(string.format("network up, %d demo group(s) removed", removed))
	log(SKYNET_TEST.geometry())
	--on from the start: a run is read back out of the log, and a watch somebody forgot to start
	--is a run to fly again
	SKYNET_TEST.startWatch(5)
end
