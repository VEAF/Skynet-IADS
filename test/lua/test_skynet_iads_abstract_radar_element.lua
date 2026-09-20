--- Standalone port of unit-tests/test-skynet-iads-abstract-radar-element.lua,
--- landing in slices. Slice 1 took the autonomy / coverage cluster, because
--- SkynetIADSAbstractRadarElement carries goLive, goDark,
--- setToCorrectAutonomousState and the HARM evasion and both tickets of
--- FEAT-LAST-LINE-OF-DEFENSE modify that class. Slice 2 takes the HARM timing
--- and defence states, the two engagement flags and the parent / child radar
--- bookkeeping. Slice 3 takes ammunition and missiles in flight, and the
--- engagement zone. Point defence and the cached-target behaviour are still
--- DCS-only; see test/lua/README.md for what is left.
---
--- The .miz version reads SAM groups, connection nodes, power sources and a
--- command centre baked into skynet-unit-tests.miz, and kills them with
--- trigger.action.explosion(...). Here they come from dcs-fixtures and are
--- killed with <obj>:__destroy() — the stub's trigger.action.explosion is a
--- no-op, so destroying the object directly is what stands in for the blast.
--- Everything else (the mocks, the assertions, their order) is the .miz test,
--- except where a comment above a test says otherwise. Those departures are
--- deliberate, each one is argued in the comment above the test it affects, and
--- test/lua/README.md lists them in one place — with what did NOT come across
--- and why. Porting a test is not copying it: a .miz test that only ever passed
--- because it ran against real DCS objects is not covered by a standalone test
--- asking the stub the same question.
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
	["SAM-SA-10"] = "SA-10",
	["SAM-SA-11"] = "SA-11",
	["SAM-SA-8"] = "SA-8",
	["SAM-Shilka"] = "Shilka",
}

--- The value of the last setOption(optionId, ...) the element's DCS representation was given, or
--- nil if it was never given one. Every fixture records its controller calls in order, so this is
--- how a test reads back an order the code issued rather than mocking the controller away.
local function lastOption(samSite, optionId)
	local last
	for _, call in ipairs(samSite:getDCSRepresentation().__controllerCalls or {}) do
		if call.id == optionId then
			last = call.value
		end
	end
	return last
end

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
	return lastOption(samSite, AI.Option.Air.id.ROE)
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

-- ---- slice 2: the two engagement flags ---------------------------------------------------
--
-- setCanEngageAirWeapons() is the only thing that ever writes the DCS ENGAGE_AIR_WEAPONS option,
-- and setCanEngageHARM() rides on it: a battery cannot shoot at a HARM without being allowed to
-- shoot at air weapons at all. The .miz version replaces getDCSRepresentation() with a mock whose
-- setOption asserts its own arguments. Here the fixture's controller already records every call in
-- order, so the assertions read the real order the real code issued -- see lastOption() above.

function TestSkynetIADSAbstractRadarElement:testCanEngageAirWeapons()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	--by default SAM site is not set to engage air weapons in Skynet:
	luaunit.assertEquals(self.samSite:getCanEngageAirWeapons(), false)
	luaunit.assertIs(self.samSite:setCanEngageAirWeapons(true), self.samSite)
	luaunit.assertEquals(self.samSite:getCanEngageAirWeapons(), true)
	luaunit.assertEquals(lastOption(self.samSite, AI.Option.Ground.id.ENGAGE_AIR_WEAPONS), true)

	self.samSite:setCanEngageAirWeapons(false)
	luaunit.assertEquals(self.samSite:getCanEngageAirWeapons(), false)
	luaunit.assertEquals(lastOption(self.samSite, AI.Option.Ground.id.ENGAGE_AIR_WEAPONS), false)

	-- a SAM site that the database says can engage HARMs gets that back when air weapons are
	-- re-enabled. The SA-6 is not one of them, so the flag is set by hand -- which is exactly what
	-- setupElements() does for an SA-10 or an SA-15, and what setCanEngageAirWeapons() reads.
	self.samSite.dataBaseSupportedTypesCanEngageHARM = true
	self.samSite:setCanEngageAirWeapons(true)
	luaunit.assertEquals(self.samSite:getCanEngageHARM(), true)
end

function TestSkynetIADSAbstractRadarElement:testCanEngageHARM()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	local airWeaponsSetTo = nil
	function self.samSite:setCanEngageAirWeapons(state)
		airWeaponsSetTo = state
	end

	luaunit.assertIs(self.samSite:setCanEngageHARM(true), self.samSite)
	luaunit.assertEquals(self.samSite:getCanEngageHARM(), true)
	luaunit.assertEquals(airWeaponsSetTo, true, "allowing HARM engagement has to allow air weapons")

	-- ... but withdrawing it does NOT take air weapons away again: a battery told to stop shooting
	-- at HARMs keeps shooting at other air weapons. That asymmetry is what the .miz test pinned.
	airWeaponsSetTo = nil
	self.samSite:setCanEngageHARM(false)
	luaunit.assertEquals(self.samSite:getCanEngageHARM(), false)
	luaunit.assertEquals(airWeaponsSetTo, nil)
end

-- ---- slice 2: the parent / child radar bookkeeping ----------------------------------------
--
-- Departure from the .miz, and the reason the mocks below are told apart by a field: the .miz
-- tests build their mock radars as bare `{}` and then assert with assertEquals. luaunit compares
-- tables by value, so two empty tables are equal to each other and to any third one -- the order
-- assertions could not fail whatever addParentRadar() did. Here the mocks carry a name and the
-- assertions use assertIs (identity), so the order they pin is the order the code produces:
-- insertToTableIfNotAlreadyAdded() appends, so it is the order they were added in.

function TestSkynetIADSAbstractRadarElement:testAddParentRadarAndClearParentRadars()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	local stateRecalculated = false
	function self.samSite:setToCorrectAutonomousState()
		stateRecalculated = true
	end

	luaunit.assertEquals(#self.samSite:getParentRadars(), 0)
	local parentRad1 = { name = "first" }
	self.samSite:addParentRadar(parentRad1)
	luaunit.assertEquals(#self.samSite:getParentRadars(), 1)

	--try adding the same radar again, make sure its not added:
	self.samSite:addParentRadar(parentRad1)
	luaunit.assertEquals(#self.samSite:getParentRadars(), 1)

	local parentRad2 = { name = "second" }
	self.samSite:addParentRadar(parentRad2)
	luaunit.assertEquals(#self.samSite:getParentRadars(), 2)

	luaunit.assertIs(self.samSite:getParentRadars()[1], parentRad1)
	luaunit.assertIs(self.samSite:getParentRadars()[2], parentRad2)

	luaunit.assertEquals(stateRecalculated, true, "gaining a parent radar has to re-decide autonomy")

	self.samSite:clearParentRadars()
	luaunit.assertEquals(#self.samSite:getParentRadars(), 0)
end

function TestSkynetIADSAbstractRadarElement:testAddChildRadarAndClearChildRadars()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()
	luaunit.assertEquals(#self.samSite:getChildRadars(), 0)
	local childRad1 = { name = "first" }
	self.samSite:addChildRadar(childRad1)
	luaunit.assertEquals(#self.samSite:getChildRadars(), 1)

	--try adding the same radar again, make sure its not added:
	self.samSite:addChildRadar(childRad1)
	luaunit.assertEquals(#self.samSite:getChildRadars(), 1)

	local childRad2 = { name = "second" }
	self.samSite:addChildRadar(childRad2)
	luaunit.assertEquals(#self.samSite:getChildRadars(), 2)

	luaunit.assertIs(self.samSite:getChildRadars()[1], childRad1)
	luaunit.assertIs(self.samSite:getChildRadars()[2], childRad2)

	self.samSite:clearChildRadars()
	luaunit.assertEquals(#self.samSite:getChildRadars(), 0)
end

--- A child radar is usable only when it has both power and a connection node: it is what the
--- network hands a site when it asks who is still reporting to it.
function TestSkynetIADSAbstractRadarElement:testGetUsableChildRadars()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	local hasPower, hasConnection = false, true
	local childRad1 = {
		hasWorkingPowerSource = function()
			return hasPower
		end,
		hasActiveConnectionNode = function()
			return hasConnection
		end,
	}
	self.samSite:addChildRadar(childRad1)
	luaunit.assertEquals(#self.samSite:getUsableChildRadars(), 0, "no power: not usable")

	hasPower, hasConnection = true, false
	luaunit.assertEquals(#self.samSite:getUsableChildRadars(), 0, "no connection node: not usable")

	hasPower, hasConnection = true, true
	luaunit.assertEquals(#self.samSite:getUsableChildRadars(), 1)
	luaunit.assertIs(self.samSite:getUsableChildRadars()[1], childRad1)

	self.samSite:clearChildRadars()
end

-- ---- slice 2: HARM timing and the defence states -----------------------------------------

function TestSkynetIADSAbstractRadarElement:testHARMDefenceStates()
	self.samSiteName = "SAM-SA-6"
	self:setUp()
	luaunit.assertEquals(self.samSite:isActive(), true)
	luaunit.assertEquals(self.samSite:isScanningForHARMs(), true, "a live site scans for HARMs")
	luaunit.assertEquals(self.samSite:isDefendingHARM(), false)
	self.samSite:goSilentToEvadeHARM()
	luaunit.assertEquals(self.samSite:isScanningForHARMs(), false, "a dark site has nothing to scan with")
	luaunit.assertEquals(self.samSite:isDefendingHARM(), true)
	luaunit.assertEquals(self.samSite:isActive(), false)
end

function TestSkynetIADSAbstractRadarElement:testGoLiveFailsWhenInHARMDefenceMode()
	self.samSiteName = "SAM-SA-6"
	self:setUp()
	luaunit.assertEquals(self.samSite:isActive(), true)
	luaunit.assertEquals(self.samSite:isScanningForHARMs(), true)
	self.samSite:goSilentToEvadeHARM()
	luaunit.assertEquals(self.samSite:isActive(), false)
	self.samSite:goLive()
	luaunit.assertEquals(self.samSite:isActive(), false, "the IADS must not be able to wake a site mid-evasion")
end

function TestSkynetIADSAbstractRadarElement:testFinishHARMDefence()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()
	self.samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(self.samSite:isActive(), false)
	self.samSite:finishHarmDefence()
	luaunit.assertEquals(self.samSite.harmShutdownTime, 0)
	luaunit.assertEquals(self.samSite:isDefendingHARM(), false)
	self.samSite:goLive()
	luaunit.assertEquals(self.samSite:isActive(), true)
end

--- Time to impact, in seconds, from a distance in nautical miles and a speed in knots. Zero speed
--- and zero distance both answer 0 -- the caller uses it as "no useful warning", not as an error.
function TestSkynetIADSAbstractRadarElement:testHARMTimeToImpactCalculation()
	self.samSiteName = "SAM-SA-6"
	self:setUp()
	luaunit.assertEquals(self.samSite:getSecondsToImpact(100, 10), 36000)
	luaunit.assertEquals(self.samSite:getSecondsToImpact(10, 400), 90)
	luaunit.assertEquals(self.samSite:getSecondsToImpact(0, 400), 0)
	luaunit.assertEquals(self.samSite:getSecondsToImpact(400, 0), 0)
end

--- The distance a HARM has to cover is the slant range, not the distance across the map: a missile
--- six kilometres up is further away than its shadow on the ground, and shutting down on the
--- shorter figure would have a battery hide too early.
function TestSkynetIADSAbstractRadarElement:testSlantRangeCalculationForHARMDefence()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()
	F.aircraftGroup("harm-shooter", { pos = { x = 30000, y = 6000, z = 0 } })
	local contact = F.iadsContact("harm-shooter-1")

	local radarUnit = self.samSite:getRadars()[1]
	local slantRange = self.samSite:getDistanceInMetersToContact(radarUnit, contact:getPosition().p)
	local overTheGround =
		SkynetIADSUtils.round(SkynetIADSUtils.get2DDist(radarUnit:getPosition().p, contact:getPosition().p), 0)

	luaunit.assertEquals(slantRange > overTheGround, true)
	-- and longer by what Pythagoras says, not by an arbitrary amount
	luaunit.assertEquals(slantRange, SkynetIADSUtils.round(math.sqrt(overTheGround * overTheGround + 6000 * 6000), 0))
end

--- How long a site stays dark: the time to impact plus a fixed 30 seconds, then a random top-up of
--- up to maxHarmPresetShutdownTime on top of that. The random draw is replaced here so the figure
--- is checkable; what the test pins is the arithmetic around it and the bounds it is drawn from.
function TestSkynetIADSAbstractRadarElement:testShutDownTimes()
	self.samSiteName = "SAM-SA-6"
	self:setUp()
	luaunit.assertEquals(self.samSite:calculateMinimalShutdownTimeInSeconds(30), 60)

	local savedRandom = SkynetIADSUtils.random
	local drawnFrom = nil
	SkynetIADSUtils.random = function(low, high)
		drawnFrom = { low, high }
		return 10
	end
	local maximalShutdownTime = self.samSite:calculateMaximalShutdownTimeInSeconds(20)
	SkynetIADSUtils.random = savedRandom

	luaunit.assertEquals(maximalShutdownTime, 30)
	luaunit.assertEquals(drawnFrom, { 1, 180 })
end

--- The angle between where a HARM is pointing and where the SAM site is from it, folded into
--- 0..180: 180 means the missile is heading straight at the site.
function TestSkynetIADSAbstractRadarElement:testCalculateAspectInDegrees()
	self.samSiteName = "SAM-SA-10"
	self:setUp()
	luaunit.assertEquals(self.samSite:calculateAspectInDegrees(0, 90), 90)
	luaunit.assertEquals(self.samSite:calculateAspectInDegrees(300, 90), 150)
	luaunit.assertEquals(self.samSite:calculateAspectInDegrees(010, 280), 90)
	luaunit.assertEquals(self.samSite:calculateAspectInDegrees(190, 350), 160)
	luaunit.assertEquals(self.samSite:calculateAspectInDegrees(090, 270), 180)
	luaunit.assertEquals(self.samSite:calculateAspectInDegrees(010, 170), 160)
end

--- Departure from the .miz, and the reason this one is rewritten rather than ported: the .miz test
--- of this name inserts one contact and asserts the count is 1 without ever calling
--- cleanUpOldObjectsIdentifiedAsHARMS(). It could not fail. What the method actually does is drop
--- every remembered HARM older than objectsIdentifiedAsHarmsMaxTargetAge (60 s), which is what
--- stops a site defending forever against a missile that hit the ground a minute ago.
function TestSkynetIADSAbstractRadarElement:testCleanUpOldObjectsIdentifiedAsHARMS()
	self.samSiteName = "SAM-SA-10"
	self:setUp()

	local function harmAged(seconds)
		return {
			getAge = function()
				return seconds
			end,
		}
	end

	local fresh = harmAged(10)
	table.insert(self.samSite.objectsIdentifiedAsHarms, fresh)
	table.insert(self.samSite.objectsIdentifiedAsHarms, harmAged(60))
	luaunit.assertEquals(self.samSite:getNumberOfObjectsItentifiedAsHARMS(), 2)

	self.samSite:cleanUpOldObjectsIdentifiedAsHARMS()
	luaunit.assertEquals(self.samSite:getNumberOfObjectsItentifiedAsHARMS(), 1, "60 s is already too old")
	luaunit.assertIs(self.samSite.objectsIdentifiedAsHarms[1], fresh)
end

--- The whole truth table of shallIgnoreHARMShutdown(), which is what decides whether a battery
--- stands its ground and shoots at the HARM instead of going dark. It says yes when the site can
--- do it alone -- enough launchers AND enough missiles AND allowed to engage HARMs -- or when its
--- point defences can, which needs both their missiles and their launchers. The .miz spells the
--- same nine cases out as nine blocks of five function definitions; the table is the same cases.
function TestSkynetIADSAbstractRadarElement:testShallIgnoreHARMShutdown()
	self.samSiteName = "SAM-SA-10"
	self:setUp()

	-- ownLaunchers, ownMissiles, canEngageHARM, pointDefenceMissiles, pointDefenceLaunchers
	local CASES = {
		{ true, true, false, false, false, false, "not allowed to engage HARMs, and no point defence" },
		{ false, false, true, false, false, false, "allowed, but nothing to shoot with" },
		{ false, true, true, false, true, false, "no launcher of its own, point defence has no missiles" },
		{ true, false, true, true, false, false, "no missiles of its own, point defence has no launchers" },
		{ true, true, true, false, false, true, "it can do it alone" },
		{ true, true, true, true, true, true, "both can" },
		{ true, false, true, true, true, true, "no missiles of its own, but the point defence is complete" },
		{ true, true, true, false, true, true, "alone, even though the point defence is out of missiles" },
		{ true, true, true, true, false, true, "alone, even though the point defence has no launchers" },
	}

	for _, case in ipairs(CASES) do
		local ownLaunchers, ownMissiles, canEngageHARM, pdMissiles, pdLaunchers, expected, why = unpack(case)
		function self.samSite:hasEnoughLaunchersToEngageMissiles()
			return ownLaunchers
		end
		function self.samSite:hasRemainingAmmoToEngageMissiles()
			return ownMissiles
		end
		function self.samSite:getCanEngageHARM()
			return canEngageHARM
		end
		function self.samSite:pointDefencesHaveRemainingAmmo()
			return pdMissiles
		end
		function self.samSite:pointDefencesHaveEnoughLaunchers()
			return pdLaunchers
		end
		luaunit.assertEquals(self.samSite:shallIgnoreHARMShutdown(), expected, why)
	end
end

--- Every option a mission writer sets on a SAM site returns the site itself, so a mission can
--- write them as one chain -- which is how documentation/api.md shows them.
function TestSkynetIADSAbstractRadarElement:testDaisychainSAMOptions()
	self.samSiteName = "SAM-SA-11"
	self:setUp()
	local powerSource = F.powerSourceStatic("SA-11-power-source")
	local connectionNode = F.connectionNodeStatic("SA-11-connection-node")

	local returnValue = self.samSite
		:setActAsEW(true)
		:addPowerSource(powerSource)
		:addConnectionNode(connectionNode)
		:setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
		:setGoLiveRangeInPercent(90)
		:setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)

	luaunit.assertIs(returnValue, self.samSite)
	luaunit.assertEquals(self.samSite:getActAsEW(), true)
	luaunit.assertEquals(self.samSite:getEngagementZone(), SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
	luaunit.assertEquals(self.samSite:getGoLiveRangeInPercent(), 90)
	luaunit.assertEquals(self.samSite:getAutonomousBehaviour(), SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	luaunit.assertIs(self.samSite:getConnectionNodes()[1], connectionNode)
	luaunit.assertIs(self.samSite:getPowerSources()[1], powerSource)
end

-- ---- slice 3: ammunition and missiles in flight -------------------------------------------
--
-- A battery that has nothing left to shoot with stops emitting: staying lit only tells the strike
-- package where it is. goDarkIfOutOfAmmo() is what enforces that, and it is polled from the HARM
-- scan rather than driven by an event, because DCS sends none when a missile leaves the rail.
--
-- Departure from the .miz, and it is the whole reason these read differently: the .miz tests
-- replace the launcher's getDCSRepresentation() with a mock whose getAmmo() rewrites the counts as
-- a side effect of being called. Here the fixture unit's ammunition is changed directly, with
-- dcsStub's __setAmmo, so the site is asked the question through the real DCS call it uses in the
-- mission. Note what "empty" means on that call: a launcher out of missiles answers **nil**, not a
-- table of zeroes, while a gun out of shells answers zeroes -- both cases are below.

function TestSkynetIADSAbstractRadarElement:testUpdateMissilesInFlight()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	local stillFlying = {
		isExist = function()
			return true
		end,
	}
	local alreadyGone = {
		isExist = function()
			return false
		end,
	}

	self.samSite.missilesInFlight = { alreadyGone, stillFlying }
	luaunit.assertEquals(self.samSite:getNumberOfMissilesInFlight(), 2)
	luaunit.assertEquals(self.samSite:hasMissilesInFlight(), true)

	self.samSite:updateMissilesInFlight()
	luaunit.assertEquals(self.samSite:getNumberOfMissilesInFlight(), 1)
	luaunit.assertIs(self.samSite.missilesInFlight[1], stillFlying, "the one that still exists is the one kept")
	luaunit.assertEquals(self.samSite:hasMissilesInFlight(), true)

	self.samSite.missilesInFlight = { alreadyGone }
	self.samSite:updateMissilesInFlight()
	luaunit.assertEquals(self.samSite:getNumberOfMissilesInFlight(), 0)
	luaunit.assertEquals(self.samSite:hasMissilesInFlight(), false)
end

--- What a site has left is the sum over its launchers, and it goes dark only when the last one is
--- empty. The fixture SA-6 has two launchers, which is what makes the sum worth asserting.
function TestSkynetIADSAbstractRadarElement:testShutDownWhenOutOfMissiles()
	self.samSiteName = "SAM-SA-6-2"
	self:setUp()

	local launchers = self.samSite:getLaunchers()
	luaunit.assertEquals(#launchers, 2)
	luaunit.assertEquals(launchers[1]:getInitialNumberOfMissiles(), 3)
	luaunit.assertEquals(self.samSite:getInitialNumberOfMissiles(), 6)
	luaunit.assertEquals(self.samSite:getRemainingNumberOfMissiles(), 6)

	--simulate firing of 1 missile
	launchers[1]:getDCSRepresentation():__setAmmo(F.launcherAmmo(2))
	luaunit.assertEquals(launchers[1]:getRemainingNumberOfMissiles(), 2)
	luaunit.assertEquals(self.samSite:getInitialNumberOfMissiles(), 6, "what it started with does not move")
	luaunit.assertEquals(self.samSite:getRemainingNumberOfMissiles(), 5)
	luaunit.assertEquals(self.samSite:hasRemainingAmmo(), true)
	self.samSite:goDarkIfOutOfAmmo()
	luaunit.assertEquals(self.samSite:isActive(), true)

	--DCS missile info is nil when no ammo is remaining
	launchers[1]:getDCSRepresentation():__setAmmo(nil)
	luaunit.assertEquals(launchers[1]:getRemainingNumberOfMissiles(), 0)
	luaunit.assertEquals(launchers[1]:getInitialNumberOfMissiles(), 3, "an empty rail still remembers its load")
	luaunit.assertEquals(self.samSite:getRemainingNumberOfMissiles(), 3)
	self.samSite:goDarkIfOutOfAmmo()
	luaunit.assertEquals(self.samSite:isActive(), true, "the other launcher still has missiles")

	launchers[2]:getDCSRepresentation():__setAmmo(nil)
	luaunit.assertEquals(self.samSite:getRemainingNumberOfMissiles(), 0)
	luaunit.assertEquals(self.samSite:hasRemainingAmmo(), false)
	self.samSite:goDarkIfOutOfAmmo()
	luaunit.assertEquals(self.samSite:isActive(), false)

	self.samSite:goLive()
	luaunit.assertEquals(self.samSite:isActive(), false, "and the network cannot wake an empty site")
end

--- The same rule for a radar-guided gun, which counts shells instead of missiles and answers a
--- table of zeroes rather than nil when the belts run out.
function TestSkynetIADSAbstractRadarElement:testShutDownShilkaWhenOutOfAmmo()
	self.samSiteName = "SAM-Shilka"
	self:setUp()

	local launcher = self.samSite:getLaunchers()[1]
	luaunit.assertEquals(launcher:getInitialNumberOfShells(), 2004)
	luaunit.assertEquals(self.samSite:getInitialNumberOfShells(), 2004)
	luaunit.assertEquals(self.samSite:getRemainingNumberOfMissiles(), 0, "a gun carries no missiles")

	launcher:getDCSRepresentation():__setAmmo(F.launcherShells(300, 200))
	luaunit.assertEquals(launcher:getRemainingNumberOfShells(), 500)
	luaunit.assertEquals(self.samSite:getInitialNumberOfShells(), 2004)
	luaunit.assertEquals(self.samSite:getRemainingNumberOfShells(), 500)
	luaunit.assertEquals(self.samSite:hasRemainingAmmo(), true)

	luaunit.assertEquals(self.samSite:isActive(), true)
	self.samSite:goDarkIfOutOfAmmo()
	luaunit.assertEquals(self.samSite:isActive(), true)

	launcher:getDCSRepresentation():__setAmmo(F.launcherShells(0, 0))
	luaunit.assertEquals(self.samSite:getRemainingNumberOfShells(), 0)
	luaunit.assertEquals(self.samSite:hasRemainingAmmo(), false)

	self.samSite:goDarkIfOutOfAmmo()
	luaunit.assertEquals(self.samSite:isActive(), false)
end

--- Losing power puts a site out whatever else is going on -- including with one of its own missiles
--- still in the air, which is the case this test exists for.
function TestSkynetIADSAbstractRadarElement:testWillSAMShutDownWhenItLoosesPowerAndAMissileIsInFlight()
	self.samSiteName = "SAM-SA-11"
	self:setUp()
	local powerSource = F.powerSourceStatic("SA-11-power-source")
	self.samSite:addPowerSource(powerSource)
	self.samSite:goLive()

	luaunit.assertEquals(self.samSite:hasWorkingPowerSource(), true)
	luaunit.assertEquals(self.samSite:isActive(), true)

	-- simulate that the SAM site has a missile in flight
	function self.samSite:hasMissilesInFlight()
		return true
	end

	-- .miz: trigger.action.explosion(powerSource:getPosition().p, 100)
	powerSource:__destroy()
	--we simulate a call to the event, since in game will be triggered to late to for later checks in this unit test
	self.samSite:onEvent(createDeadEvent())
	luaunit.assertEquals(self.samSite:hasWorkingPowerSource(), false)
	luaunit.assertEquals(self.samSite:isActive(), false)
end

--- A mission writer pointing addSAMSite() at the wrong group. Skynet builds the object anyway; it
--- just recognises nothing in it.
function TestSkynetIADSAbstractRadarElement:testCreateSamSiteFromInvalidGroup()
	self:setUp()
	self.samSite = SkynetIADSSamSite:create(F.unsupportedGroup("Invalid-for-sam"), self.skynetIADS)
	self.samSite:setupElements()

	luaunit.assertEquals(self.samSite:getNatoName(), "UNKNOWN")
	luaunit.assertEquals(#self.samSite:getRadars(), 0)
	luaunit.assertEquals(#self.samSite:getLaunchers(), 0)
	luaunit.assertEquals(#self.samSite:getSearchRadars(), 0)
	luaunit.assertEquals(#self.samSite:getTrackingRadars(), 0)
end

--- The all-in-one vehicles: one unit that is its own search radar and its own launcher, so the
--- same unit is found twice and there is no tracking radar to find.
function TestSkynetIADSAbstractRadarElement:testSamSiteGroupContainingOfOneUnitOnlySA8()
	self.samSiteName = "SAM-SA-8"
	self:setUp()
	luaunit.assertEquals(#self.samSite:getRadars(), 1)
	luaunit.assertEquals(#self.samSite:getLaunchers(), 1)
	luaunit.assertEquals(#self.samSite:getSearchRadars(), 1)
	luaunit.assertEquals(#self.samSite:getTrackingRadars(), 0)
	luaunit.assertEquals(self.samSite:getNatoName(), "SA-8")
end

-- ---- slice 3: the engagement zone, and when a site stays dark ------------------------------
--
-- Departure from the .miz, and the one place where a ported test would have been worth nothing:
-- the .miz versions assert the ranges the real DCS units report -- 53499.2265625 m for the SA-2's
-- Flat Face, read out of that unit's own sensor table. Those figures belong to DCS, not to Skynet,
-- and asking the stub the same question would only prove that dcs-fixtures says what dcs-fixtures
-- says. They stay in the .miz, and test/lua/README.md lists them under what needs the simulator.
--
-- What is Skynet's own, and is what these test, is the *decision*: which of the search radar, the
-- tracking radar and the launcher has to reach the contact before the site lights up, and what
-- setGoLiveRangeInPercent() does to that. The fixture's figures are stated here once so the
-- distances below can be read: search radar 120 km, launcher 40 km, maximum firing altitude 12 km.

local FIXTURE_SEARCH_RADAR_RANGE_M = 120000
local FIXTURE_LAUNCHER_RANGE_M = 40000

--- A contact 30 km out at 5000 m: inside the launcher's 40 km, inside its 12 km firing ceiling,
--- and well inside the search radar. The site's whole kill zone holds it.
local function contactInFiringRange(name)
	F.aircraftGroup(name, { pos = { x = 30000, y = 5000, z = 0 } })
	return F.iadsContact(name .. "-1")
end

function TestSkynetIADSAbstractRadarElement:testInformOfContactInRangeWhenEarlyWaringRadar()
	self.samSiteName = "SAM-SA-6"
	self:setUp()
	self.samSite:setActAsEW(true)
	local mockContact = {
		isIdentifiedAsHARM = function()
			return false
		end,
	}

	local askedAbout = nil
	function self.samSite:isTargetInRange(target)
		askedAbout = target
		return false
	end

	self.samSite:targetCycleUpdateStart()
	luaunit.assertEquals(self.samSite:isActive(), true)
	self.samSite:informOfContact(mockContact)
	luaunit.assertIs(askedAbout, mockContact)
	luaunit.assertEquals(self.samSite:isActive(), true)
	self.samSite:targetCycleUpdateEnd()
	luaunit.assertEquals(self.samSite:isActive(), true, "a site acting as an EW radar never goes dark on its own")
end

--- A dark site told about a contact inside its kill zone lights up. This is the door the network
--- uses on every cycle.
function TestSkynetIADSAbstractRadarElement:testSA2InformOfContactTargetInRangeMethod()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	self.samSite:goDark()
	luaunit.assertEquals(self.samSite:isActive(), false)

	local target = contactInFiringRange("test-in-firing-range-of-sa-2")

	luaunit.assertEquals(self.samSite:getEngagementZone(), SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_KILL_ZONE)
	luaunit.assertEquals(self.samSite:getSearchRadars()[1]:getTypeName(), "p-19 s-125 sr")

	-- Not a port of the .miz figures, which are DCS's: these pin the *fixture's* ranges, so that
	-- changing dcs-fixtures.lua breaks loudly here instead of quietly turning the distances the
	-- tests below reason about into something else. The site has all three kinds of element, and
	-- in kill-zone mode all three have to reach the contact.
	luaunit.assertEquals(self.samSite:getSearchRadars()[1]:getMaxRangeFindingTarget(), FIXTURE_SEARCH_RADAR_RANGE_M)
	luaunit.assertEquals(self.samSite:getTrackingRadars()[1]:getMaxRangeFindingTarget(), FIXTURE_SEARCH_RADAR_RANGE_M)
	luaunit.assertEquals(self.samSite:getLaunchers()[1]:getRange(), FIXTURE_LAUNCHER_RANGE_M)

	luaunit.assertEquals(self.samSite:isTargetInRange(target), true)
	self.samSite:informOfContact(target)
	luaunit.assertEquals(self.samSite:isActive(), true)
end

--- goDark() refuses while the site's own radar still holds something: the site is shooting.
function TestSkynetIADSAbstractRadarElement:testSA2WillNotGoDarkIfTargetIsInRange()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	local target = contactInFiringRange("test-in-firing-range-of-sa-2")

	--we return a detected target, to pervent SAM site going dark
	function self.samSite:getDetectedTargets()
		return { target }
	end

	self.samSite:informOfContact(target)
	self.samSite:goDark()
	luaunit.assertEquals(self.samSite:isActive(), true)
end

--- And it refuses while one of its missiles is still in the air, even with nothing on the scope:
--- going dark then would abandon the missile.
function TestSkynetIADSAbstractRadarElement:testSA2WillNotGoDarkIfOutOfMisslesAndMissilesAreStillInFlight()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	luaunit.assertEquals(self.samSite:hasMissilesInFlight(), false)

	self.samSite.missilesInFlight = {
		{
			isExist = function()
				return true
			end,
		},
	}
	luaunit.assertEquals(self.samSite:hasMissilesInFlight(), true)
	luaunit.assertEquals(#self.samSite:getDetectedTargets(), 0)
	luaunit.assertEquals(self.samSite:isActive(), true)
	self.samSite:goDark()
	luaunit.assertEquals(self.samSite:isActive(), true)
end

--- A HARM outranks both: a site evading one goes dark with the target still on the scope.
function TestSkynetIADSAbstractRadarElement:testSA2WillGoDarkWithTargetsInRangeAndHARMDetected()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	local target = contactInFiringRange("test-in-firing-range-of-sa-2")
	function self.samSite:getDetectedTargets()
		return { target }
	end

	self.samSite:informOfContact(target)
	self.samSite:goSilentToEvadeHARM(5)
	luaunit.assertEquals(self.samSite:isActive(), false)
end

--- So does being out of ammunition with nothing in the air: holding the target is pointless when
--- there is nothing left to send at it.
function TestSkynetIADSAbstractRadarElement:testSA2WillgoDarkIfOutOfAmmoNoMissilesAreInFlightAndTargetStillInRange()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	local target = contactInFiringRange("test-in-firing-range-of-sa-2")
	function self.samSite:getDetectedTargets()
		return { target }
	end
	function self.samSite:getRemainingNumberOfMissiles()
		return 0
	end

	luaunit.assertEquals(self.samSite:hasMissilesInFlight(), false)
	luaunit.assertEquals(self.samSite:isActive(), true)
	self.samSite:goDark()
	luaunit.assertEquals(self.samSite:isActive(), false)
end

--- An empty site stays dark when the network offers it a target it never saw itself.
function TestSkynetIADSAbstractRadarElement:testSA2OutOfMissilesNoMissilesInFlightIsInformedOfTargetByIADSHasNotDetectedTargetWithOwnRadar()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	function self.samSite:getRemainingNumberOfMissiles()
		return 0
	end

	self.samSite:goDark()
	luaunit.assertEquals(self.samSite:hasMissilesInFlight(), false)
	luaunit.assertEquals(self.samSite:isActive(), false)

	local target = contactInFiringRange("test-in-firing-range-of-sa-2")
	self.samSite:informOfContact(target)
	luaunit.assertEquals(self.samSite:isActive(), false)
end

--- setGoLiveRangeInPercent() shrinks the range the site is willing to light up at. In the default
--- kill-zone mode it is the launcher's reach that shrinks: 60% of 40 km puts a contact at 30 km
--- outside it, where 100% held it -- which is the assertion above, on the same distance.
function TestSkynetIADSAbstractRadarElement:testSA2GoLiveRangeInPercentInKillZone()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	luaunit.assertIs(self.samSite:getEngagementZone(), SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_KILL_ZONE)
	local target = contactInFiringRange("test-in-firing-range-of-sa-2")
	luaunit.assertEquals(self.samSite:getLaunchers()[1]:isInRange(target), true, "at 100% the launcher holds it")

	self.samSite:setGoLiveRangeInPercent(60)
	luaunit.assertEquals(self.samSite:getLaunchers()[1]:isInRange(target), false)
	luaunit.assertEquals(self.samSite:isTargetInRange(target), false)
end

--- In search-range mode it is the search radar's reach that shrinks, and the launcher stops
--- counting altogether: 80% of 120 km leaves a contact at 100 km outside.
function TestSkynetIADSAbstractRadarElement:testSA2GoLiveRangeInPercentSearchRange()
	self.samSiteName = "SAM-SA-2"
	self:setUp()
	self.samSite:setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
	F.aircraftGroup("test-outer-search-range", { pos = { x = 100000, y = 5000, z = 0 } })
	local target = F.iadsContact("test-outer-search-range-1")

	luaunit.assertEquals(
		self.samSite:isTargetInRange(target),
		true,
		"at 100% the search radar reaches 100 km, and the launcher is not consulted in this mode"
	)

	self.samSite:setGoLiveRangeInPercent(80)
	local radars = self.samSite:getSearchRadars()
	for i = 1, #radars do
		luaunit.assertEquals(radars[i]:isInRange(target), false)
	end
	luaunit.assertEquals(self.samSite:isTargetInRange(target), false)
end

--- Departure from the .miz: the original goes dark and informs the site a second time without
--- reopening the target cycle, so informOfContact() returns on its `targetsInRange == false` guard
--- and the site was never going to light up whatever the range was. Here each half runs through a
--- real targetCycleUpdateStart(), so the second one fails on the range and not on the guard.
function TestSkynetIADSAbstractRadarElement:testSA8GoLiveRangeInPercent()
	self.samSiteName = "SAM-SA-8"
	self:setUp()
	local target = contactInFiringRange("test-sa-8-will-go-active")

	self.samSite:goDark()
	self.samSite:targetCycleUpdateStart()
	self.samSite:informOfContact(target)
	luaunit.assertEquals(self.samSite:isActive(), true)

	self.samSite:setGoLiveRangeInPercent(20)
	self.samSite:goDark()
	self.samSite:targetCycleUpdateStart()
	self.samSite:informOfContact(target)
	luaunit.assertEquals(self.samSite:getLaunchers()[1]:isInRange(target), false)
	luaunit.assertEquals(self.samSite:isActive(), false)
end

os.exit(luaunit.LuaUnit.run())
