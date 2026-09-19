--- Tests for FIX-STALE-HARM-SILENCE ticket 02: a *ByPrefix call must unwire what it discards.
---
--- addSAMSitesByPrefix() and addEarlyWarningRadarsByPrefix() replace their whole list, and
--- nothing else in the IADS ever removes a coverage association: the per-element rebuild only
--- adds, and refreshRadarCoverage() visits the *current* elements, which a discarded object is
--- no longer among. So the objects thrown away stayed wired into the graph for the rest of the
--- mission.
---
--- The two tests that carry this suite drive what a player would see rather than counting list
--- entries: a battery whose covering radar has left the IADS must go autonomous, and a discarded
--- site must stop being told what to do. VEAF missions reach both on respawn.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

local RED = 1 -- coalition.side.RED

TestSkynetIADSBulkReAdd = {}

--- A RED SA-2 at the origin and a RED EW radar 100 km away whose 120 km range covers it. The EW
--- radar lives in a group, because prefix discovery enumerates units through groups.
function TestSkynetIADSBulkReAdd:buildNetwork()
	local iads = SkynetIADS:create()
	F.earlyWarningRadarGroup("EW-group", "EW-north", { pos = { x = 100000, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-north")
	function ewRadar:getDetectedTargets()
		return {}
	end

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end

	return iads, samSite, ewRadar
end

function TestSkynetIADSBulkReAdd:setUp()
	dcsStub.reset()
end

function TestSkynetIADSBulkReAdd:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--the EW half, and the worse of the two: a discarded EW radar object passes every test a parent is
--given -- its DCS unit exists, it has power, a connection node, it acts as EW -- so the battery
--goes on believing it is covered by a radar the IADS no longer polls, and stays dark for nobody
function TestSkynetIADSBulkReAdd:testSiteGoesAutonomousWhenItsRadarLeavesTheIADS()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	iads:activate()
	luaunit.assertEquals(samSite:getAutonomousState(), false) -- covered, held by the network

	--the mission re-declares its EW radars under a prefix that matches none of them: the IADS is
	--left without a single early warning radar
	iads:addEarlyWarningRadarsByPrefix("NO-SUCH-RADAR")

	luaunit.assertEquals(#iads:getEarlyWarningRadars(), 0)
	luaunit.assertEquals(#samSite:getParentRadars(), 0)
	luaunit.assertEquals(samSite:hasValidParentRadar(), false)
	luaunit.assertEquals(samSite:getAutonomousState(), true)
end

--and the ordinary case: re-declaring the same radars leaves exactly one parent, not two
function TestSkynetIADSBulkReAdd:testReAddingTheSameEarlyWarningRadarsLeavesOneParent()
	local iads, samSite, ewRadar = self:buildNetwork()
	self.iads = iads
	iads:activate()

	iads:addEarlyWarningRadarsByPrefix("EW")

	luaunit.assertEquals(#iads:getEarlyWarningRadars(), 1)
	luaunit.assertEquals(#samSite:getParentRadars(), 1)
	--and the one parent left is the radar the IADS actually holds, not the object it threw away
	luaunit.assertEquals(samSite:getParentRadars()[1], iads:getEarlyWarningRadars()[1])
	luaunit.assertNotEquals(samSite:getParentRadars()[1], ewRadar)
end

--the SAM half: a discarded site stays a child of the EW radar, so every informChildrenOfStateChange
--drives it -- and it still holds the controller of the DCS group the live site now owns
function TestSkynetIADSBulkReAdd:testDiscardedSitesAreNoLongerToldWhatToDo()
	local iads, _, ewRadar = self:buildNetwork()
	self.iads = iads
	iads:activate()
	local discarded = iads:getSAMSites()[1]

	iads:addSAMSitesByPrefix("SAM")

	luaunit.assertEquals(#iads:getSAMSites(), 1)
	luaunit.assertNotEquals(iads:getSAMSites()[1], discarded)
	luaunit.assertEquals(#ewRadar:getChildRadars(), 1)
	luaunit.assertEquals(ewRadar:getChildRadars()[1], iads:getSAMSites()[1])

	--the decisive one: the network no longer reaches the object it threw away
	local ordersReceived = 0
	function discarded:setToCorrectAutonomousState()
		ordersReceived = ordersReceived + 1
	end
	ewRadar:informChildrenOfStateChange()
	luaunit.assertEquals(ordersReceived, 0)
end

--a group the mission has not activated yet is skipped, as it is in DCS
function TestSkynetIADSBulkReAdd:testAnInactiveGroupIsNotAdded()
	local iads = SkynetIADS:create()
	self.iads = iads
	F.samGroup("SA-2", "SAM-asleep", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	for _, unit in ipairs(Group.getByName("SAM-asleep"):getUnits()) do
		function unit:isActive()
			return false
		end
	end

	iads:addSAMSitesByPrefix("SAM")

	luaunit.assertEquals(#iads:getSAMSites(), 0)
end

--before activate() there is no coverage to rebuild, and activate() does it once: the guard on the
--rebuild is the same one the per-element rebuild already carries
function TestSkynetIADSBulkReAdd:testNoRebuildBeforeTheIADSIsActivated()
	local iads = self:buildNetwork()
	self.iads = iads

	local rebuilds = 0
	local realBuild = SkynetIADS.buildRadarCoverage
	function iads:buildRadarCoverage()
		rebuilds = rebuilds + 1
		return realBuild(self)
	end

	iads:addSAMSitesByPrefix("SAM")
	iads:addEarlyWarningRadarsByPrefix("EW")
	luaunit.assertEquals(rebuilds, 0)

	--and once it is running, each bulk re-add rebuilds exactly once
	iads:activate()
	luaunit.assertEquals(rebuilds, 1)
	iads:addSAMSitesByPrefix("SAM")
	luaunit.assertEquals(rebuilds, 2)
	iads:addEarlyWarningRadarsByPrefix("EW")
	luaunit.assertEquals(rebuilds, 3)

	--the network is wired correctly at the end of all that, and only once
	luaunit.assertEquals(#iads:getSAMSites(), 1)
	luaunit.assertEquals(#iads:getEarlyWarningRadars(), 1)
	luaunit.assertEquals(#iads:getSAMSites()[1]:getParentRadars(), 1)
	luaunit.assertEquals(#iads:getEarlyWarningRadars()[1]:getChildRadars(), 1)
end

os.exit(luaunit.LuaUnit.run())
