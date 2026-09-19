--- Tests for the periodic coverage refresh: which battery sits under which radar has to
--- follow whatever moves.
---
--- Coverage used to be computed once and treated as if it never changed. The incremental
--- rebuild used for a moving AWACS only ever added, so an aircraft in transit accumulated
--- every battery it had ever flown near and held them all non-autonomous from hundreds of
--- kilometres away; a mobile SAM site was refreshed by nothing at all, because the check
--- tested the AWACS class rather than the fact of moving.
---
--- The test that matters here is testLiveSiteWhoseParentsDidNotChangeIsNotSentDark: a
--- sweep that blindly re-applies setToCorrectAutonomousState() darkens the whole network
--- every ten seconds, and a site that relights on the next cycle hides that in play.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

local RED = 1 -- coalition.side.RED

-- Every radar fixture sees 120 km (dcs-fixtures RADAR_RANGE_M), and an element has to travel
-- more than 10 NM (18 520 m) for the sweep to look at it. So "far" below means far enough to
-- be outside 120 km, and every move is hundreds of kilometres — never a borderline value.
local FAR_AWAY = 900000

local function deadEvent()
	return { id = world.event.S_EVENT_DEAD }
end

TestSkynetIADSCoverageRefresh = {}

function TestSkynetIADSCoverageRefresh:setUp()
	dcsStub.reset()
end

function TestSkynetIADSCoverageRefresh:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--- A SAM site at samPos covered by one airborne radar at awacsPos, and nothing else.
function TestSkynetIADSCoverageRefresh:buildAwacsNetwork(awacsPos, samPos)
	local iads = SkynetIADS:create()
	self.iads = iads

	F.awacsUnit("AWACS-1", { pos = awacsPos, coalition = RED })
	local awacs = iads:addEarlyWarningRadar("AWACS-1")
	function awacs:getDetectedTargets()
		return {}
	end

	F.samGroup("SA-2", "SAM-SA-2", { pos = samPos, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end

	iads:activate()
	return iads, samSite, awacs
end

function TestSkynetIADSCoverageRefresh:testAWACSInTransitLosesTheBatteriesItLeftBehind()
	local iads, samSite, awacs = self:buildAwacsNetwork({ x = 50000, y = 9000, z = 0 }, { x = 0, y = 0, z = 0 })

	luaunit.assertEquals(#samSite:getParentRadars(), 1)
	luaunit.assertEquals(#awacs:getChildRadars(), 1)
	luaunit.assertEquals(samSite:getAutonomousState(), false)

	--the AWACS goes home
	dcsStub.world["AWACS-1"]:__setPos({ x = FAR_AWAY, y = 9000, z = 0 })
	iads:refreshRadarCoverage()

	luaunit.assertEquals(#samSite:getParentRadars(), 0)
	luaunit.assertEquals(#awacs:getChildRadars(), 0)
	--the accepted consequence, decided on 2026-09-19: an AWACS going home has the same effect
	--as one shot down, and a battery no ground radar covers is right to become autonomous
	luaunit.assertEquals(samSite:getAutonomousState(), true)
	luaunit.assertEquals(samSite:isActive(), true)
end

function TestSkynetIADSCoverageRefresh:testAWACSComingOnStationPicksUpTheBatteriesItFliesOver()
	local iads, samSite, awacs = self:buildAwacsNetwork({ x = FAR_AWAY, y = 9000, z = 0 }, { x = 0, y = 0, z = 0 })

	luaunit.assertEquals(#samSite:getParentRadars(), 0)
	luaunit.assertEquals(samSite:getAutonomousState(), true)

	dcsStub.world["AWACS-1"]:__setPos({ x = 50000, y = 9000, z = 0 })
	iads:refreshRadarCoverage()

	luaunit.assertEquals(#samSite:getParentRadars(), 1)
	luaunit.assertEquals(#awacs:getChildRadars(), 1)
	luaunit.assertEquals(samSite:getAutonomousState(), false)
end

--a SA-15, a SA-8 or a Shilka driving in a convoy used to keep the parents it had when it
--spawned, for the whole mission
function TestSkynetIADSCoverageRefresh:testMobileSAMSiteParentsFollowIt()
	local iads = SkynetIADS:create()
	self.iads = iads

	F.earlyWarningRadarUnit("EW-west", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-west")
	function ewRadar:getDetectedTargets()
		return {}
	end

	F.samGroup("SA-6", "SAM-mobile", { pos = { x = 50000, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-mobile")
	function samSite:getDetectedTargets()
		return {}
	end
	iads:activate()

	luaunit.assertEquals(#samSite:getParentRadars(), 1)
	luaunit.assertEquals(samSite:getAutonomousState(), false)

	--the convoy drives out from under its tutor
	F.moveSamGroup("SAM-mobile", { x = FAR_AWAY, y = 0, z = 0 })
	iads:refreshRadarCoverage()

	luaunit.assertEquals(#samSite:getParentRadars(), 0)
	luaunit.assertEquals(#ewRadar:getChildRadars(), 0)
	luaunit.assertEquals(samSite:getAutonomousState(), true)

	--and back under it
	F.moveSamGroup("SAM-mobile", { x = 50000, y = 0, z = 0 })
	iads:refreshRadarCoverage()

	luaunit.assertEquals(#samSite:getParentRadars(), 1)
	luaunit.assertEquals(samSite:getAutonomousState(), false)
end

--the test that matters: a site whose parents did not change must be left alone. A blanket
--setToCorrectAutonomousState() means resetAutonomousState() and therefore goDark(), and
--goDark()'s guards do not protect a site that has just gone live on designation.
function TestSkynetIADSCoverageRefresh:testLiveSiteWhoseParentsDidNotChangeIsNotSentDark()
	local iads = SkynetIADS:create()
	self.iads = iads

	--the site's tutor, fixed and close
	F.earlyWarningRadarUnit("EW-west", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-west")
	function ewRadar:getDetectedTargets()
		return {}
	end

	--an AWACS transiting on the far side of the map: it moves every sweep and never comes
	--anywhere near the battery
	F.awacsUnit("AWACS-1", { pos = { x = FAR_AWAY, y = 9000, z = 0 }, coalition = RED })
	local awacs = iads:addEarlyWarningRadar("AWACS-1")
	function awacs:getDetectedTargets()
		return {}
	end

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 50000, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end
	iads:activate()

	local parentsBefore = samSite:getParentRadars()
	luaunit.assertEquals(#parentsBefore, 1)
	luaunit.assertIs(parentsBefore[1], ewRadar)

	--the battery has been designated a target and is live
	samSite:goLive()
	luaunit.assertEquals(samSite:isActive(), true)

	for i = 1, 3 do
		dcsStub.world["AWACS-1"]:__setPos({ x = FAR_AWAY + i * 200000, y = 9000, z = 0 })
		iads:refreshRadarCoverage()
		luaunit.assertEquals(samSite:isActive(), true)
		luaunit.assertEquals(#samSite:getParentRadars(), 1)
		luaunit.assertIs(samSite:getParentRadars()[1], ewRadar)
	end
end

--the same defect from the other side: a site that gains a *second* parent has not changed sides,
--and switching it off over that is exactly what 3a94937 fixed elsewhere — launchers up, slew onto
--the target, back to travel state, no shot. Comparing parent lists rather than autonomy would do
--precisely that, triggered by nothing more than an AWACS arriving on station.
function TestSkynetIADSCoverageRefresh:testLiveSiteGainingASecondParentIsNotSentDark()
	local iads = SkynetIADS:create()
	self.iads = iads

	F.earlyWarningRadarUnit("EW-west", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-west")
	function ewRadar:getDetectedTargets()
		return {}
	end

	--the AWACS starts well outside everything and comes on station over the battery
	F.awacsUnit("AWACS-1", { pos = { x = FAR_AWAY, y = 9000, z = 0 }, coalition = RED })
	local awacs = iads:addEarlyWarningRadar("AWACS-1")
	function awacs:getDetectedTargets()
		return {}
	end

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 50000, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end
	iads:activate()

	luaunit.assertEquals(#samSite:getParentRadars(), 1)
	luaunit.assertEquals(samSite:getAutonomousState(), false)

	--the battery has been designated a target and is live, but has not locked on yet, so goDark()'s
	--own guards would not save it
	samSite:goLive()
	luaunit.assertEquals(samSite:isActive(), true)

	dcsStub.world["AWACS-1"]:__setPos({ x = 60000, y = 9000, z = 0 })
	iads:refreshRadarCoverage()

	--the second parent was picked up
	luaunit.assertEquals(#samSite:getParentRadars(), 2)
	--and nothing switched the battery off over it
	luaunit.assertEquals(samSite:isActive(), true)
	luaunit.assertEquals(samSite:getAutonomousState(), false)
end

--the sweep makes the death-driven path redundant in theory; it is kept because it frees a
--battery at once instead of at the next sweep, and a SEAD run is a moment of play
function TestSkynetIADSCoverageRefresh:testKillingAnEWRadarStillFreesItsBatteriesWithoutASweep()
	local iads = SkynetIADS:create()
	self.iads = iads

	F.earlyWarningRadarUnit("EW-west", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-west")
	function ewRadar:getDetectedTargets()
		return {}
	end

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 50000, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end
	iads:activate()
	luaunit.assertEquals(samSite:getAutonomousState(), false)

	dcsStub.world["EW-west"]:__destroy()
	ewRadar:onEvent(deadEvent())

	--no sweep has run
	luaunit.assertEquals(samSite:getAutonomousState(), true)
end

function TestSkynetIADSCoverageRefresh:testSweepTouchesNothingWhenNothingMoved()
	local iads, samSite = self:buildAwacsNetwork({ x = 50000, y = 9000, z = 0 }, { x = 0, y = 0, z = 0 })

	local stateChanges = 0
	local realSetToCorrectAutonomousState = SkynetIADSAbstractRadarElement.setToCorrectAutonomousState
	function samSite:setToCorrectAutonomousState()
		stateChanges = stateChanges + 1
		return realSetToCorrectAutonomousState(self)
	end

	for _ = 1, 5 do
		iads:refreshRadarCoverage()
	end

	luaunit.assertEquals(stateChanges, 0)
	luaunit.assertEquals(#samSite:getParentRadars(), 1)
end

--a fixed element is skipped outright, which is what keeps the sweep M x N instead of N^2
function TestSkynetIADSCoverageRefresh:testFixedElementIsNeverConsideredMoved()
	local iads = SkynetIADS:create()
	self.iads = iads
	F.earlyWarningRadarUnit("EW-west", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-west")

	for _ = 1, 5 do
		luaunit.assertEquals(ewRadar:hasMovedSinceLastCoverageUpdate(), false)
	end
end

function TestSkynetIADSCoverageRefresh:testMovementIsMeasuredFromTheLastSweepNotFromTheStart()
	local iads = SkynetIADS:create()
	self.iads = iads
	F.awacsUnit("AWACS-1", { pos = { x = 0, y = 9000, z = 0 }, coalition = RED })
	local awacs = iads:addEarlyWarningRadar("AWACS-1")

	luaunit.assertEquals(awacs:hasMovedSinceLastCoverageUpdate(), false)

	--10 NM is 18 520 m; 10 km is not enough
	dcsStub.world["AWACS-1"]:__setPos({ x = 10000, y = 9000, z = 0 })
	luaunit.assertEquals(awacs:hasMovedSinceLastCoverageUpdate(), false)

	dcsStub.world["AWACS-1"]:__setPos({ x = 200000, y = 9000, z = 0 })
	luaunit.assertEquals(awacs:hasMovedSinceLastCoverageUpdate(), true)
	--asking moves the reference point, so a stationary AWACS is not re-evaluated forever after
	luaunit.assertEquals(awacs:hasMovedSinceLastCoverageUpdate(), false)

	--the name the script has always exposed for this still answers the same thing
	dcsStub.world["AWACS-1"]:__setPos({ x = 400000, y = 9000, z = 0 })
	luaunit.assertEquals(awacs:isUpdateOfAutonomousStateOfSAMSitesRequired(), true)
end

--until this lot there was no way at all to remove a single parent or child radar
function TestSkynetIADSCoverageRefresh:testParentAndChildRadarsCanBeRemovedIndividually()
	local iads = SkynetIADS:create()
	self.iads = iads
	F.samGroup("SA-6", "SAM-a", { coalition = RED })
	F.samGroup("SA-6", "SAM-b", { pos = { x = 1000, y = 0, z = 0 }, coalition = RED })
	local siteA = SkynetIADSSamSite:create(Group.getByName("SAM-a"), iads)
	local siteB = SkynetIADSSamSite:create(Group.getByName("SAM-b"), iads)
	siteA:setupElements()
	siteB:setupElements()

	siteA:addChildRadar(siteB)
	siteB:addParentRadarWithoutStateChange(siteA)
	luaunit.assertEquals(#siteA:getChildRadars(), 1)
	luaunit.assertEquals(#siteB:getParentRadars(), 1)

	--removing something that was never there is a no-op, not an error
	siteA:removeChildRadar(siteA)
	luaunit.assertEquals(#siteA:getChildRadars(), 1)

	siteA:removeChildRadar(siteB)
	siteB:removeParentRadar(siteA)
	luaunit.assertEquals(#siteA:getChildRadars(), 0)
	luaunit.assertEquals(#siteB:getParentRadars(), 0)

	siteA:cleanUp()
	siteB:cleanUp()
end

function TestSkynetIADSCoverageRefresh:testSweepIsArmedByActivateAndRemovedByDeactivate()
	local iads = SkynetIADS:create()
	self.iads = iads
	luaunit.assertEquals(iads:getCoverageRefreshInterval(), 10)
	luaunit.assertNil(iads.coverageRefreshMistTaskID)

	iads:activate()
	luaunit.assertNotNil(iads.coverageRefreshMistTaskID)

	iads:deactivate()
	luaunit.assertNil(iads.coverageRefreshMistTaskID)
	self.iads = nil
end

function TestSkynetIADSCoverageRefresh:testSweepIntervalIsSettableAndZeroStopsIt()
	local iads = SkynetIADS:create()
	self.iads = iads
	iads:activate()

	iads:setCoverageRefreshInterval(30)
	luaunit.assertEquals(iads:getCoverageRefreshInterval(), 30)
	luaunit.assertNotNil(iads.coverageRefreshMistTaskID)

	iads:setCoverageRefreshInterval(0)
	luaunit.assertEquals(iads:getCoverageRefreshInterval(), 0)
	luaunit.assertNil(iads.coverageRefreshMistTaskID)

	--a negative interval is nonsense and is refused
	iads:setCoverageRefreshInterval(-5)
	luaunit.assertEquals(iads:getCoverageRefreshInterval(), 0)
end

--a site is a point: the initial build and the sweep have to agree, or a borderline
--association flips at the first sweep with nothing having moved
function TestSkynetIADSCoverageRefresh:testCoverageIsMeasuredFromOnePointPerElement()
	local iads = SkynetIADS:create()
	self.iads = iads
	F.earlyWarningRadarUnit("EW-west", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-west")
	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 50000, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")

	--the site's first search radar sits one metre east of the position the fixture was given
	local position = samSite:getElementPosition()
	luaunit.assertEquals(position.x, 50001)
	luaunit.assertEquals(ewRadar:getMaxDetectionRange(), 120000)
	luaunit.assertEquals(samSite:isInRadarDetectionRangeOf(ewRadar), true)

	--an element with no radar left covers nothing
	dcsStub.world["EW-west"]:__destroy()
	luaunit.assertEquals(ewRadar:getMaxDetectionRange(), 0)
	luaunit.assertEquals(samSite:isInRadarDetectionRangeOf(ewRadar), false)
end

os.exit(luaunit.LuaUnit.run())
