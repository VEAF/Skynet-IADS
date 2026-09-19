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

	--- Records that something reported a contact to this site; see SkynetIADS:reportContact.
	function SkynetIADSSamSite:markContactReported()
		self.lastReportedContactTime = timer.getTime()
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
		if
			self:getAutonomousState() == false
			and self:getAutonomousBehaviour() == SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DCS_AI
		then
			self:goDark()
		end
		-- A site the network does not hold, and whose autonomous behaviour is to stay dark, is never
		-- lit by anything but a reported contact -- the branch above deliberately leaves it alone. So
		-- nothing else would ever switch it back off, and the last line of defense would light it for
		-- the rest of the mission. Only a site that was actually woken that way is touched here.
		if
			self.lastReportedContactTime ~= nil
			and self:getAutonomousState() == true
			and self:getAutonomousBehaviour() == SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK
		then
			self:goDark()
		end
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
end
