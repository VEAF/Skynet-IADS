--- Tests for skynet-iads-source/skynet-iads-logger.lua — the status page.
---
--- These lines are not decoration. The `skynet-runtime-debug` skill diagnoses a mission by
--- reading them back out of a `dcs.log`: it counts `ACTIVE: … | AUTONOMOUS: …` pairs, reads
--- `DETECTED TARGETS:`, `HAS AMMO:`, `SAM SITES IN COVERED AREA:`. Rename a field, drop one,
--- swap two and every diagnosis written against them goes quietly wrong while the suite stays
--- green. So what is pinned here is the *fields* — their names, their order and their values —
--- and never the whole line: a test that fails on a changed dash teaches people to delete tests.
---
--- Everything runs through the real `SkynetIADSLogger:printSystemStatus()` over a real network
--- built with `addCommandCenter` / `addEarlyWarningRadar` / `addSAMSite` / `activate`, rather
--- than calling the four printers in isolation — a printer that is perfectly tested and no
--- longer reached by the page is the failure this is meant to catch.
---
--- The counters are asserted against a network whose damage is known, and every counter in it
--- is non-zero on purpose: a printer that always reports zero would pass a presence check.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

local RED = 1 -- coalition.side.RED
local BLUE = 2 -- coalition.side.BLUE

--- Every line the logger sends to the DCS log is prefixed with this, and the skill greps for it
--- to separate Skynet's lines from everything else in dcs.log. capture() below checks it on the
--- way past, which is the cheapest place to pin it.
local SKYNET_PREFIX = "SKYNET: "

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- "ACTIVE: true| DETECTED TARGETS: 1" -> { {label="ACTIVE", value="true"}, {label="DETECTED
--- TARGETS", value="1"} }, in order.
---
--- Labels and values are trimmed, so the separator's own spacing is not part of the contract —
--- and it is not consistent in the source anyway: the page carries both "DAMAGED: 1" and
--- "DAMAGED:1", and "POWER SOURCES :" with a space before the colon. What a reader and the
--- skill both need is the label, its position and its value.
local function parseFields(line)
	local fields = {}
	for chunk in (line .. "|"):gmatch("(.-)|") do
		local label, value = chunk:match("^(.-)%s*:%s*(.*)$")
		if label then
			fields[#fields + 1] = { label = trim(label), value = trim(value) }
		else
			fields[#fields + 1] = { label = trim(chunk) }
		end
	end
	return fields
end

--- Asserts a status line field by field. `expected` is the ordered list of { label, value }.
---
--- Two assertions, on purpose. The first compares the whole label sequence, so a renamed,
--- dropped, added or reordered field fails with both sequences side by side and the reader sees
--- which one moved. The second compares values one at a time, naming the field — so a counter
--- that is merely wrong does not read like a shape change.
local function assertFields(context, line, expected)
	luaunit.assertNotNil(line, context .. ": the line was never printed")
	local fields = parseFields(line)
	local actualLabels, expectedLabels = {}, {}
	for i = 1, #fields do
		actualLabels[i] = fields[i].label
	end
	for i = 1, #expected do
		expectedLabels[i] = expected[i][1]
	end
	luaunit.assertEquals(
		table.concat(actualLabels, " | "),
		table.concat(expectedLabels, " | "),
		context
			.. ": these field names are a contract with the skynet-runtime-debug skill,"
			.. " which reads them out of a dcs.log — one was renamed, dropped, added or reordered"
	)
	for i = 1, #expected do
		luaunit.assertEquals(fields[i].value, expected[i][2], context .. ": field '" .. expected[i][1] .. "'")
	end
end

--- Runs `emit` with both recorders empty and returns what it printed:
---   .screen — what trigger.action.outText received (SkynetIADSLogger:printOutput)
---   .log    — what env.info received (SkynetIADSLogger:printOutputToLog), prefix removed
--- The prefix is asserted here rather than in a test of its own because every test needs it
--- stripped before a line can be parsed, and checking it on the way past costs nothing.
local function capture(emit)
	dcsStub.logs = {}
	dcsStub.screenText = {}
	emit()
	local printed = { screen = {}, log = {} }
	for i = 1, #dcsStub.screenText do
		printed.screen[i] = dcsStub.screenText[i].text
	end
	for i = 1, #dcsStub.logs do
		local text = dcsStub.logs[i].text
		luaunit.assertEquals(
			text:sub(1, #SKYNET_PREFIX),
			SKYNET_PREFIX,
			"every logged line carries the SKYNET prefix the skill greps for; this one does not: " .. text
		)
		printed.log[i] = text:sub(#SKYNET_PREFIX + 1)
	end
	return printed
end

--- One field's value, looked up by label rather than by position — so a test that is only
--- interested in a value stays green when a field moves, and the field-order assertions above
--- are the single place a reorder is reported.
local function fieldValue(line, label)
	luaunit.assertNotNil(line, "looking for '" .. label .. "': the line was never printed")
	local fields = parseFields(line)
	for i = 1, #fields do
		if fields[i].label == label then
			return fields[i].value
		end
	end
	luaunit.fail("no field named '" .. label .. "' in: " .. line)
end

--- The first line containing `needle`, or nil.
local function lineWith(lines, needle)
	for i = 1, #lines do
		if lines[i]:find(needle, 1, true) then
			return lines[i]
		end
	end
	return nil
end

local function countLinesWith(lines, needle)
	local count = 0
	for i = 1, #lines do
		if lines[i]:find(needle, 1, true) then
			count = count + 1
		end
	end
	return count
end

--- One element's block: from the line containing `needle` down to the rule that closes it.
--- The rule is matched as "a line that is nothing but dashes" rather than by its exact length,
--- so lengthening it stays a cosmetic change.
local function blockWith(lines, needle)
	local block = {}
	local inside = false
	for i = 1, #lines do
		local line = lines[i]
		if not inside and line:find(needle, 1, true) then
			inside = true
		end
		if inside then
			if line:match("^%-+$") then
				return block
			end
			block[#block + 1] = line
		end
	end
	return block
end

TestSkynetIADSLogger = {}

--- One RED network, "Ruby", whose damage is known element by element.
---
--- Positions matter only through the fixtures' 120 km radar range (dcs-fixtures RADAR_RANGE_M):
--- everything within a few tens of kilometres of the origin is covered by EW-Alpha, and the two
--- elements parked hundreds of kilometres out are covered by nothing.
---
--- What the page must then report, and why each figure is what it is:
---
---   COMMAND CENTERS: 3 | Destroyed: 1 (Bravo) | NoPowr: 1 (Charlie) | NoCon: 1 (Charlie)
---   EW: 3 | On: 2 (Alpha and Charlie) | Off: 1 (Bravo, sent dark) | Destroyed: 1 (Charlie)
---        | NoPowr: 1 (Charlie) | NoCon: 1 (Bravo)
---
---   Charlie is counted On *and* Destroyed, because isActive() reports the aiState Skynet last
---   set and nothing clears it when DCS removes the unit. That is the behaviour today, and the
---   page reports it faithfully; these tests pin what the page says, not whether that state is
---   the right one. If a later change makes a destroyed element read ACTIVE: false, the EW
---   summary and the destroyed-radar tests are expected to move with it.
---   SAM: 4 | On: 3 | Off: 1 (NoRadar) | Autonm: 2 (Lonely, NoAmmo) | Raddest: 1 (NoRadar)
---         | NoPowr: 1 (NoRadar) | NoCon: 1 (NoAmmo) | NoAmmo: 1 (NoAmmo)
---
--- No counter is zero, which is the point: a printer stuck at zero has to fail.
function TestSkynetIADSLogger:setUp()
	dcsStub.reset()
	local iads = SkynetIADS:create("Ruby")
	self.iads = iads

	-- Command centres. Alpha keeps one of its two power sources, which is what makes its
	-- DAMAGED and INTACT counters both non-zero; Bravo has neither kind of support wired, which
	-- is the "NO … SET" branch; Charlie has one of each and both are destroyed.
	local ccAlpha = iads:addCommandCenter(F.commandCenterStatic("CC-Alpha"))
	ccAlpha:addPowerSource(F.powerSourceStatic("CC-Alpha-power-dead"))
	ccAlpha:addPowerSource(F.powerSourceStatic("CC-Alpha-power-live"))
	ccAlpha:addConnectionNode(F.connectionNodeStatic("CC-Alpha-node"))
	dcsStub.world["CC-Alpha-power-dead"]:__destroy()

	iads:addCommandCenter(F.commandCenterStatic("CC-Bravo"))

	local ccCharlie = iads:addCommandCenter(F.commandCenterStatic("CC-Charlie"))
	ccCharlie:addPowerSource(F.powerSourceStatic("CC-Charlie-power"))
	ccCharlie:addConnectionNode(F.connectionNodeStatic("CC-Charlie-node"))
	dcsStub.world["CC-Charlie-power"]:__destroy()
	dcsStub.world["CC-Charlie-node"]:__destroy()

	dcsStub.world["CC-Bravo"]:__destroy()

	-- Early warning radars.
	F.earlyWarningRadarUnit("EW-Alpha", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local ewAlpha = iads:addEarlyWarningRadar("EW-Alpha")
	ewAlpha:addConnectionNode(F.connectionNodeStatic("EW-Alpha-node"))
	ewAlpha:addPowerSource(F.powerSourceStatic("EW-Alpha-power"))

	F.earlyWarningRadarUnit("EW-Bravo", { pos = { x = 500000, y = 0, z = 0 }, coalition = RED })
	local ewBravo = iads:addEarlyWarningRadar("EW-Bravo")
	ewBravo:addConnectionNode(F.connectionNodeStatic("EW-Bravo-node"))
	dcsStub.world["EW-Bravo-node"]:__destroy()

	F.earlyWarningRadarUnit("EW-Charlie", { pos = { x = 600000, y = 0, z = 0 }, coalition = RED })
	local ewCharlie = iads:addEarlyWarningRadar("EW-Charlie")
	ewCharlie:addPowerSource(F.powerSourceStatic("EW-Charlie-power"))
	dcsStub.world["EW-Charlie-power"]:__destroy()

	-- SAM sites.
	F.samGroup("SA-6", "SAM-Covered", { pos = { x = 20000, y = 0, z = 0 }, coalition = RED })
	local samCovered = iads:addSAMSite("SAM-Covered")
	samCovered:addPowerSource(F.powerSourceStatic("SAM-Covered-power"))
	samCovered:addConnectionNode(F.connectionNodeStatic("SAM-Covered-node"))

	F.samGroup("SA-2", "SAM-Lonely", { pos = { x = 800000, y = 0, z = 0 }, coalition = RED })
	iads:addSAMSite("SAM-Lonely")

	-- Its launchers are gone, so hasRemainingAmmo() is false through the real ammunition path
	-- (a destroyed launcher reports no missiles) rather than through an overridden method.
	F.samGroup("SA-6", "SAM-NoAmmo", { pos = { x = 30000, y = 0, z = 0 }, coalition = RED })
	local samNoAmmo = iads:addSAMSite("SAM-NoAmmo")
	samNoAmmo:addConnectionNode(F.connectionNodeStatic("SAM-NoAmmo-node"))
	dcsStub.world["SAM-NoAmmo-node"]:__destroy()
	dcsStub.world["SAM-NoAmmo-ln1"]:__destroy()
	dcsStub.world["SAM-NoAmmo-ln2"]:__destroy()

	-- Search radar destroyed: hasWorkingRadar() is false, which is the Raddest counter, and the
	-- block has to print without a distance for a contact it can no longer measure from.
	F.samGroup("SA-6", "SAM-NoRadar", { pos = { x = 40000, y = 0, z = 0 }, coalition = RED })
	local samNoRadar = iads:addSAMSite("SAM-NoRadar")
	samNoRadar:addPowerSource(F.powerSourceStatic("SAM-NoRadar-power"))
	dcsStub.world["SAM-NoRadar-power"]:__destroy()
	dcsStub.world["SAM-NoRadar-sr"]:__destroy()

	-- One hostile aircraft, seen by the covering radar and by nothing else during the cycle.
	F.aircraftGroup("Intruder", { pos = { x = 10000, y = 3000, z = 0 }, coalition = BLUE })
	function ewAlpha:getDetectedTargets()
		return { F.iadsContact("Intruder-1") }
	end
	for _, element in ipairs({ ewBravo, ewCharlie }) do
		function element:getDetectedTargets()
			return {}
		end
	end
	for _, element in ipairs(iads:getSAMSites()) do
		function element:getDetectedTargets()
			return {}
		end
	end

	iads:activate()
	-- Charlie is shot down once it is part of the network, which is the only way to get an
	-- element that the IADS still holds and DCS no longer has.
	dcsStub.world["EW-Charlie"]:__destroy()
	iads:evaluateContacts()

	ewBravo:goDark()
	-- The contact is now 7 seconds old, so LAST SEEN reads a figure that is measured rather
	-- than the zero a freshly built contact would carry whatever the printer did with it.
	dcsStub.advanceClock(7)

	-- Detections are injected here, after the cycle, rather than before it: this suite pins the
	-- printers, not the wake-up chain, and a battery that lights itself mid-test would make
	-- every counter above depend on engagement logic these tests say nothing about.
	function samCovered:getDetectedTargets()
		return { F.iadsContact("Intruder-1") }
	end
	function samNoRadar:getDetectedTargets()
		return { F.iadsContact("Intruder-1") }
	end
	function ewCharlie:getDetectedTargets()
		return { F.iadsContact("Intruder-1") }
	end
end

function TestSkynetIADSLogger:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--- Turns on the named debug settings and prints one page.
function TestSkynetIADSLogger:printPage(settings)
	local debugSettings = self.iads:getDebugSettings()
	for _, setting in ipairs(settings) do
		debugSettings[setting] = true
	end
	local iads = self.iads
	return capture(function()
		iads.logger:printSystemStatus()
	end)
end

--- The whole page, every section on.
function TestSkynetIADSLogger:printWholePage()
	return self:printPage({
		"IADSStatus",
		"contacts",
		"commandCenterStatusEnvOutput",
		"earlyWarningRadarStatusEnvOutput",
		"samSiteStatusEnvOutput",
	})
end

-- ---- the debug settings gate -------------------------------------------------------------

--- The cheapest branch in the file, and the one that decides whether anything is printed at
--- all: a mission with debug off must cost nothing and say nothing.
function TestSkynetIADSLogger:testNothingIsPrintedWhileEveryDebugSettingIsOff()
	local printed = self:printPage({})
	luaunit.assertEquals(#printed.screen, 0)
	luaunit.assertEquals(#printed.log, 0)
end

function TestSkynetIADSLogger:testIADSStatusPrintsTheSummaryAndNoContacts()
	local printed = self:printPage({ "IADSStatus" })
	luaunit.assertNotNil(lineWith(printed.screen, "COMMAND CENTERS:"))
	luaunit.assertNotNil(lineWith(printed.screen, "EW:"))
	luaunit.assertNotNil(lineWith(printed.screen, "SAM:"))
	luaunit.assertNil(lineWith(printed.screen, "CONTACT:"))
	-- the three per-element blocks have settings of their own
	luaunit.assertEquals(#printed.log, 0)
end

function TestSkynetIADSLogger:testContactsPrintsTheContactsAndNoSummary()
	local printed = self:printPage({ "contacts" })
	luaunit.assertNil(lineWith(printed.screen, "COMMAND CENTERS:"))
	luaunit.assertNotNil(lineWith(printed.screen, "CONTACT:"))
end

function TestSkynetIADSLogger:testTheIADSHeaderCarriesTheCoalitionAndTheNetworkName()
	local printed = self:printPage({ "IADSStatus" })
	-- named rather than indexed blind: with the header gone, printed.screen[1] is nil and
	-- assertStrContains raises from inside luaunit instead of saying what is missing
	local header = lineWith(printed.screen, "IADS:")
	luaunit.assertNotNil(header, "the page opens on an IADS header line and it was not printed")
	luaunit.assertEquals(printed.screen[1], header, "the header opens the page rather than sitting in it")
	luaunit.assertStrContains(header, "COALITION: RED")
	luaunit.assertStrContains(header, "NAME: Ruby")
end

function TestSkynetIADSLogger:testEachStatusBlockIsGatedByItsOwnSetting()
	local blocks = {
		{ setting = "commandCenterStatusEnvOutput", header = "COMMAND CENTER STATUS:" },
		{ setting = "earlyWarningRadarStatusEnvOutput", header = "EW RADAR STATUS:" },
		{ setting = "samSiteStatusEnvOutput", header = "SAM STATUS:" },
	}
	for _, block in ipairs(blocks) do
		local debugSettings = self.iads:getDebugSettings()
		for _, other in ipairs(blocks) do
			debugSettings[other.setting] = (other.setting == block.setting)
		end
		local printed = self:printPage({})
		for _, other in ipairs(blocks) do
			local found = lineWith(printed.log, other.header) ~= nil
			luaunit.assertEquals(
				found,
				other.setting == block.setting,
				"with only "
					.. block.setting
					.. " on, '"
					.. other.header
					.. "' should"
					.. (other.setting == block.setting and " " or " not ")
					.. "be printed"
			)
		end
	end
end

-- ---- the summary page --------------------------------------------------------------------

function TestSkynetIADSLogger:testCommandCentreSummaryCountersAreRight()
	local printed = self:printPage({ "IADSStatus" })
	assertFields("the command centre summary", lineWith(printed.screen, "COMMAND CENTERS:"), {
		{ "COMMAND CENTERS", "3" },
		{ "Destroyed", "1" },
		{ "NoPowr", "1" },
		{ "NoCon", "1" },
	})
end

function TestSkynetIADSLogger:testEarlyWarningRadarSummaryCountersAreRight()
	local printed = self:printPage({ "IADSStatus" })
	assertFields("the early warning radar summary", lineWith(printed.screen, "EW:"), {
		{ "EW", "3" },
		{ "On", "2" },
		{ "Off", "1" },
		{ "Destroyed", "1" },
		{ "NoPowr", "1" },
		{ "NoCon", "1" },
	})
end

function TestSkynetIADSLogger:testSAMSiteSummaryCountersAreRight()
	local printed = self:printPage({ "IADSStatus" })
	assertFields("the SAM site summary", lineWith(printed.screen, "SAM:"), {
		{ "SAM", "4" },
		{ "On", "3" },
		{ "Off", "1" },
		{ "Autonm", "2" },
		{ "Raddest", "1" },
		{ "NoPowr", "1" },
		{ "NoCon", "1" },
		{ "NoAmmo", "1" },
	})
end

function TestSkynetIADSLogger:testContactLineCarriesNameTypeSpeedAndAge()
	local printed = self:printPage({ "contacts" })
	assertFields("the contact line of the summary page", lineWith(printed.screen, "CONTACT:"), {
		{ "CONTACT", "Intruder-1" },
		{ "TYPE", "F-16C" },
		{ "GS", "0" },
		-- the cycle saw it, then the clock moved on by 7 seconds
		{ "LAST SEEN", "7" },
	})
end

-- ---- the command centre block ------------------------------------------------------------

function TestSkynetIADSLogger:testCommandCentreBlockOpensOnceWithTheCoalition()
	local printed = self:printWholePage()
	luaunit.assertEquals(countLinesWith(printed.log, "COMMAND CENTER STATUS:"), 1)
	luaunit.assertStrContains(lineWith(printed.log, "COMMAND CENTER STATUS:"), "COALITION: RED")
	luaunit.assertEquals(countLinesWith(printed.log, "GROUP: CC-"), 3)
end

function TestSkynetIADSLogger:testCommandCentreSupportCountersAreRight()
	local printed = self:printWholePage()
	local alpha = blockWith(printed.log, "GROUP: CC-Alpha")

	assertFields("CC-Alpha's identity", alpha[1], {
		{ "GROUP", "CC-Alpha" },
		{ "TYPE", "COMMAND CENTER" },
	})
	assertFields("CC-Alpha's connection nodes", lineWith(alpha, "CONNECTION NODES:"), {
		{ "CONNECTION NODES", "1" },
		{ "DAMAGED", "0" },
		{ "INTACT", "1" },
	})
	-- two power sources, one of them destroyed: the only element on the page whose DAMAGED and
	-- INTACT are both non-zero, so neither can be a constant
	assertFields("CC-Alpha's power sources", lineWith(alpha, "POWER SOURCES"), {
		{ "POWER SOURCES", "2" },
		{ "DAMAGED", "1" },
		{ "INTACT", "1" },
	})

	local charlie = blockWith(printed.log, "GROUP: CC-Charlie")
	assertFields("CC-Charlie's connection nodes", lineWith(charlie, "CONNECTION NODES:"), {
		{ "CONNECTION NODES", "1" },
		{ "DAMAGED", "1" },
		{ "INTACT", "0" },
	})
	assertFields("CC-Charlie's power sources", lineWith(charlie, "POWER SOURCES"), {
		{ "POWER SOURCES", "1" },
		{ "DAMAGED", "1" },
		{ "INTACT", "0" },
	})
end

--- A mission that wires neither kind of support is the common case, and it has to say so rather
--- than print a row of zeroes that reads like damage.
function TestSkynetIADSLogger:testCommandCentreWithNoSupportSaysSoInsteadOfCounting()
	local printed = self:printWholePage()
	local bravo = blockWith(printed.log, "GROUP: CC-Bravo")
	luaunit.assertNotNil(lineWith(bravo, "NO CONNECTION NODES SET"))
	luaunit.assertNotNil(lineWith(bravo, "NO POWER SOURCES SET"))
	-- and neither counting line was printed. DAMAGED is the needle because it appears only in
	-- the counting form: looking for "POWER SOURCES :" would pin the space before the colon that
	-- this file says is not part of the contract, and an assertion that can no longer match is
	-- an assertion that says nothing.
	luaunit.assertNil(lineWith(bravo, "DAMAGED"))
end

-- ---- the early warning radar block --------------------------------------------------------

function TestSkynetIADSLogger:testEarlyWarningRadarBlockOpensOnceWithTheCoalition()
	local printed = self:printWholePage()
	luaunit.assertEquals(countLinesWith(printed.log, "EW RADAR STATUS:"), 1)
	luaunit.assertStrContains(lineWith(printed.log, "EW RADAR STATUS:"), "COALITION: RED")
end

function TestSkynetIADSLogger:testEarlyWarningRadarStateLineFieldsAreRight()
	local printed = self:printWholePage()
	local alpha = blockWith(printed.log, "UNIT: EW-Alpha")

	-- the EW block says UNIT where the SAM block says GROUP, and the skill's reading table
	-- tells the two apart by exactly that
	assertFields("EW-Alpha's identity", alpha[1], {
		{ "UNIT", "EW-Alpha" },
		{ "TYPE", "Box Spring" },
	})
	assertFields("EW-Alpha's state line", lineWith(alpha, "ACTIVE:"), {
		{ "ACTIVE", "true" },
		{ "DETECTED TARGETS", "1" },
		{ "DEFENDING HARM", "false" },
	})
end

function TestSkynetIADSLogger:testEarlyWarningRadarListsEverySiteItCovers()
	local printed = self:printWholePage()
	local alpha = blockWith(printed.log, "UNIT: EW-Alpha")

	local countLine = lineWith(alpha, "SAM SITES IN COVERED AREA:")
	assertFields("EW-Alpha's covered-site count", countLine, { { "SAM SITES IN COVERED AREA", "3" } })

	-- the count is only worth something if the names that follow it agree
	local names = {}
	local seenCountLine = false
	for i = 1, #alpha do
		if seenCountLine and not alpha[i]:find(":", 1, true) then
			names[#names + 1] = alpha[i]
		end
		if alpha[i] == countLine then
			seenCountLine = true
		end
	end
	table.sort(names)
	luaunit.assertEquals(names, { "SAM-Covered", "SAM-NoAmmo", "SAM-NoRadar" })
end

--- The distance is measured from the element printing the block, not from the player — the
--- skill's reading table warns about exactly this, so the figure has to be the radar's own.
function TestSkynetIADSLogger:testEarlyWarningRadarContactLineCarriesTheDistanceFromThatRadar()
	local printed = self:printWholePage()
	local alpha = blockWith(printed.log, "UNIT: EW-Alpha")

	-- EW-Alpha stands at the origin, the intruder at x = 10 000 m and 3 000 m up:
	-- sqrt(10000^2 + 3000^2) = 10 440 m, and 10 440 / 1852 = 5.637… NM, rounded to 5.64.
	assertFields("EW-Alpha's contact line", lineWith(alpha, "CONTACT:"), {
		{ "CONTACT", "Intruder-1" },
		{ "TYPE", "F-16C" },
		{ "DISTANCE NM", "5.64" },
	})
end

--- Half a destroyed network is exactly the state someone is reading the log in. A radar DCS no
--- longer has must print, and say so, rather than throw on the way to the name.
function TestSkynetIADSLogger:testDestroyedEarlyWarningRadarPrintsDESTROYEDAndKeepsGoing()
	local printed = self:printWholePage()
	local charlie = blockWith(printed.log, "UNIT: DESTROYED")

	assertFields("a destroyed radar's identity", charlie[1], {
		{ "UNIT", "DESTROYED" },
		{ "TYPE", "Box Spring" },
	})
	-- it still holds the contact its cache carried, and still cannot measure a distance to it,
	-- so the count is printed and the CONTACT line is not
	assertFields("a destroyed radar's state line", lineWith(charlie, "ACTIVE:"), {
		{ "ACTIVE", "true" },
		{ "DETECTED TARGETS", "1" },
		{ "DEFENDING HARM", "false" },
	})
	luaunit.assertNil(lineWith(charlie, "CONTACT:"))
	-- and the block after it was still printed, so the page did not stop there
	luaunit.assertNotNil(lineWith(printed.log, "SAM STATUS:"))
end

function TestSkynetIADSLogger:testEarlyWarningRadarWithADamagedConnectionNodeCountsIt()
	local printed = self:printWholePage()
	local bravo = blockWith(printed.log, "UNIT: EW-Bravo")
	assertFields("EW-Bravo's connection nodes", lineWith(bravo, "CONNECTION NODES:"), {
		{ "CONNECTION NODES", "1" },
		{ "DAMAGED", "1" },
		{ "INTACT", "0" },
	})
	luaunit.assertNotNil(lineWith(bravo, "NO POWER SOURCES SET"))
end

-- ---- the SAM site block -------------------------------------------------------------------

function TestSkynetIADSLogger:testSAMSiteBlockOpensOnceWithTheCoalition()
	local printed = self:printWholePage()
	luaunit.assertEquals(countLinesWith(printed.log, "SAM STATUS:"), 1)
	luaunit.assertStrContains(lineWith(printed.log, "SAM STATUS:"), "COALITION: RED")
	luaunit.assertEquals(countLinesWith(printed.log, "GROUP: SAM-"), 4)
end

--- The nine fields the skill reads to decide whether the chain works at all. ACTIVE with
--- AUTONOMOUS is the pair it counts across a whole log; HAS AMMO is what it checks before
--- believing a site will ever light up again.
function TestSkynetIADSLogger:testSAMSiteStateLineFieldsAreRight()
	local printed = self:printWholePage()
	local covered = blockWith(printed.log, "GROUP: SAM-Covered")

	assertFields("SAM-Covered's identity", covered[1], {
		{ "GROUP", "SAM-Covered" },
		{ "TYPE", "SA-6" },
	})
	assertFields("SAM-Covered's state line", lineWith(covered, "ACTIVE:"), {
		{ "ACTIVE", "true" },
		{ "AUTONOMOUS", "false" },
		{ "IS ACTING AS EW", "false" },
		{ "CAN ENGAGE AIR WEAPONS", "true" },
		{ "CAN ENGAGE HARMS", "false" },
		{ "HAS AMMO", "true" },
		{ "DETECTED TARGETS", "1" },
		{ "DEFENDING HARM", "false" },
		{ "MISSILES IN FLIGHT", "0" },
	})
end

--- The two states that read as failures and are not: a battery on its own, and one that has
--- shot itself dry. Both have to be distinguishable on the page.
function TestSkynetIADSLogger:testAnAutonomousSiteAndAnEmptyOneReadDifferently()
	local printed = self:printWholePage()

	local lonely = lineWith(blockWith(printed.log, "GROUP: SAM-Lonely"), "ACTIVE:")
	luaunit.assertEquals(fieldValue(lonely, "AUTONOMOUS"), "true", "SAM-Lonely")
	luaunit.assertEquals(fieldValue(lonely, "HAS AMMO"), "true", "SAM-Lonely")

	local empty = lineWith(blockWith(printed.log, "GROUP: SAM-NoAmmo"), "ACTIVE:")
	luaunit.assertEquals(fieldValue(empty, "AUTONOMOUS"), "true", "SAM-NoAmmo")
	luaunit.assertEquals(fieldValue(empty, "HAS AMMO"), "false", "SAM-NoAmmo")
end

--- A site whose search radar is gone still holds what it last saw, and has nothing left to
--- measure the distance with. It has to print the count and skip the CONTACT line, not throw.
function TestSkynetIADSLogger:testSiteWithNoRadarPrintsItsContactCountWithoutADistance()
	local printed = self:printWholePage()
	local noRadar = blockWith(printed.log, "GROUP: SAM-NoRadar")

	luaunit.assertEquals(fieldValue(lineWith(noRadar, "ACTIVE:"), "DETECTED TARGETS"), "1", "SAM-NoRadar")
	luaunit.assertNil(lineWith(noRadar, "CONTACT:"))
	assertFields("SAM-NoRadar's power sources", lineWith(noRadar, "POWER SOURCES"), {
		{ "POWER SOURCES", "1" },
		{ "DAMAGED", "1" },
		{ "INTACT", "0" },
	})
end

-- ---- printOutput / printOutputToLog -------------------------------------------------------

function TestSkynetIADSLogger:testPlainOutputGoesToTheScreenUntouched()
	local logger = self.iads.logger
	local printed = capture(function()
		logger:printOutput("a plain line")
	end)
	luaunit.assertEquals(printed.screen, { "a plain line" })
	luaunit.assertEquals(#printed.log, 0)
end

function TestSkynetIADSLogger:testWarningsArePrefixedWhileWarningsAreOn()
	local logger = self.iads.logger
	luaunit.assertEquals(logger:getDebugSettings().warnings, true, "warnings are on by default")
	local printed = capture(function()
		logger:printOutput("the radio menu is missing", true)
	end)
	luaunit.assertEquals(printed.screen, { "WARNING: the radio menu is missing" })
end

function TestSkynetIADSLogger:testWarningsAreSilentOnceWarningsAreOff()
	local logger = self.iads.logger
	logger:getDebugSettings().warnings = false
	local printed = capture(function()
		logger:printOutput("the radio menu is missing", true)
		logger:printOutput("a plain line")
	end)
	-- the setting silences warnings, not everything
	luaunit.assertEquals(printed.screen, { "a plain line" })
end

function TestSkynetIADSLogger:testLoggedLinesGoToTheDCSLogWithTheSkynetPrefix()
	local logger = self.iads.logger
	capture(function()
		logger:printOutputToLog("a line for dcs.log")
	end)
	luaunit.assertEquals(#dcsStub.screenText, 0, "the log is not the screen")
	luaunit.assertEquals(dcsStub.logs[1].text, SKYNET_PREFIX .. "a line for dcs.log")
	luaunit.assertEquals(dcsStub.logs[1].level, "I")
end

os.exit(luaunit.LuaUnit.run())
