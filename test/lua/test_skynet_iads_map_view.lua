--- Standalone tests for SkynetIADSMapView (skynet-iads-source/skynet-iads-map-view.lua): the drawing
--- of a network on the F10 map.
---
--- The map is dcsStub.marks, what DCS holds for each mark id. Each test drives the view the way a
--- mission does -- displayMap(), the settings, the radio menu -- then lets the view's timer run with
--- refresh(), and only then asserts what is on the map.
---
--- The view redraws only what changed, because every mark added or removed is an event DCS sends to
--- every Skynet element. So "what is redrawn" is asserted by mark id: an item left alone keeps its ids.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/../common/dcs-stub.lua")
local loader = dofile(base .. "/../common/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/../common/dcs-fixtures.lua")

local RED = coalition.side.RED
local SHAPES, COLOURS, LAYERS = SkynetIADSMapView.shapes, SkynetIADSMapView.colours, SkynetIADSMapView.layers

TestSkynetIADSMapView = {}

function TestSkynetIADSMapView:setUp()
	dcsStub.reset()
	SkynetIADSMapView.lastMarkId = nil
	SkynetIADSMapView.firstMarkId = 7300000
end

function TestSkynetIADSMapView:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--- An EW radar covering an SA-6 that an SA-15 defends, and a command center with its power source.
--- The SA-6 sits 20 km north of the EW radar, inside its 120 km detection range, so the coverage
--- Skynet builds at activate() makes the EW radar its parent.
function TestSkynetIADSMapView:buildNetwork()
	local iads = SkynetIADS:create("Ruby")
	self.iads = iads
	F.earlyWarningRadarUnit("EW-north", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	self.ew = iads:addEarlyWarningRadar("EW-north")
	F.samGroup("SA-6", "SAM-SA-6", { pos = { x = 20000, y = 0, z = 0 }, coalition = RED })
	self.sam = iads:addSAMSite("SAM-SA-6")
	F.samGroup("SA-15", "SAM-SA-15", { pos = { x = 22000, y = 0, z = 0 }, coalition = RED })
	self.pointDefence = iads:addSAMSite("SAM-SA-15")
	self.sam:addPointDefence(self.pointDefence)
	for _, element in ipairs({ self.ew, self.sam, self.pointDefence }) do
		function element:getDetectedTargets()
			return {}
		end
	end
	-- built as F.commandCenterStatic and F.powerSourceStatic do, away from the sites
	local commandCenter =
		dcsStub.makeStatic({ name = "CC", type = "Comms tower M", pos = { x = -30000, y = 0, z = 0 } })
	self.commandCenter = iads:addCommandCenter(commandCenter)
	self.powerSource =
		dcsStub.makeStatic({ name = "CC-power", type = "Electric power box", pos = { x = -40000, y = 0, z = 0 } })
	self.commandCenter:addPowerSource(self.powerSource)
	iads:activate()
	return iads
end

--- What the view's timer does every second.
local function refresh()
	dcsStub.advanceClock(1)
	dcsStub.fireDueTimers()
end

--- The marks drawn for one item of the view, by the key the view files it under.
local function marksOf(iads, key)
	local drawn = iads.mapView.drawnItems[key]
	return drawn and drawn.markIds or {}
end

local function marksOfKind(kind)
	local found = {}
	for id, mark in pairs(dcsStub.marks) do
		if mark.kind == kind then
			found[#found + 1] = id
		end
	end
	return found
end

--- Shows the layers in `shown` and hides every other one.
local function showOnly(settings, shown)
	for _, layer in pairs(LAYERS) do
		settings:setLayer(layer, false)
	end
	for _, layer in ipairs(shown) do
		settings:setLayer(layer, true)
	end
end

local function copy(list)
	local copied = {}
	for i = 1, #list do
		copied[i] = list[i]
	end
	return copied
end

-- ---- showing and hiding ------------------------------------------------------------------

function TestSkynetIADSMapView:testNothingIsDrawnUntilTheMapIsDisplayed()
	local iads = self:buildNetwork()
	refresh()
	luaunit.assertEquals(dcsStub.markCount(), 0)
	luaunit.assertEquals(iads:isMapDisplayed(), false)
end

function TestSkynetIADSMapView:testDisplayMapDrawsTheNetworkAtTheNextTick()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	luaunit.assertEquals(iads:isMapDisplayed(), true)
	refresh()
	luaunit.assertTrue(#marksOf(iads, self.ew) > 0, "the EW radar")
	luaunit.assertTrue(#marksOf(iads, self.sam) > 0, "the SAM site")
	luaunit.assertTrue(#marksOf(iads, self.pointDefence) > 0, "the point defence")
	luaunit.assertTrue(#marksOf(iads, self.commandCenter) > 0, "the command center")
	luaunit.assertTrue(#marksOf(iads, self.powerSource) > 0, "its power source")
	luaunit.assertEquals(#marksOf(iads, "coverage:EW-north>SAM-SA-6"), 1)
	luaunit.assertEquals(#marksOf(iads, "pointDefence:SAM-SA-15>SAM-SA-6"), 1)
	luaunit.assertEquals(#marksOf(iads, "power:CC>CC-power"), 1)
end

function TestSkynetIADSMapView:testHidingTheMapErasesItAndStopsItsTimer()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	iads:displayMap(false)
	luaunit.assertEquals(dcsStub.markCount(), 0)
	luaunit.assertEquals(iads:isMapDisplayed(), false)
	refresh()
	luaunit.assertEquals(dcsStub.markCount(), 0, "no timer draws it back")
end

function TestSkynetIADSMapView:testDeactivateStopsTheTimerAndErasesTheMap()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	iads:deactivate()
	self.iads = nil
	luaunit.assertEquals(dcsStub.markCount(), 0)
	luaunit.assertEquals(iads:isMapDisplayed(), false)
	refresh()
	luaunit.assertEquals(dcsStub.markCount(), 0)
end

function TestSkynetIADSMapView:testDisplayingTwiceStartsOneTimer()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	iads:displayMap(true)
	refresh()
	local count = dcsStub.markCount()
	iads:displayMap(false)
	luaunit.assertEquals(dcsStub.markCount(), 0)
	luaunit.assertTrue(count > 0)
	refresh()
	luaunit.assertEquals(dcsStub.markCount(), 0, "a second timer would draw it back")
end

-- ---- redrawing only what changed ----------------------------------------------------------

function TestSkynetIADSMapView:testATickWithNothingChangedRedrawsNothing()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	local before = {}
	for id in pairs(dcsStub.marks) do
		before[id] = true
	end
	refresh()
	for id in pairs(dcsStub.marks) do
		luaunit.assertTrue(before[id], "mark " .. id .. " was drawn again")
	end
end

function TestSkynetIADSMapView:testASiteGoingLiveRedrawsThatSiteOnly()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	local ewMarks, samMarks = copy(marksOf(iads, self.ew)), copy(marksOf(iads, self.sam))
	self.sam:goLive()
	refresh()
	luaunit.assertEquals(marksOf(iads, self.ew), ewMarks, "the EW radar is left alone")
	luaunit.assertNotEquals(marksOf(iads, self.sam), samMarks, "the SAM site is drawn again")
	for _, id in ipairs(samMarks) do
		luaunit.assertNil(dcsStub.marks[id], "its old marks are erased")
	end
end

function TestSkynetIADSMapView:testASiteThatMovesFarEnoughIsRedrawnWhereItIs()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	local samMarks = copy(marksOf(iads, self.sam))
	F.moveSamGroup("SAM-SA-6", { x = 20500, y = 0, z = 0 })
	refresh()
	luaunit.assertEquals(marksOf(iads, self.sam), samMarks, "500 m is below the threshold")
	F.moveSamGroup("SAM-SA-6", { x = 25000, y = 0, z = 0 })
	refresh()
	luaunit.assertNotEquals(marksOf(iads, self.sam), samMarks)
end

function TestSkynetIADSMapView:testADestroyedElementStaysDrawnDashedWhereItWas()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	dcsStub.world["EW-north"]:__destroy()
	refresh()
	local shape = dcsStub.marks[marksOf(iads, self.ew)[1]]
	luaunit.assertEquals(shape.kind, "rect")
	luaunit.assertEquals(shape.args[5], SkynetIADSMapView.lineTypes.dashed)
	luaunit.assertEquals(shape.args[1].x, SkynetIADSMapView.sizes.ew, "centred on its last position")
end

function TestSkynetIADSMapView:testALostCoverageErasesItsLine()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	local line = marksOf(iads, "coverage:EW-north>SAM-SA-6")[1]
	dcsStub.world["EW-north"]:__destroy()
	refresh()
	luaunit.assertNil(dcsStub.marks[line])
	luaunit.assertNil(iads.mapView.drawnItems["coverage:EW-north>SAM-SA-6"])
end

--- The coverage line is drawn from isCoveredBy(), the rule Skynet itself goes autonomous by: a
--- parent that is no longer acting as EW is still in the site's parent list.
function TestSkynetIADSMapView:testACoverageLineFollowsSkynetsOwnCoverageRule()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	luaunit.assertEquals(#marksOf(iads, "coverage:EW-north>SAM-SA-6"), 1)
	function self.ew:getActAsEW()
		return false
	end
	local stillAParent = false
	for _, parent in ipairs(self.sam:getParentRadars()) do
		stillAParent = stillAParent or parent == self.ew
	end
	luaunit.assertTrue(stillAParent, "the EW radar is still in the parent list")
	refresh()
	luaunit.assertNil(iads.mapView.drawnItems["coverage:EW-north>SAM-SA-6"])
end

function TestSkynetIADSMapView:testAFailingItemIsLoggedAndTheRestIsDrawn()
	local iads = self:buildNetwork()
	function self.sam:isDefendingHARM()
		error("boom")
	end
	iads:displayMap(true)
	refresh()
	luaunit.assertTrue(#marksOf(iads, self.ew) > 0)
	luaunit.assertTrue(#marksOf(iads, self.commandCenter) > 0)
	local logged = false
	for _, entry in ipairs(dcsStub.logs) do
		if entry.text:find("SKYNET MAP VIEW") and entry.text:find("boom") then
			logged = true
		end
	end
	luaunit.assertTrue(logged)
end

-- ---- styles ---------------------------------------------------------------------------------

function TestSkynetIADSMapView:testStylesFollowTheElementsState()
	self:buildNetwork()
	local style = SkynetIADSMapView.radarElementStyle(self.ew, true)
	luaunit.assertEquals({ style.shape, style.fill }, { SHAPES.square, COLOURS.blue })
	style = SkynetIADSMapView.radarElementStyle(self.sam, false)
	luaunit.assertEquals({ style.shape, style.fill, style.outline }, { SHAPES.triangle, COLOURS.grey, COLOURS.grey })
	self.sam:goLive()
	style = SkynetIADSMapView.radarElementStyle(self.sam, false)
	luaunit.assertEquals(style.fill, COLOURS.red)
	self.sam:goAutonomous()
	style = SkynetIADSMapView.radarElementStyle(self.sam, false)
	luaunit.assertEquals(style.outline, COLOURS.orange, "autonomous")
	style = SkynetIADSMapView.radarElementStyle(self.pointDefence, false)
	luaunit.assertEquals(style.shape, SHAPES.invertedTriangle)
	style = SkynetIADSMapView.commandCenterStyle(self.commandCenter)
	luaunit.assertEquals(style.fill, COLOURS.green)
	self.powerSource:__destroy()
	style = SkynetIADSMapView.commandCenterStyle(self.commandCenter)
	luaunit.assertEquals(style.fill, COLOURS.orange, "unpowered")
end

function TestSkynetIADSMapView:testStylesUnderAHARMAndOnceDestroyed()
	self:buildNetwork()
	function self.sam:isDefendingHARM()
		return true
	end
	luaunit.assertEquals(SkynetIADSMapView.radarElementStyle(self.sam, false).fill, COLOURS.black, "silenced by a HARM")
	self.pointDefence:setIsPointDefending(true)
	luaunit.assertEquals(SkynetIADSMapView.radarElementStyle(self.pointDefence, false).fill, COLOURS.purple)
	dcsStub.world["SAM-SA-6"]:__destroy()
	local style = SkynetIADSMapView.radarElementStyle(self.sam, false)
	luaunit.assertEquals({ style.fill, style.dashed }, { COLOURS.grey, true })
	dcsStub.world["CC"]:__destroy()
	style = SkynetIADSMapView.commandCenterStyle(self.commandCenter)
	luaunit.assertEquals({ style.fill, style.dashed }, { COLOURS.red, true })
end

function TestSkynetIADSMapView:testAPointDefenceHeldLiveDrawsItsLineSolidPurple()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	local key = "pointDefence:SAM-SA-15>SAM-SA-6"
	luaunit.assertEquals(dcsStub.marks[marksOf(iads, key)[1]].args[4], SkynetIADSMapView.lineTypes.dashed)
	self.pointDefence:setIsPointDefending(true)
	refresh()
	luaunit.assertNil(iads.mapView.drawnItems[key])
	local line = dcsStub.marks[marksOf(iads, "pointDefending:SAM-SA-15>SAM-SA-6")[1]]
	luaunit.assertEquals(line.args[4], SkynetIADSMapView.lineTypes.solid)
	luaunit.assertEquals(line.args[3], SkynetIADSMapView.colour(COLOURS.purple), "the colour of the point defence")
end

function TestSkynetIADSMapView:testALostPowerSourceIsRedrawnDashedRed()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	self.powerSource:__destroy()
	refresh()
	local square = dcsStub.marks[marksOf(iads, self.powerSource)[1]]
	luaunit.assertEquals(square.args[5], SkynetIADSMapView.lineTypes.dashed)
	luaunit.assertEquals(square.args[3], SkynetIADSMapView.colour(COLOURS.red))
	local commandCenter = dcsStub.marks[marksOf(iads, self.commandCenter)[1]]
	luaunit.assertEquals(commandCenter.args[3], SkynetIADSMapView.colour(COLOURS.orange), "unpowered")
end

--- An airborne EW radar never stops: it is redrawn past a longer distance than a ground element.
function TestSkynetIADSMapView:testAnAirborneRadarMovesFurtherBeforeItIsRedrawn()
	self:buildNetwork()
	local awacs = F.awacsUnit("AWACS")
	luaunit.assertEquals(SkynetIADSMapView.moveThresholdOf(awacs), SkynetIADSMapView.airMoveThreshold)
	luaunit.assertEquals(SkynetIADSMapView.moveThresholdOf(self.sam), SkynetIADSMapView.groundMoveThreshold)
end

function TestSkynetIADSMapView:testTwoShapesTooCloseForALineDrawNone()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	F.moveSamGroup("SAM-SA-15", { x = 20100, y = 0, z = 0 })
	refresh()
	luaunit.assertNotNil(iads.mapView.drawnItems["pointDefence:SAM-SA-15>SAM-SA-6"])
	luaunit.assertEquals(#marksOf(iads, "pointDefence:SAM-SA-15>SAM-SA-6"), 0)
end

-- ---- settings: layers and coalition -----------------------------------------------------------

function TestSkynetIADSMapView:testEveryLayerIsOnAndEveryCoalitionSeesByDefault()
	local iads = self:buildNetwork()
	local settings = iads:getDisplayMapSettings()
	for _, layer in pairs(LAYERS) do
		luaunit.assertTrue(settings:hasLayer(layer), layer)
	end
	luaunit.assertNil(settings.targetCoalition)
	iads:displayMap(true)
	refresh()
	for _, mark in pairs(dcsStub.marks) do
		luaunit.assertEquals(mark.coalition, -1)
	end
end

function TestSkynetIADSMapView:testAnEmptyLayerListDrawsNothing()
	local iads = self:buildNetwork()
	showOnly(iads:getDisplayMapSettings(), {})
	iads:displayMap(true)
	refresh()
	luaunit.assertEquals(dcsStub.markCount(), 0)
end

function TestSkynetIADSMapView:testALayerTakenOutWhileShownIsErasedAtTheNextTick()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	luaunit.assertEquals(#marksOfKind("text") > 0, true)
	showOnly(iads:getDisplayMapSettings(), { LAYERS.elements, LAYERS.rangeCircles })
	refresh()
	luaunit.assertEquals(#marksOfKind("text"), 0, "labels")
	luaunit.assertNil(iads.mapView.drawnItems["coverage:EW-north>SAM-SA-6"])
	luaunit.assertNil(iads.mapView.drawnItems["pointDefence:SAM-SA-15>SAM-SA-6"])
	luaunit.assertTrue(#marksOf(iads, self.sam) > 0, "the shapes stay")
end

function TestSkynetIADSMapView:testRangeCirclesAreDrawnForLiveSitesOnly()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	luaunit.assertEquals(#marksOfKind("circle"), 0, "every site is dark")
	self.sam:goLive()
	refresh()
	luaunit.assertEquals(#marksOfKind("circle"), 1)
	showOnly(iads:getDisplayMapSettings(), { LAYERS.elements })
	refresh()
	luaunit.assertEquals(#marksOfKind("circle"), 0)
end

--- The circle is where Skynet wakes the site: its launchers' range in the kill zone, its search
--- radars' in the search range, either scaled by the go-live percentage. The figures come from
--- the site itself, never pinned here.
function TestSkynetIADSMapView:testTheRangeCircleIsTheGoLiveRange()
	local iads = self:buildNetwork()
	local launcherRange, searchRange = 0, 0
	for _, launcher in ipairs(self.sam:getLaunchers()) do
		launcherRange = math.max(launcherRange, launcher:getRange())
	end
	for _, radar in ipairs(self.sam:getSearchRadars()) do
		searchRange = math.max(searchRange, radar:getMaxRangeFindingTarget())
	end
	luaunit.assertNotEquals(launcherRange, searchRange, "the two zones must differ for this test to tell them apart")
	iads:displayMap(true)
	refresh() -- past the network's first cycle, which sends a site with no target dark
	self.sam:goLive()
	refresh()
	local function radius()
		local circles = marksOfKind("circle")
		luaunit.assertEquals(#circles, 1)
		return dcsStub.marks[circles[1]].args[2]
	end
	luaunit.assertEquals(radius(), launcherRange, "the kill zone, by default")
	self.sam:setGoLiveRangeInPercent(50)
	refresh()
	luaunit.assertEquals(radius(), launcherRange / 2)
	self.sam:setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
	self.sam:setGoLiveRangeInPercent(200)
	refresh()
	luaunit.assertEquals(radius(), searchRange * 2)
end

function TestSkynetIADSMapView:testTheCoalitionSettingRedrawsEverythingForThatCoalition()
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	local count = dcsStub.markCount()
	iads:getDisplayMapSettings().targetCoalition = coalition.side.BLUE
	refresh()
	luaunit.assertEquals(dcsStub.markCount(), count)
	for _, mark in pairs(dcsStub.marks) do
		luaunit.assertEquals(mark.coalition, coalition.side.BLUE)
	end
end

-- ---- mark ids ---------------------------------------------------------------------------------

function TestSkynetIADSMapView:testMarkIdsCountFromTheFirstMarkId()
	SkynetIADSMapView.firstMarkId = 500
	local iads = self:buildNetwork()
	iads:displayMap(true)
	refresh()
	local lowest
	for id in pairs(dcsStub.marks) do
		lowest = (lowest == nil or id < lowest) and id or lowest
	end
	luaunit.assertEquals(lowest, 500)
end

function TestSkynetIADSMapView:testTwoNetworksNeverShareAMarkId()
	local red = self:buildNetwork()
	local blue = SkynetIADS:create("Sapphire")
	F.earlyWarningRadarUnit("EW-blue", { pos = { x = 0, y = 0, z = 90000 }, coalition = coalition.side.BLUE })
	blue:addEarlyWarningRadar("EW-blue")
	blue:activate()
	red:displayMap(true)
	blue:displayMap(true) -- the stub raises on an id drawn twice
	refresh()
	luaunit.assertTrue(#marksOf(blue, blue:getEarlyWarningRadars()[1]) > 0)
	blue:deactivate()
end

-- ---- the radio menu -------------------------------------------------------------------------

function TestSkynetIADSMapView:testTheMapRadioCommandsSwitchTheMapAndItsLayers()
	local iads = self:buildNetwork()
	iads:addRadioMenu()
	local function click(label)
		local item = dcsStub.radioItemNamed(label)
		luaunit.assertNotNil(item, "no radio command named '" .. label .. "'")
		item.handler(item.args)
	end
	click("Map - Show/hide")
	luaunit.assertEquals(iads:isMapDisplayed(), true)
	local settings = iads:getDisplayMapSettings()
	click("Map - Show/hide coverage lines (EW -> SAM)")
	luaunit.assertFalse(settings:hasLayer(LAYERS.coverage))
	luaunit.assertTrue(settings:hasLayer(LAYERS.rangeCircles), "the other layers are left alone")
	luaunit.assertNil(iads.mapView.drawnItems["coverage:EW-north>SAM-SA-6"], "erased at once, not at the next tick")
	click("Map - Show/hide coverage lines (EW -> SAM)")
	luaunit.assertTrue(settings:hasLayer(LAYERS.coverage))
	click("Map - Show/hide range circles")
	luaunit.assertFalse(settings:hasLayer(LAYERS.rangeCircles))
	click("Map - Show/hide")
	luaunit.assertEquals(iads:isMapDisplayed(), false)
end

os.exit(luaunit.LuaUnit.run())
