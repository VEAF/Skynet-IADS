do
	SkynetIADSJammer = {}
	SkynetIADSJammer.__index = SkynetIADSJammer

	function SkynetIADSJammer:create(emitter, iads)
		local jammer = {}
		setmetatable(jammer, SkynetIADSJammer)
		jammer.radioMenu = nil
		jammer.emitter = emitter
		jammer.jammerTaskID = nil
		jammer.iads = { iads }
		jammer.maximumEffectiveDistanceNM = 200
		--the sites this jammer put on weapon hold in the last cycle, so it can hand them back when
		--it stops jamming them: see releaseSitesNoLongerJammed()
		jammer.jammedSites = {}
		--jammer probability settings are stored here, visualisation, see: https://docs.google.com/spreadsheets/d/16rnaU49ZpOczPEsdGJ6nfD0SLPxYLEYKmmo4i2Vfoe0/edit#gid=0
		jammer.jammerTable = {
			["SA-2"] = {
				["function"] = function(distanceNauticalMiles)
					return (1.4 ^ distanceNauticalMiles) + 90
				end,
				["canjam"] = true,
			},
			["SA-3"] = {
				["function"] = function(distanceNauticalMiles)
					return (1.4 ^ distanceNauticalMiles) + 80
				end,
				["canjam"] = true,
			},
			["SA-6"] = {
				["function"] = function(distanceNauticalMiles)
					return (1.4 ^ distanceNauticalMiles) + 23
				end,
				["canjam"] = true,
			},
			["SA-8"] = {
				["function"] = function(distanceNauticalMiles)
					return (1.35 ^ distanceNauticalMiles) + 30
				end,
				["canjam"] = true,
			},
			["SA-10"] = {
				["function"] = function(distanceNauticalMiles)
					return (1.07 ^ (distanceNauticalMiles / 1.13)) + 5
				end,
				["canjam"] = true,
			},
			["SA-11"] = {
				["function"] = function(distanceNauticalMiles)
					return (1.25 ^ distanceNauticalMiles) + 15
				end,
				["canjam"] = true,
			},
			["SA-15"] = {
				["function"] = function(distanceNauticalMiles)
					return (1.15 ^ distanceNauticalMiles) + 5
				end,
				["canjam"] = true,
			},
		}
		return jammer
	end

	function SkynetIADSJammer:masterArmOn()
		self:masterArmSafe()
		self.jammerTaskID = SkynetIADSUtils.scheduleFunction(SkynetIADSJammer.runCycle, { self }, 1, 10)
	end

	function SkynetIADSJammer:addFunction(natoName, jammerFunction)
		self.jammerTable[natoName] = {
			["function"] = jammerFunction,
			["canjam"] = true,
		}
	end

	function SkynetIADSJammer:setMaximumEffectiveDistance(distance)
		self.maximumEffectiveDistanceNM = distance
	end

	function SkynetIADSJammer:disableFor(natoName)
		self.jammerTable[natoName]["canjam"] = false
	end

	function SkynetIADSJammer:isKnownRadarEmitter(natoName)
		local isActive = false
		for unitName, unit in pairs(self.jammerTable) do
			if unitName == natoName and unit["canjam"] == true then
				isActive = true
			end
		end
		return isActive
	end

	function SkynetIADSJammer:addIADS(iads)
		table.insert(self.iads, iads)
	end

	function SkynetIADSJammer:getSuccessProbability(distanceNauticalMiles, natoName)
		local probability = 0
		local jammerSettings = self.jammerTable[natoName]
		if jammerSettings ~= nil then
			probability = jammerSettings["function"](distanceNauticalMiles)
		end
		return probability
	end

	function SkynetIADSJammer:getDistanceNMToRadarUnit(radarUnit)
		return SkynetIADSUtils.metersToNM(
			SkynetIADSUtils.get3DDist(self.emitter:getPosition().p, radarUnit:getPosition().p)
		)
	end

	-- I try to emulate the system as it would work in real life, so a jammer can only jam a SAM site if has line of sight to at least one radar in the group
	-- Of the radars it can see, the nearest is the one it works against. Returns nil when it can see none.
	function SkynetIADSJammer:getDistanceToNearestVisibleRadar(samSite)
		local nearest = nil
		local radars = samSite:getRadars()
		for i = 1, #radars do
			local radar = radars[i]
			if self:hasLineOfSightToRadar(radar) then
				local distance = self:getDistanceNMToRadarUnit(radar)
				if nearest == nil or distance < nearest then
					nearest = distance
				end
			end
		end
		return nearest
	end

	-- Hands back every site this jammer was holding that it is no longer jamming. Without this a
	-- site keeps the last state jam() wrote: a jammer shot down, flown out of range or blocked by
	-- terrain used to leave its targets on weapon hold, and an autonomous site never passes
	-- through goLive() to have that cleared.
	-- A site that has gone dark is not released and does not need to be: goLive() sets weapon free
	-- on its way back up, and a dark site is not shooting meanwhile. Leaving it alone also keeps
	-- this away from the controller of a site that went dark under HARM attack, where goDark() has
	-- called setOnOff(false) on purpose.
	function SkynetIADSJammer:releaseSitesNoLongerJammed(sitesStillJammed)
		for samSite in pairs(self.jammedSites) do
			if sitesStillJammed[samSite] == nil and samSite:isDestroyed() == false and samSite:isActive() == true then
				samSite:stopJamming()
			end
		end
		self.jammedSites = sitesStillJammed
	end

	function SkynetIADSJammer.runCycle(self)
		if self.emitter:isExist() == false then
			self:masterArmSafe()
			return
		end

		local sitesJammedThisCycle = {}
		for i = 1, #self.iads do
			local iads = self.iads[i]
			local samSites = iads:getActiveSAMSites()
			for j = 1, #samSites do
				local samSite = samSites[j]
				local natoName = samSite:getNatoName()
				if self:isKnownRadarEmitter(natoName) then
					local distance = self:getDistanceToNearestVisibleRadar(samSite)
					if distance ~= nil and distance <= self.maximumEffectiveDistanceNM then
						if iads:getDebugSettings().jammerProbability then
							iads:printOutput("JAMMER: Distance: " .. distance)
						end
						samSite:jam(self:getSuccessProbability(distance, natoName))
						sitesJammedThisCycle[samSite] = true
					end
				end
			end
		end
		self:releaseSitesNoLongerJammed(sitesJammedThisCycle)
	end

	function SkynetIADSJammer:hasLineOfSightToRadar(radar)
		local radarPos = radar:getPosition().p
		--lift the radar 30 meters off the ground, some 3d models are dug in to the ground, creating issues in calculating LOS
		radarPos.y = radarPos.y + 30
		return land.isVisible(radarPos, self.emitter:getPosition().p)
	end

	function SkynetIADSJammer:masterArmSafe()
		SkynetIADSUtils.removeFunction(self.jammerTaskID)
		self:releaseSitesNoLongerJammed({})
	end

	--TODO: Remove Menu when emitter dies:
	function SkynetIADSJammer:addRadioMenu()
		self.radioMenu = missionCommands.addSubMenu("Jammer: " .. self.emitter:getName())
		missionCommands.addCommand(
			"Master Arm On",
			self.radioMenu,
			SkynetIADSJammer.updateMasterArm,
			{ self = self, option = "masterArmOn" }
		)
		missionCommands.addCommand(
			"Master Arm Safe",
			self.radioMenu,
			SkynetIADSJammer.updateMasterArm,
			{ self = self, option = "masterArmSafe" }
		)
	end

	function SkynetIADSJammer.updateMasterArm(params)
		local option = params.option
		local self = params.self
		if option == "masterArmOn" then
			self:masterArmOn()
		elseif option == "masterArmSafe" then
			self:masterArmSafe()
		end
	end

	function SkynetIADSJammer:removeRadioMenu()
		missionCommands.removeItem(self.radioMenu)
	end
end
