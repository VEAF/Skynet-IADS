--- Standalone port of unit-tests/test-skynet-iads-jammer.lua.
--- The DCS-mission version reads a "jammer-source" unit baked into
--- skynet-unit-tests.miz and kills the emitter with
--- trigger.action.explosion(...). Here the emitter is a code-defined
--- dcsStub.makeUnit fixture, killed with emitter:__destroy(), and the
--- "is any task still scheduled?" checks use dcsStub.scheduledCount() in
--- place of the iterate-removeFunction(0..10000) idiom.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()

TestSkynetIADSJammer = {}

function TestSkynetIADSJammer:setUp()
	dcsStub.reset()
	dcsStub.stubUtilsScheduler()
	self.emitter = dcsStub.makeUnit({ name = "jammer-source", type = "F-16C", pos = { x = 0, y = 1000, z = 0 } })
	self.mockIADS = {}
	function self.mockIADS:getDebugSettings()
		return {}
	end
	self.jammer = SkynetIADSJammer:create(self.emitter, self.mockIADS)
end

function TestSkynetIADSJammer:tearDown()
	self.jammer:masterArmSafe()
end

-- ---- distance setter (ported verbatim) ------------------------------

function TestSkynetIADSJammer:testSetJammerDistance()
	self.jammer:setMaximumEffectiveDistance(20)
	luaunit.assertEquals(self.jammer.maximumEffectiveDistanceNM, 20)
end

-- ---- full run cycle (ported verbatim) ------------------------------
-- Mocks the SAM/radar/IADS surface exactly as the .miz test does, so the
-- fake scheduler is never fired automatically; runCycle is invoked directly.

function TestSkynetIADSJammer:testSetupJammerAndRunCycle()
	luaunit.assertEquals(self.jammer.jammerTaskID, nil)
	self.jammer:masterArmOn()
	luaunit.assertNotIs(self.jammer.jammerTaskID, nil)

	local mockRadar = {}
	local mockSAM = {}
	local calledJam = false

	function mockSAM:getRadars()
		return { mockRadar }
	end

	function mockSAM:getNatoName()
		return "SA-2"
	end

	function mockSAM:jam(prob)
		calledJam = true
	end

	function self.mockIADS:getActiveSAMSites()
		return { mockSAM }
	end

	function self.jammer:getDistanceNMToRadarUnit(radarUnit)
		return 50
	end

	function self.jammer:hasLineOfSightToRadar(radar)
		return true
	end

	self.jammer.runCycle(self.jammer)
	luaunit.assertEquals(calledJam, true)
end

-- ---- known/unknown radar emitter (ported verbatim) ---------------

function TestSkynetIADSJammer:testIsActiveForUnknownType()
	luaunit.assertEquals(self.jammer:isKnownRadarEmitter("ABC-Test"), false)
end

function TestSkynetIADSJammer:testIsActiveForKnownType()
	luaunit.assertEquals(self.jammer:isKnownRadarEmitter("SA-2"), true)
end

-- ---- scheduler lifecycle (adapted) ------------------------------
-- .miz version scans removeFunction(0..10000) for a live id; here
-- dcsStub.scheduledCount() reports the live task count directly.

function TestSkynetIADSJammer:testCleanUpJammer()
	self.jammer:masterArmOn()
	luaunit.assertEquals(dcsStub.scheduledCount(), 1)

	self.jammer:masterArmSafe()
	luaunit.assertEquals(dcsStub.scheduledCount(), 0)
end

-- ---- custom jammer function (ported verbatim) -------------------

function TestSkynetIADSJammer:testAddJammerFunction()
	local function f(distanceNM)
		return 2 * distanceNM
	end
	self.jammer:addFunction("SA-99", f)
	luaunit.assertEquals(self.jammer:getSuccessProbability(20, "SA-99"), 40)
	luaunit.assertEquals(self.jammer:isKnownRadarEmitter("SA-99"), true)
	self.jammer:disableFor("SA-99")
	luaunit.assertEquals(self.jammer:isKnownRadarEmitter("SA-99"), false)
end

-- ---- dead emitter stops the cycle (adapted) --------------------
-- .miz version kills the emitter with trigger.action.explosion(pos, 500);
-- here emitter:__destroy() flips isExist() to false. runCycle sees the
-- dead emitter, calls masterArmSafe(), and the scheduled task is gone.

function TestSkynetIADSJammer:testDestroyEmitter()
	self:tearDown()
	local emitter = dcsStub.makeUnit({ name = "jammer-source-2", type = "F-16C", pos = { x = 0, y = 1000, z = 0 } })
	self.jammer = SkynetIADSJammer:create(emitter, SkynetIADS:create())
	self.jammer:masterArmOn()
	luaunit.assertEquals(dcsStub.scheduledCount(), 1)

	emitter:__destroy()
	self.jammer.runCycle(self.jammer)

	luaunit.assertEquals(dcsStub.scheduledCount(), 0)
end

-- ---- CHORE-TEST-COVERAGE-FLOOR ticket 06 ---------------------------------------------------
--
-- What the port above never reached: the per-type probability curves, the real distance and
-- line-of-sight helpers the run cycle gates on, and the radio menu that is the only way a
-- player arms or safes a jammer in a running mission.

--- Replaces land.isVisible for the duration of `body`, restoring it whatever happens -- a suite
--- that leaks a fixed line of sight poisons every test that runs after it.
local function withLineOfSight(visible, body)
	local realIsVisible = land.isVisible
	land.isVisible = function()
		return visible
	end
	local ok, err = pcall(body)
	land.isVisible = realIsVisible
	if not ok then
		error(err, 0)
	end
end

--- A radar the real hasLineOfSightToRadar() can work on: it reads getPosition().p and lifts
--- it 30 m, so a bare table is not enough. Only the tests that override that helper can skip
--- this, and those are the ones not interested in line of sight.
local function mockRadarAt(x)
	local radar = {}
	function radar:getPosition()
		return { p = { x = x, y = 0, z = 0 } }
	end
	return radar
end

-- ---- the probability curves ---------------------------------------------------------------

--- Every type Skynet ships a curve for has its own, and an unknown type is not jammed at all.
--- The values are deliberately not pinned: they are tuning, and the defect worth catching is a
--- curve wired to the wrong type -- a copy-paste that hands the SA-10 the SA-2's numbers, which
--- would make the hardest system in the game the easiest to jam.
function TestSkynetIADSJammer:testEveryKnownTypeHasACurveOfItsOwn()
	local seen = {}
	local types = { "SA-2", "SA-3", "SA-6", "SA-8", "SA-10", "SA-11", "SA-15" }
	for _, natoName in ipairs(types) do
		local probability = self.jammer:getSuccessProbability(20, natoName)
		luaunit.assertTrue(probability > 0, natoName .. " has no jamming curve")
		luaunit.assertNil(seen[probability], natoName .. " shares a curve with " .. tostring(seen[probability]))
		seen[probability] = natoName
	end
end

function TestSkynetIADSJammer:testATypeWithNoCurveIsNeverJammed()
	luaunit.assertEquals(self.jammer:getSuccessProbability(20, "SA-99"), 0)
	luaunit.assertEquals(self.jammer:isKnownRadarEmitter("SA-99"), false)
end

--- Measured, and surprising enough to be worth writing down rather than left for the next
--- reader to discover: the curves RISE with distance. `jam()` compares this figure with
--- math.random(1, 100), so anything at or above 100 jams with certainty -- which an SA-2 reaches
--- at roughly 6 NM, and every type reaches long before the 200 NM cutoff in
--- maximumEffectiveDistanceNM. A jammer is therefore at its weakest sitting on top of the
--- battery and unbeatable from a hundred miles away, until it crosses the cutoff and stops
--- working entirely.
---
--- That reads inverted, but it is upstream behaviour keyed to a spreadsheet this repository does
--- not have (see the comment in skynet-iads-jammer.lua), so it is recorded here, not changed.
--- If someone establishes the intent and flips the curves, this test is what tells them every
--- caller that depended on the old shape.
function TestSkynetIADSJammer:testTheCurvesRiseWithDistanceWhichIsSurprising()
	local close = self.jammer:getSuccessProbability(1, "SA-6")
	local far = self.jammer:getSuccessProbability(50, "SA-6")
	luaunit.assertTrue(far > close, "the curve rises with distance")
	luaunit.assertTrue(
		self.jammer:getSuccessProbability(10, "SA-2") > 100,
		"an SA-2 ten miles off is jammed whatever math.random(1, 100) rolls"
	)
end

-- ---- distance and line of sight -----------------------------------------------------------

--- The run cycle gates on this before jamming anything, so it has to measure from the emitter to
--- the radar and not the other way, or to something else entirely.
function TestSkynetIADSJammer:testDistanceIsMeasuredFromTheEmitterToTheRadar()
	-- the emitter built in setUp sits at the origin, 1 000 m up; a radar 1 852 m away on the
	-- ground is one nautical mile out horizontally, so the slant range is
	-- sqrt(1852^2 + 1000^2) = 2 104.7337 m, and 2 104.7337 / 1852 = 1.136465 NM. The tolerance is
	-- there for floating point, not for arithmetic nobody checked.
	local radar = dcsStub.makeUnit({ name = "radar-1nm", pos = { x = 1852, y = 0, z = 0 } })
	luaunit.assertAlmostEquals(self.jammer:getDistanceNMToRadarUnit(radar), 1.136465, 1e-6)
end

--- The emitter has to see the radar. The 30 m lift is there because some DCS 3D models are dug
--- into the ground and would otherwise never be visible; what matters to a test is that the
--- answer is the one land.isVisible gave, both ways round.
function TestSkynetIADSJammer:testLineOfSightIsWhatTheTerrainSays()
	local radar = dcsStub.makeUnit({ name = "radar-los", pos = { x = 10000, y = 0, z = 0 } })
	withLineOfSight(true, function()
		luaunit.assertEquals(self.jammer:hasLineOfSightToRadar(radar), true)
	end)
	withLineOfSight(false, function()
		luaunit.assertEquals(self.jammer:hasLineOfSightToRadar(radar), false)
	end)
end

--- A battery behind a ridge is not jammed, however close it is and whatever its type.
function TestSkynetIADSJammer:testABatteryWithNoLineOfSightIsNotJammed()
	local mockRadar = mockRadarAt(10000)
	local jammed = 0
	local mockSAM = {}
	function mockSAM:getRadars()
		return { mockRadar }
	end
	function mockSAM:getNatoName()
		return "SA-2"
	end
	function mockSAM:jam(_)
		jammed = jammed + 1
	end
	function self.mockIADS:getActiveSAMSites()
		return { mockSAM }
	end
	function self.jammer:getDistanceNMToRadarUnit(_)
		return 5
	end

	withLineOfSight(false, function()
		self.jammer.runCycle(self.jammer)
	end)
	luaunit.assertEquals(jammed, 0)

	withLineOfSight(true, function()
		self.jammer.runCycle(self.jammer)
	end)
	luaunit.assertEquals(jammed, 1, "and it is jammed once the ridge is out of the way")
end

--- Beyond the maximum effective distance the jammer does nothing, which is the only thing that
--- keeps the rising curves above from making it omnipotent.
function TestSkynetIADSJammer:testABatteryBeyondTheEffectiveDistanceIsNotJammed()
	local mockRadar = mockRadarAt(10000)
	local jammed = 0
	local mockSAM = {}
	function mockSAM:getRadars()
		return { mockRadar }
	end
	function mockSAM:getNatoName()
		return "SA-2"
	end
	function mockSAM:jam(_)
		jammed = jammed + 1
	end
	function self.mockIADS:getActiveSAMSites()
		return { mockSAM }
	end
	self.jammer:setMaximumEffectiveDistance(100)
	function self.jammer:getDistanceNMToRadarUnit(_)
		return 101
	end
	withLineOfSight(true, function()
		self.jammer.runCycle(self.jammer)
	end)
	luaunit.assertEquals(jammed, 0)
end

--- With jammerProbability on, the cycle says how far away it was when it jammed -- which is what
--- someone reads when a battery went to weapon hold and they want to know who did it.
function TestSkynetIADSJammer:testTheJammerProbabilitySettingReportsTheDistance()
	local iads = SkynetIADS:create("Ruby")
	iads:getDebugSettings().jammerProbability = true
	local jammer = SkynetIADSJammer:create(self.emitter, iads)

	local mockRadar = mockRadarAt(10000)
	local mockSAM = {}
	function mockSAM:getRadars()
		return { mockRadar }
	end
	function mockSAM:getNatoName()
		return "SA-6"
	end
	function mockSAM:jam(_) end
	function iads:getActiveSAMSites()
		return { mockSAM }
	end
	function jammer:getDistanceNMToRadarUnit(_)
		return 42
	end

	dcsStub.screenText = {}
	withLineOfSight(true, function()
		jammer.runCycle(jammer)
	end)
	luaunit.assertEquals(#dcsStub.screenText, 1)
	luaunit.assertStrContains(dcsStub.screenText[1].text, "JAMMER: Distance: 42")
	iads:deactivate()
end

-- ---- more than one network ------------------------------------------------------------------

--- A jammer built against one network can be handed a second, and then works both. A mission
--- with a red and a blue IADS has exactly this shape.
function TestSkynetIADSJammer:testAJammerCanBeGivenASecondNetwork()
	luaunit.assertEquals(#self.jammer.iads, 1)
	local jammedBy = {}
	local function networkWithOneSite(name)
		local network = {}
		function network:getDebugSettings()
			return {}
		end
		local mockSAM = {}
		function mockSAM:getRadars()
			return { mockRadarAt(10000) }
		end
		function mockSAM:getNatoName()
			return "SA-2"
		end
		function mockSAM:jam(_)
			jammedBy[#jammedBy + 1] = name
		end
		function network:getActiveSAMSites()
			return { mockSAM }
		end
		return network
	end

	local jammer = SkynetIADSJammer:create(self.emitter, networkWithOneSite("red"))
	jammer:addIADS(networkWithOneSite("blue"))
	luaunit.assertEquals(#jammer.iads, 2)

	function jammer:getDistanceNMToRadarUnit(_)
		return 5
	end
	withLineOfSight(true, function()
		jammer.runCycle(jammer)
	end)
	table.sort(jammedBy)
	luaunit.assertEquals(jammedBy, { "blue", "red" })
end

-- ---- the radio menu -------------------------------------------------------------------------

--- The only way a player arms or safes a jammer in a running mission.
function TestSkynetIADSJammer:testTheRadioMenuCarriesTheEmitterName()
	dcsStub.radioItems = {}
	self.jammer:addRadioMenu()

	local names = {}
	for i = 1, #dcsStub.radioItems do
		names[i] = dcsStub.radioItems[i].name
	end
	luaunit.assertEquals(names, { "Jammer: jammer-source", "Master Arm On", "Master Arm Safe" })
	for i = 2, 3 do
		luaunit.assertEquals(dcsStub.radioItems[i].path[1], "Jammer: jammer-source")
	end
end

--- Clicking the two commands is what updateMasterArm exists for, and arming is what puts the
--- cycle on the scheduler.
function TestSkynetIADSJammer:testTheRadioCommandsArmAndSafeTheJammer()
	dcsStub.radioItems = {}
	self.jammer:addRadioMenu()

	local function click(label)
		local item = dcsStub.radioItemNamed(label)
		luaunit.assertNotNil(item, "no radio command named '" .. label .. "'")
		item.handler(item.args)
	end

	luaunit.assertEquals(dcsStub.scheduledCount(), 0)
	click("Master Arm On")
	luaunit.assertEquals(dcsStub.scheduledCount(), 1, "arming schedules the jamming cycle")
	click("Master Arm Safe")
	luaunit.assertEquals(dcsStub.scheduledCount(), 0, "and safing takes it off again")
end

--- An option updateMasterArm does not know leaves the jammer alone rather than throwing at a
--- player who clicked something.
function TestSkynetIADSJammer:testAnUnknownMasterArmOptionDoesNothing()
	SkynetIADSJammer.updateMasterArm({ self = self.jammer, option = "not-an-option" })
	luaunit.assertEquals(dcsStub.scheduledCount(), 0)
end

function TestSkynetIADSJammer:testRemovingTheRadioMenuTakesItsCommandsWithIt()
	dcsStub.radioItems = {}
	self.jammer:addRadioMenu()
	luaunit.assertEquals(#dcsStub.radioItems, 3)
	self.jammer:removeRadioMenu()
	luaunit.assertEquals(#dcsStub.radioItems, 0)
end

os.exit(luaunit.LuaUnit.run())
