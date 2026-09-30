do
	SkynetIADSSamSite = {}
	SkynetIADSSamSite = inheritsFrom(SkynetIADSAbstractRadarElement)

	function SkynetIADSSamSite:create(samGroup, iads)
		local sam = self:superClass():create(samGroup, iads)
		setmetatable(sam, self)
		self.__index = self
		sam.targetsInRange = false
		sam.goLiveConstraints = {}
		sam.lastLineOfDefenceRadius = nil
		sam.lastReportedContactTime = nil
		return sam
	end

	--- The radius inside which this site notices an aircraft with no radar of its own, in metres.
	--
	-- Drawn once and kept for the whole mission: redrawn every cycle, an aircraft loitering near the
	-- mean would make the site blink every five seconds, and a pilot could learn the exact distance
	-- from a fixed one. It is drawn on first use rather than at creation so that a mission calling
	-- SkynetIADS:setLastLineOfDefenceRadius() after adding its sites gets the bounds it asked for —
	-- that setter clears what was drawn.
	function SkynetIADSSamSite:getLastLineOfDefenceRadius()
		if self.lastLineOfDefenceRadius == nil then
			local minRadius, maxRadius = self.iads:getLastLineOfDefenceRadius()
			self.lastLineOfDefenceRadius = SkynetIADSUtils.random(minRadius, maxRadius)
		end
		return self.lastLineOfDefenceRadius
	end

	function SkynetIADSSamSite:clearLastLineOfDefenceRadius()
		self.lastLineOfDefenceRadius = nil
	end

	function SkynetIADSSamSite:isEligibleForLastLineOfDefence()
		if self:hasTargetsInRange() or self:getActAsEW() then
			return false
		end
		if self:getAutonomousState() == false then
			return true
		end
		return self:getAutonomousBehaviour() == SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK
	end

	--- Is that report recent enough to keep the site lit?
	--
	-- Without it targetCycleUpdateEnd() sends the site dark five seconds after the aircraft leaves,
	-- so a fast pass lights it for a single cycle and a racetrack makes it blink.
	function SkynetIADSSamSite:hasFreshReportedContact()
		if self.lastReportedContactTime == nil then
			return false
		end
		return (timer.getTime() - self.lastReportedContactTime) < self.iads:getLastLineOfDefencePersistence()
	end

	function SkynetIADSSamSite:hasTargetsInRange()
		return self.targetsInRange
	end

	function SkynetIADSSamSite:addGoLiveConstraint(constraintName, constraint)
		self.goLiveConstraints[constraintName] = constraint
	end

	function SkynetIADSAbstractRadarElement:areGoLiveConstraintsSatisfied(contact)
		for constraintName, constraint in pairs(self.goLiveConstraints) do
			if constraint(contact) ~= true then
				return false
			end
		end
		return true
	end

	function SkynetIADSAbstractRadarElement:removeGoLiveConstraint(constraintName)
		local constraints = {}
		for cName, constraint in pairs(self.goLiveConstraints) do
			if cName ~= constraintName then
				constraints[cName] = constraint
			end
		end
		self.goLiveConstraints = constraints
	end

	function SkynetIADSAbstractRadarElement:getGoLiveConstraints()
		return self.goLiveConstraints
	end

	function SkynetIADSSamSite:isDestroyed()
		local isDestroyed = true
		for i = 1, #self.launchers do
			local launcher = self.launchers[i]
			if launcher:isExist() == true then
				isDestroyed = false
			end
		end
		local radars = self:getRadars()
		for i = 1, #radars do
			local radar = radars[i]
			if radar:isExist() == true then
				isDestroyed = false
			end
		end
		return isDestroyed
	end

	function SkynetIADSSamSite:targetCycleUpdateStart()
		self.targetsInRange = false
	end

	function SkynetIADSSamSite:targetCycleUpdateEnd()
		if self.targetsInRange == true or self.actAsEW == true or self:hasFreshReportedContact() then
			return
		end
		-- an autonomous site in DCS AI mode stays live
		if
			self:getAutonomousState() == true
			and self:getAutonomousBehaviour() == SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DCS_AI
		then
			return
		end
		self:goDark()
	end

	function SkynetIADSSamSite:informOfContact(contact)
		-- we make sure isTargetInRange (expensive call) is only triggered if no previous calls to this method resulted in targets in range
		if
			self.targetsInRange == false
			and self:areGoLiveConstraintsSatisfied(contact) == true
			and self:isTargetInRange(contact)
			and (
				contact:isIdentifiedAsHARM() == false
				or (contact:isIdentifiedAsHARM() == true and self:getCanEngageHARM() == true)
			)
		then
			self:goLive()
			self.targetsInRange = true
		end
	end

	--- A contact reported to this site rather than detected by a radar; see SkynetIADS:reportContact.
	--
	-- Unlike informOfContact() it does not require the target to be inside the firing envelope: a
	-- site goes live because it was told the aircraft is there, not because it can hit it. Requiring
	-- the kill zone would mean a Shilka, useful range ~2.5 km, never wakes. The go-live constraints
	-- and goLive()'s guards still hold, so a site silenced to evade a HARM, out of ammunition, without
	-- power or destroyed stays dark.
	--
	-- Answers whether the site is live after the call.
	function SkynetIADSSamSite:informOfReportedContact(contact)
		if self:areGoLiveConstraintsSatisfied(contact) == false then
			return false
		end
		self:goLive()
		if self:isActive() == false then
			return false
		end
		self.lastReportedContactTime = timer.getTime()
		return true
	end
end
