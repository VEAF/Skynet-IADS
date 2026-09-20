do
--Figures that belong to Eagle Dynamics are NOT asserted here any more.
--
--125 such assertions came out of the in-sim suites, 58 of them from this file. The one that
--made the case was in test-skynet-iads-red-sam-sites-and-ew-radars.lua: `getRange() == 35000` for
--the SA-11's missile. ED has since made it 46000, so a Buk battery wakes 11 km further out in
--every mission that places one -- and the only way anyone found out was running that mission in
--DCS after three years, where it read as a red test rather than as news.
--
--For the other suites, those figures are now recorded in test/lua/dcs-figures.lua and a weekly
--workflow reports when one moves. NOT FOR THIS ONE. The generator reads the Quaggles datamine,
--which dumps stock DCS: 14 of the 18 radar types this suite exercises come from the HighDigitSAMs
--mod and are in no dump. Their figures are watched by nothing, and asserting them here watched
--them no better -- this mission cannot even be loaded without the mod, which is why its three
--newest tests had never run once before 2026-09-20.
--
--What stays here is what a stub cannot answer: terrain elevation, real detection geometry, what
--DCS reports about a group's composition, and Skynet's own decisions. Assertions on figures the
--test itself fabricates through a mocked getDCSRepresentation() stay too -- those are not ED's.

TestSyknetIADSHighDigitSAMSites = {}

function TestSyknetIADSHighDigitSAMSites:setUp()
	if self.samSiteName then
		self.skynetIADS = SkynetIADS:create()
		local samSite = Group.getByName(self.samSiteName)
		self.samSite = SkynetIADSSamSite:create(samSite, self.skynetIADS)
		self.samSite:setupElements()
	end
	if self.ewName then
		self.skynetIADS = SkynetIADS:create()
		local ewRadar = Unit.getByName(self.ewName)
		self.ewRadar = SkynetIADSEWRadar:create(ewRadar, self.skynetIADS)
		self.ewRadar:setupElements()
	end
end

function TestSyknetIADSHighDigitSAMSites:tearDown()
	if self.samSite then	
		self.samSite:cleanUp()
	end
	
	if self.ewRadar then
		self.ewRadar:cleanUp()
	end
end

function TestSyknetIADSHighDigitSAMSites:testSA20AGargoyle()
	self.samSiteName = "SAM-SA-20A"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-20A")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 2)
	
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "S-300PMU1 5P85CE ln")
	
	local launcher2 = launchers[2]
	lu.assertEquals(launcher2:getTypeName(), "S-300PMU1 5P85DE ln")
	
	local searchRadars = self.samSite:getSearchRadars()
	lu.assertEquals(#searchRadars, 2)
	
	local searchRadars1 = searchRadars[1]
	lu.assertEquals(searchRadars1:getTypeName(), "S-300PMU1 40B6MD sr")

	local searchRadars2 = searchRadars[2]
	lu.assertEquals(searchRadars2:getTypeName(), "S-300PMU1 64N6E sr")
	
	local trackingRadars = self.samSite:getTrackingRadars()
	lu.assertEquals(#trackingRadars, 2)
	
	local trackingRadar1 = trackingRadars[1]
	lu.assertEquals(trackingRadar1:getTypeName(), "S-300PMU1 40B6M tr")
	
	local trackingRadar2 = trackingRadars[2]
	lu.assertEquals(trackingRadar2:getTypeName(), "S-300PMU1 30N6E tr")
	
	lu.assertEquals(self.samSite:getHARMDetectionChance(), 90)
	lu.assertEquals(self.samSite:getCanEngageHARM(), true)
	
	--output sensor data to dcs.log:
	--lu.assertEquals(launcher1:getDCSRepresentation():getSensors(), "00")

end

function TestSyknetIADSHighDigitSAMSites:testBigBird()
	self.ewName = "Big-Bird"
	self:setUp()
	lu.assertEquals(self.ewRadar:getNatoName(), "Big Bird")
end

function TestSyknetIADSHighDigitSAMSites:testClamShell()
	self.ewName = "Clam-Shell"
	self:setUp()
	lu.assertEquals(self.ewRadar:getNatoName(), "Clam Shell")
end

function TestSyknetIADSHighDigitSAMSites:testBillBoardC()
	self.ewName = "Bill-Board-C"
	self:setUp()
	lu.assertEquals(self.ewRadar:getNatoName(), "Bill Board-C")
end

function TestSyknetIADSHighDigitSAMSites:testHighScreenB()
	self.ewName = "High-Screen-B"
	self:setUp()
	lu.assertEquals(self.ewRadar:getNatoName(), "High Screen-B")
end

function TestSyknetIADSHighDigitSAMSites:testClamShell2()
	self.ewName = "Clam-Shell-2"
	self:setUp()
	lu.assertEquals(self.ewRadar:getNatoName(), "Clam Shell")
end

function TestSyknetIADSHighDigitSAMSites:testSnowDrift()
	self.ewName = "Snow-Drift"
	self:setUp()
	lu.assertEquals(self.ewRadar:getNatoName(), "Snow Drift")
end

function TestSyknetIADSHighDigitSAMSites:testUnnamedRadar()
	self.ewName = "unnamed-radar"
	self:setUp()
	lu.assertEquals(self.ewRadar:getNatoName(), "UNKNOWN")
	lu.assertEquals(self.ewRadar:getHARMDetectionChance(), 90)
end

function TestSyknetIADSHighDigitSAMSites:testSA23GladiatorOrGiant()
	self.samSiteName = "SAM-SA-23"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-23")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 2)

	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "S-300VM 9A83ME ln")

	local launcher1 = launchers[2]
	lu.assertEquals(launcher1:getTypeName(), "S-300VM 9A82ME ln")
	
	local searchRadars = self.samSite:getSearchRadars()
	lu.assertEquals(#searchRadars, 2)
	
	local searchRadars1 = searchRadars[1]
	lu.assertEquals(searchRadars1:getTypeName(), "S-300VM 9S15M2 sr")
	
	local searchRadars1 = searchRadars[2]
	lu.assertEquals(searchRadars1:getTypeName(), "S-300VM 9S19M2 sr")
	
	local trackingRadars = self.samSite:getTrackingRadars()
	lu.assertEquals(#trackingRadars, 1)
	
	local trackingRadar1 = trackingRadars[1]
	lu.assertEquals(trackingRadar1:getTypeName(), "S-300VM 9S32ME tr")

	lu.assertEquals(self.samSite:getHARMDetectionChance(), 90)
	lu.assertEquals(self.samSite:getCanEngageHARM(), true)
	
end

function TestSyknetIADSHighDigitSAMSites:testSA10BGrumble()
	self.samSiteName = "SAM-SA-10B"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-10B")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 2)
	
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "S-300PS 5P85SE_mod ln")
	
	local launcher1 = launchers[2]
	lu.assertEquals(launcher1:getTypeName(), "S-300PS 5P85SU_mod ln")
	
	local searchRadars = self.samSite:getSearchRadars()
	lu.assertEquals(#searchRadars, 2)
	
	local searchRadars1 = searchRadars[1]
	lu.assertEquals(searchRadars1:getTypeName(), "S-300PS SA-10B 40B6MD MAST sr")
	
	local searchRadars1 = searchRadars[2]
	lu.assertEquals(searchRadars1:getTypeName(), "S-300PS 64H6E TRAILER sr")
	
	local trackingRadars = self.samSite:getTrackingRadars()
	lu.assertEquals(#trackingRadars, 2)
	
	local trackingRadar1 = trackingRadars[1]
	lu.assertEquals(trackingRadar1:getTypeName(), "S-300PS 30N6 TRAILER tr")
	
	local trackingRadar1 = trackingRadars[2]
	lu.assertEquals(trackingRadar1:getTypeName(), "S-300PS SA-10B 40B6M MAST tr")
	
	lu.assertEquals(self.samSite:getHARMDetectionChance(), 90)
	lu.assertEquals(self.samSite:getCanEngageHARM(), true)
	
end

function TestSyknetIADSHighDigitSAMSites:testEDDefaultSA10GrubleWith55VRUD()
	self.samSiteName = "SAM-SA-10C-5V55RUD"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-10")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 2)
	
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "S-300PS 5P85DE ln")
end

function TestSyknetIADSHighDigitSAMSites:testSA10BGrumbleWith55VRUD()
	self.samSiteName = "SAM-SA-10B-5V55RUD"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-10B")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 2)
end

function TestSyknetIADSHighDigitSAMSites:testSA20AGargoyleWith55VRUD()
	self.samSiteName = "SAM-SA-20A-5V55RUD"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-20A")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 2)
end

function TestSyknetIADSHighDigitSAMSites:testSA17Grizzly()
	self.samSiteName = "SAM-SA-17"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-17")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 1)
	
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "SA-17 Buk M1-2 LN 9A310M1-2")
end

function TestSyknetIADSHighDigitSAMSites:testSA2GuidelineWithV7595V23()
	self.samSiteName = "SAM-SA-2-V-759-5V23"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-2")

	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 1)
	
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "S_75M_Volhov_V759")
end	

function TestSyknetIADSHighDigitSAMSites:testSA3GoaWithV601P5V27()
	self.samSiteName = "SAM-SA-3-V-601P-5V27"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-3")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 1)
	
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "5p73 V-601P ln")
end

function TestSyknetIADSHighDigitSAMSites:testSA2GuidelineWithHQ2()
	self.samSiteName = "SAM-SA-2HQ-2"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-2")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 1)
	
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "HQ_2_Guideline_LN")
	
end

function TestSyknetIADSHighDigitSAMSites:testSA12GladiatorGiant()
	self.samSiteName = "SAM-SA-12-S300V"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-12")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 2)
	
	
	local searchRadars = self.samSite:getSearchRadars()
	lu.assertEquals(#searchRadars, 2)
	
	local searchRadar1 = searchRadars[1]
	lu.assertEquals(searchRadar1:getTypeName(), "S-300V 9S15 sr")

	local searchRadar2 = searchRadars[2]
	lu.assertEquals(searchRadar2:getTypeName(), "S-300V 9S19 sr")
	
	local trackingRadars = self.samSite:getTrackingRadars()
	lu.assertEquals(#trackingRadars, 1)
	
	local trackingRadar1 = trackingRadars[1]
	lu.assertEquals(trackingRadar1:getTypeName(), "S-300V 9S32 tr")
		
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "S-300V 9A83 ln")
	
	local launcher2 = launchers[2]
	lu.assertEquals(launcher2:getTypeName(), "S-300V 9A82 ln")
	
	lu.assertEquals(self.samSite:getHARMDetectionChance(), 90)
	lu.assertEquals(self.samSite:getCanEngageHARM(), true)
	
	
end

function TestSyknetIADSHighDigitSAMSites:testSA20BGargoyle()
	self.samSiteName = "SAM-SA-20B"
	self:setUp()
	lu.assertEquals(self.samSite:getNatoName(), "SA-20B")
	
	local searchRadars = self.samSite:getSearchRadars()
	lu.assertEquals(#searchRadars, 1)
	
	local searchRadar1 = searchRadars[1]
	lu.assertEquals(searchRadar1:getTypeName(), "S-300PMU2 64H6E2 sr")
	
	local trackingRadars = self.samSite:getTrackingRadars()
	lu.assertEquals(#trackingRadars, 1)
	
	local trackingRadar1 = trackingRadars[1]
	lu.assertEquals(trackingRadar1:getTypeName(), "S-300PMU2 92H6E tr")
	
	local launchers = self.samSite:getLaunchers()
	lu.assertEquals(#launchers, 1)
	
	local launcher1 = launchers[1]
	lu.assertEquals(launcher1:getTypeName(), "S-300PMU2 5P85SE2 ln")
	
	lu.assertEquals(self.samSite:getHARMDetectionChance(), 90)
	lu.assertEquals(self.samSite:getCanEngageHARM(), true)
	
end

end