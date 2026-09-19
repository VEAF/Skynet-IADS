do
	SkynetIADS = {}
	SkynetIADS.__index = SkynetIADS

	-- Single source of truth for the shipped artifact's version. Read by
	-- build-tools/build-compiled-script.ps1 and stamped into the banner it writes.
	SkynetIADS.version = "3.5.0"

	SkynetIADS.database = samTypesDB

	function SkynetIADS:create(name)
		local iads = {}
		setmetatable(iads, SkynetIADS)
		iads.radioMenu = nil
		iads.earlyWarningRadars = {}
		iads.samSites = {}
		iads.commandCenters = {}
		iads.ewRadarScanMistTaskID = nil
		iads.coverageRefreshMistTaskID = nil
		iads.coalition = nil
		iads.contacts = {}
		iads.maxTargetAge = 32
		iads.name = name
		iads.harmDetection = SkynetIADSHARMDetection:create(iads)
		iads.logger = SkynetIADSLogger:create(iads)
		if iads.name == nil then
			iads.name = ""
		end
		iads.contactUpdateInterval = 5
		iads.lastLineOfDefenceEnabled = true
		iads.lastLineOfDefenceMinRadius = 10000
		iads.lastLineOfDefenceMaxRadius = 15000
		iads.lastLineOfDefencePersistence = 45
		iads.coverageRefreshInterval = 10
		world.addEventHandler(iads)
		return iads
	end

	-- Last line of defense ------------------------------------------------------------------------
	--
	-- A SAM site held dark by the network has its emission switched off, so it is blind: the only
	-- route back to life is an EW radar that covers it holding the target. Fly under the radar
	-- horizon and no battery reacts, whatever the distance — proximity to the site is an input
	-- nowhere in the cycle, because the only sensor that could measure it is the one that was just
	-- switched off. So a dark site keeps a short virtual detection radius of its own, Skynet's, with
	-- no DCS radar involved.
	--
	-- On by default: off means nobody finds it, and the report comes back in six months.

	function SkynetIADS:setLastLineOfDefence(state)
		if state == true or state == false then
			self.lastLineOfDefenceEnabled = state
		end
		return self
	end

	function SkynetIADS:getLastLineOfDefence()
		return self.lastLineOfDefenceEnabled
	end

	--- Bounds, in metres, of the radius each site draws once for the whole mission.
	function SkynetIADS:setLastLineOfDefenceRadius(minRadius, maxRadius)
		if minRadius and maxRadius and minRadius > 0 and maxRadius >= minRadius then
			self.lastLineOfDefenceMinRadius = minRadius
			self.lastLineOfDefenceMaxRadius = maxRadius
			--sites that already drew a radius have to draw again, from the new bounds
			for i = 1, #self.samSites do
				self.samSites[i]:clearLastLineOfDefenceRadius()
			end
		end
		return self
	end

	--- Answers the minimum and the maximum, in that order.
	function SkynetIADS:getLastLineOfDefenceRadius()
		return self.lastLineOfDefenceMinRadius, self.lastLineOfDefenceMaxRadius
	end

	--- How long a site stays lit after the last contact reported to it, in seconds.
	function SkynetIADS:setLastLineOfDefencePersistence(seconds)
		if seconds and seconds >= 0 then
			self.lastLineOfDefencePersistence = seconds
		end
		return self
	end

	function SkynetIADS:getLastLineOfDefencePersistence()
		return self.lastLineOfDefencePersistence
	end

	--- Wakes a SAM site on a DCS unit, as if something had reported that aircraft to the network.
	--
	-- This is a public entry point of Skynet, and the last line of defense below is its first
	-- caller. It is public because code outside Skynet — VEAF's spotter network — has to be able to
	-- wake a site, and the alternative is that code writing into targetsInRange and its friends on
	-- every cycle.
	--
	-- Unlike SkynetIADSSamSite:informOfContact() it does not require the target to be inside the
	-- firing envelope: a site lights up because something told it the aircraft is there, not because
	-- it can hit it. Requiring the kill zone would mean a Shilka, useful range ~2.5 km, never wakes.
	-- Everything else still holds — the site's own go-live constraints, and goLive()'s guards, so a
	-- site silenced to evade a HARM, out of ammunition, without power or destroyed stays dark.
	--
	-- Answers whether the site is live after the call.
	function SkynetIADS:reportContact(dcsUnit, samSite)
		if dcsUnit == nil or samSite == nil or dcsUnit:isExist() == false then
			return false
		end
		local contact = SkynetIADSContact:create({ object = dcsUnit }, samSite)
		if samSite:areGoLiveConstraintsSatisfied(contact) == false then
			return false
		end
		samSite:goLive()
		if samSite:isActive() == false then
			return false
		end
		samSite:markContactReported()
		return true
	end

	--- Every hostile aircraft and helicopter currently flying.
	--
	-- Enumerated once per cycle and shared by every site: a mission carrying sixty batteries would
	-- otherwise sweep the coalitions sixty times every five seconds. Neutral is not hostile.
	function SkynetIADS:getHostileAirUnits()
		local hostileUnits = {}
		local categories = { Group.Category.AIRPLANE, Group.Category.HELICOPTER }
		for _, coalitionID in pairs(coalition.side) do
			if coalitionID ~= self:getCoalition() and coalitionID ~= coalition.side.NEUTRAL then
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

	--- Is this site one the last line of defense has to look after?
	--
	-- The sites that matter are the ones something is holding in the dark: the network, or their own
	-- autonomous behaviour when it is set to stay dark. A site already triggered by an EW radar this
	-- cycle, one acting as an EW radar, and one the DCS AI is already running are all left alone.
	function SkynetIADS:isSiteEligibleForLastLineOfDefence(samSite)
		if samSite:hasTargetsInRange() or samSite:getActAsEW() then
			return false
		end
		if samSite:getAutonomousState() == false then
			return true
		end
		return samSite:getAutonomousBehaviour() == SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK
	end

	--- Wakes every dark site an enemy aircraft is flying over.
	function SkynetIADS:evaluateLastLineOfDefence(samSites)
		if self.lastLineOfDefenceEnabled == false then
			return
		end
		local hostileUnits = nil
		local hostilePositions = nil
		for i = 1, #samSites do
			local samSite = samSites[i]
			if self:isSiteEligibleForLastLineOfDefence(samSite) then
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
						if distance <= radius and self:reportContact(hostileUnits[j], samSite) then
							break
						end
					end
				end
			end
		end
	end

	function SkynetIADS:onEvent(event)
		if event.id == world.event.S_EVENT_BIRTH then
			env.info("New Object Spawned")
			--	self:addSAMSite(event.initiator:getGroup():getName());
		end
	end

	function SkynetIADS:setUpdateInterval(interval)
		self.contactUpdateInterval = interval
	end

	function SkynetIADS:setCoalition(item)
		if item then
			local coalitionID = item:getCoalition()
			if self.coalitionID == nil then
				self.coalitionID = coalitionID
			end
			if self.coalitionID ~= coalitionID then
				self:printOutputToLog("element: " .. item:getName() .. " has a different coalition than the IADS", true)
			end
		end
	end

	function SkynetIADS:addJammer(jammer)
		table.insert(self.jammers, jammer)
	end

	function SkynetIADS:getCoalition()
		return self.coalitionID
	end

	function SkynetIADS:getDestroyedEarlyWarningRadars()
		local destroyedSites = {}
		for i = 1, #self.earlyWarningRadars do
			local ewSite = self.earlyWarningRadars[i]
			if ewSite:isDestroyed() then
				table.insert(destroyedSites, ewSite)
			end
		end
		return destroyedSites
	end

	function SkynetIADS:getUsableAbstractRadarElemtentsOfTable(abstractRadarTable)
		local usable = {}
		for i = 1, #abstractRadarTable do
			local abstractRadarElement = abstractRadarTable[i]
			if
				abstractRadarElement:hasActiveConnectionNode()
				and abstractRadarElement:hasWorkingPowerSource()
				and abstractRadarElement:isDestroyed() == false
			then
				table.insert(usable, abstractRadarElement)
			end
		end
		return usable
	end

	function SkynetIADS:getUsableEarlyWarningRadars()
		return self:getUsableAbstractRadarElemtentsOfTable(self.earlyWarningRadars)
	end

	function SkynetIADS:createTableDelegator(units)
		local sites = SkynetIADSTableDelegator:create()
		for i = 1, #units do
			local site = units[i]
			table.insert(sites, site)
		end
		return sites
	end

	function SkynetIADS:addEarlyWarningRadarsByPrefix(prefix)
		self:deactivateEarlyWarningRadars()
		self.earlyWarningRadars = {}
		for unitName in pairs(SkynetIADSUtils.getUnitNames()) do
			local pos = self:findSubString(unitName, prefix)
			--the listing can contain StaticObjects, we check to see we only add Units
			local unit = Unit.getByName(unitName)
			if pos and pos == 1 and unit then
				self:addEarlyWarningRadar(unitName)
			end
		end
		self:rebuildRadarCoverageAfterBulkReAdd()
		return self:createTableDelegator(self.earlyWarningRadars)
	end

	function SkynetIADS:addEarlyWarningRadar(earlyWarningRadarUnitName)
		local earlyWarningRadarUnit = Unit.getByName(earlyWarningRadarUnitName)
		if earlyWarningRadarUnit == nil then
			self:printOutputToLog(
				"you have added an EW Radar that does not exist, check name of Unit in Setup and Mission editor: "
					.. earlyWarningRadarUnitName,
				true
			)
			return
		end
		self:setCoalition(earlyWarningRadarUnit)
		local ewRadar = nil
		local category = earlyWarningRadarUnit:getDesc().category
		if category == Unit.Category.AIRPLANE or category == Unit.Category.SHIP then
			ewRadar = SkynetIADSAWACSRadar:create(earlyWarningRadarUnit, self)
		else
			ewRadar = SkynetIADSEWRadar:create(earlyWarningRadarUnit, self)
		end
		ewRadar:setupElements()
		ewRadar:setCachedTargetsMaxAge(self:getCachedTargetsMaxAge())
		-- for performance improvement, if iads is not scanning no update coverage update needs to be done, will be executed once when iads activates
		if self.ewRadarScanMistTaskID ~= nil then
			self:buildRadarCoverageForEarlyWarningRadar(ewRadar)
		end
		ewRadar:setActAsEW(true)
		ewRadar:setToCorrectAutonomousState()
		ewRadar:goLive()
		table.insert(self.earlyWarningRadars, ewRadar)
		if self:getDebugSettings().addedEWRadar then
			self:printOutputToLog("ADDED: " .. ewRadar:getDescription())
		end
		return ewRadar
	end

	function SkynetIADS:getCachedTargetsMaxAge()
		return self.contactUpdateInterval
	end

	function SkynetIADS:getEarlyWarningRadars()
		return self:createTableDelegator(self.earlyWarningRadars)
	end

	function SkynetIADS:getEarlyWarningRadarByUnitName(unitName)
		for i = 1, #self.earlyWarningRadars do
			local ewRadar = self.earlyWarningRadars[i]
			if ewRadar:getDCSName() == unitName then
				return ewRadar
			end
		end
	end

	function SkynetIADS:findSubString(haystack, needle)
		return string.find(haystack, needle, 1, true)
	end

	function SkynetIADS:addSAMSitesByPrefix(prefix)
		self:deativateSAMSites()
		self.samSites = {}
		for groupName in pairs(SkynetIADSUtils.getGroupNames()) do
			local pos = self:findSubString(groupName, prefix)
			if pos and pos == 1 then
				--the listing returns groups, units and, StaticObjects
				local dcsObject = Group.getByName(groupName)
				if dcsObject and dcsObject:getUnits()[1]:isActive() then
					self:addSAMSite(groupName)
				end
			end
		end
		self:rebuildRadarCoverageAfterBulkReAdd()
		return self:createTableDelegator(self.samSites)
	end

	--- Unwires the elements a *ByPrefix call discarded, by rebuilding the whole coverage graph.
	--
	-- Those two functions replace an entire list, and nothing else removes an association: the
	-- per-element rebuild in addSAMSite() / addEarlyWarningRadar() only ever adds, and
	-- refreshRadarCoverage() walks getAbstracRadarElements(), which reads the current lists — a
	-- discarded object is in neither, so it is never visited and stays wired in forever. A discarded
	-- EW radar still passes every test a parent is given (its DCS unit exists, it has power, a
	-- connection node, it acts as EW), so the battery believes it is covered by a radar the IADS no
	-- longer polls, and stays dark under nobody's watch. A discarded SAM site stays a child of its
	-- EW radar and keeps driving the controller of the DCS group the live site also owns.
	--
	-- buildRadarCoverage() is the only code that purges, and it purges all three holders. It is
	-- guarded exactly as the incremental rebuild is: before activate() there is no coverage to
	-- rebuild, and activate() will do it once.
	function SkynetIADS:rebuildRadarCoverageAfterBulkReAdd()
		if self.ewRadarScanMistTaskID ~= nil then
			self:buildRadarCoverage()
		end
	end

	function SkynetIADS:getSAMSitesByPrefix(prefix)
		local returnSams = {}
		for i = 1, #self.samSites do
			local samSite = self.samSites[i]
			local groupName = samSite:getDCSName()
			local pos = self:findSubString(groupName, prefix)
			if pos and pos == 1 then
				table.insert(returnSams, samSite)
			end
		end
		return self:createTableDelegator(returnSams)
	end

	function SkynetIADS:addSAMSite(samSiteName)
		local samSiteDCS = Group.getByName(samSiteName)
		if samSiteDCS == nil then
			self:printOutputToLog(
				"you have added an SAM Site that does not exist, check name of Group in Setup and Mission editor: "
					.. tostring(samSiteName),
				true
			)
			return
		end
		self:setCoalition(samSiteDCS)
		local samSite = SkynetIADSSamSite:create(samSiteDCS, self)
		samSite:setupElements()
		samSite:setCanEngageAirWeapons(true)
		samSite:goLive()
		samSite:setCachedTargetsMaxAge(self:getCachedTargetsMaxAge())
		if samSite:getNatoName() == "UNKNOWN" then
			self:printOutputToLog(
				"you have added an SAM site that Skynet IADS can not handle: " .. samSite:getDCSName(),
				true
			)
			samSite:cleanUp()
		else
			samSite:goDark()
			table.insert(self.samSites, samSite)
			if self:getDebugSettings().addedSAMSite then
				self:printOutputToLog("ADDED: " .. samSite:getDescription())
			end
			-- for performance improvement, if iads is not scanning no update coverage update needs to be done, will be executed once when iads activates
			if self.ewRadarScanMistTaskID ~= nil then
				self:buildRadarCoverageForSAMSite(samSite)
			end
			return samSite
		end
	end

	function SkynetIADS:getUsableSAMSites()
		return self:getUsableAbstractRadarElemtentsOfTable(self.samSites)
	end

	function SkynetIADS:getDestroyedSAMSites()
		local destroyedSites = {}
		for i = 1, #self.samSites do
			local samSite = self.samSites[i]
			if samSite:isDestroyed() then
				table.insert(destroyedSites, samSite)
			end
		end
		return destroyedSites
	end

	function SkynetIADS:getSAMSites()
		return self:createTableDelegator(self.samSites)
	end

	function SkynetIADS:getActiveSAMSites()
		local activeSAMSites = {}
		for i = 1, #self.samSites do
			if self.samSites[i]:isActive() then
				table.insert(activeSAMSites, self.samSites[i])
			end
		end
		return activeSAMSites
	end

	function SkynetIADS:getSAMSiteByGroupName(groupName)
		for i = 1, #self.samSites do
			local samSite = self.samSites[i]
			if samSite:getDCSName() == groupName then
				return samSite
			end
		end
	end

	function SkynetIADS:getSAMSitesByNatoName(natoName)
		local selectedSAMSites = SkynetIADSTableDelegator:create()
		for i = 1, #self.samSites do
			local samSite = self.samSites[i]
			if samSite:getNatoName() == natoName then
				table.insert(selectedSAMSites, samSite)
			end
		end
		return selectedSAMSites
	end

	function SkynetIADS:addCommandCenter(commandCenter)
		self:setCoalition(commandCenter)
		local comCenter = SkynetIADSCommandCenter:create(commandCenter, self)
		table.insert(self.commandCenters, comCenter)
		-- when IADS is active the radars will be added to the new command center. If it not active this will happen when radar coverage is built
		if self.ewRadarScanMistTaskID ~= nil then
			self:addRadarsToCommandCenters()
		end
		return comCenter
	end

	function SkynetIADS:isCommandCenterUsable()
		if #self:getCommandCenters() == 0 then
			return true
		end
		local usableComCenters = self:getUsableAbstractRadarElemtentsOfTable(self:getCommandCenters())
		return (#usableComCenters > 0)
	end

	function SkynetIADS:getCommandCenters()
		return self.commandCenters
	end

	function SkynetIADS.evaluateContacts(self)
		local ewRadars = self:getUsableEarlyWarningRadars()
		local samSites = self:getUsableSAMSites()

		--will add SAM Sites acting as EW Rardars to the ewRadars array:
		for i = 1, #samSites do
			local samSite = samSites[i]
			--We inform SAM sites that a target update is about to happen. If they have no targets in range after the cycle they go dark
			samSite:targetCycleUpdateStart()
			if samSite:getActAsEW() then
				table.insert(ewRadars, samSite)
			end
			--if the sam site is not in ew mode and active we grab the detected targets right here
			if samSite:isActive() and samSite:getActAsEW() == false then
				local contacts = samSite:getDetectedTargets()
				for j = 1, #contacts do
					local contact = contacts[j]
					self:mergeContact(contact)
				end
			end
		end

		local samSitesToTrigger = {}

		for i = 1, #ewRadars do
			local ewRadar = ewRadars[i]
			--call go live in case ewRadar had to shut down (HARM attack)
			ewRadar:goLive()
			-- an element that has moved is picked up by SkynetIADS:refreshRadarCoverage(). It used to
			-- be handled here, for AWACS only, by buildRadarCoverageForEarlyWarningRadar -- which only
			-- ever adds, so an AWACS in transit accumulated every battery it had ever flown near
			local ewContacts = ewRadar:getDetectedTargets()
			if #ewContacts > 0 then
				local samSitesUnderCoverage = ewRadar:getUsableChildRadars()
				for j = 1, #samSitesUnderCoverage do
					local samSiteUnterCoverage = samSitesUnderCoverage[j]
					--we add them to a hash to make sure each SAM site is in the collection only once, reducing the number of loops we conduct later on
					--sites that are already active are included deliberately: targetCycleUpdateStart() has just
					--cleared their targetsInRange flag, so skipping them left it false and targetCycleUpdateEnd()
					--sent them dark again on the very next cycle, with the target still under EW coverage
					samSitesToTrigger[samSiteUnterCoverage:getDCSName()] = samSiteUnterCoverage
				end
				for j = 1, #ewContacts do
					local contact = ewContacts[j]
					self:mergeContact(contact)
				end
			end
		end

		self:cleanAgedTargets()

		for samName, samToTrigger in pairs(samSitesToTrigger) do
			for j = 1, #self.contacts do
				local contact = self.contacts[j]
				-- the DCS Radar only returns enemy aircraft, if that should change a coalition check will be required
				-- currently every type of object in the air is handed of to the SAM site, including missiles
				--local description = contact:getDesc()
				--local category = description.category
				--if category and category ~= Unit.Category.GROUND_UNIT and category ~= Unit.Category.SHIP and category ~= Unit.Category.STRUCTURE then
				--	samToTrigger:informOfContact(contact)
				--end
				--[[
				Above code will not always work, as it assumes the contact is a unit. But actually a contact can be a unit or a weapon.
				Categories returned by description.category will not be the same for a unit or a weapon:
					Unit.Category = { AIRPLANE=0, HELICOPTER=1, GROUND_UNIT=2, SHIP=3, STRUCTURE=4 }
					Weapon.Category = { SHELL=0, MISSILE=1, ROCKET=2, BOMB=3 }

				So as it is, as we consider only the units categories that are not in [2, 3, 4]:
					An airplane or a helicopter will be passed to the sites as designed
					A missile (HARM, JSOW...) will be passed as well but only by chance because its category is equal to AIRPLANE
					A bomb though will not be passed because its category is equal to SHIP

				This has become an issue since the Phalanx has been introduced, as it is a unit capable of engaging incoming bombs.
				As it is now, a Phalanx will be kept off when bombs are inbound.

				Proposed correction consist in correctly considering the contact object category, before looking at its description category.
				I also think it would be better to test for categories to include, rather than categories to exclude, but this is another matter.

				Note 1: we could enhance that by only turning the site on when they can indeed engage the target, like it is done for the HARMs.
				Note 2: maybe the shells and rockets can be engaged by the CRAMs as it is in real life ?

				Modified code follows...
			]]

				local bShouldInform = false
				local objectCategory = contact:getCategory()
				local category = contact:getDesc().category

				if objectCategory == Object.Category.UNIT then
					bShouldInform = category ~= Unit.Category.GROUND_UNIT
						and category ~= Unit.Category.SHIP
						and category ~= Unit.Category.STRUCTURE
				elseif objectCategory == Object.Category.WEAPON then
					bShouldInform = category ~= Weapon.Category.SHELL and category ~= Weapon.Category.ROCKET
				end

				if category and bShouldInform then
					samToTrigger:informOfContact(contact)
				end
			end
		end

		self:evaluateLastLineOfDefence(samSites)

		for i = 1, #samSites do
			local samSite = samSites[i]
			samSite:targetCycleUpdateEnd()
		end

		self.harmDetection:setContacts(self:getContacts())
		self.harmDetection:evaluateContacts()

		self.logger:printSystemStatus()
	end

	function SkynetIADS:cleanAgedTargets()
		local contactsToKeep = {}
		for i = 1, #self.contacts do
			local contact = self.contacts[i]
			if contact:getAge() < self.maxTargetAge then
				table.insert(contactsToKeep, contact)
			end
		end
		self.contacts = contactsToKeep
	end

	--TODO unit test this method:
	function SkynetIADS:getAbstracRadarElements()
		local abstractRadarElements = {}
		local ewRadars = self:getEarlyWarningRadars()
		local samSites = self:getSAMSites()

		for i = 1, #ewRadars do
			local ewRadar = ewRadars[i]
			table.insert(abstractRadarElements, ewRadar)
		end

		for i = 1, #samSites do
			local samSite = samSites[i]
			table.insert(abstractRadarElements, samSite)
		end
		return abstractRadarElements
	end

	function SkynetIADS:addRadarsToCommandCenters()
		--we clear any existing radars that may have been added earlier
		local comCenters = self:getCommandCenters()
		for i = 1, #comCenters do
			local comCenter = comCenters[i]
			comCenter:clearChildRadars()
		end

		-- then we add child radars to the command centers
		local abstractRadarElements = self:getAbstracRadarElements()
		for i = 1, #abstractRadarElements do
			local abstractRadar = abstractRadarElements[i]
			self:addSingleRadarToCommandCenters(abstractRadar)
		end
	end

	function SkynetIADS:addSingleRadarToCommandCenters(abstractRadarElement)
		local comCenters = self:getCommandCenters()
		for i = 1, #comCenters do
			local comCenter = comCenters[i]
			comCenter:addChildRadar(abstractRadarElement)
		end
	end

	-- this method rebuilds the radar coverage of the IADS, a complete rebuild is only required the first time the IADS is activated
	-- during runtime it is sufficient to call buildRadarCoverageForSAMSite or buildRadarCoverageForEarlyWarningRadar method that just updates the IADS for one unit, this saves script execution time
	--
	-- That last sentence is true for an **addition** -- a new SAM site, a new fixed EW radar -- and
	-- false for anything that **moves**: those two only ever add, through
	-- insertToTableIfNotAlreadyAdded, and this is the only function that clears anything. Applying
	-- them to an AWACS in transit is what made it accumulate every battery it had ever flown near.
	-- Movement is refreshRadarCoverage()'s job, and it purges.
	--
	-- It is false for a **removal** too, which is the other half of the same thing: a *ByPrefix call
	-- replaces a whole list, and the elements it drops stay wired in until something clears. So this
	-- runs at runtime as well, from rebuildRadarCoverageAfterBulkReAdd().
	function SkynetIADS:buildRadarCoverage()
		--to build the basic radar coverage we use all SAM sites. Checks if SAM site has power or a connection node is done when using the SAM site later on
		local samSites = self:getSAMSites()

		--first we clear all child and parent radars that may have been added previously
		for i = 1, #samSites do
			local samSite = samSites[i]
			samSite:clearChildRadars()
			samSite:clearParentRadars()
		end

		local ewRadars = self:getEarlyWarningRadars()

		for i = 1, #ewRadars do
			local ewRadar = ewRadars[i]
			ewRadar:clearChildRadars()
		end

		--then we rebuild the radar coverage
		local abstractRadarElements = self:getAbstracRadarElements()
		for i = 1, #abstractRadarElements do
			local abstract = abstractRadarElements[i]
			self:buildRadarCoverageForAbstractRadarElement(abstract)
		end

		self:addRadarsToCommandCenters()

		--we call this once on all sam sites, to make sure autonomous sites go live when IADS activates
		for i = 1, #samSites do
			local samSite = samSites[i]
			samSite:informChildrenOfStateChange()
		end
	end

	function SkynetIADS:buildRadarCoverageForAbstractRadarElement(abstractRadarElement)
		--the reference point the next sweep measures movement against; laying it down only at the
		--first sweep would put it after the element has already moved, so the move would measure zero
		abstractRadarElement:markCoverageUpdated()
		local abstractRadarElements = self:getAbstracRadarElements()
		for i = 1, #abstractRadarElements do
			local aElementToCompare = abstractRadarElements[i]
			if aElementToCompare ~= abstractRadarElement then
				if abstractRadarElement:isInRadarDetectionRangeOf(aElementToCompare) then
					self:buildRadarAssociation(aElementToCompare, abstractRadarElement)
				end
				if aElementToCompare:isInRadarDetectionRangeOf(abstractRadarElement) then
					self:buildRadarAssociation(abstractRadarElement, aElementToCompare)
				end
			end
		end
	end

	function SkynetIADS:buildRadarAssociation(parent, child)
		--chilren should only be SAM sites not EW radars
		if getmetatable(child) == SkynetIADSSamSite then
			parent:addChildRadar(child)
		end
		--Only SAM Sites should have parent Radars, not EW Radars
		if getmetatable(child) == SkynetIADSSamSite then
			child:addParentRadar(parent)
		end
	end

	function SkynetIADS:buildRadarCoverageForSAMSite(samSite)
		self:buildRadarCoverageForAbstractRadarElement(samSite)
		self:addSingleRadarToCommandCenters(samSite)
	end

	function SkynetIADS:buildRadarCoverageForEarlyWarningRadar(ewRadar)
		self:buildRadarCoverageForAbstractRadarElement(ewRadar)
		self:addSingleRadarToCommandCenters(ewRadar)
	end

	-- Coverage refresh ----------------------------------------------------------------------------
	--
	-- Which battery sits under which radar is geometry, and geometry changes when something moves.
	-- Until now it was computed once and treated as if it never changed: buildRadarCoverage() is the
	-- only thing that clears anything, and the incremental rebuild used for a moving AWACS only ever
	-- adds. So an AWACS in transit accumulated every battery it had ever flown near and held them
	-- all non-autonomous from hundreds of kilometres away, and a mobile SAM site — a SA-15, a SA-8,
	-- a Shilka in a convoy — was refreshed by nothing at all.

	function SkynetIADS:setCoverageRefreshInterval(interval)
		if interval and interval >= 0 then
			self.coverageRefreshInterval = interval
			if self.ewRadarScanMistTaskID ~= nil then
				self:scheduleCoverageRefresh()
			end
		end
		return self
	end

	function SkynetIADS:getCoverageRefreshInterval()
		return self.coverageRefreshInterval
	end

	--- (Re)arms the periodic sweep. An interval of 0 stops it.
	function SkynetIADS:scheduleCoverageRefresh()
		SkynetIADSUtils.removeFunction(self.coverageRefreshMistTaskID)
		self.coverageRefreshMistTaskID = nil
		if self.coverageRefreshInterval > 0 then
			self.coverageRefreshMistTaskID = SkynetIADSUtils.scheduleFunction(
				SkynetIADS.refreshRadarCoverage,
				{ self },
				1,
				self.coverageRefreshInterval
			)
		end
	end

	--- Re-evaluates the coverage of every element that has moved since the last sweep.
	--
	-- Only mobile elements are re-evaluated — the geometry between two fixed elements never changes
	-- — which is M x N instead of the N^2 of a full rebuild.
	--
	-- And a site's autonomous state is only touched when the answer has actually changed.
	-- buildRadarCoverage() ends with informChildrenOfStateChange() on every SAM, which for a covered
	-- site means resetAutonomousState() and therefore goDark(). Run periodically as-is, that would
	-- hand an extinction order to the whole network on every sweep — and goDark()'s guards protect a
	-- site that has acquired a track or has missiles in flight, but not one that has just gone live
	-- on designation and not yet locked on (see the fix in 3a94937 for what that looks like in game:
	-- launchers up, slew onto the target, back to travel state, and no shot).
	--
	-- Note this is the *autonomy* that is compared, not the parent list: a site that gains a second
	-- parent while keeping its first has not changed sides, and switching it off over that would be
	-- the very defect above, triggered by nothing more than an AWACS arriving on station.
	function SkynetIADS.refreshRadarCoverage(self)
		local abstractRadarElements = self:getAbstracRadarElements()

		local movedElements = {}
		for i = 1, #abstractRadarElements do
			local abstractRadarElement = abstractRadarElements[i]
			if abstractRadarElement:hasMovedSinceLastCoverageUpdate() then
				table.insert(movedElements, abstractRadarElement)
			end
		end
		if #movedElements == 0 then
			return
		end

		for i = 1, #movedElements do
			local movedElement = movedElements[i]
			for j = 1, #abstractRadarElements do
				local elementToCompare = abstractRadarElements[j]
				if elementToCompare ~= movedElement then
					self:updateRadarAssociation(elementToCompare, movedElement)
					self:updateRadarAssociation(movedElement, elementToCompare)
				end
			end
		end

		local samSites = self:getSAMSites()
		for i = 1, #samSites do
			local samSite = samSites[i]
			--a site is autonomous exactly when no valid parent covers it, so the two disagreeing is
			--what "this site's situation changed" means
			if samSite:hasValidParentRadar() == samSite:getAutonomousState() then
				samSite:setToCorrectAutonomousState()
			end
		end
	end

	--- Adds the association when the child now sits inside the parent's detection range, removes it
	--- when it no longer does. Deliberately quiet: the caller decides who is told about it.
	function SkynetIADS:updateRadarAssociation(parent, child)
		--children should only be SAM sites, not EW radars
		if getmetatable(child) ~= SkynetIADSSamSite then
			return
		end
		if child:isInRadarDetectionRangeOf(parent) then
			parent:addChildRadar(child)
			child:addParentRadarWithoutStateChange(parent)
		else
			parent:removeChildRadar(child)
			child:removeParentRadar(parent)
		end
	end

	function SkynetIADS:mergeContact(contact)
		local existingContact = false
		for i = 1, #self.contacts do
			local iadsContact = self.contacts[i]
			if iadsContact:getName() == contact:getName() then
				iadsContact:refresh()
				--these contacts are used in the logger we set a kown harm state of a contact coming from a SAM site. So the logger will show them als HARMs
				contact:setHARMState(iadsContact:getHARMState())
				local radars = contact:getAbstractRadarElementsDetected()
				for j = 1, #radars do
					local radar = radars[j]
					iadsContact:addAbstractRadarElementDetected(radar)
				end
				existingContact = true
			end
		end
		if existingContact == false then
			table.insert(self.contacts, contact)
		end
	end

	function SkynetIADS:getContacts()
		return self.contacts
	end

	function SkynetIADS:getDebugSettings()
		return self.logger.debugOutput
	end

	function SkynetIADS:printOutput(output, typeWarning)
		self.logger:printOutput(output, typeWarning)
	end

	function SkynetIADS:printOutputToLog(output)
		self.logger:printOutputToLog(output)
	end

	-- will start going through the Early Warning Radars and SAM sites to check what targets they have detected
	function SkynetIADS.activate(self)
		SkynetIADSUtils.removeFunction(self.ewRadarScanMistTaskID)
		self.ewRadarScanMistTaskID =
			SkynetIADSUtils.scheduleFunction(SkynetIADS.evaluateContacts, { self }, 1, self.contactUpdateInterval)
		self:buildRadarCoverage()
		self:scheduleCoverageRefresh()
	end

	function SkynetIADS:setupSAMSitesAndThenActivate(setupTime)
		self:activate()
		self.logger:printOutputToLog(
			"DEPRECATED: setupSAMSitesAndThenActivate, no longer needed since using enableEmission instead of AI on / off allows for the Ground units to setup with their radars turned off"
		)
	end

	function SkynetIADS:deactivate()
		SkynetIADSUtils.removeFunction(self.ewRadarScanMistTaskID)
		SkynetIADSUtils.removeFunction(self.coverageRefreshMistTaskID)
		self.coverageRefreshMistTaskID = nil
		SkynetIADSUtils.removeFunction(self.samSetupMistTaskID)
		self:deativateSAMSites()
		self:deactivateEarlyWarningRadars()
		self:deactivateCommandCenters()
	end

	function SkynetIADS:deactivateCommandCenters()
		for i = 1, #self.commandCenters do
			local comCenter = self.commandCenters[i]
			comCenter:cleanUp()
		end
	end

	function SkynetIADS:deativateSAMSites()
		for i = 1, #self.samSites do
			local samSite = self.samSites[i]
			samSite:cleanUp()
		end
	end

	function SkynetIADS:deactivateEarlyWarningRadars()
		for i = 1, #self.earlyWarningRadars do
			local ewRadar = self.earlyWarningRadars[i]
			ewRadar:cleanUp()
		end
	end

	function SkynetIADS:addRadioMenu()
		self.radioMenu = missionCommands.addSubMenu("SKYNET IADS " .. self:getCoalitionString())
		missionCommands.addCommand(
			"show IADS Status",
			self.radioMenu,
			SkynetIADS.updateDisplay,
			{ self = self, value = true, option = "IADSStatus" }
		)
		missionCommands.addCommand(
			"hide IADS Status",
			self.radioMenu,
			SkynetIADS.updateDisplay,
			{ self = self, value = false, option = "IADSStatus" }
		)
		missionCommands.addCommand(
			"show contacts",
			self.radioMenu,
			SkynetIADS.updateDisplay,
			{ self = self, value = true, option = "contacts" }
		)
		missionCommands.addCommand(
			"hide contacts",
			self.radioMenu,
			SkynetIADS.updateDisplay,
			{ self = self, value = false, option = "contacts" }
		)
	end

	function SkynetIADS:removeRadioMenu()
		missionCommands.removeItem(self.radioMenu)
	end

	function SkynetIADS.updateDisplay(params)
		local option = params.option
		local self = params.self
		local value = params.value
		if option == "IADSStatus" then
			self:getDebugSettings()[option] = value
		elseif option == "contacts" then
			self:getDebugSettings()[option] = value
		end
	end

	function SkynetIADS:getCoalitionString()
		local coalitionStr = "RED"
		if self.coalitionID == coalition.side.BLUE then
			coalitionStr = "BLUE"
		elseif self.coalitionID == coalition.side.NEUTRAL then
			coalitionStr = "NEUTRAL"
		end

		if self.name then
			coalitionStr = "COALITION: " .. coalitionStr .. " | NAME: " .. self.name
		end

		return coalitionStr
	end

	function SkynetIADS:getMooseConnector()
		if self.mooseConnector == nil then
			self.mooseConnector = SkynetMooseA2ADispatcherConnector:create(self)
		end
		return self.mooseConnector
	end

	function SkynetIADS:addMooseSetGroup(mooseSetGroup)
		self:getMooseConnector():addMooseSetGroup(mooseSetGroup)
	end
end
