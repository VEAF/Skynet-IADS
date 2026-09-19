--- Standalone tests for SkynetIADS (skynet-iads-source/skynet-iads.lua),
--- mirroring how test_skynet_iads_sam_site.lua/test_skynet_iads_jammer.lua/
--- etc. each own their class. Add future SkynetIADS-level tests here rather
--- than spawning a new narrowly-named file per fix.
---
--- Two things live here.
---
--- A regression test for 3a94937: a live SAM site must stay live while its target remains under
--- EW radar coverage. Mirrors unit-tests/test-skynet-iads.lua's
--- testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage, built on dcs-fixtures instead of the
--- skynet-unit-tests.miz.
---
--- And, since CHORE-TEST-COVERAGE-FLOOR ticket 05, the network facade a mission maker actually
--- writes against: the getters documentation/api.md shows on the SkynetIADS object, the enrolment
--- calls and their failure paths, and the radio menu. That documentation is a promise, and until
--- this the suite had never executed getSAMSiteByGroupName -- the single most used call in the
--- whole of api.md, eleven examples deep. A getter that breaks makes every documented example
--- fail in someone's mission with no way to tell whose fault it is.
---
--- Everything is driven through the public API -- addSAMSite / addEarlyWarningRadar / activate --
--- and never by reaching into self.samSites: a getter test that builds its own table proves the
--- table.
---
--- Four tests here used to pin behaviour that was wrong and said so: the three setup warnings that
--- never left dcs.log, and the line every birth event wrote. FIX-SETUP-WARNINGS-AND-LOG-NOISE fixed
--- both, and those four now assert the behaviour rather than record it.
---
--- One characterisation test is left, on addRadioMenu() and marked PINS A DEFECT where it sits. It
--- stays because the defect needs somebody to decide what DCS should show a player, not because the
--- behaviour is endorsed.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

TestSkynetIADS = {}

function TestSkynetIADS:setUp()
	dcsStub.reset()
end

--- Only the tests that build a network through buildNetwork() set self.iads; the regression test
--- below deactivates its own, so this is a guard, not a duplicate.
function TestSkynetIADS:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--a SAM site that is already live must stay live while the target is still under EW coverage.
--targetCycleUpdateStart() clears targetsInRange on every cycle, so if evaluateContacts() skips
--sites that are already active, nothing sets the flag again and targetCycleUpdateEnd() sends them
--dark on the next cycle. In game that reads as a site raising its launchers and standing down
--every few seconds without ever firing. Regression test for 3a94937.
function TestSkynetIADS:testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage()
	local iads = SkynetIADS:create()

	F.earlyWarningRadarUnit("EW-west23")
	local ewRadar = iads:addEarlyWarningRadar("EW-west23")

	-- EW-west23 sits at the origin with a 120 km detection range (RADAR_RANGE_M in
	-- dcs-fixtures.lua); the SA-2 group's units sit at x=1..4 m. A target at
	-- x=10000 m / y=2000 m altitude is ~10 km out — well inside both the EW radar's
	-- 120 km range and the SA-2 launcher's 40 km rangeMaxAltMin (real SA-2 data in
	-- skynet-iads-source/skynet-iads-sam-launcher.lua, reused by dcs-fixtures.lua's
	-- launcherAmmo for the search radar).
	dcsStub.makeUnit({
		name = "test-in-firing-range-of-sa-2",
		type = "F-16C",
		pos = { x = 10000, y = 2000, z = 0 },
		desc = { category = Unit.Category.AIRPLANE },
	})

	function ewRadar:getDetectedTargets()
		return { F.iadsContact("test-in-firing-range-of-sa-2") }
	end

	F.samGroup("SA-2", "SAM-SA-2")
	local samSite = iads:addSAMSite("SAM-SA-2")

	function samSite:getDetectedTargets()
		return {}
	end

	samSite:goDark()
	luaunit.assertEquals(samSite:isActive(), false) -- addSAMSite() leaves it dark; cycle 1 must be what brings it live
	iads:activate()

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)

	--the target has not moved and the EW radar still sees it, so a second cycle must not
	--switch the site off
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)

	--and a third, to show it is a steady state and not a one-cycle grace period
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)

	iads:deactivate()
end

-- ---- the network facade (CHORE-TEST-COVERAGE-FLOOR ticket 05) -----------------------------

local RED = 1 -- coalition.side.RED
local BLUE = 2 -- coalition.side.BLUE
local NEUTRAL = 0 -- coalition.side.NEUTRAL

--- The names a getter returned, sorted, so a test states a set rather than an order no caller
--- relies on.
local function namesOf(elements)
	local names = {}
	for i = 1, #elements do
		names[i] = elements[i]:getDCSName()
	end
	table.sort(names)
	return names
end

--- Runs `emit` with both recorders empty and returns what a player and a dcs.log would have seen.
local function capture(emit)
	dcsStub.logs = {}
	dcsStub.screenText = {}
	emit()
	local screen, log = {}, {}
	for i = 1, #dcsStub.screenText do
		screen[i] = dcsStub.screenText[i].text
	end
	for i = 1, #dcsStub.logs do
		log[i] = dcsStub.logs[i].text
	end
	return { screen = screen, log = log }
end

--- One RED network, "Ruby", built the way documentation/api.md builds one, and arranged so that
--- every getter below has a different answer -- a getter that returns everything, or nothing, has
--- to fail somewhere.
---
---   RED-SAM-north   SA-6, 0 km       covered by EW-north, so dark and not autonomous
---   RED-SAM-south   SA-2, 30 km      covered too; the only SA-2, so NATO-name lookups differ
---   RED-SAM-lonely  SA-6, 400 km     no radar within 120 km: autonomous, and therefore the only
---                                    site getActiveSAMSites() returns
---   OTHER-SAM-east  SA-6, 40 km      destroyed after activate(); the only destroyed site, and the
---                                    only one whose name does not start with "RED-"
---   EW-north        alive            EW-dead  destroyed after activate()
---
--- Radar range is the fixtures' 120 km (dcs-fixtures RADAR_RANGE_M), which is what makes 400 km
--- "covered by nobody" and 40 km "covered". EW-dead sits at 800 km, far enough from the lonely
--- battery that destroying it changes no coverage.
function TestSkynetIADS:buildNetwork()
	local iads = SkynetIADS:create("Ruby")
	self.iads = iads

	local function addSAMSite(natoShort, groupName, x)
		F.samGroup(natoShort, groupName, { pos = { x = x, y = 0, z = 0 }, coalition = RED })
		local samSite = iads:addSAMSite(groupName)
		-- the real getDetectedTargets returns DCS world radar contacts, which would make the
		-- lit/dark mix below depend on engagement logic these tests say nothing about
		function samSite:getDetectedTargets()
			return {}
		end
		return samSite
	end

	addSAMSite("SA-6", "RED-SAM-north", 0)
	addSAMSite("SA-2", "RED-SAM-south", 30000)
	addSAMSite("SA-6", "RED-SAM-lonely", 400000)
	addSAMSite("SA-6", "OTHER-SAM-east", 40000)

	local function addEarlyWarningRadar(unitName, x)
		F.earlyWarningRadarUnit(unitName, { pos = { x = x, y = 0, z = 0 }, coalition = RED })
		local ewRadar = iads:addEarlyWarningRadar(unitName)
		function ewRadar:getDetectedTargets()
			return {}
		end
		return ewRadar
	end

	addEarlyWarningRadar("EW-north", 0)
	addEarlyWarningRadar("EW-dead", 800000)

	iads:activate()
	-- shot down once they are part of the network, which is the only way to get elements the IADS
	-- still holds and DCS no longer has
	dcsStub.world["OTHER-SAM-east"]:__destroy()
	dcsStub.world["EW-dead"]:__destroy()
	return iads
end

-- ---- the getters api.md documents ---------------------------------------------------------

--- getSAMSiteByGroupName is how all eleven examples in documentation/api.md reach a battery
--- before configuring it. Until ticket 05 the suite had never run it.
function TestSkynetIADS:testGetSAMSiteByGroupNameReturnsThatBatteryAndNoOther()
	local iads = self:buildNetwork()
	local samSite = iads:getSAMSiteByGroupName("RED-SAM-south")
	luaunit.assertNotNil(samSite)
	luaunit.assertEquals(samSite:getDCSName(), "RED-SAM-south")
	luaunit.assertEquals(samSite:getNatoName(), "SA-2")
end

--- What a miss gives back is part of the contract and api.md does not say. It is not nil: the
--- function falls off its own end, so it returns *no value at all*. That is the same as nil in
--- `local s = iads:getSAMSiteByGroupName(name)`, which is how every documented example writes it,
--- and is not the same anywhere a call is forwarded -- select("#", ...) sees zero, and a wrapper
--- passing it on hands its callee one argument short.
function TestSkynetIADS:testGetSAMSiteByGroupNameReturnsNoValueForAnUnknownName()
	local iads = self:buildNetwork()
	luaunit.assertNil((iads:getSAMSiteByGroupName("no-such-group")))
	luaunit.assertEquals(select("#", iads:getSAMSiteByGroupName("no-such-group")), 0)
end

function TestSkynetIADS:testGetEarlyWarningRadarByUnitNameFindsThatRadar()
	local iads = self:buildNetwork()
	local ewRadar = iads:getEarlyWarningRadarByUnitName("EW-north")
	luaunit.assertNotNil(ewRadar)
	luaunit.assertEquals(ewRadar:getDCSName(), "EW-north")
end

function TestSkynetIADS:testGetEarlyWarningRadarByUnitNameReturnsNoValueForAnUnknownName()
	local iads = self:buildNetwork()
	luaunit.assertNil((iads:getEarlyWarningRadarByUnitName("no-such-unit")))
	luaunit.assertEquals(select("#", iads:getEarlyWarningRadarByUnitName("no-such-unit")), 0)
end

function TestSkynetIADS:testGetSAMSitesByNatoNameReturnsOnlyThatType()
	local iads = self:buildNetwork()
	luaunit.assertEquals(namesOf(iads:getSAMSitesByNatoName("SA-2")), { "RED-SAM-south" })
	luaunit.assertEquals(
		namesOf(iads:getSAMSitesByNatoName("SA-6")),
		{ "OTHER-SAM-east", "RED-SAM-lonely", "RED-SAM-north" }
	)
end

function TestSkynetIADS:testGetSAMSitesByNatoNameReturnsAnEmptyListForATypeNothingMatches()
	local iads = self:buildNetwork()
	local selected = iads:getSAMSitesByNatoName("SA-99")
	luaunit.assertNotNil(selected, "the miss is an empty list, not a nil the caller has to guard")
	luaunit.assertEquals(#selected, 0)
end

function TestSkynetIADS:testGetSAMSitesByPrefixReturnsOnlyTheSitesThatMatch()
	local iads = self:buildNetwork()
	luaunit.assertEquals(
		namesOf(iads:getSAMSitesByPrefix("RED-")),
		{ "RED-SAM-lonely", "RED-SAM-north", "RED-SAM-south" },
		"OTHER-SAM-east does not start with the prefix and must not come back"
	)
end

--- The prefix is anchored: it has to start the group name, not merely appear in it. Every group
--- in this network contains "SAM", and none of them is returned. api.md calls the argument a
--- prefix and is right to, but nothing said what happens to a substring, and "it quietly matches
--- nothing" is a surprising enough answer to be worth a test.
function TestSkynetIADS:testGetSAMSitesByPrefixIsAnchoredAtTheStartOfTheGroupName()
	local iads = self:buildNetwork()
	luaunit.assertEquals(#iads:getSAMSitesByPrefix("SAM"), 0)
	luaunit.assertEquals(#iads:getSAMSitesByPrefix("ED-SAM"), 0)
end

function TestSkynetIADS:testGetSAMSitesByPrefixReturnsAnEmptyListForAPrefixNothingMatches()
	local iads = self:buildNetwork()
	local selected = iads:getSAMSitesByPrefix("no-such-prefix")
	luaunit.assertNotNil(selected)
	luaunit.assertEquals(#selected, 0)
end

function TestSkynetIADS:testGetSAMSitesAndGetEarlyWarningRadarsReturnEverythingEnrolled()
	local iads = self:buildNetwork()
	luaunit.assertEquals(
		namesOf(iads:getSAMSites()),
		{ "OTHER-SAM-east", "RED-SAM-lonely", "RED-SAM-north", "RED-SAM-south" }
	)
	luaunit.assertEquals(namesOf(iads:getEarlyWarningRadars()), { "EW-dead", "EW-north" })
end

--- A destroyed element stays enrolled and keeps being reported by the plain getters; these two
--- are how a mission asks what it has lost.
function TestSkynetIADS:testTheDestroyedGettersReturnOnlyWhatDCSNoLongerHas()
	local iads = self:buildNetwork()
	luaunit.assertEquals(namesOf(iads:getDestroyedSAMSites()), { "OTHER-SAM-east" })
	luaunit.assertEquals(namesOf(iads:getDestroyedEarlyWarningRadars()), { "EW-dead" })
	-- and they are still in the full lists, which is the distinction worth pinning
	luaunit.assertEquals(#iads:getSAMSites(), 4)
	luaunit.assertEquals(#iads:getEarlyWarningRadars(), 2)
end

--- Only the battery no radar covers is lit: it went autonomous and was handed back to the DCS AI.
--- The three the network holds are dark, which is the normal state and the one to count.
function TestSkynetIADS:testGetActiveSAMSitesReturnsTheOnesEmitting()
	local iads = self:buildNetwork()
	luaunit.assertEquals(namesOf(iads:getActiveSAMSites()), { "RED-SAM-lonely" })
	luaunit.assertEquals(iads:getSAMSiteByGroupName("RED-SAM-lonely"):getAutonomousState(), true)
	luaunit.assertEquals(iads:getSAMSiteByGroupName("RED-SAM-north"):isActive(), false)
end

-- ---- getCoalitionString, which opens every line the debug skill reads ----------------------

function TestSkynetIADS:testGetCoalitionStringNamesEachSide()
	local iads = self:buildNetwork()
	luaunit.assertEquals(iads:getCoalitionString(), "COALITION: RED | NAME: Ruby")

	local blue = SkynetIADS:create("Sapphire")
	blue:setCoalition(dcsStub.makeUnit({ name = "blue-probe", coalition = BLUE }))
	luaunit.assertEquals(blue:getCoalitionString(), "COALITION: BLUE | NAME: Sapphire")

	local neutral = SkynetIADS:create("Pearl")
	neutral:setCoalition(dcsStub.makeUnit({ name = "neutral-probe", coalition = NEUTRAL }))
	luaunit.assertEquals(neutral:getCoalitionString(), "COALITION: NEUTRAL | NAME: Pearl")
end

--- create() with no name stores "", not nil, so the NAME field is always there and always
--- empty-tailed. Every status line and the radio menu title carry it, which is why it is pinned
--- rather than left to whoever next reads a log and wonders about the trailing separator.
function TestSkynetIADS:testGetCoalitionStringAlwaysCarriesANameFieldEvenWhenUnnamed()
	local unnamed = SkynetIADS:create()
	unnamed:setCoalition(dcsStub.makeUnit({ name = "red-probe", coalition = RED }))
	luaunit.assertEquals(unnamed:getCoalitionString(), "COALITION: RED | NAME: ")
end

-- ---- enrolment, and what a typo in the mission editor gets you -----------------------------

function TestSkynetIADS:testAddSAMSiteEnrolsTheGroupAndHandsItBack()
	local iads = self:buildNetwork()
	F.samGroup("SA-6", "RED-SAM-late", { pos = { x = 10000, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("RED-SAM-late")
	luaunit.assertNotNil(samSite)
	luaunit.assertEquals(samSite:getDCSName(), "RED-SAM-late")
	-- assertIs, not assertEquals: the claim is that the getter hands back the very object
	-- addSAMSite() enrolled, which is what every chained example in api.md depends on. Deep
	-- equality would also accept a copy the IADS does not hold.
	luaunit.assertIs(iads:getSAMSiteByGroupName("RED-SAM-late"), samSite)
	luaunit.assertEquals(#iads:getSAMSites(), 5)
end

function TestSkynetIADS:testAddEarlyWarningRadarEnrolsTheUnitAndHandsItBack()
	local iads = self:buildNetwork()
	F.earlyWarningRadarUnit("EW-late", { pos = { x = 10000, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-late")
	luaunit.assertNotNil(ewRadar)
	luaunit.assertIs(iads:getEarlyWarningRadarByUnitName("EW-late"), ewRadar)
	luaunit.assertEquals(#iads:getEarlyWarningRadars(), 3)
end

--- A name that is not in the mission enrols nothing, says so in dcs.log, and warns the players.
---
--- Both copies, on purpose: the log line is what the skynet-runtime-debug skill greps for, and
--- the screen warning is what reaches the person who can fix it while they are still in the
--- mission editor loop. "WARNING: " belongs to the screen copy only -- on a log line already
--- prefixed "SKYNET: " it buys nothing.
function TestSkynetIADS:testAddingASAMSiteThatIsNotInTheMissionEnrolsNothing()
	local iads = self:buildNetwork()
	local printed = capture(function()
		luaunit.assertNil((iads:addSAMSite("typo-in-the-mission-editor")))
	end)
	luaunit.assertEquals(#iads:getSAMSites(), 4, "nothing was enrolled")
	luaunit.assertEquals(#printed.log, 1)
	luaunit.assertStrContains(printed.log[1], "typo-in-the-mission-editor")
	luaunit.assertStrContains(printed.log[1], "does not exist")
	luaunit.assertNotStrContains(printed.log[1], "WARNING")
	luaunit.assertEquals(#printed.screen, 1)
	luaunit.assertStrContains(printed.screen[1], "WARNING: ")
	luaunit.assertStrContains(printed.screen[1], "typo-in-the-mission-editor")
end

--- Same promise for an early warning radar: both copies, prefix on the screen one only.
function TestSkynetIADS:testAddingAnEarlyWarningRadarThatIsNotInTheMissionEnrolsNothing()
	local iads = self:buildNetwork()
	local printed = capture(function()
		luaunit.assertNil((iads:addEarlyWarningRadar("typo-in-the-mission-editor")))
	end)
	luaunit.assertEquals(#iads:getEarlyWarningRadars(), 2, "nothing was enrolled")
	luaunit.assertEquals(#printed.log, 1)
	luaunit.assertStrContains(printed.log[1], "does not exist")
	luaunit.assertNotStrContains(printed.log[1], "WARNING")
	luaunit.assertEquals(#printed.screen, 1)
	luaunit.assertStrContains(printed.screen[1], "WARNING: ")
	luaunit.assertStrContains(printed.screen[1], "typo-in-the-mission-editor")
end

--- The escape hatch: a mission that knows about its own warnings turns them off and keeps the
--- log. `warnings` is on by default, so this is the only way out of the screen copy.
function TestSkynetIADS:testTheWarningsSettingSilencesTheScreenCopyAndKeepsTheLog()
	local iads = self:buildNetwork()
	iads:getDebugSettings().warnings = false
	local printed = capture(function()
		iads:addSAMSite("typo-in-the-mission-editor")
		iads:addEarlyWarningRadar("typo-in-the-mission-editor")
		iads:setCoalition(dcsStub.makeUnit({ name = "blue-intruder", coalition = BLUE }))
	end)
	luaunit.assertEquals(#printed.screen, 0, "the setting silences what a player sees")
	luaunit.assertEquals(#printed.log, 3, "and leaves every line in dcs.log")
end

--- A group Skynet has no SAM data for is rejected and cleaned up rather than enrolled half-built.
--- A truck convoy is the realistic case: someone points a prefix at the wrong group.
function TestSkynetIADS:testAGroupSkynetHasNoSAMDataForIsRejected()
	local iads = self:buildNetwork()
	dcsStub.makeGroup({
		name = "RED-SAM-not-really",
		coalition = RED,
		category = Group.Category.GROUND,
		units = { { name = "RED-SAM-not-really-1", type = "Ural-375", pos = { x = 0, y = 0, z = 0 }, coalition = RED } },
	})
	local printed = capture(function()
		luaunit.assertNil((iads:addSAMSite("RED-SAM-not-really")))
	end)
	luaunit.assertEquals(#iads:getSAMSites(), 4, "nothing was enrolled")
	luaunit.assertEquals(#printed.log, 1)
	luaunit.assertStrContains(printed.log[1], "can not handle")
	luaunit.assertStrContains(printed.log[1], "RED-SAM-not-really")
	luaunit.assertNotStrContains(printed.log[1], "WARNING")
	luaunit.assertEquals(#printed.screen, 1, "a prefix pointed at a truck convoy is a setup mistake too")
	luaunit.assertStrContains(printed.screen[1], "WARNING: ")
	luaunit.assertStrContains(printed.screen[1], "RED-SAM-not-really")
end

-- ---- the radio menu --------------------------------------------------------------------

--- What a player finds under F10: one submenu named after the network, and four commands.
function TestSkynetIADS:testAddRadioMenuBuildsTheMenuAPlayerSees()
	local iads = self:buildNetwork()
	dcsStub.radioItems = {}
	iads:addRadioMenu()

	local names = {}
	for i = 1, #dcsStub.radioItems do
		names[i] = dcsStub.radioItems[i].name
	end
	luaunit.assertEquals(names, {
		"SKYNET IADS COALITION: RED | NAME: Ruby",
		"show IADS Status",
		"hide IADS Status",
		"show contacts",
		"hide contacts",
	})
	-- the four commands sit under the submenu, not beside it
	for i = 2, 5 do
		luaunit.assertEquals(dcsStub.radioItems[i].path[1], names[1])
		luaunit.assertEquals(#dcsStub.radioItems[i].path, 2)
	end
end

--- Clicking a command is the only way those two debug settings are reachable in a running
--- mission, so the handler and its arguments are what matter, not the label.
function TestSkynetIADS:testTheRadioCommandsDriveTheDebugSettings()
	local iads = self:buildNetwork()
	dcsStub.radioItems = {}
	iads:addRadioMenu()

	local function click(label)
		local item = dcsStub.radioItemNamed(label)
		luaunit.assertNotNil(item, "no radio command named '" .. label .. "'")
		item.handler(item.args)
	end

	luaunit.assertEquals(iads:getDebugSettings().IADSStatus, false)
	click("show IADS Status")
	luaunit.assertEquals(iads:getDebugSettings().IADSStatus, true)
	click("hide IADS Status")
	luaunit.assertEquals(iads:getDebugSettings().IADSStatus, false)

	luaunit.assertEquals(iads:getDebugSettings().contacts, false)
	click("show contacts")
	luaunit.assertEquals(iads:getDebugSettings().contacts, true)
	click("hide contacts")
	luaunit.assertEquals(iads:getDebugSettings().contacts, false)
end

function TestSkynetIADS:testRemoveRadioMenuTakesTheSubmenuAndItsCommandsAway()
	local iads = self:buildNetwork()
	dcsStub.radioItems = {}
	iads:addRadioMenu()
	luaunit.assertEquals(#dcsStub.radioItems, 5)
	iads:removeRadioMenu()
	luaunit.assertEquals(#dcsStub.radioItems, 0, "removing a submenu removes what is under it")
end

--- PINS A DEFECT. addRadioMenu() has no idempotence guard: a second call issues the whole set of
--- menu calls again -- another submenu with the same title, another four commands -- and
--- overwrites self.radioMenu with the second path. Nothing in Skynet prevents it, and a mission
--- that re-runs its setup (a respawn script, a reload of the IADS configuration) does exactly
--- this.
---
--- What DCS then shows a player is NOT asserted here. Both submenus are built with the same name,
--- so they carry the same path, and whether DCS collapses them, replaces the first or shows two
--- is behaviour this repository has not verified -- see the note in dcs-stub.lua. That
--- uncertainty is the point: the caller cannot reason about it either, which is why the guard
--- belongs in addRadioMenu() rather than in a mission maker's head.
function TestSkynetIADS:testAddRadioMenuTwiceBuildsTheWholeMenuAgain()
	local iads = self:buildNetwork()
	dcsStub.radioItems = {}
	iads:addRadioMenu()
	luaunit.assertEquals(#dcsStub.radioItems, 5)
	local firstMenuPath = iads.radioMenu

	iads:addRadioMenu()
	luaunit.assertEquals(#dcsStub.radioItems, 10, "a second call re-issues every menu call")
	luaunit.assertNotIs(iads.radioMenu, firstMenuPath, "and the IADS now points at the second one")
	-- the two submenus are indistinguishable by the only handle DCS gives back
	luaunit.assertEquals(iads.radioMenu, firstMenuPath)
end

function TestSkynetIADS:testUpdateDisplayIgnoresASettingItDoesNotKnow()
	local iads = self:buildNetwork()
	SkynetIADS.updateDisplay({ self = iads, value = true, option = "notASetting" })
	luaunit.assertNil(iads:getDebugSettings().notASetting, "an unknown option must not invent a setting")
end

-- ---- the settings api.md tells a mission maker to change ----------------------------------

--- setUpdateInterval is also what a detected contact's cache is allowed to age to, because
--- getCachedTargetsMaxAge() returns the same field -- so raising the cycle interval quietly
--- raises how stale a radar's picture may be. Worth having written down somewhere.
function TestSkynetIADS:testSetUpdateIntervalAlsoMovesTheCachedTargetAge()
	local iads = self:buildNetwork()
	luaunit.assertEquals(iads:getCachedTargetsMaxAge(), 5, "the default cycle is five seconds")
	iads:setUpdateInterval(11)
	luaunit.assertEquals(iads:getCachedTargetsMaxAge(), 11)
end

function TestSkynetIADS:testLastLineOfDefenceIsOnByDefaultAndCanBeTurnedOff()
	local iads = self:buildNetwork()
	luaunit.assertEquals(iads:getLastLineOfDefence(), true, "off means nobody finds it; it ships on")
	iads:setLastLineOfDefence(false)
	luaunit.assertEquals(iads:getLastLineOfDefence(), false)
	-- anything that is not a boolean leaves the setting alone
	iads:setLastLineOfDefence("yes please")
	luaunit.assertEquals(iads:getLastLineOfDefence(), false)
end

--- Still in api.md, and still what some missions call. It has to do both halves of what its
--- name says: activate the network, and say it is deprecated.
---
--- Activation is observed where it is actually visible from outside -- the cycle. activate()
--- schedules evaluateContacts(), and evaluateContacts() ends by printing the status page, so
--- with IADSStatus on a due timer that fires produces output and a network that was never
--- activated produces none. Coverage is no use as a witness here: deactivate() cleans the
--- elements up but leaves the parent links standing, so the graph looks the same either way.
---
--- Without this, dropping the self:activate() call from setupSAMSitesAndThenActivate() would
--- leave the test green while every mission on the deprecated entry point got a network that
--- never runs a cycle.
function TestSkynetIADS:testSetupSAMSitesAndThenActivateActivatesAndSaysItIsDeprecated()
	local iads = self:buildNetwork()
	iads:getDebugSettings().IADSStatus = true
	iads:deactivate()

	local silent = capture(function()
		dcsStub.advanceClock(30)
		dcsStub.fireDueTimers()
	end)
	luaunit.assertEquals(#silent.screen, 0, "a deactivated network runs no cycle")

	local printed = capture(function()
		iads:setupSAMSitesAndThenActivate()
	end)
	luaunit.assertEquals(#printed.log, 1)
	luaunit.assertStrContains(printed.log[1], "DEPRECATED")
	luaunit.assertStrContains(printed.log[1], "setupSAMSitesAndThenActivate")

	local cycled = capture(function()
		dcsStub.advanceClock(30)
		dcsStub.fireDueTimers()
	end)
	luaunit.assertNotNil(
		(function()
			for i = 1, #cycled.screen do
				if cycled.screen[i]:find("COMMAND CENTERS:", 1, true) then
					return cycled.screen[i]
				end
			end
		end)(),
		"the deprecated call activates the network: a cycle ran and printed the status page"
	)
end

--- A mission that points a red IADS at a blue group says so in the log and on screen. This is the
--- second most likely setup mistake after a mistyped name.
function TestSkynetIADS:testAnElementOfTheWrongCoalitionIsReported()
	local iads = self:buildNetwork()
	local printed = capture(function()
		iads:setCoalition(dcsStub.makeUnit({ name = "blue-intruder", coalition = BLUE }))
	end)
	luaunit.assertEquals(#printed.log, 1)
	luaunit.assertStrContains(printed.log[1], "blue-intruder")
	luaunit.assertStrContains(printed.log[1], "different coalition")
	luaunit.assertNotStrContains(printed.log[1], "WARNING")
	luaunit.assertEquals(iads:getCoalition(), RED, "and the IADS keeps the side it already had")
	luaunit.assertEquals(#printed.screen, 1)
	luaunit.assertStrContains(printed.screen[1], "WARNING: ")
	luaunit.assertStrContains(printed.screen[1], "blue-intruder")
end

--- The two debug settings a mission turns on while wiring a network up, to check that what it
--- thinks it enrolled is what Skynet enrolled.
function TestSkynetIADS:testTheEnrolmentDebugSettingsAnnounceWhatWasAdded()
	local iads = self:buildNetwork()
	iads:getDebugSettings().addedSAMSite = true
	iads:getDebugSettings().addedEWRadar = true

	F.samGroup("SA-2", "RED-SAM-announced", { pos = { x = 5000, y = 0, z = 0 }, coalition = RED })
	F.earlyWarningRadarUnit("EW-announced", { pos = { x = 5000, y = 0, z = 0 }, coalition = RED })
	local printed = capture(function()
		iads:addSAMSite("RED-SAM-announced")
		iads:addEarlyWarningRadar("EW-announced")
	end)

	luaunit.assertEquals(#printed.log, 2)
	luaunit.assertStrContains(printed.log[1], "ADDED:")
	luaunit.assertStrContains(printed.log[1], "RED-SAM-announced")
	luaunit.assertStrContains(printed.log[1], "SA-2")
	luaunit.assertStrContains(printed.log[2], "EW-announced")
end

--- A command centre joining a network that is already running has to be wired to the radars there
--- and then; before activate() there is no coverage yet and activate() does it once.
---
--- Six is every enrolled element, and that is the point: two of them -- OTHER-SAM-east and
--- EW-dead -- were destroyed before the command centre joined, and they are wired up all the
--- same. A change that filtered destroyed elements out would turn this red, and would be a
--- decision rather than a regression.
function TestSkynetIADS:testACommandCentreAddedToARunningNetworkIsWiredToItsRadars()
	local iads = self:buildNetwork()
	local commandCenter = iads:addCommandCenter(F.commandCenterStatic("CC-late"))
	luaunit.assertEquals(
		#commandCenter:getChildRadars(),
		6,
		"every enrolled element reports to the command centre, the two destroyed ones included"
	)
	luaunit.assertEquals(iads:isCommandCenterUsable(), true)
end

--- With no command centre at all the network is usable, which is what lets a mission skip them
--- entirely -- most do.
function TestSkynetIADS:testANetworkWithNoCommandCentreIsUsable()
	local iads = self:buildNetwork()
	luaunit.assertEquals(#iads:getCommandCenters(), 0)
	luaunit.assertEquals(iads:isCommandCenterUsable(), true)
end
-- ---- events -----------------------------------------------------------------------------

--- A birth event is not something Skynet acts on. It used to write one unprefixed line per unit
--- that appeared, player slots included, naming nothing and telling nobody anything.
---
--- The second half is the one worth keeping: enrolling a group on birth is the idea that was
--- commented out in the source, and someone may revive it. If they do, this goes red.
function TestSkynetIADS:testABirthEventWritesNothingAndEnrolsNothing()
	local iads = self:buildNetwork()
	local before = #iads:getSAMSites()
	local printed = capture(function()
		iads:onEvent({ id = world.event.S_EVENT_BIRTH })
	end)
	luaunit.assertEquals(#printed.log, 0)
	luaunit.assertEquals(#printed.screen, 0)
	luaunit.assertEquals(#iads:getSAMSites(), before, "nothing is enrolled by a birth event")
end

function TestSkynetIADS:testAnEventSkynetDoesNotHandleIsSilent()
	local iads = self:buildNetwork()
	local printed = capture(function()
		iads:onEvent({ id = world.event.S_EVENT_DEAD })
	end)
	luaunit.assertEquals(#printed.log, 0)
	luaunit.assertEquals(#printed.screen, 0)
end

-- ---- the cycle's remaining corners, and the table delegator (ticket 06) ---------------------

--- A battery set to act as an early warning radar feeds the network instead of being fed by it:
--- the cycle treats it as a radar, and its contacts reach every site under its coverage. That is
--- the recommended setup for a long-range system, so it is not an edge case.
function TestSkynetIADS:testABatteryActingAsEarlyWarningFeedsTheNetwork()
	local iads = self:buildNetwork()
	local watcher = iads:getSAMSiteByGroupName("RED-SAM-north")
	watcher:setActAsEW(true)

	F.aircraftGroup("Intruder", { pos = { x = 10000, y = 3000, z = 0 }, coalition = BLUE })
	function watcher:getDetectedTargets()
		return { F.iadsContact("Intruder-1") }
	end

	iads:evaluateContacts()
	luaunit.assertEquals(#iads:getContacts(), 1, "what the watcher saw reached the network")
	luaunit.assertEquals(iads:getContacts()[1]:getName(), "Intruder-1")
end

--- The same aircraft seen by two elements is one contact in the network, carrying both of
--- the radars that saw it. That second part is not bookkeeping: the HARM detection counts
--- how many *new* radars have seen a track before deciding it is an anti-radiation missile,
--- so a merge that dropped them would make every missile look like it had been seen once.
---
--- A contact records the element that saw it through the second argument of
--- SkynetIADSContact:create, which is what the real getDetectedTargets() passes; the
--- fixture helper does not, so these two build their contacts by hand.
function TestSkynetIADS:testTheSameAircraftSeenTwiceIsOneContactCarryingBothRadars()
	local iads = self:buildNetwork()
	F.aircraftGroup("Intruder", { pos = { x = 10000, y = 3000, z = 0 }, coalition = BLUE })

	local function seenBy(element)
		local contact = SkynetIADSContact:create({ object = dcsStub.world["Intruder-1"] }, element)
		contact:refresh()
		return contact
	end

	local watcher = iads:getSAMSiteByGroupName("RED-SAM-north")
	watcher:setActAsEW(true)
	function watcher:getDetectedTargets()
		return { seenBy(self) }
	end

	local lonely = iads:getSAMSiteByGroupName("RED-SAM-lonely")
	luaunit.assertEquals(lonely:isActive(), true, "the autonomous battery is lit, so it reports its own")
	function lonely:getDetectedTargets()
		return { seenBy(self) }
	end

	iads:evaluateContacts()

	luaunit.assertEquals(#iads:getContacts(), 1, "merged on the contact's name, not counted twice")
	luaunit.assertEquals(
		#iads:getContacts()[1]:getAbstractRadarElementsDetected(),
		2,
		"and it carries both of the elements that saw it"
	)
end

--- The network wakes a battery for an aircraft, and for a missile, but not for a shell or a
--- rocket in flight -- otherwise every artillery barrage in the mission lights up the air
--- defence.
function TestSkynetIADS:testABatteryIsNotWokenByAShellOrARocket()
	local iads = self:buildNetwork()
	local lonely = iads:getSAMSiteByGroupName("RED-SAM-lonely")

	local informedOf = {}
	function lonely:informOfContact(contact)
		informedOf[#informedOf + 1] = contact:getName()
	end

	-- a weapon in flight: Object.getCategory answers WEAPON, and desc.category tells a missile
	-- from a shell
	local function weaponContact(name, weaponCategory)
		local unit = dcsStub.makeUnit({
			name = name,
			type = name,
			pos = { x = 400100, y = 2000, z = 0 },
			category = Object.Category.WEAPON,
			desc = { category = weaponCategory },
		})
		local contact = SkynetIADSContact:create({ object = unit })
		contact:refresh()
		return contact
	end

	local watcher = iads:getSAMSiteByGroupName("RED-SAM-north")
	watcher:setActAsEW(true)
	function watcher:getDetectedTargets()
		return {
			weaponContact("inbound-missile", Weapon.Category.MISSILE),
			weaponContact("outgoing-shell", Weapon.Category.SHELL),
			weaponContact("outgoing-rocket", Weapon.Category.ROCKET),
		}
	end
	-- the cycle asks which covered batteries are *usable*, not which are covered
	function watcher:getUsableChildRadars()
		return { lonely }
	end

	iads:evaluateContacts()
	luaunit.assertEquals(informedOf, { "inbound-missile" })
end

-- ---- the table delegator ---------------------------------------------------------------------

--- getSAMSites() answers a delegator, not a plain list: calling a method on it calls that method
--- on every site. This is what makes the one-liners in documentation/api.md work --
--- `redIADS:getSAMSitesByNatoName('SA-10'):setActAsEW(true)` is one call reaching several
--- batteries, and nothing had ever executed the forwarding.
function TestSkynetIADS:testAMethodCalledOnTheListReachesEverySite()
	local iads = self:buildNetwork()
	local sites = iads:getSAMSitesByNatoName("SA-6")
	luaunit.assertEquals(#sites, 3)

	local called = {}
	for i = 1, #sites do
		local site = sites[i]
		function site:setGoLiveRangeInPercent(percent)
			called[#called + 1] = site:getDCSName() .. ":" .. tostring(percent)
		end
	end

	local returned = sites:setGoLiveRangeInPercent(70)
	table.sort(called)
	luaunit.assertEquals(called, {
		"OTHER-SAM-east:70",
		"RED-SAM-lonely:70",
		"RED-SAM-north:70",
	})
	luaunit.assertIs(returned, sites, "and it answers the list again, so calls chain")
end

--- Chaining is the whole point of answering the list: api.md writes several options in a row on
--- one line.
function TestSkynetIADS:testCallsOnTheListChain()
	local iads = self:buildNetwork()
	local sites = iads:getSAMSitesByNatoName("SA-2")
	local calls = {}
	for i = 1, #sites do
		local site = sites[i]
		function site:setActAsEW(value)
			calls[#calls + 1] = "actAsEW=" .. tostring(value)
		end
		function site:setHARMDetectionChance(chance)
			calls[#calls + 1] = "harm=" .. tostring(chance)
		end
	end

	sites:setActAsEW(true):setHARMDetectionChance(80)
	luaunit.assertEquals(calls, { "actAsEW=true", "harm=80" })
end

--- An empty list takes the call and does nothing, which is what makes it safe to chain options
--- onto a prefix that matched nothing -- the promise made in documentation/api.md.
function TestSkynetIADS:testAMethodCalledOnAnEmptyListDoesNothing()
	local iads = self:buildNetwork()
	local none = iads:getSAMSitesByPrefix("no-such-prefix")
	luaunit.assertEquals(#none, 0)
	luaunit.assertIs(none:setActAsEW(true), none)
end

os.exit(luaunit.LuaUnit.run())
