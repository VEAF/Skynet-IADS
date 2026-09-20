--- What dcs-figures.lua is for, and what would make it worthless.
--
-- The file is generated from a pinned dump of the DCS database, and its job is to make a change in
-- ED's own figures visible: when the SA-11's missile went from 35000 m to 46000 m, a Buk battery
-- started waking 11 km further out in every mission, and nothing in this project said so. The
-- weekly pin bump turns that into a pull request whose diff names the figure.
--
-- A generated file is only worth what its generator got right, and the ways a regex-based generator
-- fails are quiet: it stops matching and writes an empty table, or it matches half of what it should
-- and writes a plausible one. These tests are the ones that would catch that.

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")

local figures = dofile(base .. "/dcs-figures.lua")

--- Figures a real DCS run reported on 2026-09-20, straight out of dcs.log. These are the anchor:
--- they are what the simulator answered, not what the dump says, so they are what proves the dump
--- can stand in for the simulator.
local OBSERVED_IN_DCS = {
	{ what = "SA-11 launcher range", missile = "SA9M38M1", field = "range", value = 46000 },
	{ what = "HQ-7 launcher range", missile = "HQ-7B", field = "range", value = 15000 },
	{ what = "SA-15 launcher range", missile = "SA9M330", field = "range", value = 12000 },
	{ what = "SA-15 firing ceiling", missile = "SA9M330", field = "maxAltitude", value = 6000 },
	{ what = "SA-11 firing ceiling", missile = "SA9M38M1", field = "maxAltitude", value = 22000 },
}

--- The same, for radars: what getMaxRangeFindingTarget() answered in that run, against the raw
--- figure the dump states. DCS scales the raw figure for the reference target's radar cross-section.
local OBSERVED_RADAR_RANGES = {
	{ unit = "SA-11 Buk SR 9S18M1", raw = 100000, reported = 66874.03125 },
	{ unit = "ZSU-23-4 Shilka", raw = 7500, reported = 5015.552734375 },
}

TestDcsFigures = {}

function TestDcsFigures:test_the_table_is_not_empty()
	-- The failure this guards: a regex that stops matching writes a well-formed, empty file, and
	-- every other test here would pass over it in silence.
	luaunit.assertTrue(figures.datamineRef ~= nil and #figures.datamineRef == 40)
	local radars, missiles = 0, 0
	for _ in pairs(figures.radars) do
		radars = radars + 1
	end
	for _ in pairs(figures.missiles) do
		missiles = missiles + 1
	end
	luaunit.assertTrue(radars >= 25, "only " .. radars .. " radars; the dump holds far more")
	luaunit.assertTrue(missiles >= 150, "only " .. missiles .. " missiles; the dump holds far more")
end

function TestDcsFigures:test_every_entry_states_a_usable_figure()
	-- A zero range is not a smaller number, it is a missing one: Skynet reads getRange() to decide
	-- whether a contact is engageable, so a zero would read as "never".
	for unitType, radar in pairs(figures.radars) do
		luaunit.assertTrue(type(radar.sensor) == "string" and #radar.sensor > 0, unitType .. ": no sensor named")
		luaunit.assertTrue(
			type(radar.detectionDistance) == "number" and radar.detectionDistance > 0,
			unitType .. ": detection distance is " .. tostring(radar.detectionDistance)
		)
	end
	for name, missile in pairs(figures.missiles) do
		luaunit.assertTrue(type(missile.displayName) == "string" and #missile.displayName > 0, name .. ": no name")
		luaunit.assertTrue(
			type(missile.range) == "number" and missile.range > 0,
			name .. ": range is " .. tostring(missile.range)
		)
	end
end

function TestDcsFigures:test_matches_what_dcs_reported_for_missiles()
	for _, sample in ipairs(OBSERVED_IN_DCS) do
		local missile = figures.missiles[sample.missile]
		luaunit.assertNotNil(missile, sample.missile .. " is not in the generated figures")
		luaunit.assertEquals(missile[sample.field], sample.value, sample.what)
	end
end

function TestDcsFigures:test_matches_what_dcs_reported_for_radars()
	-- The relation, and the reason for the tolerance: DCS evaluates this in single precision, and
	-- Lua has only doubles. The SA-11 lands exactly either way; the Shilka misses by 4.5e-4 in
	-- double precision, which is one unit in the last place of a 32-bit float at that magnitude.
	-- Asserting equality here would fail for a reason that has nothing to do with ED's data.
	local scale = figures.referenceRcs ^ 0.25
	for _, sample in ipairs(OBSERVED_RADAR_RANGES) do
		local radar = figures.radars[sample.unit]
		luaunit.assertNotNil(radar, sample.unit .. " is not in the generated figures")
		luaunit.assertEquals(radar.detectionDistance, sample.raw, sample.unit .. ": raw detection distance")
		local derived = radar.detectionDistance * scale
		luaunit.assertTrue(
			math.abs(derived - sample.reported) / sample.reported < 1e-6,
			sample.unit
				.. ": derived "
				.. derived
				.. " is not within a float of the "
				.. sample.reported
				.. " DCS reported"
		)
	end
end

function TestDcsFigures:test_covers_the_radars_skynet_models()
	-- samTypesDB is the list of what Skynet knows how to read. A radar in there and not here means
	-- the generator's walk from a Skynet type to its sensor broke for that type, and the figure it
	-- was meant to watch is unwatched -- which is the one failure this whole file exists to prevent.
	local loader = dofile(base .. "/skynet-loader.lua")
	loader.load("skynet-iads-supported-types")

	-- Radarless by design: both are infrared, they carry no sensor, and Skynet falls back to a
	-- default range for them. Listed here so that any OTHER absence is a failure.
	local radarless = { ["Strela-1 9P31"] = true, ["Strela-10M3"] = true }

	local missing = {}
	for _, samType in pairs(samTypesDB) do
		for _, role in ipairs({ "searchRadar", "trackingRadar" }) do
			for unitType in pairs(samType[role] or {}) do
				if not figures.radars[unitType] and not radarless[unitType] then
					table.insert(missing, unitType)
				end
			end
		end
	end
	luaunit.assertEquals(missing, {}, "samTypesDB names these radars, and the figures do not carry them")
end

os.exit(luaunit.LuaUnit.run())
