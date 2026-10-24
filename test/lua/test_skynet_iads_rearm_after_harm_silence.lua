--- Tests for FIX-REARM-AFTER-HARM-SILENCE: a site HARM defence silenced gets its AI back when the
--- silence ends, because a DCS ammo truck does not rearm a unit whose AI is off.
---
--- The silence turns the AI off against a DCS multiplayer bug, and only goLive() used to turn it
--- back on -- which refuses a site with no ammunition left. A site silenced after it ran dry was
--- therefore off, and unrearmable, for the rest of the mission.
---
--- The end of a silence is driven the way a mission reaches it: the clock moves past the shutdown
--- time and the scheduler fires the task goSilentToEvadeHARM() armed.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

local RED = 1 -- coalition.side.RED

TestSkynetIADSRearmAfterHarmSilence = {}

--- A RED SA-2 at the origin. With `withNetwork`, a RED EW radar 100 km away covers it and holds it
--- dark; without, the site is autonomous. Neither radar reports anything.
function TestSkynetIADSRearmAfterHarmSilence:buildSite(withNetwork, autonomousBehaviour)
	local iads = SkynetIADS:create()
	self.iads = iads
	if withNetwork then
		F.earlyWarningRadarUnit("EW-north", { pos = { x = 100000, y = 0, z = 0 }, coalition = RED })
		local ewRadar = iads:addEarlyWarningRadar("EW-north")
		function ewRadar:getDetectedTargets()
			return {}
		end
	end

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end
	if autonomousBehaviour then
		samSite:setAutonomousBehaviour(autonomousBehaviour)
	end

	iads:activate()
	return samSite
end

--- The last setOnOff() the site's DCS group received, or nil if none.
local function lastSetOnOff(samSite)
	local calls = samSite:getDCSRepresentation().__controllerCalls
	for i = #calls, 1, -1 do
		if calls[i].setOnOff ~= nil then
			return calls[i].setOnOff
		end
	end
	return nil
end

local function countSetOnOff(samSite)
	local count = 0
	local calls = samSite:getDCSRepresentation().__controllerCalls
	for i = 1, #calls do
		if calls[i].setOnOff ~= nil then
			count = count + 1
		end
	end
	return count
end

--- Every launcher fires its last missile: DCS then reports no ammunition at all.
local function drain(samSite)
	local launchers = samSite:getLaunchers()
	for i = 1, #launchers do
		launchers[i]:getDCSRepresentation():__setAmmo(nil)
	end
end

local function destroy(samSite)
	local units = samSite:getDCSRepresentation():getUnits()
	for i = 1, #units do
		units[i]:__destroy()
	end
end

--- A live site is silenced by HARM defence, which turns its AI off.
local function silence(samSite, timeToImpact)
	samSite:goLive()
	luaunit.assertEquals(samSite:isActive(), true)
	samSite:goSilentToEvadeHARM(timeToImpact or 10)
	luaunit.assertEquals(samSite:isDefendingHARM(), true)
	luaunit.assertEquals(lastSetOnOff(samSite), false)
end

local function endSilence(samSite)
	dcsStub.advanceClock(samSite:getHARMShutdownTime() + 1)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(samSite:isDefendingHARM(), false)
end

function TestSkynetIADSRearmAfterHarmSilence:setUp()
	dcsStub.reset()
end

function TestSkynetIADSRearmAfterHarmSilence:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

function TestSkynetIADSRearmAfterHarmSilence:testSilenceEndTurnsTheAIBackOnForASiteWithAmmo()
	local samSite = self:buildSite(true)
	silence(samSite)

	endSilence(samSite)

	luaunit.assertEquals(lastSetOnOff(samSite), true)
	luaunit.assertEquals(samSite:isActive(), false)
end

--the case the fix is for: goLive() refuses an empty site, so nothing else would ever turn it on
function TestSkynetIADSRearmAfterHarmSilence:testSilenceEndTurnsTheAIBackOnForASiteOutOfAmmo()
	local samSite = self:buildSite(true)
	silence(samSite)
	drain(samSite)

	endSilence(samSite)

	luaunit.assertEquals(lastSetOnOff(samSite), true)
	luaunit.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADSRearmAfterHarmSilence:testSilenceEndLeavesTheEmissionOff()
	local samSite = self:buildSite(true)
	silence(samSite)
	luaunit.assertEquals(samSite:getDCSRepresentation().__emissionEnabled, false)

	endSilence(samSite)

	luaunit.assertEquals(samSite:getDCSRepresentation().__emissionEnabled, false)
end

function TestSkynetIADSRearmAfterHarmSilence:testAutonomousDCSAISiteOutOfAmmoEndsTheSilenceWithItsAIOn()
	local samSite = self:buildSite(false, SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DCS_AI)
	luaunit.assertEquals(samSite:getAutonomousState(), true)
	silence(samSite)
	drain(samSite)

	endSilence(samSite)

	luaunit.assertEquals(lastSetOnOff(samSite), true)
	luaunit.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADSRearmAfterHarmSilence:testAutonomousDarkSiteOutOfAmmoEndsTheSilenceWithItsAIOn()
	local samSite = self:buildSite(false, SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	luaunit.assertEquals(samSite:getAutonomousState(), true)
	silence(samSite)
	drain(samSite)

	endSilence(samSite)

	luaunit.assertEquals(lastSetOnOff(samSite), true)
	luaunit.assertEquals(samSite:isActive(), false)
end

--a site discarded mid-silence leaves its DCS group behind: the site created for it next must find it on
function TestSkynetIADSRearmAfterHarmSilence:testCleanUpMidSilenceTurnsTheAIBackOn()
	local samSite = self:buildSite(true)
	silence(samSite)
	drain(samSite)

	samSite:cleanUp()

	luaunit.assertEquals(lastSetOnOff(samSite), true)
	luaunit.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADSRearmAfterHarmSilence:testCleanUpOutsideASilenceDoesNotTouchTheAI()
	local samSite = self:buildSite(true)
	local before = countSetOnOff(samSite)

	samSite:cleanUp()

	luaunit.assertEquals(countSetOnOff(samSite), before)
end

function TestSkynetIADSRearmAfterHarmSilence:testSilenceEndOnADestroyedSiteDoesNotTouchTheAI()
	local samSite = self:buildSite(true)
	silence(samSite)
	destroy(samSite)
	local before = countSetOnOff(samSite)

	endSilence(samSite)

	luaunit.assertEquals(countSetOnOff(samSite), before)
end

function TestSkynetIADSRearmAfterHarmSilence:testCleanUpOfADestroyedSiteMidSilenceDoesNotTouchTheAI()
	local samSite = self:buildSite(true)
	silence(samSite)
	destroy(samSite)
	local before = countSetOnOff(samSite)

	samSite:cleanUp()

	luaunit.assertEquals(countSetOnOff(samSite), before)
end

--a second HARM silences a site already silent: the AI stays off until the second silence ends
function TestSkynetIADSRearmAfterHarmSilence:testASecondSilenceKeepsTheAIOffUntilItEnds()
	local samSite = self:buildSite(true)
	silence(samSite, 10)

	samSite:goSilentToEvadeHARM(60)

	luaunit.assertEquals(samSite:isDefendingHARM(), true)
	luaunit.assertEquals(lastSetOnOff(samSite), false)

	endSilence(samSite)

	luaunit.assertEquals(lastSetOnOff(samSite), true)
end

os.exit(luaunit.LuaUnit.run())
