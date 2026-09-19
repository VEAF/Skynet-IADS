--- How a battery learns its own range — `setupRangeData` on the search radar and on the
--- launcher, and the delegation between the two.
---
--- This is what decides whether a target is engageable at all, so a battery that reads its range
--- as zero detects nothing for a whole mission and looks exactly like one that is out of
--- position. The `skynet-runtime-debug` skill warns about that case by name.
---
--- The two classes are tested together because the interesting part is what they do to each
--- other: a unit with no sensor data asks the launcher, a launcher with no usable range asks the
--- search radar, and the only thing stopping that from running forever is a counter.
---
--- Units are built here rather than in dcs-fixtures because these are ammunition and sensor
--- shapes, not missions: a gun with shells and no missiles, a launcher whose two altitude bands
--- disagree, a radar that sees further low than high. Nothing else would reuse them.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()

--- The shape SkynetIADSSAMSearchRadar:setupRangeData walks: data[i] -> subEntries[j].
local function radarSensors(upperHemisphere, lowerHemisphere)
	return {
		{
			{
				type = Unit.SensorType.RADAR,
				detectionDistanceAir = {
					upperHemisphere = { headOn = upperHemisphere },
					lowerHemisphere = { headOn = lowerHemisphere or upperHemisphere },
				},
			},
		},
	}
end

--- An infrared sensor carries no detectionDistanceAir at all; setupRangeData has to walk past it
--- rather than read a range out of it.
local function infraredSensors()
	return { { { type = Unit.SensorType.IRST } } }
end

local function missiles(count, rangeMaxAltMin, rangeMaxAltMax, altMax)
	return {
		{
			desc = {
				category = Weapon.Category.MISSILE,
				rangeMaxAltMin = rangeMaxAltMin,
				rangeMaxAltMax = rangeMaxAltMax,
				altMax = altMax or 0,
			},
			count = count,
		},
	}
end

local function shells(count)
	return { { desc = { category = Weapon.Category.SHELL, altMax = 0 }, count = count } }
end

local function targetAt(x, y)
	local unit = dcsStub.makeUnit({ name = "target-" .. x .. "-" .. y, pos = { x = x, y = y, z = 0 } })
	return unit
end

TestSkynetIADSRangeData = {}

function TestSkynetIADSRangeData:setUp()
	dcsStub.reset()
end

-- ---- the search radar reads its range from its sensors --------------------------------------

function TestSkynetIADSRangeData:testTheRangeComesFromTheRadarSensor()
	local unit = dcsStub.makeUnit({ name = "sr", sensors = radarSensors(120000) })
	local radar = SkynetIADSSAMSearchRadar:create(unit)
	radar:setupRangeData()
	luaunit.assertEquals(radar:getMaxRangeFindingTarget(), 120000)
end

--- Some radars reach further against a low target than a high one. The larger of the two is
--- taken, because the question this range answers is "could it ever see it", not "at what
--- altitude".
function TestSkynetIADSRangeData:testTheFurtherOfTheTwoHemispheresWins()
	local lowSeeing =
		SkynetIADSSAMSearchRadar:create(dcsStub.makeUnit({ name = "sr-low", sensors = radarSensors(60000, 90000) }))
	lowSeeing:setupRangeData()
	luaunit.assertEquals(lowSeeing:getMaxRangeFindingTarget(), 90000)

	local highSeeing =
		SkynetIADSSAMSearchRadar:create(dcsStub.makeUnit({ name = "sr-high", sensors = radarSensors(90000, 60000) }))
	highSeeing:setupRangeData()
	luaunit.assertEquals(highSeeing:getMaxRangeFindingTarget(), 90000)
end

--- A sensor that is not a radar carries no air detection distance, and walking into it as if it
--- did would index a nil.
function TestSkynetIADSRangeData:testANonRadarSensorIsIgnored()
	local radar = SkynetIADSSAMSearchRadar:create(dcsStub.makeUnit({ name = "sr-ir", sensors = infraredSensors() }))
	radar:setupRangeData()
	luaunit.assertEquals(radar:getMaxRangeFindingTarget(), 0)
end

function TestSkynetIADSRangeData:testADestroyedRadarLearnsNothing()
	local unit = dcsStub.makeUnit({ name = "sr-dead", sensors = radarSensors(120000) })
	local radar = SkynetIADSSAMSearchRadar:create(unit)
	unit:__destroy()
	radar:setupRangeData()
	luaunit.assertEquals(radar:getMaxRangeFindingTarget(), 0)
	luaunit.assertEquals(radar:isInRange(targetAt(100, 0)), false, "and it is in range of nothing")
end

-- ---- the launcher reads its range from its ammunition ---------------------------------------

--- Two altitude bands, and the longer one is the range. Real SA-2 data has altMin >= altMax, so
--- this is the other way round, which is the branch the SA-2 fixture never takes.
function TestSkynetIADSRangeData:testTheLongerAltitudeBandIsTheLaunchersRange()
	local launcher =
		SkynetIADSSAMLauncher:create(dcsStub.makeUnit({ name = "ln-high", ammo = missiles(4, 30000, 45000, 12000) }))
	launcher:setupRangeData()
	luaunit.assertEquals(launcher:getRange(), 45000)
	luaunit.assertEquals(launcher:getMaximumFiringAltitude(), 12000)
	luaunit.assertEquals(launcher:getRemainingNumberOfMissiles(), 4)
end

--- A gun, not a missile launcher: shells are counted on their own, and a battery with shells
--- left is not out of ammunition.
function TestSkynetIADSRangeData:testShellsAreCountedSeparatelyFromMissiles()
	local gun = SkynetIADSSAMLauncher:create(dcsStub.makeUnit({ name = "aaa", ammo = shells(500) }))
	gun:setupRangeData()
	luaunit.assertEquals(gun:getRemainingNumberOfShells(), 500)
	luaunit.assertEquals(gun:getRemainingNumberOfMissiles(), 0)
	luaunit.assertEquals(gun:getInitialNumberOfShells(), 500)
end

--- Radar-guided anti-aircraft artillery reports no firing altitude, so its horizontal range
--- stands in for the ceiling. Worth pinning: the fallback is what keeps a gun from being
--- considered able to reach anything at any height.
function TestSkynetIADSRangeData:testAGunWithNoFiringAltitudeUsesItsRangeAsTheCeiling()
	local gun = SkynetIADSSAMLauncher:create(
		dcsStub.makeUnit({ name = "aaa-range", pos = { x = 0, y = 0, z = 0 }, ammo = missiles(100, 2500, 0, 0) })
	)
	gun:setupRangeData()
	luaunit.assertEquals(gun:getMaximumFiringAltitude(), 0)
	luaunit.assertEquals(gun:getRange(), 2500)
	luaunit.assertEquals(gun:isWithinFiringHeight(targetAt(0, 2000)), true, "2 000 m up is inside 2 500")
	luaunit.assertEquals(gun:isWithinFiringHeight(targetAt(0, 3000)), false, "3 000 m up is not")
end

function TestSkynetIADSRangeData:testADestroyedLauncherIsInRangeOfNothing()
	local unit = dcsStub.makeUnit({ name = "ln-dead", ammo = missiles(4, 40000, 30000, 12000) })
	local launcher = SkynetIADSSAMLauncher:create(unit)
	launcher:setupRangeData()
	unit:__destroy()
	luaunit.assertEquals(launcher:isInRange(targetAt(100, 100)), false)
	luaunit.assertEquals(launcher:getRemainingNumberOfMissiles(), 0, "and it carries nothing any more")
end

-- ---- what each asks the other ---------------------------------------------------------------

--- The SA-13 reports no sensor data at all, so the search radar takes its range from the
--- launcher's ammunition instead. Without this a whole class of battery would read range zero
--- and never engage anything.
function TestSkynetIADSRangeData:testARadarWithNoSensorsTakesTheLaunchersRange()
	local unit = dcsStub.makeUnit({ name = "sa13", ammo = missiles(2, 5000, 8000, 3500) })
	local radar = SkynetIADSSAMSearchRadar:create(unit)
	radar:setupRangeData()
	luaunit.assertEquals(radar:getMaxRangeFindingTarget(), 8000, "the range came from the missiles")
end

--- The two delegate to each other, so something has to stop them. A unit with neither usable
--- sensors nor a usable range would bounce forever if the counter were removed; the assertion
--- that matters is that this call returns at all.
function TestSkynetIADSRangeData:testTheDelegationBetweenTheTwoTerminates()
	local unit = dcsStub.makeUnit({ name = "neither", ammo = missiles(1, 0, 0, 0) })
	local radar = SkynetIADSSAMSearchRadar:create(unit)
	radar:setupRangeData()
	luaunit.assertEquals(radar:getMaxRangeFindingTarget(), 0)
	-- three bounces, exactly: the radar hands over on each of its own entries and the launcher
	-- hands back while triedSensors is still <= 2, so the counter reads 3 when it stops. Asserted
	-- exactly rather than as an upper bound -- a guard loosened to <= 3 would end at 4, and a test
	-- that accepted that would say nothing about the one thing it is named for.
	luaunit.assertEquals(radar.triedSensors, 3)
end

-- ---- how far a site will let a target come before it fires ----------------------------------

--- setGoLiveRangeInPercent narrows the range a site treats as engageable, which is how a mission
--- makes a battery hold fire until a target is well inside its envelope.
function TestSkynetIADSRangeData:testTheFiringRangePercentNarrowsTheHorizontalRange()
	local radar = SkynetIADSSAMSearchRadar:create(
		dcsStub.makeUnit({ name = "sr-percent", pos = { x = 0, y = 0, z = 0 }, sensors = radarSensors(100000) })
	)
	radar:setupRangeData()
	luaunit.assertEquals(radar:isInRange(targetAt(80000, 0)), true, "80 km is inside 100 km")

	radar:setFiringRangePercent(50)
	luaunit.assertEquals(radar:isInRange(targetAt(80000, 0)), false, "and outside half of it")
	luaunit.assertEquals(radar:isInRange(targetAt(40000, 0)), true)
end

os.exit(luaunit.LuaUnit.run())
