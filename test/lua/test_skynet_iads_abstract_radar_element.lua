--- Standalone port of unit-tests/test-skynet-iads-abstract-radar-element.lua —
--- first slice: the autonomy / coverage cluster (8 of that file's 50 tests).
---
--- Ported here because SkynetIADSAbstractRadarElement carries goLive, goDark,
--- setToCorrectAutonomousState and the HARM evasion, and both tickets of
--- FEAT-LAST-LINE-OF-DEFENSE modify that class — this is the regression net
--- that work needs. The remaining clusters (HARM timing, point defence,
--- cached-targets / aspect calculation, the SA-2 range tests) are still
--- DCS-only; see test/lua/README.md for what is left.
---
--- The .miz version reads SAM groups, connection nodes, power sources and a
--- command centre baked into skynet-unit-tests.miz, and kills them with
--- trigger.action.explosion(...). Here they come from dcs-fixtures and are
--- killed with <obj>:__destroy() — the stub's trigger.action.explosion is a
--- no-op, so destroying the object directly is what stands in for the blast.
--- Everything else (the mocks, the assertions, their order) is the .miz test,
--- with one deliberate departure: the .miz's enableEmission mocks set their flag
--- to a hard-coded true/false and ignore the argument, so `emissionState` only
--- ever recorded *that* the call happened. Here the mock records the argument,
--- which is what the assertion underneath it reads as.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

-- one-liner from the .miz's skynet-unit-tests.lua
local function createDeadEvent()
	return { id = world.event.S_EVENT_DEAD }
end

-- maps the .miz group names to a fixture NATO short + which SAM it models
local GROUPS = {
	["SAM-SA-6"] = "SA-6",
	["SAM-SA-6-2"] = "SA-6",
	["SAM-SA-2"] = "SA-2",
}

TestSkynetIADSAbstractRadarElement = {}

function TestSkynetIADSAbstractRadarElement:setUp()
	dcsStub.reset()
	self.skynetIADS = SkynetIADS:create()
	if self.samSiteName then
		local group = F.samGroup(GROUPS[self.samSiteName] or "SA-6", self.samSiteName)
		self.samSite = SkynetIADSSamSite:create(group, self.skynetIADS)
		-- overwritten as in the .miz: the real getDetectedTargets returns DCS world
		-- radar contacts which would interfere with these tests.
		function self.samSite:getDetectedTargets()
			return {}
		end
		self.samSite:setupElements()
		self.samSite:goLive()
	end
end

function TestSkynetIADSAbstractRadarElement:tearDown()
	if self.samSite then
		self.samSite:goDark()
		self.samSite:cleanUp()
	end
	if self.skynetIADS then
		self.skynetIADS:deactivate()
	end
	self.samSite = nil
	self.samSiteName = nil
end

--TODO: test other calls in the GoDark Method
function TestSkynetIADSAbstractRadarElement:testGoDark()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	local mockRepresentation = {}

	local emissionState = nil

	function mockRepresentation:enableEmission(state)
		emissionState = state
	end

	function mockRepresentation:isExist()
		return true
	end

	function self.samSite:getDCSRepresentation()
		return mockRepresentation
	end

	local mockController = {}

	function mockController:setOption() end

	function mockRepresentation:getController()
		return mockController
	end

	table.insert(self.samSite.cachedTargets, { "Mock1" })
	self.samSite:goDark()
	luaunit.assertEquals(self.samSite:isActive(), false)
	luaunit.assertEquals(emissionState, false)
	luaunit.assertEquals(#self.samSite.cachedTargets, 0)
end

--TODO: test other calls in the GoLive Method
function TestSkynetIADSAbstractRadarElement:testGoLive()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()
	self.samSite:goDark()

	local mockRepresentation = {}

	local emissionState = nil

	function mockRepresentation:enableEmission(state)
		emissionState = state
	end

	function mockRepresentation:isExist()
		return true
	end

	function self.samSite:getDCSRepresentation()
		return mockRepresentation
	end

	local mockController = {}

	function mockController:setOption() end

	function mockRepresentation:getController()
		return mockController
	end

	--test so see if controller is called when setting site live:
	local call = 0
	function mockController:setOnOff(state)
		luaunit.assertEquals(state, true)
		call = 1
	end

	self.samSite:goLive()
	luaunit.assertEquals(call, 1)
	luaunit.assertEquals(self.samSite:isActive(), true)
	luaunit.assertEquals(emissionState, true)
end

function TestSkynetIADSAbstractRadarElement:testGoDarkDueToHARMTestIfAIisOff()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	local mockController = {}
	local call = 0
	function mockController:setOnOff(state)
		luaunit.assertEquals(state, false)
		call = 1
	end
	function self.samSite:getController()
		return mockController
	end
	self.samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(self.samSite:isActive(), false)
	luaunit.assertEquals(call, 1)

	--test so no controller call is made if sam site is destroyed:
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	mockController = {}
	call = 0
	function mockController:setOnOff()
		call = call + 1
	end
	function self.samSite:getController()
		return mockController
	end
	function self.samSite:isDestroyed()
		return true
	end
	self.samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(self.samSite:isActive(), false)
	luaunit.assertEquals(call, 0)
end

function TestSkynetIADSAbstractRadarElement:testInformChildrenOfStateChange()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	--we ensure the moose connector is updated if a state of an IADS radar changes
	local updateCalled = false
	local mockMoose = {}
	function mockMoose:update()
		updateCalled = true
	end
	function self.samSite.iads:getMooseConnector()
		return mockMoose
	end

	local calls = 0
	local childRad1 = {}
	function childRad1:setToCorrectAutonomousState()
		calls = calls + 1
	end
	self.samSite:addChildRadar(childRad1)

	local childRad2 = {}
	function childRad2:setToCorrectAutonomousState()
		calls = calls + 1
	end
	self.samSite:addChildRadar(childRad2)

	self.samSite:informChildrenOfStateChange()

	luaunit.assertEquals(updateCalled, true)
	luaunit.assertEquals(calls, 2)
end

--this test is related to testInformChildrenOfStateChange it tests, if SAM site go to their correct state depending on destruction of connection nodes and power sources
-- TODO: remove SkynetIADS variable to reduce test cupling its not needed for this test, sam and ew site could just be instantiated by ther own.
function TestSkynetIADSAbstractRadarElement:testSAMSiteAndEWRadarLoosesConnectionAndPowerSourceThenAddANewOneAgain()
	self:tearDown()
	self.testIADS = SkynetIADS:create()

	F.samGroup("SA-6", "SAM-SA-6")
	F.earlyWarningRadarUnit("EW-west2")

	local connectionNode = F.connectionNodeStatic("SA-6 Connection Node-autonomous-test")
	local nonAutonomousSAM = self.testIADS:addSAMSite("SAM-SA-6"):addConnectionNode(connectionNode)
	self.testIADS:addEarlyWarningRadar("EW-west2")

	self.testIADS:buildRadarCoverage()

	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), false)
	-- .miz: trigger.action.explosion(connectionNode:getPosition().p, 500)
	connectionNode:__destroy()
	--we simulate a call to the event, since in game will be triggered to late to for later checks in this unit test
	nonAutonomousSAM:onEvent(createDeadEvent())
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), true)

	local connectionNodeReAdd = F.connectionNodeStatic("SA-6 Connection Node-autonomous-readd")
	nonAutonomousSAM:addConnectionNode(connectionNodeReAdd)
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), false)

	local ewRadar = self.testIADS:getEarlyWarningRadarByUnitName("EW-west2")
	local ewConnectionNode = F.connectionNodeStatic("ew-west-connection-node-test")
	ewRadar:addConnectionNode(ewConnectionNode)

	ewConnectionNode:__destroy()
	--we simulate a call to the event, since in game will be triggered to late to for later checks in this unit test
	ewRadar:onEvent(createDeadEvent())
	luaunit.assertEquals(ewRadar:hasActiveConnectionNode(), false)
	luaunit.assertEquals(ewRadar:getAutonomousState(), true)
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), true)

	ewRadar:addConnectionNode(F.connectionNodeUnit("connection-node-ew"))
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), false)

	local ewPowerSource = F.powerSourceStatic("ew-power-source")
	ewRadar:addPowerSource(ewPowerSource)
	ewPowerSource:__destroy()
	--we simulate a call to the event, since in game will be triggered to late to for later checks in this unit test
	ewRadar:onEvent(createDeadEvent())
	luaunit.assertEquals(ewRadar:hasWorkingPowerSource(), false)
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), true)

	local ewPowerSource2 = F.powerSourceStatic("ew-power-source-2")
	ewRadar:addPowerSource(ewPowerSource2)
	luaunit.assertEquals(ewRadar:isActive(), true)
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), false)

	--test if a SAM site will stay active if it's in EW mode and it's parent EW radar becomes inoperable as long as SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK is set this will work
	nonAutonomousSAM:setActAsEW(true)
	ewPowerSource2:__destroy()
	--we simulate a call to the event, since in game will be triggered to late to for later checks in this unit test
	ewRadar:onEvent(createDeadEvent())
	luaunit.assertEquals(ewRadar:isActive(), false)
	luaunit.assertEquals(ewRadar:hasWorkingPowerSource(), false)
	luaunit.assertEquals(nonAutonomousSAM:isActive(), true)
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), true)

	--test if command center is destroyed all SAM sites and EW radars should go autonomous:
	ewRadar.powerSources = {}
	nonAutonomousSAM.powerSources = {}
	nonAutonomousSAM:setActAsEW(false)
	ewRadar:setToCorrectAutonomousState()
	ewRadar:informChildrenOfStateChange()

	luaunit.assertEquals(ewRadar:isActive(), true)
	luaunit.assertEquals(nonAutonomousSAM:isActive(), false)
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), false)

	local commandCenter = F.commandCenterStatic("command-center-unit-test")
	local comCenter = self.testIADS:addCommandCenter(commandCenter)

	self.testIADS:buildRadarCoverage()
	luaunit.assertEquals(#comCenter:getChildRadars(), 2)
	-- .miz: trigger.action.explosion(commandCenter:getPosition().p, 5000)
	commandCenter:__destroy()
	--we simulate a call to the event, since in game will be triggered to late to for later checks in this unit test
	comCenter:onEvent(createDeadEvent())

	luaunit.assertEquals(self.testIADS:isCommandCenterUsable(), false)
	luaunit.assertEquals(ewRadar:getAutonomousState(), true)
	luaunit.assertEquals(nonAutonomousSAM:getAutonomousState(), true)

	self.testIADS:deactivate()
end

--TODO: add tests for more check true / false combiations connectionnode power source etc.
function TestSkynetIADSAbstractRadarElement:testSetToCorrectAutonomousState()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	self.samSite:goAutonomous()
	luaunit.assertEquals(self.samSite:getAutonomousState(), true)

	function self.samSite:hasActiveConnectionNode()
		return true
	end

	local parentRad = {}
	function parentRad:hasWorkingPowerSource()
		return true
	end
	function parentRad:hasActiveConnectionNode()
		return true
	end
	function parentRad:getActAsEW()
		return true
	end
	function parentRad:isDestroyed()
		return false
	end

	self.samSite:addParentRadar(parentRad)
	self.samSite:setToCorrectAutonomousState()
	luaunit.assertEquals(self.samSite:getAutonomousState(), false)

	--check when SAM site does not have active connection node
	self.samSite:goAutonomous()
	luaunit.assertEquals(self.samSite:getAutonomousState(), true)

	function self.samSite:hasActiveConnectionNode()
		return false
	end

	parentRad = {}
	function parentRad:hasWorkingPowerSource()
		return true
	end
	function parentRad:hasActiveConnectionNode()
		return true
	end
	function parentRad:getActAsEW()
		return true
	end
	function parentRad:isDestroyed()
		return false
	end

	self.samSite:addParentRadar(parentRad)
	self.samSite:setToCorrectAutonomousState()
	luaunit.assertEquals(self.samSite:getAutonomousState(), true)
end

function TestSkynetIADSAbstractRadarElement:testWillGoLiveWhenAutonomousAndHARMDefenceFinished()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()
	self.samSite:setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DCS_AI)
	self.samSite:goSilentToEvadeHARM(1)
	self.samSite:finishHarmDefence()
	luaunit.assertEquals(self.samSite:isActive(), true)
end

function TestSkynetIADSAbstractRadarElement:testActAsEarlyWarningRadar()
	self.samSiteName = "SAM-SA-6"
	self:setUp()
	self.samSite:goDark()
	luaunit.assertEquals(self.samSite:isActive(), false)
	self.samSite:setActAsEW(true)
	luaunit.assertEquals(self.samSite:isActive(), true)
	self.samSite:targetCycleUpdateEnd()

	-- SAM Site should not shut down when out of ammo and in EW Mode
	function self.samSite:getRemainingNumberOfMissiles()
		return 0
	end

	self.samSite:goDarkIfOutOfAmmo()
	luaunit.assertEquals(self.samSite:isActive(), true)

	luaunit.assertEquals(self.samSite:isActive(), true)

	-- test when stopping EW mode the child SAM site should go dark
	F.samGroup("SA-6", "SAM-SA-6-2")
	local samSA62 = SkynetIADSSamSite:create(Group.getByName("SAM-SA-6-2"), self.skynetIADS)
	samSA62:setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	samSA62:setupElements()
	samSA62:goLive()
	self.samSite:addChildRadar(samSA62)
	samSA62:addParentRadar(self.samSite)
	self.samSite:informChildrenOfStateChange()
	luaunit.assertEquals(samSA62:getAutonomousState(), false)

	self.samSite:setActAsEW(false)
	luaunit.assertEquals(self.samSite:isActive(), false)
	luaunit.assertEquals(samSA62:getAutonomousState(), true)
	luaunit.assertEquals(samSA62:isActive(), false)
	samSA62:cleanUp()
end

-- ---- the jamming timeout (FIX-JAMMER-SILENCE-OUTLIVES-THE-JAMMER) --------------------------
--
-- jam() writes the site's ROE and stamps lastJammerUpdate. Nothing in the jammer ever takes the
-- weapon hold off again: what does is evaluateIfTargetsContainHARMs(), which goLive() schedules
-- every two seconds and which calls jam(0) -- a probability no roll can beat -- once ten seconds
-- have passed without the jammer saying anything. That is how a battery comes back when the
-- jammer is destroyed, switched off, flown out of range or loses line of sight.
--
-- It had no test, which is why a lot was once written to build a second release path beside it.
-- Two things to know if this ever goes red:
--
--   * the guard is `lastJammerUpdate > 0`, so a test whose clock still reads 0 when it jams can
--     never release and will look like a defect that is not there;
--   * the release rides on the HARM scan, so a site that is dark is not released -- it is not
--     scanning, and goLive() sets weapon free on the way back up anyway.

local function lastROE(samSite)
	local last
	for _, call in ipairs(samSite:getDCSRepresentation().__controllerCalls or {}) do
		if call.id == AI.Option.Air.id.ROE then
			last = call.value
		end
	end
	return last
end

function TestSkynetIADSAbstractRadarElement:testAJammedSiteIsReleasedTenSecondsAfterTheJammerStops()
	self.samSiteName = "SAM-SA-6"
	self:setUp()
	dcsStub.advanceClock(100) -- a mission is never at t=0 when a jammer acts, and the guard is > 0

	self.samSite:jam(100) -- a probability no roll can beat: certainly jammed
	luaunit.assertEquals(lastROE(self.samSite), AI.Option.Air.val.ROE.WEAPON_HOLD)

	-- the jammer says nothing more, as if it had just been shot down
	dcsStub.advanceClock(4)
	SkynetIADSAbstractRadarElement.evaluateIfTargetsContainHARMs(self.samSite)
	luaunit.assertEquals(
		lastROE(self.samSite),
		AI.Option.Air.val.ROE.WEAPON_HOLD,
		"four seconds in, the site is still held: the timeout is ten"
	)

	dcsStub.advanceClock(8)
	SkynetIADSAbstractRadarElement.evaluateIfTargetsContainHARMs(self.samSite)
	luaunit.assertEquals(
		lastROE(self.samSite),
		AI.Option.Air.val.ROE.WEAPON_FREE,
		"past ten seconds with no word from the jammer, the site is handed back"
	)
end

--- And it is handed back once, not on every scan afterwards: lastJammerUpdate is cleared, which is
--- what stops a battery being told it is free sixty times a minute for the rest of the mission.
function TestSkynetIADSAbstractRadarElement:testTheReleaseHappensOnceNotOnEveryScan()
	self.samSiteName = "SAM-SA-6"
	self:setUp()
	dcsStub.advanceClock(100)

	self.samSite:jam(100)
	dcsStub.advanceClock(12)
	SkynetIADSAbstractRadarElement.evaluateIfTargetsContainHARMs(self.samSite)
	local callsAfterRelease = #self.samSite:getDCSRepresentation().__controllerCalls

	for _ = 1, 5 do
		dcsStub.advanceClock(2)
		SkynetIADSAbstractRadarElement.evaluateIfTargetsContainHARMs(self.samSite)
	end

	luaunit.assertEquals(#self.samSite:getDCSRepresentation().__controllerCalls, callsAfterRelease)
	luaunit.assertEquals(self.samSite.lastJammerUpdate, 0)
end

os.exit(luaunit.LuaUnit.run())
