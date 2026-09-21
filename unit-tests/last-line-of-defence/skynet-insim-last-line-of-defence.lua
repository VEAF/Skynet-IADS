--- In-sim checks for the last line of defense and the coverage refresh.
--
-- Two runs, because FEAT-LAST-LINE-OF-DEFENSE has two mechanisms, and neither can be proved by a
-- test against a stub: the failure mode that matters is a piece of code that is perfectly tested
-- and never called by the cycle.
--
-- **Run 1, the last line of defense.** A SAM site held dark by the network, and an early warning
-- radar placed so far away that it covers the site on Skynet's flat 2D geometry while seeing
-- nothing at all of an aircraft on the deck. It is the shape of the report this whole lot came
-- from — fly under the EWR's horizon and no battery reacts. It starts with the mission;
-- SKYNET_TEST.launchIntruder() flies it.
--
-- **Run 2, coverage follows what moves.** A battery whose only parent is an AWACS, and an AWACS
-- that flies away from it. Started on demand by SKYNET_TEST.startCoverageRun(), in a network of
-- its own.
--
-- Everything is driven from outside through VEAF's dcs-bridge, so nobody has to fly. The mission
-- carries no player task.
--
-- **Each run also answers in one word.** SKYNET_TEST.verdict() and SKYNET_TEST.coverageVerdict()
-- return IDLE, RUNNING, PASS or FAIL with a reason, which is what `build-tools/run-smoke.py` polls.
-- Before that, reading a run meant reading the log by eye; the watches still write those lines, and
-- they remain the way to see *how* a run went rather than whether it passed.
--
-- Each check must be able to fail BOTH ways. For run 1: the site lights up when the intruder
-- crosses its last-line-of-defense radius, AND it falls silent once the persistence has run out.
-- For run 2: the battery is held non-autonomous while the AWACS covers it, AND it is handed back
-- once the AWACS has left. A run that only ever shows one of the two proves nothing.

do
	SKYNET_TEST = {}

	SKYNET_TEST.SAM_PREFIX = "TEST-SAM"
	SKYNET_TEST.EW_PREFIX = "TEST-EW"
	SKYNET_TEST.SAM_GROUP = "TEST-SAM-SA-6"
	SKYNET_TEST.EW_UNIT = "TEST-EW-far"
	SKYNET_TEST.INTRUDER_GROUP = "TEST-INTRUDER"

	--- How long a run may take before its verdict stops saying RUNNING and says what is missing.
	--
	-- Ten minutes. Run 1 flies 80 km at 200 m/s, so seven is the honest figure and this leaves room
	-- for a slow load. The runner has a timeout of its own, but a timeout there can only say "still
	-- RUNNING"; a deadline here can say *which half* never happened, which is the whole difference
	-- between a report somebody can act on and one they have to reproduce.
	SKYNET_TEST.RUN_DEADLINE = 600

	--- What each run has actually been seen to do, accumulated by its watch.
	--
	-- A verdict cannot be computed on demand from the current state, because both runs are about a
	-- **transition**: a battery that is dark right now is either one that never lit or one that has
	-- correctly gone quiet again, and those are the pass and the fail. So the watch records the
	-- edges as they go past, and the verdict reads the record.
	SKYNET_TEST.run1 = { started = nil, wasActive = nil, sawLit = false, sawDark = false }
	SKYNET_TEST.run2 = { started = nil, wasAutonomous = nil, sawHeld = false, sawHandedBack = false }

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
		--a fresh measurement per launch. The watch has been recording since mission start, so
		--without this a second run would inherit the first one's edges and pass on them
		SKYNET_TEST.run1 = { started = timer.getTime(), wasActive = nil, sawLit = false, sawDark = false }
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
	--- Records run 1's two edges: the site lighting up, and falling silent again afterwards.
	--
	-- Called from the watch, so it must not raise: the watch is a scheduled function, and DCS drops
	-- a schedule whose body errors. The run would then go blind from that second on and look exactly
	-- like a run where nothing happened -- which is the failure this whole file exists to detect.
	local function recordRun1()
		local samSite = SKYNET_TEST.samSite()
		if samSite == nil then
			return
		end
		local active = samSite:isActive()
		local record = SKYNET_TEST.run1
		if record.wasActive == false and active then
			record.sawLit = true
		elseif record.wasActive and not active and record.sawLit then
			--only after a light-up. A site that was never lit cannot have gone quiet, and counting
			--the initial dark state as "went dark" would pass a run in which nothing happened at all
			record.sawDark = true
		end
		record.wasActive = active
	end

	function SKYNET_TEST.startWatch(intervalSeconds)
		intervalSeconds = intervalSeconds or 5
		SKYNET_TEST.stopWatch()
		SKYNET_TEST.watchID = timer.scheduleFunction(function(_, time)
			pcall(recordRun1)
			env.info("SKYNET-TEST-WATCH:\n" .. SKYNET_TEST.status())
			return time + intervalSeconds
		end, nil, timer.getTime() + intervalSeconds)
		return "watch started, every " .. intervalSeconds .. "s"
	end

	--- Run 1's verdict, as one word, for `build-tools/run-smoke.py`.
	--
	-- **Returns a word, never a boolean and never a table.** dcs-bridge's `handleExec` ends on
	-- `tostring(result ~= nil and result or "")`, and that idiom turns a `false` into the empty
	-- string -- indistinguishable from nil, from a crash, and from success. A runner cannot tell
	-- those apart, so the scenario never puts it in that position.
	function SKYNET_TEST.verdict()
		local record = SKYNET_TEST.run1
		if record.started == nil then
			return "IDLE"
		end
		if record.sawLit and record.sawDark then
			return "PASS"
		end
		if timer.getTime() - record.started < SKYNET_TEST.RUN_DEADLINE then
			return "RUNNING"
		end
		if not record.sawLit then
			return "FAIL: the site never lit up -- the last line of defence did not wake it"
		end
		return "FAIL: the site lit up but never went quiet again -- the persistence never expired"
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

	-- The second check: coverage follows what moves -------------------------------------------------
	--
	-- A battery whose only parent is an AWACS, and an AWACS that flies away from it. Before this lot
	-- the incremental rebuild only ever added, so that battery kept the parent for the rest of the
	-- mission and stayed non-autonomous with the aircraft at the other end of the map. The periodic
	-- sweep has to take it back.
	--
	-- It runs in a network of its own, so neither check can disturb the other, and it is not started
	-- at load: it spawns two groups and builds a second IADS, which has no business happening in a
	-- mission somebody opened to look at the first check.
	--
	-- The geometry rests on two measured numbers rather than guessed ones. The A-50's detection range
	-- is 204.5 km, read back in game; a sweep only rebuilds for an element that has moved more than
	-- 10 NM (18.5 km) since its last rebuild. So the AWACS starts at 190 km -- inside its range,
	-- therefore covering -- and flies straight away from the battery: the range is crossed at
	-- 204.5 km and the movement threshold at 208.6 km, and the first sweep after both drops the link.

	SKYNET_TEST.COVERAGE_SAM_GROUP = "TEST2-SAM-coverage"
	SKYNET_TEST.COVERAGE_AWACS_UNIT = "TEST2-EW-awacs-1"

	local function airborneWaypoint(point, altitude, speed)
		return {
			["x"] = point.x,
			["y"] = point.y,
			["alt"] = altitude,
			["alt_type"] = "BARO",
			["type"] = "Turning Point",
			["action"] = "Turning Point",
			["speed"] = speed,
			["speed_locked"] = true,
			["ETA"] = 0,
			["ETA_locked"] = false,
			["formation_template"] = "",
			["task"] = { ["id"] = "ComboTask", ["params"] = { ["tasks"] = {} } },
		}
	end

	--- Distance, parents and autonomy in one line: the three things this run turns on.
	function SKYNET_TEST.coverageStatus()
		if SKYNET_TEST.iads2 == nil then
			return "coverage: not started -- call SKYNET_TEST.startCoverageRun()"
		end
		local site = SKYNET_TEST.iads2:getSAMSiteByGroupName(SKYNET_TEST.COVERAGE_SAM_GROUP)
		local awacs = SKYNET_TEST.iads2:getEarlyWarningRadarByUnitName(SKYNET_TEST.COVERAGE_AWACS_UNIT)
		if site == nil or awacs == nil then
			return "coverage: the battery or the AWACS is missing"
		end
		local sitePosition = site:getElementPosition()
		local awacsPosition = awacs:getElementPosition()
		if sitePosition == nil or awacsPosition == nil then
			return "coverage: no position -- the battery or the AWACS no longer exists"
		end
		return string.format(
			"COVERAGE: AWACS at %.1f km (range %.1f km) | battery AUTONOMOUS=%s parents=%d | AWACS covers %d site(s)",
			site:getDistanceToUnit(sitePosition, awacsPosition) / 1000,
			awacs:getMaxDetectionRange() / 1000,
			tostring(site:getAutonomousState()),
			#site:getParentRadars(),
			#awacs:getChildRadars()
		)
	end

	--- Records run 2's two edges: the battery held by the AWACS, and handed back once it leaves.
	--
	-- Same nil-safety obligation as recordRun1: this runs inside a scheduled function.
	local function recordRun2()
		if SKYNET_TEST.iads2 == nil then
			return
		end
		local site = SKYNET_TEST.iads2:getSAMSiteByGroupName(SKYNET_TEST.COVERAGE_SAM_GROUP)
		if site == nil then
			return
		end
		local autonomous = site:getAutonomousState()
		local record = SKYNET_TEST.run2
		if not autonomous then
			--held by the network: the AWACS is a parent and the battery is not on its own
			record.sawHeld = true
		elseif record.wasAutonomous == false and record.sawHeld then
			record.sawHandedBack = true
		end
		record.wasAutonomous = autonomous
	end

	function SKYNET_TEST.startCoverageWatch(intervalSeconds)
		intervalSeconds = intervalSeconds or 5
		if SKYNET_TEST.coverageWatchID then
			timer.removeFunction(SKYNET_TEST.coverageWatchID)
		end
		SKYNET_TEST.coverageWatchID = timer.scheduleFunction(function(_, time)
			pcall(recordRun2)
			env.info("SKYNET-TEST-" .. SKYNET_TEST.coverageStatus())
			return time + intervalSeconds
		end, nil, timer.getTime() + intervalSeconds)
		return "coverage watch started, every " .. intervalSeconds .. "s"
	end

	--- Run 2's verdict, as one word. See SKYNET_TEST.verdict for why it is never a boolean.
	function SKYNET_TEST.coverageVerdict()
		local record = SKYNET_TEST.run2
		if record.started == nil then
			return "IDLE"
		end
		if record.sawHeld and record.sawHandedBack then
			return "PASS"
		end
		if timer.getTime() - record.started < SKYNET_TEST.RUN_DEADLINE then
			return "RUNNING"
		end
		if not record.sawHeld then
			return "FAIL: the battery was never held -- the AWACS never became its parent"
		end
		return "FAIL: the battery was held and never handed back -- the coverage refresh did not purge"
	end

	--- Spawns the battery and its AWACS, wires them into a second network, and starts watching.
	--
	-- separationKm is how far the AWACS starts from the battery; the default puts it inside its own
	-- detection range and close enough to the edge that one and a half minutes of flight crosses it.
	function SKYNET_TEST.startCoverageRun(separationKm)
		separationKm = separationKm or 190
		--a position the demo mission already carried a SAM on, so the terrain is known to take one,
		--and far enough from TEST-EW-far (633 km) that the fixed radar cannot be a second parent --
		--a battery with two parents would not change autonomy when one of them leaves
		local battery = { x = -108202, y = 516834 }
		local awacsStart = { x = battery.x, y = battery.y - separationKm * 1000 }
		local awacsEnd = { x = battery.x, y = awacsStart.y - 100000 }

		local samGroup = {
			["name"] = SKYNET_TEST.COVERAGE_SAM_GROUP,
			["task"] = "Ground Nothing",
			["taskSelected"] = true,
			["hidden"] = false,
			["units"] = {
				{
					["name"] = "TEST2-SAM-radar",
					["type"] = "Kub 1S91 str",
					["x"] = battery.x,
					["y"] = battery.y,
					["heading"] = 0,
					["skill"] = "Excellent",
				},
				{
					["name"] = "TEST2-SAM-ln-1",
					["type"] = "Kub 2P25 ln",
					["x"] = battery.x + 60,
					["y"] = battery.y,
					["heading"] = 0,
					["skill"] = "Excellent",
				},
			},
			["route"] = {
				["points"] = {
					{
						["x"] = battery.x,
						["y"] = battery.y,
						["type"] = "Turning Point",
						["action"] = "Off Road",
						["speed"] = 0,
					},
				},
			},
		}

		local awacsGroup = {
			["name"] = "TEST2-EW-awacs",
			["task"] = "AWACS",
			["taskSelected"] = true,
			["hidden"] = false,
			["uncontrolled"] = false,
			["start_time"] = 0,
			["route"] = {
				["points"] = { airborneWaypoint(awacsStart, 8000, 220), airborneWaypoint(awacsEnd, 8000, 220) },
			},
			["units"] = {
				{
					["name"] = SKYNET_TEST.COVERAGE_AWACS_UNIT,
					["type"] = "A-50",
					["skill"] = "Excellent",
					["x"] = awacsStart.x,
					["y"] = awacsStart.y,
					["alt"] = 8000,
					["alt_type"] = "BARO",
					["speed"] = 220,
					["heading"] = 0,
					["payload"] = { ["fuel"] = 60000, ["flare"] = 0, ["chaff"] = 0, ["gun"] = 0, ["pylons"] = {} },
					["callsign"] = { [1] = 2, [2] = 1, [3] = 1, ["name"] = "Overlord21" },
				},
			},
		}

		if coalition.addGroup(country.id.RUSSIA, Group.Category.GROUND, samGroup) == nil then
			return "the battery did not spawn"
		end
		if coalition.addGroup(country.id.RUSSIA, Group.Category.AIRPLANE, awacsGroup) == nil then
			return "the AWACS did not spawn"
		end

		SKYNET_TEST.iads2 = SkynetIADS:create("COVERAGE-TEST")
		local coverageDebug = SKYNET_TEST.iads2:getDebugSettings()
		coverageDebug.radarWentDark = true
		coverageDebug.radarWentLive = true
		SKYNET_TEST.iads2:addEarlyWarningRadar(SKYNET_TEST.COVERAGE_AWACS_UNIT)
		SKYNET_TEST.iads2:addSAMSite(SKYNET_TEST.COVERAGE_SAM_GROUP)
		SKYNET_TEST.iads2:activate()

		SKYNET_TEST.run2 = { started = timer.getTime(), wasAutonomous = nil, sawHeld = false, sawHandedBack = false }
		SKYNET_TEST.startCoverageWatch(5)
		log("coverage run started")
		return SKYNET_TEST.coverageStatus()
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
