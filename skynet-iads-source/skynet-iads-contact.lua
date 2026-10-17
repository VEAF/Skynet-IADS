do
	SkynetIADSContact = {}
	SkynetIADSContact = inheritsFrom(SkynetIADSAbstractDCSObjectWrapper)

	SkynetIADSContact.CLIMB = "CLIMB"
	SkynetIADSContact.DESCEND = "DESCEND"

	SkynetIADSContact.HARM = "HARM"
	SkynetIADSContact.NOT_HARM = "NOT_HARM"
	SkynetIADSContact.HARM_UNKNOWN = "HARM_UNKNOWN"

	-- what a contact is, for deciding whether a site wakes for it; see getTargetClass()
	SkynetIADSContact.CLASS_AIRCRAFT = "aircraft"
	SkynetIADSContact.CLASS_ARM = "arm"
	SkynetIADSContact.CLASS_MISSILE = "missile"
	SkynetIADSContact.CLASS_BOMB = "bomb"

	function SkynetIADSContact:create(dcsRadarTarget, abstractRadarElementDetected)
		local instance = self:superClass():create(dcsRadarTarget.object)
		setmetatable(instance, self)
		self.__index = self
		instance.abstractRadarElementsDetected = {}
		table.insert(instance.abstractRadarElementsDetected, abstractRadarElementDetected)
		instance.firstContactTime = timer.getAbsTime()
		instance.lastTimeSeen = 0
		instance.dcsRadarTarget = dcsRadarTarget
		instance.position = instance:getDCSRepresentation():getPosition()
		instance.numOfTimesRefreshed = 0
		instance.speed = 0
		instance.harmState = SkynetIADSContact.HARM_UNKNOWN
		instance.simpleAltitudeProfile = {}
		instance.targetClass = instance:readTargetClass()
		return instance
	end

	-- the class depends only on the DCS object's type, so it is read once
	function SkynetIADSContact:readTargetClass()
		local objectCategory = self:getCategory()
		local desc = self:getDesc()
		if objectCategory == Object.Category.UNIT then
			if desc.category == Unit.Category.AIRPLANE or desc.category == Unit.Category.HELICOPTER then
				return SkynetIADSContact.CLASS_AIRCRAFT
			end
		elseif objectCategory == Object.Category.WEAPON then
			if desc.category == Weapon.Category.BOMB then
				return SkynetIADSContact.CLASS_BOMB
			elseif desc.category == Weapon.Category.MISSILE then
				if
					desc.missileCategory == Weapon.MissileCategory.AAM
					or desc.missileCategory == Weapon.MissileCategory.SAM
				then
					return nil
				elseif desc.guidance == Weapon.GuidanceType.RADAR_PASSIVE then
					return SkynetIADSContact.CLASS_ARM
				end
				return SkynetIADSContact.CLASS_MISSILE
			end
		end
		return nil
	end

	--- One of the CLASS_ constants, or nil for a contact no site wakes for: a ground unit, a ship, a
	-- structure, a shell, a rocket, a torpedo, an air-to-air or a surface-to-air missile.
	function SkynetIADSContact:getTargetClass()
		return self.targetClass
	end

	function SkynetIADSContact:setHARMState(state)
		self.harmState = state
	end

	function SkynetIADSContact:getHARMState()
		return self.harmState
	end

	function SkynetIADSContact:isIdentifiedAsHARM()
		return self.harmState == SkynetIADSContact.HARM
	end

	function SkynetIADSContact:isHARMStateUnknown()
		return self.harmState == SkynetIADSContact.HARM_UNKNOWN
	end

	function SkynetIADSContact:getMagneticHeading()
		if self:isExist() then
			return SkynetIADSUtils.round(
				SkynetIADSUtils.toDegree(SkynetIADSUtils.getHeading(self:getDCSRepresentation()))
			)
		else
			return -1
		end
	end

	function SkynetIADSContact:getAbstractRadarElementsDetected()
		return self.abstractRadarElementsDetected
	end

	function SkynetIADSContact:addAbstractRadarElementDetected(radar)
		self:insertToTableIfNotAlreadyAdded(self.abstractRadarElementsDetected, radar)
	end

	function SkynetIADSContact:isTypeKnown()
		return self.dcsRadarTarget.type
	end

	function SkynetIADSContact:isDistanceKnown()
		return self.dcsRadarTarget.distance
	end

	function SkynetIADSContact:getTypeName()
		if self:isIdentifiedAsHARM() then
			return SkynetIADSContact.HARM
		end

		-- a contact can be a unit or a weapon (missile, bomb, rocket, shell); in both cases self.typeName holds the DCS type name
		local category = self:getCategory()
		if category == Object.Category.UNIT or category == Object.Category.WEAPON then
			return self.typeName
		end
		return "UNKNOWN"
	end

	function SkynetIADSContact:getCategory()
		-- Note: we don't use self:getDCSRepresentation():getCategory()
		-- because it will fail with an error if self:getDCSRepresentation() is not nil but the unit is destroyed.
		-- Using the static Object.getCategory instead gets us nil in that case, and we only call it once there is a representation to pass it.
		if self:getDCSRepresentation() ~= nil then
			return Object.getCategory(self:getDCSRepresentation())
		end
		return nil
	end

	function SkynetIADSContact:getPosition()
		return self.position
	end

	function SkynetIADSContact:getGroundSpeedInKnots(decimals)
		if decimals == nil then
			decimals = 2
		end
		return SkynetIADSUtils.round(self.speed, decimals)
	end

	function SkynetIADSContact:getHeightInFeetMSL()
		if self:isExist() then
			return SkynetIADSUtils.round(SkynetIADSUtils.metersToFeet(self:getDCSRepresentation():getPosition().p.y), 0)
		else
			return 0
		end
	end

	function SkynetIADSContact:getDesc()
		if self:isExist() then
			return self:getDCSRepresentation():getDesc()
		else
			return {}
		end
	end

	function SkynetIADSContact:getNumberOfTimesHitByRadar()
		return self.numOfTimesRefreshed
	end

	function SkynetIADSContact:refresh()
		if self:isExist() then
			local timeDelta = (timer.getAbsTime() - self.lastTimeSeen)
			if timeDelta > 0 then
				self.numOfTimesRefreshed = self.numOfTimesRefreshed + 1
				local distance = SkynetIADSUtils.metersToNM(
					SkynetIADSUtils.get2DDist(self.position.p, self:getDCSRepresentation():getPosition().p)
				)
				local hours = timeDelta / 3600
				self.speed = (distance / hours)
				self:updateSimpleAltitudeProfile()
				self.position = self:getDCSRepresentation():getPosition()
			end
		end
		self.lastTimeSeen = timer.getAbsTime()
	end

	function SkynetIADSContact:updateSimpleAltitudeProfile()
		local currentAltitude = self:getDCSRepresentation():getPosition().p.y

		local previousPath = ""
		if #self.simpleAltitudeProfile > 0 then
			previousPath = self.simpleAltitudeProfile[#self.simpleAltitudeProfile]
		end

		if self.position.p.y > currentAltitude and previousPath ~= SkynetIADSContact.DESCEND then
			table.insert(self.simpleAltitudeProfile, SkynetIADSContact.DESCEND)
		elseif self.position.p.y < currentAltitude and previousPath ~= SkynetIADSContact.CLIMB then
			table.insert(self.simpleAltitudeProfile, SkynetIADSContact.CLIMB)
		end
	end

	function SkynetIADSContact:getSimpleAltitudeProfile()
		return self.simpleAltitudeProfile
	end

	function SkynetIADSContact:getAge()
		return SkynetIADSUtils.round(timer.getAbsTime() - self.lastTimeSeen)
	end
end
