do
	--this class is currently used for AWACS and Ships, at a latter date a separate class for ships could be created, currently not needed
	SkynetIADSAWACSRadar = {}
	SkynetIADSAWACSRadar = inheritsFrom(SkynetIADSAbstractRadarElement)

	function SkynetIADSAWACSRadar:create(radarUnit, iads)
		local instance = self:superClass():create(radarUnit, iads)
		setmetatable(instance, self)
		self.__index = self
		instance.natoName = radarUnit:getTypeName()
		return instance
	end

	function SkynetIADSAWACSRadar:setupElements()
		local unit = self:getDCSRepresentation()
		local radar = SkynetIADSSAMSearchRadar:create(unit)
		radar:setupRangeData()
		table.insert(self.searchRadars, radar)
	end

	-- AWACs will not scan for HARMS
	function SkynetIADSAWACSRadar:scanForHarms() end

	-- The movement check used to live here, and being a method of this class is exactly what made it
	-- apply to AWACS and to nothing else that moves. It is now
	-- SkynetIADSAbstractRadarElement:hasMovedSinceLastCoverageUpdate(); this name is kept because it
	-- is part of the public surface of the script.
	function SkynetIADSAWACSRadar:isUpdateOfAutonomousStateOfSAMSitesRequired()
		return self:hasMovedSinceLastCoverageUpdate()
	end
end
