--- Tests for FIX-COVERAGE-UPDATE-DARKENS-SITES: recording that a radar covers a battery must not
--- switch the battery off.
---
--- SkynetIADS:buildRadarAssociation() went through addParentRadar(), which ends in
--- informChildrenOfStateChange() -> resetAutonomousState() -> goDark(). So writing down a fact of
--- geometry handed an extinction order to every battery the new radar covers -- including one lit
--- by network designation and not yet locked on, which is exactly the case goDark()'s own guards
--- do not cover.
---
--- The test that carries this suite is testSiteLitByDesignationSurvivesANewEarlyWarningRadar: it
--- drives a real SkynetIADS.evaluateContacts() cycle, so it fails on the behaviour a player sees
--- rather than on a call count. The call count is the second test, and it is what proves the N^2
--- noise is gone rather than merely moved.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

local RED = 1 -- coalition.side.RED
local BLUE = 2 -- coalition.side.BLUE

-- every radar fixture sees 120 km (dcs-fixtures RADAR_RANGE_M)
local OUT_OF_RANGE = 900000

TestSkynetIADSCoverageUpdateNotification = {}

function TestSkynetIADSCoverageUpdateNotification:setUp()
	dcsStub.reset()
end

function TestSkynetIADSCoverageUpdateNotification:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--- A RED SA-2 at the origin, one RED EW radar 100 km away covering it, and a hostile aircraft
--- inside the battery's firing envelope that only the EW radar can see. The last line of defense
--- is switched off so the only thing that can light the battery is network designation.
function TestSkynetIADSCoverageUpdateNotification:buildDesignatedNetwork()
	local iads = SkynetIADS:create()
	self.iads = iads
	iads:setLastLineOfDefence(false)

	F.earlyWarningRadarUnit("EW-north", { pos = { x = 100000, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-north")

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end

	--10 km out at 5 000 m: inside the SA-2's 40 km envelope and under its 12 000 m ceiling
	F.aircraftGroup("intruder", { pos = { x = 10000, y = 5000, z = 0 }, coalition = BLUE })
	function ewRadar:getDetectedTargets()
		return { F.iadsContact("intruder-1") }
	end

	iads:activate()
	return iads, samSite, ewRadar
end

--the one that matters: a battery lit by the network, through a real contact cycle, must still be
--lit after another radar joins the mission somewhere else
function TestSkynetIADSCoverageUpdateNotification:testSiteLitByDesignationSurvivesANewEarlyWarningRadar()
	local iads, samSite = self:buildDesignatedNetwork()

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)
	luaunit.assertEquals(samSite:getAutonomousState(), false)

	--a second EW radar joins the running IADS, 60 km from the battery, so it covers it too
	F.earlyWarningRadarUnit("EW-south", { pos = { x = 0, y = 0, z = 60000 }, coalition = RED })
	iads:addEarlyWarningRadar("EW-south")

	--it gained a parent, and nothing switched it off over that
	luaunit.assertEquals(#samSite:getParentRadars(), 2)
	luaunit.assertEquals(samSite:isActive(), true)
	luaunit.assertEquals(samSite:getAutonomousState(), false)
end

--the same, from the other entry point: enrolling another battery must not darken the one that is
--already engaging
function TestSkynetIADSCoverageUpdateNotification:testSiteLitByDesignationSurvivesANewSAMSite()
	local iads, samSite = self:buildDesignatedNetwork()

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)

	F.samGroup("SA-6", "SAM-SA-6", { pos = { x = 30000, y = 0, z = 0 }, coalition = RED })
	local newSite = iads:addSAMSite("SAM-SA-6")
	function newSite:getDetectedTargets()
		return {}
	end

	luaunit.assertEquals(samSite:isActive(), true)
	luaunit.assertEquals(samSite:getAutonomousState(), false)
end

--autonomy is still maintained through the incremental path: a site that gains its first covering
--radar stops being autonomous. This is the regression the quiet association could buy in silence.
function TestSkynetIADSCoverageUpdateNotification:testSiteGainingItsFirstCoveringRadarStopsBeingAutonomous()
	local iads = SkynetIADS:create()
	self.iads = iads

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end
	iads:activate()
	luaunit.assertEquals(samSite:getAutonomousState(), true)

	--an EW radar is added 60 km away, well inside its 120 km range
	F.earlyWarningRadarUnit("EW-north", { pos = { x = 60000, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-north")
	function ewRadar:getDetectedTargets()
		return {}
	end

	luaunit.assertEquals(#samSite:getParentRadars(), 1)
	luaunit.assertEquals(samSite:getAutonomousState(), false)
	luaunit.assertEquals(#ewRadar:getChildRadars(), 1)
end

--and the mirror: a battery enrolled under an existing radar is held by the network at once, while
--one enrolled out of everybody's range is autonomous. addSAMSite() inserts into the list before it
--rebuilds, where addEarlyWarningRadar() does the opposite -- the two are not symmetrical.
function TestSkynetIADSCoverageUpdateNotification:testSiteAddedUnderAnExistingRadarIsHeldByTheNetwork()
	local iads = SkynetIADS:create()
	self.iads = iads

	F.earlyWarningRadarUnit("EW-north", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-north")
	function ewRadar:getDetectedTargets()
		return {}
	end
	iads:activate()

	F.samGroup("SA-2", "SAM-covered", { pos = { x = 60000, y = 0, z = 0 }, coalition = RED })
	local covered = iads:addSAMSite("SAM-covered")
	function covered:getDetectedTargets()
		return {}
	end
	luaunit.assertEquals(#covered:getParentRadars(), 1)
	luaunit.assertEquals(covered:getAutonomousState(), false)

	F.samGroup("SA-2", "SAM-alone", { pos = { x = OUT_OF_RANGE, y = 0, z = 0 }, coalition = RED })
	local alone = iads:addSAMSite("SAM-alone")
	function alone:getDetectedTargets()
		return {}
	end
	luaunit.assertEquals(#alone:getParentRadars(), 0)
	luaunit.assertEquals(alone:getAutonomousState(), true)
end

--- Counts informChildrenOfStateChange() on every radar element for the duration of fn().
local function countStateChangeNotifications(fn)
	local real = SkynetIADSAbstractRadarElement.informChildrenOfStateChange
	local calls = 0
	SkynetIADSAbstractRadarElement.informChildrenOfStateChange = function(element)
		calls = calls + 1
		return real(element)
	end
	local ok, err = pcall(fn)
	SkynetIADSAbstractRadarElement.informChildrenOfStateChange = real
	if not ok then
		error(err, 0)
	end
	return calls
end

--activate() is the hottest path in the project and cannot be checked in DCS from here, so its work
--is pinned: buildRadarCoverage() ends with one explicit notification per SAM site, and that is all
--there should be. On the fixture this was found on -- 3 EW radars, 10 SAM sites -- it used to be
--250 calls for the 10 that are needed, each one walking the element's children and updating the
--MOOSE connector.
function TestSkynetIADSCoverageUpdateNotification:testActivateNotifiesEachSAMSiteExactlyOnce()
	local iads = SkynetIADS:create()
	self.iads = iads

	for i = 1, 3 do
		local name = "EW-" .. i
		F.earlyWarningRadarUnit(name, { pos = { x = i * 1000, y = 0, z = 0 }, coalition = RED })
		local ewRadar = iads:addEarlyWarningRadar(name)
		function ewRadar:getDetectedTargets()
			return {}
		end
	end
	for i = 1, 10 do
		local name = "SAM-" .. i
		--all within every radar's 120 km range, so the coverage graph is complete
		F.samGroup("SA-2", name, { pos = { x = i * 5000, y = 0, z = 0 }, coalition = RED })
		local samSite = iads:addSAMSite(name)
		function samSite:getDetectedTargets()
			return {}
		end
	end

	local calls = countStateChangeNotifications(function()
		iads:activate()
	end)

	luaunit.assertEquals(calls, 10)
end

os.exit(luaunit.LuaUnit.run())
