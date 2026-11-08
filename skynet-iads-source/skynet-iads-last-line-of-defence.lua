do
	-- A SAM site held dark by the network has its emission switched off, so it is blind: the only
	-- route back to life is an EW radar that covers it holding the target. Fly under the radar
	-- horizon and no battery reacts, whatever the distance — proximity to the site is an input
	-- nowhere in the cycle, because the only sensor that could measure it is the one that was just
	-- switched off. So a dark site keeps a short virtual detection radius of its own, Skynet's, with
	-- no DCS radar involved.
	--
	-- On by default.
	SkynetIADSLastLineOfDefence = {}
	SkynetIADSLastLineOfDefence.__index = SkynetIADSLastLineOfDefence

	function SkynetIADSLastLineOfDefence:create(iads)
		local lastLineOfDefence = {}
		setmetatable(lastLineOfDefence, self)
		lastLineOfDefence.iads = iads
		lastLineOfDefence.enabled = true
		lastLineOfDefence.minRadius = 10000
		lastLineOfDefence.maxRadius = 15000
		lastLineOfDefence.persistence = 45
		return lastLineOfDefence
	end

	--- Every hostile aircraft and helicopter currently flying.
	--
	-- Enumerated once per cycle and shared by every site: a mission carrying sixty batteries would
	-- otherwise sweep the coalitions sixty times every five seconds. Neutral is not hostile.
	function SkynetIADSLastLineOfDefence:getHostileAirUnits()
		local hostileUnits = {}
		local categories = { Group.Category.AIRPLANE, Group.Category.HELICOPTER }
		for _, coalitionID in pairs(coalition.side) do
			if coalitionID ~= self.iads:getCoalition() and coalitionID ~= coalition.side.NEUTRAL then
				for i = 1, #categories do
					local groups = coalition.getGroups(coalitionID, categories[i]) or {}
					for _, group in pairs(groups) do
						--coalition.getGroups can hand back a group that no longer exists; asking it for
						--its units raises, and inside a pairs loop that aborts the whole listing
						if group and (group.isExist == nil or group:isExist()) then
							for _, unit in pairs(group:getUnits() or {}) do
								if unit:isExist() and unit:inAir() then
									table.insert(hostileUnits, unit)
								end
							end
						end
					end
				end
			end
		end
		return hostileUnits
	end

	--- Wakes every dark site an enemy aircraft is flying over.
	function SkynetIADSLastLineOfDefence:evaluate(samSites)
		if self.enabled == false then
			return
		end
		local hostileUnits = nil
		local hostilePositions = nil
		for i = 1, #samSites do
			local samSite = samSites[i]
			if samSite:isEligibleForLastLineOfDefence() then
				--built at most once per cycle, and not at all when every site is already busy. The
				--positions are read here too: asking each unit again for every site would be one DCS
				--call per site per aircraft, sixty times over on a mission carrying sixty batteries
				if hostileUnits == nil then
					hostileUnits = self:getHostileAirUnits()
					if #hostileUnits == 0 then
						--nothing is flying; reading each site's position would be pure waste
						return
					end
					hostilePositions = {}
					for j = 1, #hostileUnits do
						hostilePositions[j] = hostileUnits[j]:getPosition().p
					end
				end
				local samSitePosition = samSite:getElementPosition()
				if samSitePosition ~= nil then
					local radius = samSite:getLastLineOfDefenceRadius()
					for j = 1, #hostileUnits do
						--2D, the way Skynet measures everything else
						local distance = samSite:getDistanceToUnit(samSitePosition, hostilePositions[j])
						if distance <= radius and self.iads:reportContact(hostileUnits[j], samSite) then
							break
						end
					end
				end
			end
		end
	end
end
