--- Reusable fixture builders for the standalone Lua test suite. Uses the
--- dcsStub globals; no os/io. SAM group compositions are keyed to
--- skynet-iads-source/skynet-iads-supported-types.lua (samTypesDB).

local F = {}

local RADAR_RANGE_M = 120000

local function searchRadarSensors()
	-- shape iterated by SkynetIADSSAMSearchRadar:setupRangeData (data[i] -> subEntries[j])
	return {
		{
			{
				type = Unit.SensorType.RADAR,
				detectionDistanceAir = {
					upperHemisphere = { headOn = RADAR_RANGE_M },
					lowerHemisphere = { headOn = RADAR_RANGE_M },
				},
			},
		},
	}
end

local function launcherAmmo(count)
	return {
		{
			desc = {
				category = Weapon.Category.MISSILE,
				-- real SA-2 data (see the trailing comment block in
				-- skynet-iads-source/skynet-iads-sam-launcher.lua). altMin >= altMax, so
				-- setupRangeData takes altMin: maximumRange stays 40000 m.
				rangeMaxAltMin = 40000,
				rangeMaxAltMax = 30000,
				altMax = 12000,
			},
			count = count,
		},
	}
end

--- What a radar-guided gun carries instead of missiles: shells, in two belts.
---
--- Shape and figures are the ZSU-23-4's, from the .miz suite's own
--- testShutDownShilkaWhenOutOfAmmo: 23 mm AP and 23 mm HE, category SHELL rather than MISSILE, and
--- no range fields at all — which is what sends SkynetIADSSAMLauncher:setupRangeData() back to the
--- search radar's sensors for the range, the branch its comment calls "all in one units like the
--- shilka".
local function launcherShells(armourPiercing, highExplosive)
	return {
		{ desc = { category = Weapon.Category.SHELL, displayName = "23mm AP" }, count = armourPiercing },
		{ desc = { category = Weapon.Category.SHELL, displayName = "23mm HE" }, count = highExplosive },
	}
end

-- natoShort -> ordered unit specs (types verbatim from samTypesDB)
local SAM_COMPOSITIONS = {
	["SA-6"] = function(groupName)
		return {
			{ name = groupName .. "-sr", type = "Kub 1S91 str", sensors = searchRadarSensors() },
			{ name = groupName .. "-ln1", type = "Kub 2P25 ln", ammo = launcherAmmo(3) },
			{ name = groupName .. "-ln2", type = "Kub 2P25 ln", ammo = launcherAmmo(3) },
		}
	end,
	["SA-2"] = function(groupName)
		return {
			{ name = groupName .. "-sr", type = "p-19 s-125 sr", sensors = searchRadarSensors() },
			{ name = groupName .. "-tr", type = "SNR_75V", sensors = searchRadarSensors() },
			{ name = groupName .. "-ln1", type = "S_75M_Volhov", ammo = launcherAmmo(3) },
			{ name = groupName .. "-ln2", type = "S_75M_Volhov", ammo = launcherAmmo(3) },
		}
	end,
	-- The two compositions below share launcherAmmo(), whose missile data is the real SA-2's: the
	-- unit *types* are each SAM's own, so samTypesDB recognises them, but the range and altitude a
	-- launcher reports are an SA-2's. Nothing asserts an SA-10 or SA-11 range today. A test that
	-- means to needs its own ammo table here first, or it will pin an SA-2's 40 km reach on an
	-- S-300.
	--
	-- samTypesDB "S-300": search radar, tracking radar and launcher, plus a command post
	-- marked required that setupElements() never looks at (it reads searchRadar, launchers and
	-- trackingRadar only), so the fixture leaves it out. can_engage_harm is true for this type,
	-- which is why it is the one the HARM tests use.
	["SA-10"] = function(groupName)
		return {
			{ name = groupName .. "-sr", type = "S-300PS 40B6MD sr", sensors = searchRadarSensors() },
			{ name = groupName .. "-tr", type = "S-300PS 40B6M tr", sensors = searchRadarSensors() },
			{ name = groupName .. "-ln1", type = "S-300PS 5P85D ln", ammo = launcherAmmo(3) },
		}
	end,
	-- samTypesDB "Buk": a search radar and a launcher, no tracking radar.
	["SA-11"] = function(groupName)
		return {
			{ name = groupName .. "-sr", type = "SA-11 Buk SR 9S18M1", sensors = searchRadarSensors() },
			{ name = groupName .. "-ln1", type = "SA-11 Buk LN 9A310M1", ammo = launcherAmmo(3) },
		}
	end,
	-- samTypesDB "Osa": one vehicle that is its own search radar and its own launcher, so
	-- setupElements() finds the same unit twice and the site has one radar, one launcher and no
	-- tracking radar. The fixture therefore carries both sensors and ammo on a single unit.
	["SA-8"] = function(groupName)
		return {
			{
				name = groupName .. "-1",
				type = "Osa 9A33 ln",
				sensors = searchRadarSensors(),
				ammo = launcherAmmo(3),
			},
		}
	end,
	-- samTypesDB "Tor": another all-in-one vehicle, and the one the point-defence tests use — it is
	-- a short-range piece with can_engage_harm set, which is what a SAM site puts around itself to
	-- shoot at the missiles aimed at its radar.
	["SA-15"] = function(groupName)
		return {
			{
				name = groupName .. "-1",
				type = "Tor 9A331",
				sensors = searchRadarSensors(),
				ammo = launcherAmmo(3),
			},
		}
	end,
	-- samTypesDB "ZSU-23-4 Shilka": the same all-in-one shape as the SA-8, but it shoots shells.
	["Shilka"] = function(groupName)
		return {
			{
				name = groupName .. "-1",
				type = "ZSU-23-4 Shilka",
				sensors = searchRadarSensors(),
				ammo = launcherShells(503, 1501),
			},
		}
	end,
}

--- F.samGroup(natoShort, groupName [, opts])
---   opts.pos       — where the site stands; its units are laid out a metre apart from there
---   opts.coalition — the side it belongs to, so SkynetIADS:setCoalition() has something to read
function F.samGroup(natoShort, groupName, opts)
	opts = opts or {}
	local origin = opts.pos or { x = 0, y = 0, z = 0 }
	local build = SAM_COMPOSITIONS[natoShort]
	if not build then
		error("dcs-fixtures: no SAM composition for '" .. tostring(natoShort) .. "'")
	end
	local units = build(groupName)
	for i = 1, #units do
		units[i].pos = units[i].pos or { x = origin.x + i, y = origin.y, z = origin.z }
		units[i].coalition = opts.coalition
	end
	-- dcsStub.makeGroup sets setmetatable(g, Group), so setupElements() iterates
	-- the member units instead of treating the group as one unit.
	return dcsStub.makeGroup({
		name = groupName,
		units = units,
		coalition = opts.coalition,
		category = Group.Category.GROUND,
	})
end

--- The two ammunition tables above, for a test that needs to change what a launcher is carrying
--- after the site was built — `<launcher>:getDCSRepresentation():__setAmmo(F.launcherAmmo(2))` is
--- one missile fired. `__setAmmo(nil)` is a launcher that has run dry, which is what DCS reports.
F.launcherAmmo = launcherAmmo
F.launcherShells = launcherShells

--- A ground group of units no `samTypesDB` entry names — an infantry squad here.
---
--- Skynet builds a SAM site object out of whatever group a mission hands it, so this is what one
--- looks like when `addSAMSite()` is pointed at the wrong group: setupElements() matches nothing,
--- the site keeps the "UNKNOWN" NATO name it was created with, and it has no radars and no
--- launchers. A mission writer's typo, in other words.
function F.unsupportedGroup(groupName)
	return dcsStub.makeGroup({
		name = groupName,
		category = Group.Category.GROUND,
		units = {
			{ name = groupName .. "-1", type = "Infantry AK", pos = { x = 0, y = 0, z = 0 } },
		},
	})
end

--- Moves every unit of a SAM group, the way a mobile site drives away in a convoy.
function F.moveSamGroup(groupName, pos)
	local group = dcsStub.world[groupName]
	if not group then
		error("dcs-fixtures: no group registered as '" .. tostring(groupName) .. "'")
	end
	local units = group:getUnits()
	for i = 1, #units do
		units[i]:__setPos({ x = pos.x + i, y = pos.y, z = pos.z })
	end
end

--- One hostile aircraft in a group of its own, visible to coalition.getGroups.
--- opts.inAir defaults to true; set it false to park it on a ramp.
function F.aircraftGroup(name, opts)
	opts = opts or {}
	local pos = opts.pos or { x = 0, y = 3000, z = 0 }
	dcsStub.makeGroup({
		name = name,
		coalition = opts.coalition,
		category = opts.category or Group.Category.AIRPLANE,
		units = {
			{
				name = name .. "-1",
				type = opts.type or "F-16C",
				pos = pos,
				coalition = opts.coalition,
				inAir = opts.inAir,
				desc = { category = Unit.Category.AIRPLANE },
			},
		},
	})
	return dcsStub.world[name .. "-1"]
end

--- An airborne early warning radar: SkynetIADS:addEarlyWarningRadar() builds a
--- SkynetIADSAWACSRadar from it because its desc.category is AIRPLANE.
function F.awacsUnit(name, opts)
	opts = opts or {}
	return dcsStub.makeUnit({
		name = name,
		type = "A-50",
		pos = opts.pos or { x = 0, y = 9000, z = 0 },
		coalition = opts.coalition,
		desc = { category = Unit.Category.AIRPLANE },
		sensors = searchRadarSensors(),
	})
end

function F.earlyWarningRadarUnit(name, opts)
	-- '1L13 EWR' (Box Spring) is a plain ground search radar in samTypesDB with
	-- no launcher entry, so SkynetIADSEWRadar:setupElements() finds it via the
	-- same 'searchRadar' lookup SAM search radars use. desc.category is set
	-- explicitly so SkynetIADS:addEarlyWarningRadar()'s AIRPLANE/SHIP check
	-- reliably takes the ground-radar branch instead of building an AWACS radar.
	opts = opts or {}
	return dcsStub.makeUnit({
		name = name,
		type = "1L13 EWR",
		pos = opts.pos or { x = 0, y = 0, z = 0 },
		coalition = opts.coalition,
		desc = { category = Unit.Category.GROUND_UNIT },
		sensors = searchRadarSensors(),
	})
end

--- The same EW radar, but inside a group of its own.
---
--- In DCS every unit belongs to a group, and `SkynetIADSUtils.getUnitNames()` enumerates units
--- *through* groups — so a bare unit, which is what `F.earlyWarningRadarUnit` registers, is
--- invisible to `SkynetIADS:addEarlyWarningRadarsByPrefix()`. Any test that drives prefix discovery
--- needs this one; `unitName` is what the prefix is matched against.
function F.earlyWarningRadarGroup(groupName, unitName, opts)
	opts = opts or {}
	dcsStub.makeGroup({
		name = groupName,
		coalition = opts.coalition,
		category = Group.Category.GROUND,
		units = {
			{
				name = unitName,
				type = "1L13 EWR",
				pos = opts.pos or { x = 0, y = 0, z = 0 },
				coalition = opts.coalition,
				desc = { category = Unit.Category.GROUND_UNIT },
				sensors = searchRadarSensors(),
			},
		},
	})
	return dcsStub.world[unitName]
end

function F.connectionNodeUnit(name)
	-- makeUnit self-registers into dcsStub.world (name given), like makeStatic below.
	return dcsStub.makeUnit({ name = name, type = "Ural-375", pos = { x = 0, y = 0, z = 0 } })
end

function F.connectionNodeStatic(name)
	return dcsStub.makeStatic({ name = name, type = "Comms tower M", pos = { x = 0, y = 0, z = 0 } })
end

function F.powerSourceStatic(name)
	-- A power source is only ever probed with isExist() — by
	-- SkynetIADSAbstractElement:genericCheckOneObjectIsAlive, and by the logger's
	-- damaged-power-source count, which are its only two readers. So the type
	-- string is decoration; 'Electric power box' is a real DCS static, kept so a
	-- fixture reads like the mission.
	return dcsStub.makeStatic({ name = name, type = "Electric power box", pos = { x = 0, y = 0, z = 0 } })
end

function F.commandCenterStatic(name)
	-- SkynetIADSCommandCenter overrides goLive()/goDark() to no-ops, and
	-- SkynetIADS:addCommandCenter() never calls setupElements() on it (only EW
	-- radars and SAM sites get that), so the type is never looked up in
	-- samTypesDB. The wrapper still reads getTypeName() when it builds the
	-- instance, so the fixture needs one — it is just never matched against
	-- anything.
	return dcsStub.makeStatic({ name = name, type = "Comms tower M", pos = { x = 0, y = 0, z = 0 } })
end

function F.iadsContact(unitName)
	local unit = dcsStub.world[unitName]
	if not unit then
		error("dcs-fixtures: no fixture registered as '" .. tostring(unitName) .. "'")
	end
	local contact = SkynetIADSContact:create({ object = unit })
	contact:refresh()
	return contact
end

return F
