--- Standalone port of unit-tests/test-skynet-iads-harm-detection.lua.
--- That legacy suite is gone: every test of it runs here, so both its copies -- the loose
--- file and the one baked into skynet-unit-tests.miz -- were removed by
--- CHORE-PROFESSIONALIZE-THE-REPO ticket 04, rather than left to drift against this one.
--- All 6 tests are mock-driven and require only local mock tables.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

TestSkynetIADSHARMDetection = {}

function TestSkynetIADSHARMDetection:setUp()
	dcsStub.reset()
	local iads = SkynetIADS:create()
	self.harmDetection = SkynetIADSHARMDetection:create(iads)
end

function TestSkynetIADSHARMDetection:testContact0GroundSpeed()
	local mockContact = {}
	function mockContact:getGroundSpeedInKnots(round)
		return 0
	end

	local calledProfileInfo = false
	function mockContact:getSimpleAltitudeProfile()
		calledProfileInfo = true
	end
	self.harmDetection:setContacts({ mockContact })
	self.harmDetection:evaluateContacts()
	luaunit.assertEquals(calledProfileInfo, false)
end

function TestSkynetIADSHARMDetection:testEvaluateContactsContactIsHARMInClimb()
	--test with a contact that shall be identified as a HARM
	local mockContactHARM = {}

	function mockContactHARM:getGroundSpeedInKnots(round)
		return 1500
	end

	function mockContactHARM:isHARMStateUnknown()
		return true
	end

	function mockContactHARM:getSimpleAltitudeProfile()
		return { SkynetIADSContact.CLIMB }
	end

	local harmStateCalled = false
	function mockContactHARM:setHARMState(state)
		harmStateCalled = true
		luaunit.assertEquals(state, SkynetIADSContact.HARM)
	end

	local calls = 0
	function mockContactHARM:isIdentifiedAsHARM()
		calls = calls + 1
		if calls == 2 then
			return true
		else
			return false
		end
	end

	local mockRadar = {}
	function mockRadar:getHARMDetectionChance()
		return 50
	end

	function mockContactHARM:getAbstractRadarElementsDetected()
		return { mockRadar }
	end

	local probCalled = false
	function self.harmDetection:shallReactToHARM(prob)
		luaunit.assertEquals(prob, 50)
		probCalled = true
		return true
	end

	local contactInform = false
	function self.harmDetection:informRadarsOfHARM(contact)
		luaunit.assertEquals(mockContactHARM, contact)
		contactInform = true
	end

	self.harmDetection:setContacts({ mockContactHARM })

	local calledCleanedAgedTargets = false
	function self.harmDetection:cleanAgedContacts()
		calledCleanedAgedTargets = true
	end
	self.harmDetection:evaluateContacts()

	luaunit.assertEquals(calledCleanedAgedTargets, true)

	luaunit.assertEquals(harmStateCalled, true)
	luaunit.assertEquals(probCalled, true)
	luaunit.assertEquals(contactInform, true)
end

function TestSkynetIADSHARMDetection:testEvaluateContactsContactDetectedAsHARMHas3rdAltitudeChangeRecorded()
	--a contact previously identified as a HARM has a 3rd altitude change recorded, this means it's an aircraft previously falsely detected as HARM
	local mockContactHARM = {}

	function mockContactHARM:getGroundSpeedInKnots(round)
		return 1000
	end

	function mockContactHARM:isHARMStateUnknown()
		return false
	end

	function mockContactHARM:getSimpleAltitudeProfile()
		return { SkynetIADSContact.DESCEND, SkynetIADSContact.CLIMB, SkynetIADSContact.DESCEND }
	end

	local harmStateCalled = false
	function mockContactHARM:setHARMState(state)
		harmStateCalled = true
		luaunit.assertEquals(state, SkynetIADSContact.HARM_UNKNOWN)
	end

	local calls = 0
	function mockContactHARM:isIdentifiedAsHARM()
		calls = calls + 1
		if calls == 2 then
			return true
		else
			return false
		end
	end

	local contactInform = false
	function self.harmDetection:informRadarsOfHARM(contact)
		contactInform = true
	end

	function self.harmDetection:getNewRadarsThatHaveDetectedContact(contact)
		return { "MockRadar" }
	end

	self.harmDetection:setContacts({ mockContactHARM })
	self.harmDetection:evaluateContacts()

	luaunit.assertEquals(harmStateCalled, true)
	luaunit.assertEquals(contactInform, false)
end

function TestSkynetIADSHARMDetection:testGetDetectionProbability()
	local mockSAM1 = {}
	function mockSAM1:getHARMDetectionChance()
		return 60
	end

	local mockSam2 = {}
	function mockSam2:getHARMDetectionChance()
		return 30
	end

	local mockNewRadarsDetected = { mockSAM1, mockSam2 }

	luaunit.assertEquals(self.harmDetection:getDetectionProbability(mockNewRadarsDetected), 72)

	function mockSAM1:getHARMDetectionChance()
		return 20
	end

	function mockSam2:getHARMDetectionChance()
		return 90
	end

	luaunit.assertEquals(self.harmDetection:getDetectionProbability(mockNewRadarsDetected), 92)
end

function TestSkynetIADSHARMDetection:testGetNewRadarsThatHaveDetectedContact()
	local mockContact = {}
	local mockRadar1 = { "MockRadar1" }
	local mockRadar2 = { "MockRadar2" }
	local detectedRadars = { mockRadar1, mockRadar2 }
	function mockContact:getAbstractRadarElementsDetected()
		return detectedRadars
	end
	local result = self.harmDetection:getNewRadarsThatHaveDetectedContact(mockContact)
	luaunit.assertEquals(result, { mockRadar1, mockRadar2 })
	luaunit.assertEquals(self.harmDetection.contactRadarsEvaluated[mockContact], { mockRadar1, mockRadar2 })

	local result2 = self.harmDetection:getNewRadarsThatHaveDetectedContact(mockContact)
	luaunit.assertEquals(result2, {})
	luaunit.assertEquals(self.harmDetection.contactRadarsEvaluated[mockContact], { mockRadar1, mockRadar2 })

	local mockRadar3 = { "MockRadar3" }
	table.insert(detectedRadars, mockRadar3)
	luaunit.assertEquals(#mockContact:getAbstractRadarElementsDetected(), 3)
	local result3 = self.harmDetection:getNewRadarsThatHaveDetectedContact(mockContact)
	luaunit.assertEquals(result3, { mockRadar3 })
	luaunit.assertEquals(self.harmDetection.contactRadarsEvaluated[mockContact], { mockRadar1, mockRadar2, mockRadar3 })

	local mockRadar4 = { "MockRadar4" }
	table.insert(detectedRadars, mockRadar4)
	local result4 = self.harmDetection:getNewRadarsThatHaveDetectedContact(mockContact)
	luaunit.assertEquals(result4, { mockRadar4 })
	luaunit.assertEquals(
		self.harmDetection.contactRadarsEvaluated[mockContact],
		{ mockRadar1, mockRadar2, mockRadar3, mockRadar4 }
	)
end

function TestSkynetIADSHARMDetection:testCleanAgedContacts()
	local mockContact1 = {}
	function mockContact1:getAge()
		return 1
	end

	local mockContact2 = {}
	function mockContact2:getAge()
		return 33
	end

	local contactRadars = {}
	contactRadars[mockContact1] = "keep"
	contactRadars[mockContact2] = "delete"
	self.harmDetection.contactRadarsEvaluated = contactRadars
	self.harmDetection:cleanAgedContacts()

	local count = 0
	for key, value in pairs(self.harmDetection.contactRadarsEvaluated) do
		count = count + 1
	end
	luaunit.assertEquals(count, 1)
	luaunit.assertEquals(self.harmDetection.contactRadarsEvaluated[mockContact1], "keep")
end

-- ---- CHORE-TEST-COVERAGE-FLOOR ticket 06 ---------------------------------------------------
--
-- The tests above are the port of the .miz suite and drive evaluateContacts() with mock
-- contacts. What they never reached is the half of the decision that says "no": the branch that
-- marks a contact NOT_HARM, the one that takes an identification back when the track turns out
-- to manoeuvre, the debug output either writes, and the handing of a confirmed HARM to the
-- network. FIX-STALE-HARM-SILENCE exists because this area is easy to get wrong.

--- A contact that looks exactly like an anti-radiation missile: fast, and on a profile with no
--- more than two legs. `harmState` is what the detection is deciding, so it is real state here
--- rather than an assertion trap.
local function fastContact(name, profile)
	local contact = {
		harmState = SkynetIADSContact.HARM_UNKNOWN,
		__name = name,
	}
	function contact:getGroundSpeedInKnots(_)
		return 1500 -- well past HARM_THRESHOLD_SPEED_KTS
	end
	function contact:getSimpleAltitudeProfile()
		return profile or { SkynetIADSContact.CLIMB }
	end
	function contact:getAbstractRadarElementsDetected()
		return { {
			getHARMDetectionChance = function()
				return 90
			end,
		} }
	end
	function contact:setHARMState(state)
		self.harmState = state
	end
	function contact:isIdentifiedAsHARM()
		return self.harmState == SkynetIADSContact.HARM
	end
	function contact:getAge()
		return 0
	end
	function contact:getName()
		return name
	end
	function contact:getTypeName()
		return "AGM-88"
	end
	return contact
end

--- Replaces math.random for the duration of `body` so the coin toss inside shallReactToHARM is
--- a decision the test makes rather than one it hopes for. Restored whatever happens -- through
--- pcall, so a failing assertion inside `body` cannot leave a fixed math.random behind to poison
--- every test that runs after it.
---
--- luacheck objects to assigning a field of a standard global, and it is right to in general.
--- Here it is the point: shallReactToHARM() rolls a die, and a test that cannot control the die
--- can only assert what happens to be true this run. Silenced at the two lines that do it, the
--- way skynet-iads-utils.lua silences 143 for its unpack fallback, rather than in .luacheckrc --
--- the ratchet there exists to erode, never to grow.
local function withRoll(value, body)
	local realRandom = math.random
	math.random = function() -- luacheck: ignore 122
		return value
	end
	local ok, err = pcall(body)
	math.random = realRandom -- luacheck: ignore 122
	if not ok then
		error(err, 0)
	end
end

local function loggedLines()
	local lines = {}
	for i = 1, #dcsStub.logs do
		lines[i] = dcsStub.logs[i].text
	end
	return lines
end

local function lineWith(lines, needle)
	for i = 1, #lines do
		if lines[i]:find(needle, 1, true) then
			return lines[i]
		end
	end
	return nil
end

--- The roll beats the probability, so the network decides this one is not a HARM. Nothing is
--- silenced, and the contact is marked so the next cycle does not re-evaluate it from scratch.
function TestSkynetIADSHARMDetection:testAContactTheRollAcquitsIsMarkedNotAHARM()
	local contact = fastContact("Pilot #12")
	self.harmDetection:setContacts({ contact })
	-- detection probability is 90; a roll of 91 is above it, so shallReactToHARM says no
	withRoll(91, function()
		self.harmDetection:evaluateContacts()
	end)
	luaunit.assertEquals(contact.harmState, SkynetIADSContact.NOT_HARM)
	luaunit.assertEquals(contact:isIdentifiedAsHARM(), false)
end

function TestSkynetIADSHARMDetection:testARollAtTheProbabilityIdentifiesTheHARM()
	local contact = fastContact("Pilot #12")
	self.harmDetection:setContacts({ contact })
	-- 90 >= 90: the comparison is inclusive, which is the edge worth pinning
	withRoll(90, function()
		self.harmDetection:evaluateContacts()
	end)
	luaunit.assertEquals(contact.harmState, SkynetIADSContact.HARM)
end

--- Both outcomes write a line naming the contact and the probability, and both are gated by the
--- harmDefence setting. This is what someone reads in a dcs.log when a battery went silent and
--- they want to know what convinced it.
function TestSkynetIADSHARMDetection:testHARMDefenceLoggingReportsBothOutcomesWithTheProbability()
	self.harmDetection.iads:getDebugSettings().harmDefence = true

	local identified = fastContact("Pilot #12")
	self.harmDetection:setContacts({ identified })
	dcsStub.logs = {}
	withRoll(1, function()
		self.harmDetection:evaluateContacts()
	end)
	local line = lineWith(loggedLines(), "HARM IDENTIFIED:")
	luaunit.assertNotNil(line)
	luaunit.assertStrContains(line, "AGM-88")
	luaunit.assertStrContains(line, "90%")

	local acquitted = fastContact("Pilot #13")
	self.harmDetection:setContacts({ acquitted })
	dcsStub.logs = {}
	withRoll(100, function()
		self.harmDetection:evaluateContacts()
	end)
	local acquittedLine = lineWith(loggedLines(), "HARM NOT IDENTIFIED:")
	luaunit.assertNotNil(acquittedLine)
	luaunit.assertStrContains(acquittedLine, "90%")
end

function TestSkynetIADSHARMDetection:testNeitherOutcomeIsLoggedWhileHARMDefenceIsOff()
	luaunit.assertEquals(self.harmDetection.iads:getDebugSettings().harmDefence, false, "off by default")
	self.harmDetection:setContacts({ fastContact("Pilot #12") })
	dcsStub.logs = {}
	withRoll(1, function()
		self.harmDetection:evaluateContacts()
	end)
	luaunit.assertNil(lineWith(loggedLines(), "HARM IDENTIFIED:"))
end

--- A missile flies one leg. A track already called a HARM that then shows a third leg was an
--- aircraft manoeuvring all along, and the identification is taken back -- otherwise every
--- battery it overflies stays silent for nothing.
function TestSkynetIADSHARMDetection:testAnIdentificationIsTakenBackWhenTheTrackManoeuvres()
	self.harmDetection.iads:getDebugSettings().harmDefence = true
	local contact = fastContact("Pilot #12", {
		SkynetIADSContact.CLIMB,
		SkynetIADSContact.DESCEND,
		SkynetIADSContact.CLIMB,
	})
	contact.harmState = SkynetIADSContact.HARM

	self.harmDetection:setContacts({ contact })
	dcsStub.logs = {}
	self.harmDetection:evaluateContacts()

	luaunit.assertEquals(contact.harmState, SkynetIADSContact.HARM_UNKNOWN)
	local line = lineWith(loggedLines(), "CORRECTING HARM STATE")
	luaunit.assertNotNil(line)
	luaunit.assertStrContains(line, "Pilot #12")
end

--- The point of identifying a HARM at all: every usable battery and every usable early warning
--- radar is told, through the real getUsableSAMSites() / getUsableEarlyWarningRadars() rather
--- than a mock list -- a warning that goes to a list nobody builds warns nobody.
function TestSkynetIADSHARMDetection:testAConfirmedHARMIsHandedToEveryUsableElement()
	local iads = SkynetIADS:create("Ruby")
	local harmDetection = SkynetIADSHARMDetection:create(iads)

	local informed = {}
	local function enrol(element, name)
		function element:informOfHARM(contact)
			informed[#informed + 1] = name
		end
		function element:getDetectedTargets()
			return {}
		end
	end

	F.samGroup("SA-6", "RED-SAM-north", { pos = { x = 0, y = 0, z = 0 }, coalition = 1 })
	enrol(iads:addSAMSite("RED-SAM-north"), "RED-SAM-north")
	F.samGroup("SA-2", "RED-SAM-south", { pos = { x = 20000, y = 0, z = 0 }, coalition = 1 })
	enrol(iads:addSAMSite("RED-SAM-south"), "RED-SAM-south")
	F.earlyWarningRadarUnit("EW-north", { pos = { x = 0, y = 0, z = 0 }, coalition = 1 })
	enrol(iads:addEarlyWarningRadar("EW-north"), "EW-north")

	local contact = fastContact("Pilot #12")
	contact.harmState = SkynetIADSContact.HARM
	harmDetection:setContacts({ contact })
	harmDetection:evaluateContacts()

	table.sort(informed)
	luaunit.assertEquals(informed, { "EW-north", "RED-SAM-north", "RED-SAM-south" })
	iads:deactivate()
end

--- An element the network cannot use -- no working connection node -- is not warned, because it
--- is not in the usable list. Worth its own test: the difference between "every element" and
--- "every usable element" is a battery left emitting while a missile is inbound.
function TestSkynetIADSHARMDetection:testAnUnusableBatteryIsNotWarned()
	local iads = SkynetIADS:create("Ruby")
	local harmDetection = SkynetIADSHARMDetection:create(iads)

	local informed = {}
	F.samGroup("SA-6", "RED-SAM-cut-off", { pos = { x = 0, y = 0, z = 0 }, coalition = 1 })
	local samSite = iads:addSAMSite("RED-SAM-cut-off")
	function samSite:informOfHARM(_)
		informed[#informed + 1] = "RED-SAM-cut-off"
	end
	function samSite:getDetectedTargets()
		return {}
	end
	samSite:addConnectionNode(F.connectionNodeStatic("RED-SAM-cut-off-node"))
	dcsStub.world["RED-SAM-cut-off-node"]:__destroy()

	local contact = fastContact("Pilot #12")
	contact.harmState = SkynetIADSContact.HARM
	harmDetection:setContacts({ contact })
	harmDetection:evaluateContacts()

	luaunit.assertEquals(informed, {})
	iads:deactivate()
end

os.exit(luaunit.LuaUnit.run())
