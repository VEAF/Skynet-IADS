--- Tests for FIX-STALE-HARM-SILENCE (issue #3): a site torn down while it was evading a
--- HARM must be able to come back to life.
---
--- cleanUp() cancelled the HARM timers but left harmSilenceID set, and goLive() refuses
--- while that field is there. Nothing would ever clear it -- the task that would have is
--- the one cleanUp just removed -- so the site was deaf for the rest of the mission.
---
--- What matters is not that the field is nil, it is that the site answers again. So the
--- three tests that carry this suite drive the three doors a mission actually uses:
--- network designation, the last line of defense, and SkynetIADS:reportContact(). All
--- three pass through the same guard in goLive(), and all three are what a player notices.
--- The state assertions come after, as the narrow unit check.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

local RED = 1 -- coalition.side.RED
local BLUE = 2 -- coalition.side.BLUE

TestSkynetIADSHarmSilenceCleanup = {}

--- A RED SA-2 at the origin, held dark by a RED EW radar 100 km away whose 120 km range
--- covers it. The EW radar reports nothing unless a test says otherwise.
function TestSkynetIADSHarmSilenceCleanup:buildNetwork()
	local iads = SkynetIADS:create()
	--a fixed radius makes every distance in these tests a decision rather than a draw
	iads:setLastLineOfDefenceRadius(10000, 10000)

	F.earlyWarningRadarUnit("EW-north", { pos = { x = 100000, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-north")
	function ewRadar:getDetectedTargets()
		return {}
	end

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end

	iads:activate()
	return iads, samSite, ewRadar
end

--- The teardown a mission reaches on respawn: SkynetIADS:deactivate() runs cleanUp() on
--- every site, and the sites survive it -- deactivate() empties no list, so activate()
--- puts the very same objects back to work. Going through the public pair rather than
--- calling samSite:cleanUp() is what makes this a mission scenario instead of a unit poke.
function TestSkynetIADSHarmSilenceCleanup:respawnCycle(iads)
	iads:deactivate()
	iads:activate()
end

function TestSkynetIADSHarmSilenceCleanup:setUp()
	dcsStub.reset()
end

function TestSkynetIADSHarmSilenceCleanup:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--the network door: an EW radar holds the contact and the battery is told to engage it
function TestSkynetIADSHarmSilenceCleanup:testCleanedUpSiteStillWakesOnNetworkDesignation()
	local iads, samSite, ewRadar = self:buildNetwork()
	self.iads = iads
	--switched off so that nothing but the designation can light this site up
	iads:setLastLineOfDefence(false)
	--10 km out at 2000 m: inside the SA-2's 40 km launcher range, so informOfContact() takes it
	F.aircraftGroup("intruder", { pos = { x = 10000, y = 2000, z = 0 }, coalition = BLUE })
	function ewRadar:getDetectedTargets()
		return { F.iadsContact("intruder-1") }
	end

	samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(samSite:isDefendingHARM(), true)

	self:respawnCycle(iads)

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)
	luaunit.assertEquals(samSite:hasTargetsInRange(), true)
end

--the last line of defense: no radar holds anything, the aircraft is simply overhead
function TestSkynetIADSHarmSilenceCleanup:testCleanedUpSiteStillWakesOnTheLastLineOfDefence()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(samSite:isDefendingHARM(), true)

	self:respawnCycle(iads)

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)
end

--the public door, the one VEAF's spotter network calls
function TestSkynetIADSHarmSilenceCleanup:testCleanedUpSiteStillAnswersReportContact()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	--45 km out: outside the kill zone and outside the drawn radius, so only reportContact reaches it
	local intruder = F.aircraftGroup("intruder", { pos = { x = 45000, y = 500, z = 0 }, coalition = BLUE })

	samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(samSite:isDefendingHARM(), true)

	self:respawnCycle(iads)

	luaunit.assertEquals(iads:reportContact(intruder, samSite), true)
	luaunit.assertEquals(samSite:isActive(), true)
end

--the narrow check underneath the three above: the fields the timers stood for are gone
function TestSkynetIADSHarmSilenceCleanup:testCleanUpClearsTheHARMState()
	local iads, samSite = self:buildNetwork()
	self.iads = iads

	samSite:goLive()
	samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(samSite:isDefendingHARM(), true)
	luaunit.assertTrue(samSite:getHARMShutdownTime() > 0)

	samSite:cleanUp()

	luaunit.assertEquals(samSite:isDefendingHARM(), false)
	luaunit.assertEquals(samSite:getHARMShutdownTime(), 0)
	luaunit.assertEquals(samSite:isScanningForHARMs(), false)
end

--cleanUp() forgets the HARM defence, it must never finish it: finishHarmDefence() ends in
--goAutonomous(), which on a DCS-AI site means goLive() -- a battery being torn down would
--light its radar up on the way out, with the missile still inbound
function TestSkynetIADSHarmSilenceCleanup:testCleanUpDoesNotLightUpAnAutonomousSite()
	local iads = SkynetIADS:create()
	self.iads = iads
	--no EW radar anywhere, so the site is autonomous and handed back to the DCS AI
	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end
	iads:activate()
	luaunit.assertEquals(samSite:getAutonomousState(), true)

	samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(samSite:isActive(), false)

	samSite:cleanUp()

	luaunit.assertEquals(samSite:isActive(), false)
end

os.exit(luaunit.LuaUnit.run())
