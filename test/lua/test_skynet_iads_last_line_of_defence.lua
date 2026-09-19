--- Tests for the last line of defense: a SAM site held dark by the network wakes
--- when a hostile aircraft flies over it, with no radar contact anywhere.
---
--- Almost every test here drives the real SkynetIADS.evaluateContacts() rather than
--- calling the wake-up directly. That is deliberate: the failure mode this feature has
--- to avoid is a wake-up that is perfectly tested and never called by the cycle. The
--- scenario is the one that was reported — an EW radar covers the site, sees nothing,
--- and the aircraft is right on top of the battery.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

local RED = 1 -- coalition.side.RED
local BLUE = 2 -- coalition.side.BLUE

TestSkynetIADSLastLineOfDefence = {}

--- Builds the reported situation: a RED SA-2 at the origin, a RED EW radar 100 km away
--- whose 120 km detection range covers the battery (so the battery is held dark) but
--- which never reports a contact.
---
--- Both radars are told to report nothing, so anything that happens to the site in a
--- cycle can only come from the last line of defense.
function TestSkynetIADSLastLineOfDefence:buildNetwork()
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

function TestSkynetIADSLastLineOfDefence:setUp()
	dcsStub.reset()
end

function TestSkynetIADSLastLineOfDefence:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--the whole point of the lot: no radar holds the target, and the site still lights up
function TestSkynetIADSLastLineOfDefence:testDarkSiteWakesWhenHostileAircraftEntersItsRadius()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	luaunit.assertEquals(samSite:isActive(), false)
	luaunit.assertEquals(samSite:getAutonomousState(), false) -- held by the network, not autonomous

	iads:evaluateContacts()

	luaunit.assertEquals(samSite:isActive(), true)
	--it is still the network's site: it went live without becoming autonomous
	luaunit.assertEquals(samSite:getAutonomousState(), false)
end

function TestSkynetIADSLastLineOfDefence:testSiteDoesNotWakeForAircraftOutsideTheRadius()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	--20 km out, twice the 10 km radius drawn for this test
	F.aircraftGroup("intruder", { pos = { x = 20000, y = 500, z = 0 }, coalition = BLUE })

	iads:evaluateContacts()

	luaunit.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADSLastLineOfDefence:testSiteDoesNotWakeForAFriendlyAircraft()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	--same position as the intruder above, but on the network's own side
	F.aircraftGroup("wingman", { pos = { x = 8000, y = 500, z = 0 }, coalition = RED })

	iads:evaluateContacts()

	luaunit.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADSLastLineOfDefence:testSiteDoesNotWakeForAircraftOnTheGround()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	--parked on a ramp 8 km away: inside the radius, but not flying over anything
	F.aircraftGroup("parked", { pos = { x = 8000, y = 0, z = 0 }, coalition = BLUE, inAir = false })

	iads:evaluateContacts()

	luaunit.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADSLastLineOfDefence:testSiteDoesNotWakeWhenTheSettingIsOff()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	iads:setLastLineOfDefence(false)
	F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	iads:evaluateContacts()

	luaunit.assertEquals(samSite:isActive(), false)
	--and switching it back on is enough for the very next cycle to react
	iads:setLastLineOfDefence(true)
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)
end

--the subtlest behaviour in this project: the last line of defense must never cancel HARM evasion
function TestSkynetIADSLastLineOfDefence:testSiteDefendingAgainstAHARMDoesNotWake()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	samSite:goSilentToEvadeHARM(10)
	luaunit.assertEquals(samSite:isDefendingHARM(), true)
	luaunit.assertEquals(samSite:isActive(), false)

	iads:evaluateContacts()

	luaunit.assertEquals(samSite:isActive(), false)
	luaunit.assertEquals(samSite:isDefendingHARM(), true)
end

--a site with nothing left to shoot would light up for nothing and be killed for it
function TestSkynetIADSLastLineOfDefence:testSiteWithoutAmmunitionDoesNotWake()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	local launchers = samSite:getLaunchers()
	for i = 1, #launchers do
		launchers[i]:getDCSRepresentation():__destroy()
	end
	luaunit.assertEquals(samSite:hasRemainingAmmo(), false)

	iads:evaluateContacts()

	luaunit.assertEquals(samSite:isActive(), false)
end

--a constraint the mission author wrote explicitly is still the author's decision; only the
--kill-zone test is bypassed
function TestSkynetIADSLastLineOfDefence:testGoLiveConstraintsAreHonoured()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	--500 m / 0.3048 = 1640 ft, so this constraint refuses the intruder
	samSite:addGoLiveConstraint("high-flyers-only", function(contact)
		return contact:getHeightInFeetMSL() > 4000
	end)

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), false)

	samSite:removeGoLiveConstraint("high-flyers-only")
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)
end

--a fast pass must leave the site lit, or it flickers for a single cycle and nothing more
function TestSkynetIADSLastLineOfDefence:testSiteStaysLitForThePersistenceThenGoesDark()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	local intruder = F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)

	--the aircraft is gone, well outside the radius
	intruder:__setPos({ x = 200000, y = 500, z = 0 })

	--44 s later the site is still lit: the default persistence is 45 s
	dcsStub.setClock(44)
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)

	--46 s and it falls silent, on the normal cycle, with no special case
	dcsStub.setClock(46)
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADSLastLineOfDefence:testPersistenceIsSettable()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	iads:setLastLineOfDefencePersistence(5)
	luaunit.assertEquals(iads:getLastLineOfDefencePersistence(), 5)
	local intruder = F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)

	intruder:__setPos({ x = 200000, y = 500, z = 0 })
	dcsStub.setClock(6)
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), false)
end

--drawn once for the mission: a radius redrawn every cycle makes an aircraft loitering near
--the mean switch the site on and off every five seconds
function TestSkynetIADSLastLineOfDefence:testDrawnRadiusIsStableAcrossCycles()
	local iads = SkynetIADS:create()
	self.iads = iads
	iads:setLastLineOfDefenceRadius(10000, 15000)
	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")

	local firstDraw = samSite:getLastLineOfDefenceRadius()
	luaunit.assertTrue(firstDraw >= 10000 and firstDraw <= 15000)
	for _ = 1, 20 do
		luaunit.assertEquals(samSite:getLastLineOfDefenceRadius(), firstDraw)
	end
end

--the radius is drawn on first use, so bounds set after the sites were added still apply
function TestSkynetIADSLastLineOfDefence:testChangingTheBoundsRedrawsTheRadius()
	local iads = SkynetIADS:create()
	self.iads = iads
	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")

	iads:setLastLineOfDefenceRadius(10000, 10000)
	luaunit.assertEquals(samSite:getLastLineOfDefenceRadius(), 10000)

	iads:setLastLineOfDefenceRadius(30000, 30000)
	luaunit.assertEquals(samSite:getLastLineOfDefenceRadius(), 30000)

	--nonsense bounds are refused, and what was drawn stands
	iads:setLastLineOfDefenceRadius(50000, 40000)
	luaunit.assertEquals(samSite:getLastLineOfDefenceRadius(), 30000)
end

--the enumeration is the expensive part; a mission with sixty batteries must not sweep the
--coalitions sixty times every five seconds
function TestSkynetIADSLastLineOfDefence:testHostileAirUnitsAreEnumeratedOnceForTheWholeCycle()
	local iads = SkynetIADS:create()
	self.iads = iads
	iads:setLastLineOfDefenceRadius(10000, 10000)

	F.earlyWarningRadarUnit("EW-north", { pos = { x = 100000, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-north")
	function ewRadar:getDetectedTargets()
		return {}
	end

	for i = 1, 5 do
		local name = "SAM-" .. i
		--50 km apart, so no aircraft is near any of them
		F.samGroup("SA-2", name, { pos = { x = i * 50000, y = 0, z = 0 }, coalition = RED })
		local site = iads:addSAMSite(name)
		function site:getDetectedTargets()
			return {}
		end
	end
	iads:activate()

	local enumerations = 0
	local realGetHostileAirUnits = SkynetIADS.getHostileAirUnits
	function iads:getHostileAirUnits()
		enumerations = enumerations + 1
		return realGetHostileAirUnits(self)
	end

	iads:evaluateContacts()
	luaunit.assertEquals(enumerations, 1)
end

--a site with no network left, told to stay dark on its own, is exactly the one that will never
--see anything coming -- so it wakes too
function TestSkynetIADSLastLineOfDefence:testAutonomousDarkSiteWakesAndFallsSilentAgain()
	local iads = SkynetIADS:create()
	self.iads = iads
	iads:setLastLineOfDefenceRadius(10000, 10000)

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end
	--no EW radar anywhere, and told to stay dark rather than hand over to the DCS AI
	samSite:setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	iads:activate()

	luaunit.assertEquals(samSite:getAutonomousState(), true)
	luaunit.assertEquals(samSite:isActive(), false)

	local intruder = F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)

	--and it must fall silent again: nothing else would ever switch this one back off, so without
	--the matching guard the last line of defense would light it for the rest of the mission
	intruder:__setPos({ x = 200000, y = 500, z = 0 })
	dcsStub.setClock(46)
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), false)
end

--a site the DCS AI is already running has nothing to gain from the sweep
function TestSkynetIADSLastLineOfDefence:testAutonomousDCSAISiteIsLeftAlone()
	local iads = SkynetIADS:create()
	self.iads = iads
	iads:setLastLineOfDefenceRadius(10000, 10000)

	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end
	iads:activate()
	luaunit.assertEquals(samSite:getAutonomousState(), true)
	luaunit.assertEquals(samSite:isActive(), true)

	F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })
	local radiusDraws = 0
	local realRadius = SkynetIADSSamSite.getLastLineOfDefenceRadius
	function samSite:getLastLineOfDefenceRadius()
		radiusDraws = radiusDraws + 1
		return realRadius(self)
	end

	iads:evaluateContacts()
	luaunit.assertEquals(radiusDraws, 0)
	luaunit.assertEquals(samSite:isActive(), true)
end

--the public door itself, called the way VEAF's spotter network will call it
function TestSkynetIADSLastLineOfDefence:testReportContactIsAPublicEntryPoint()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	--45 km out: far outside the kill zone, and outside the drawn radius too. reportContact
	--wakes the site anyway, which is what informOfContact() refuses to do.
	local intruder = F.aircraftGroup("intruder", { pos = { x = 45000, y = 500, z = 0 }, coalition = BLUE })

	luaunit.assertEquals(samSite:isActive(), false)
	luaunit.assertEquals(iads:reportContact(intruder, samSite), true)
	luaunit.assertEquals(samSite:isActive(), true)

	--and the site it woke is held lit by the same persistence
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)
	dcsStub.setClock(46)
	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADSLastLineOfDefence:testReportContactRefusesNonsense()
	local iads, samSite = self:buildNetwork()
	self.iads = iads
	local intruder = F.aircraftGroup("intruder", { pos = { x = 8000, y = 500, z = 0 }, coalition = BLUE })

	luaunit.assertEquals(iads:reportContact(nil, samSite), false)
	luaunit.assertEquals(iads:reportContact(intruder, nil), false)
	intruder:__destroy()
	luaunit.assertEquals(iads:reportContact(intruder, samSite), false)
	luaunit.assertEquals(samSite:isActive(), false)
end

--a site that an EW radar has already triggered this cycle must not be swept again
function TestSkynetIADSLastLineOfDefence:testSiteAlreadyTriggeredByAnEWRadarIsSkipped()
	local iads = SkynetIADS:create()
	self.iads = iads
	iads:setLastLineOfDefenceRadius(10000, 10000)

	F.earlyWarningRadarUnit("EW-north", { pos = { x = 100000, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-north")
	F.samGroup("SA-2", "SAM-SA-2", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local samSite = iads:addSAMSite("SAM-SA-2")
	function samSite:getDetectedTargets()
		return {}
	end

	--10 km out at 2000 m: inside the SA-2's 40 km launcher range, so informOfContact() takes it
	local intruder = F.aircraftGroup("intruder", { pos = { x = 10000, y = 2000, z = 0 }, coalition = BLUE })
	function ewRadar:getDetectedTargets()
		return { F.iadsContact("intruder-1") }
	end
	iads:activate()

	local radiusDraws = 0
	local realRadius = SkynetIADSSamSite.getLastLineOfDefenceRadius
	function samSite:getLastLineOfDefenceRadius()
		radiusDraws = radiusDraws + 1
		return realRadius(self)
	end

	iads:evaluateContacts()
	luaunit.assertEquals(samSite:isActive(), true)
	luaunit.assertEquals(samSite:hasTargetsInRange(), true)
	luaunit.assertEquals(radiusDraws, 0)
	luaunit.assertIsTrue(intruder:isExist())
end

os.exit(luaunit.LuaUnit.run())
