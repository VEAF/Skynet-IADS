--- Tests for FIX-POINT-DEFENCE-FLAPPING-UNDER-HARM: a SAM site whose point defence can take the
--- inbound HARM must stay as it was while the point defence engages.
---
--- Coverage is geometry, so a site and the point defence beside it are each other's parent and
--- child. A point defence that went live by acting as EW sent that change down the link, and the
--- protected site got resetAutonomousState() -> goDark(): dark for the whole HARM when it acts as
--- EW, dark too when it is live with no track of its own. These drive both through the calls a
--- mission makes: informOfHARM() from the HARM detection, evaluateContacts() every cycle, and the
--- HARM scan that ages the HARM out.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/../common/dcs-stub.lua")
local loader = dofile(base .. "/../common/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/../common/dcs-fixtures.lua")

local RED = 1 -- coalition.side.RED

TestSkynetIADSPointDefenceUnderHARM = {}

--- An SA-10 at the origin and an SA-15 1.5 km north of it as its point defence, both under a
--- 1L13 100 km away. No radar detects anything unless a test says so.
function TestSkynetIADSPointDefenceUnderHARM:buildNetwork()
	local iads = SkynetIADS:create()
	iads:setLastLineOfDefence(false)

	F.earlyWarningRadarUnit("EW-north", { pos = { x = 100000, y = 0, z = 0 }, coalition = RED })
	local ewRadar = iads:addEarlyWarningRadar("EW-north")
	function ewRadar:getDetectedTargets()
		return {}
	end

	F.samGroup("SA-10", "SAM-SA-10", { pos = { x = 0, y = 0, z = 0 }, coalition = RED })
	local site = iads:addSAMSite("SAM-SA-10")
	function site:getDetectedTargets()
		return {}
	end
	F.samGroup("SA-15", "SAM-SA-15", { pos = { x = 1500, y = 0, z = 0 }, coalition = RED })
	local pointDefence = iads:addSAMSite("SAM-SA-15")
	function pointDefence:getDetectedTargets()
		return {}
	end
	site:addPointDefence(pointDefence)
	site:setHARMDetectionChance(100)

	iads:activate()
	return iads, site, pointDefence
end

--- A HARM 10 km east of the site's radar, flying straight at it. getAge() is what the HARM scan
--- reads to forget it: set `harm.age` past the site's maximum target age and it is gone.
local function inboundHARM(site)
	local radarPosition = site:getRadars()[1]:getPosition().p
	local position = { x = radarPosition.x, y = 5000, z = radarPosition.z + 10000 }
	local harm = { age = 0 }
	function harm.getPosition()
		return { p = position }
	end
	function harm.getMagneticHeading()
		return SkynetIADSUtils.toDegree(SkynetIADSUtils.getHeadingPoints(position, radarPosition))
	end
	function harm.getGroundSpeedInKnots()
		return 1200
	end
	function harm.getAge()
		return harm.age
	end
	return harm
end

local function isIn(list, element)
	for i = 1, #list do
		if list[i] == element then
			return true
		end
	end
	return false
end

function TestSkynetIADSPointDefenceUnderHARM:setUp()
	dcsStub.reset()
end

function TestSkynetIADSPointDefenceUnderHARM:tearDown()
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

--- The documented setup: an SA-10 acting as EW, protected by an SA-15.
function TestSkynetIADSPointDefenceUnderHARM:testSiteActingAsEWStaysLiveWhileItsPointDefenceEngages()
	local iads, site, pointDefence = self:buildNetwork()
	self.iads = iads
	site:setActAsEW(true)
	-- the link the change used to travel down, made by geometry alone
	luaunit.assertTrue(isIn(pointDefence:getChildRadars(), site))
	luaunit.assertEquals(site:isActive(), true)
	luaunit.assertEquals(pointDefence:isActive(), false)

	local harm = inboundHARM(site)
	site:informOfHARM(harm)
	luaunit.assertEquals(site:isActive(), true, "the point defence going live sent the site dark")
	luaunit.assertEquals(pointDefence:isActive(), true)
	luaunit.assertEquals(pointDefence:getActAsEW(), false)

	-- the next cycles: goLive() on every radar acting as EW, the point defence's target cycle
	for _ = 1, 2 do
		SkynetIADS.evaluateContacts(iads)
		site:informOfHARM(harm)
		luaunit.assertEquals(site:isActive(), true, "a contact cycle sent the site dark")
		luaunit.assertEquals(pointDefence:isActive(), true, "a contact cycle sent the point defence dark")
	end

	harm.age = site.objectsIdentifiedAsHarmsMaxTargetAge + 1
	SkynetIADSAbstractRadarElement.evaluateIfTargetsContainHARMs(site)
	luaunit.assertEquals(pointDefence:isActive(), false, "the HARM is gone: the point defence stands down")
	luaunit.assertEquals(site:isActive(), true)
	SkynetIADS.evaluateContacts(iads)
	luaunit.assertEquals(pointDefence:isActive(), false)
end

--- A site live on a contact the network reported, before its own radar holds a track: nothing in
--- goDark()'s guard holds it up, so the point defence going live must not send it anything.
function TestSkynetIADSPointDefenceUnderHARM:testSiteLiveWithNoTrackOfItsOwnStaysLiveWhileItsPointDefenceEngages()
	local iads, site, pointDefence = self:buildNetwork()
	self.iads = iads
	site:goLive()
	luaunit.assertEquals(site:isActive(), true)

	site:informOfHARM(inboundHARM(site))
	luaunit.assertEquals(site:isActive(), true, "the point defence going live sent the site dark")
	luaunit.assertEquals(pointDefence:isActive(), true)
	luaunit.assertEquals(pointDefence:getActAsEW(), false)
end

--- The protected site goes dark of its own accord while the HARM is still remembered, here for
--- want of a target. Its HARM scan is what ages the HARM out and releases the point defence, so
--- the scan has to go on until then, and only then stop.
function TestSkynetIADSPointDefenceUnderHARM:testPointDefenceStandsDownOnceTheHARMIsGoneAfterTheSiteWentDark()
	local iads, site, pointDefence = self:buildNetwork()
	self.iads = iads
	site:goLive()
	local harm = inboundHARM(site)
	site:informOfHARM(harm)
	luaunit.assertEquals(pointDefence:isActive(), true)

	-- the contact cycle: nothing in range, so the site goes dark
	SkynetIADS.evaluateContacts(iads)
	luaunit.assertEquals(site:isActive(), false)
	luaunit.assertEquals(pointDefence:isActive(), true, "the HARM is still remembered")

	harm.age = site.objectsIdentifiedAsHarmsMaxTargetAge + 1
	dcsStub.advanceClock(3)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(pointDefence:isActive(), false, "the HARM is gone: the point defence stands down")
	luaunit.assertEquals(site:isScanningForHARMs(), false, "a dark site with nothing remembered stops scanning")
end

os.exit(luaunit.LuaUnit.run())
