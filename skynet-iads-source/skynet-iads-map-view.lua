do
	-- The map view: draws one Skynet network on the F10 map, and keeps the drawing current.
	--
	-- Legend (each shape carries its DCS name):
	--   EW radar (or a SAM site acting as EW)   square          blue: live, grey: dark, black: defending HARM
	--   SAM site                                triangle        red: live, grey: dark, black: defending HARM, outline orange: autonomous
	--   point defence                           small triangle, pointing down: purple while point defending
	--   command center                          rectangle       green: powered, orange: unpowered, red: destroyed
	--   command center power source             small square    green: alive, red: destroyed
	--   destroyed element                       dashed outline, at its last known position
	--   range circle                            for live SAM site, red circle: Skynet go-live range
	--   coverage (EW radar -> SAM site)         solid blue line
	--   point defence -> protected site         dashed grey line, solid purple while defending against a HARM
	--   command center -> power source          dashed green line
	--
	-- Vocabulary:
	--   element      a Skynet element: an EW radar, a SAM site (point defences included), a command center, a power source
	--   relation     a line between two elements: coverage, point defence, power
	--   anchor       an element whose position an item's drawing depends on
	--   mark         one DCS F10 map drawing, known by its id
	--   item         what the view draws, erases and redraws as a whole, with its own marks: a radar element
	--                (its shape, label and range circle), a command center, a power source, or a relation.
	--                The view lists the items it should draw afresh at every tick
	--   drawn item   the record of an item that is on the map: its marks, and the state and anchor positions
	--                it was drawn with. Kept from one tick to the next, under the item's key
	--
	-- A tick compares the two: an item whose state changed or whose anchors moved is erased and drawn
	-- again, an item listed and not drawn is drawn, a drawn item no longer listed is erased.

	SkynetIADSMapView = {}

	---------------------------------------------------------------------------------------------------
	--- Global parameters
	SkynetIADSMapView.logPrefix = "SKYNET MAP VIEW: "
	SkynetIADSMapView.refreshPeriod = 1 -- seconds between two ticks
	SkynetIADSMapView.firstMarkId = 7300000 -- DCS allocates no mark ids: every script picks its own. A mission can change this if it collides with its own
	SkynetIADSMapView.lastMarkId = nil -- nil until the first mark; one counter for every network, so two never share an id
	SkynetIADSMapView.groundMoveThreshold = 2000 -- metres a ground element moves before what is drawn for it is redrawn
	SkynetIADSMapView.airMoveThreshold = 10000 -- metres an airborne element moves before what is drawn for it is redrawn

	---------------------------------------------------------------------------------------------------
	--- Enums
	--- What a map can draw. Every layer is shown by default.
	SkynetIADSMapView.layers = {
		elements = "elements", -- the shapes: radars, SAM sites, command centers, power sources, and power lines
		coverage = "coverage", -- coverage lines, EW radar -> SAM site
		pointDefence = "pointDefence", -- point defence lines
		rangeCircles = "rangeCircles", -- go-live range of live SAM sites
		labels = "labels", -- names under the shapes
	}

	SkynetIADSMapView.relationKinds = {
		coverage = "coverage", -- EW radar -> SAM site it covers
		pointDefence = "pointDefence", -- point defence -> site it protects
		pointDefending = "pointDefending", -- the same, while the point defence is held live against a HARM
		power = "power", -- command center -> power source
	}

	SkynetIADSMapView.shapes = {
		square = "square",
		triangle = "triangle",
		invertedTriangle = "invertedTriangle",
	}

	SkynetIADSMapView.lineTypes = { solid = 1, dashed = 2 } -- DCS line types
	SkynetIADSMapView.freeformPolygon = 7 -- DCS markupToAll's shape id
	SkynetIADSMapView.allCoalitions = -1 -- DCS mark coalition seen by everyone

	---------------------------------------------------------------------------------------------------
	--- Drawing parameters (sizes in meters)
	SkynetIADSMapView.fillAlpha = 0.35
	SkynetIADSMapView.colours = {
		red = { 1, 0, 0 },
		grey = { 0.5, 0.5, 0.5 },
		blue = { 0, 0.45, 1 },
		orange = { 1, 0.55, 0 },
		purple = { 0.65, 0.2, 0.85 },
		green = { 0, 0.75, 0 },
		black = { 0, 0, 0 },
	}
	SkynetIADSMapView.sizes = {
		ew = 700, -- square half-side
		sam = 800, -- triangle circumradius
		pointDefence = 500, -- inverted triangle circumradius, so it stands apart from the site it protects
		commandCenterHalfWidth = 800,
		commandCenterHalfHeight = 400,
		powerSource = 350, -- square half-side
	}
	SkynetIADSMapView.lineMargin = 200 -- between a line's end and the shape it points at
	SkynetIADSMapView.labelOffset = 300 -- between a shape and its label, south of it
	SkynetIADSMapView.labelFontSizes = { large = 13, small = 10 }

	-- how each kind of relation is drawn
	SkynetIADSMapView.relationStyles = {
		[SkynetIADSMapView.relationKinds.coverage] = { colour = SkynetIADSMapView.colours.blue, dashed = false },
		[SkynetIADSMapView.relationKinds.pointDefence] = { colour = SkynetIADSMapView.colours.grey, dashed = true },
		[SkynetIADSMapView.relationKinds.pointDefending] = { colour = SkynetIADSMapView.colours.purple, dashed = false },
		[SkynetIADSMapView.relationKinds.power] = { colour = SkynetIADSMapView.colours.green, dashed = true },
	}

	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------
	---  SkynetIADSMapViewSettings class
	---  What a map view draws, and for whom. Read at every tick; changing it changes nothing on the map
	---  until the view's next update.
	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------
	SkynetIADSMapViewSettings = {}

	---------------------------------------------------------------------------------------------------
	---  CTOR
	function SkynetIADSMapViewSettings:create()
		local this = {
			layers = {}, -- set of SkynetIADSMapView.layers: layer -> true when shown
			targetCoalition = nil, -- the coalition that sees the drawing, nil for every coalition
		}
		for _, layer in pairs(SkynetIADSMapView.layers) do
			this.layers[layer] = true
		end

		setmetatable(this, self)
		self.__index = self

		return this
	end

	function SkynetIADSMapViewSettings:hasLayer(layer)
		return self.layers[layer] == true
	end

	function SkynetIADSMapViewSettings:setLayer(layer, shown)
		self.layers[layer] = shown == true or nil
	end

	function SkynetIADSMapViewSettings:toggleLayer(layer)
		self:setLayer(layer, not self:hasLayer(layer))
	end

	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------
	---  Item classes
	---  Every item has the same interface:
	---    view                the map view that listed it
	---    key                 what the item is filed under, the same from one tick to the next: the
	---                        element itself, or a string for a relation
	---    name                what a log calls it
	---    anchorElements      the elements whose position the drawing depends on
	---    getState()          everything the drawing depends on but the anchors' positions, as a string:
	---                        two equal states draw the same marks
	---    draw(drawn)         draws the item's marks, filed in `drawn`
	---  Items are thrown away at the end of the tick that listed them.
	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------

	---------------------------------------------------------------------------------------------------
	--- SkynetIADSMapViewRadarItem: an EW radar or a SAM site, with its label and range circle
	SkynetIADSMapViewRadarItem = {}

	function SkynetIADSMapViewRadarItem:create(view, element, isEwRadar)
		local this = {
			view = view,
			key = element,
			name = view:nameOf(element),
			anchorElements = { element },
			element = element,
			isEwRadar = isEwRadar,
		}

		setmetatable(this, self)
		self.__index = self

		return this
	end

	--- The range circle drawn around the element, in metres: 0 for an EW radar, a dark or a destroyed
	--- site, or when the range circles are left out.
	function SkynetIADSMapViewRadarItem:getDrawnRange()
		if
			self.isEwRadar
			or not self.view.settings:hasLayer(SkynetIADSMapView.layers.rangeCircles)
			or not self.element:isActive()
			or self.element:isDestroyed()
		then
			return 0
		end
		return SkynetIADSMapView.goLiveRange(self.element)
	end

	function SkynetIADSMapViewRadarItem:getState()
		local settings = self.view.settings
		return table.concat({
			SkynetIADSMapView.styleState(SkynetIADSMapView.radarElementStyle(self.element, self.isEwRadar)),
			self:getDrawnRange(),
			self.view:nameOf(self.element),
			tostring(settings:hasLayer(SkynetIADSMapView.layers.elements)),
			tostring(settings:hasLayer(SkynetIADSMapView.layers.labels)),
		}, "|")
	end

	function SkynetIADSMapViewRadarItem:draw(drawn)
		local position = self.view:positionOf(self.element)
		if not position then
			return
		end
		local layers = SkynetIADSMapView.layers
		local style = SkynetIADSMapView.radarElementStyle(self.element, self.isEwRadar)
		local range = self:getDrawnRange()
		if range > 0 then
			SkynetIADSMapView.drawCircle(drawn, position, range, SkynetIADSMapView.colours.red)
		end
		if self.view.settings:hasLayer(layers.elements) then
			SkynetIADSMapView.drawShape(drawn, position, style)
			if self.view.settings:hasLayer(layers.labels) then
				local fontSizes = SkynetIADSMapView.labelFontSizes
				local fontSize = style.shape == SkynetIADSMapView.shapes.invertedTriangle and fontSizes.small
					or fontSizes.large
				local name = self.view:nameOf(self.element)
				SkynetIADSMapView.drawLabel(drawn, position, style.size, style.outline, name, fontSize)
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	--- SkynetIADSMapViewCommandCenterItem: a command center, with its label
	SkynetIADSMapViewCommandCenterItem = {}

	function SkynetIADSMapViewCommandCenterItem:create(view, commandCenter)
		local this = {
			view = view,
			key = commandCenter,
			name = view:nameOf(commandCenter),
			anchorElements = { commandCenter },
			element = commandCenter,
		}

		setmetatable(this, self)
		self.__index = self

		return this
	end

	function SkynetIADSMapViewCommandCenterItem:getState()
		return table.concat({
			SkynetIADSMapView.styleState(SkynetIADSMapView.commandCenterStyle(self.element)),
			self.view:nameOf(self.element),
			tostring(self.view.settings:hasLayer(SkynetIADSMapView.layers.labels)),
		}, "|")
	end

	function SkynetIADSMapViewCommandCenterItem:draw(drawn)
		local position = self.view:positionOf(self.element)
		if not position then
			return
		end
		local sizes = SkynetIADSMapView.sizes
		local style = SkynetIADSMapView.commandCenterStyle(self.element)
		SkynetIADSMapView.drawRectangle(
			drawn,
			position,
			sizes.commandCenterHalfWidth,
			sizes.commandCenterHalfHeight,
			style
		)
		if self.view.settings:hasLayer(SkynetIADSMapView.layers.labels) then
			local name = self.view:nameOf(self.element)
			local fontSize = SkynetIADSMapView.labelFontSizes.large
			SkynetIADSMapView.drawLabel(drawn, position, sizes.commandCenterHalfHeight, style.outline, name, fontSize)
		end
	end

	---------------------------------------------------------------------------------------------------
	--- SkynetIADSMapViewPowerSourceItem: a command center's power source, with its label
	SkynetIADSMapViewPowerSourceItem = {}

	function SkynetIADSMapViewPowerSourceItem:create(view, powerSource)
		local this = {
			view = view,
			key = powerSource,
			name = view:nameOf(powerSource),
			anchorElements = { powerSource },
			powerSource = powerSource,
		}

		setmetatable(this, self)
		self.__index = self

		return this
	end

	function SkynetIADSMapViewPowerSourceItem:getState()
		return table.concat({
			tostring(SkynetIADSMapView.powerSourceIsAlive(self.powerSource)),
			self.view:nameOf(self.powerSource),
			tostring(self.view.settings:hasLayer(SkynetIADSMapView.layers.labels)),
		}, "|")
	end

	function SkynetIADSMapViewPowerSourceItem:draw(drawn)
		local position = self.view:positionOf(self.powerSource)
		if not position then
			return
		end
		local colours = SkynetIADSMapView.colours
		local alive = SkynetIADSMapView.powerSourceIsAlive(self.powerSource)
		local colour = alive and colours.green or colours.red
		local style = { fill = colour, outline = colour, dashed = not alive }
		local size = SkynetIADSMapView.sizes.powerSource
		SkynetIADSMapView.drawRectangle(drawn, position, size, size, style)
		if self.view.settings:hasLayer(SkynetIADSMapView.layers.labels) then
			SkynetIADSMapView.drawLabel(drawn, position, size, colour, self.view:nameOf(self.powerSource))
		end
	end

	---------------------------------------------------------------------------------------------------
	--- SkynetIADSMapViewRelationItem: a line from one element to another
	SkynetIADSMapViewRelationItem = {}

	--- `kind` is one of SkynetIADSMapView.relationKinds.
	function SkynetIADSMapViewRelationItem:create(view, kind, from, to)
		local key = kind .. ":" .. view:nameOf(from) .. ">" .. view:nameOf(to)
		local this = {
			view = view,
			key = key,
			name = key,
			anchorElements = { from, to },
			kind = kind,
			from = from,
			to = to,
		}

		setmetatable(this, self)
		self.__index = self

		return this
	end

	--- A relation's look depends only on its kind, which is in its key, and on where its ends are.
	function SkynetIADSMapViewRelationItem:getState()
		return self.kind
	end

	--- The line, each end pulled back off the shape it touches; nothing when the two shapes overlap.
	function SkynetIADSMapViewRelationItem:draw(drawn)
		local from = self.view:positionOf(self.from)
		local to = self.view:positionOf(self.to)
		if not from or not to then
			return
		end
		local dx, dz = to.x - from.x, to.z - from.z
		local length = math.sqrt(dx * dx + dz * dz)
		local fromGap = SkynetIADSMapView.footprintOf(self.from) + SkynetIADSMapView.lineMargin
		local toGap = SkynetIADSMapView.footprintOf(self.to) + SkynetIADSMapView.lineMargin
		if length <= fromGap + toGap then
			return
		end
		local ux, uz = dx / length, dz / length
		local style = SkynetIADSMapView.relationStyles[self.kind]
		SkynetIADSMapView.drawLine(
			drawn,
			{ x = from.x + ux * fromGap, y = from.y, z = from.z + uz * fromGap },
			{ x = to.x - ux * toGap, y = to.y, z = to.z - uz * toGap },
			style.colour,
			style.dashed
		)
	end

	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------
	---  SkynetIADSMapViewDrawnItem class
	---  The record of an item on the map: its marks, and what it was drawn with.
	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------
	SkynetIADSMapViewDrawnItem = {}

	---------------------------------------------------------------------------------------------------
	---  CTOR
	function SkynetIADSMapViewDrawnItem:create(view, item, state)
		local this = {
			state = state, -- the item's state when drawn
			anchorElements = item.anchorElements,
			anchorPositions = {}, -- anchorPositions[i]: where anchorElements[i] was when drawn, nil if unknown
			coalition = view.drawnCoalition, -- the coalition its marks are drawn for
			markIds = {},
		}
		for i, anchor in ipairs(item.anchorElements) do
			this.anchorPositions[i] = view:positionOf(anchor)
		end

		setmetatable(this, self)
		self.__index = self

		return this
	end

	--- A new mark id, filed in this drawn item so it can be erased alone.
	function SkynetIADSMapViewDrawnItem:newMarkId()
		SkynetIADSMapView.lastMarkId = (SkynetIADSMapView.lastMarkId or (SkynetIADSMapView.firstMarkId - 1)) + 1
		table.insert(self.markIds, SkynetIADSMapView.lastMarkId)
		return SkynetIADSMapView.lastMarkId
	end

	function SkynetIADSMapViewDrawnItem:erase()
		for _, id in ipairs(self.markIds) do
			pcall(trigger.action.removeMark, id)
		end
		self.markIds = {}
	end

	--- Has any anchor moved past its threshold, or appeared, or gone, since it was drawn?
	function SkynetIADSMapViewDrawnItem:hasMoved(view)
		for i, anchor in ipairs(self.anchorElements) do
			local now, before = view:positionOf(anchor), self.anchorPositions[i]
			if (now == nil) ~= (before == nil) then
				return true
			end
			if now then
				local dx, dz = now.x - before.x, now.z - before.z
				local threshold = SkynetIADSMapView.moveThresholdOf(anchor)
				if dx * dx + dz * dz > threshold * threshold then
					return true
				end
			end
		end
		return false
	end

	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------
	---  SkynetIADSMapView class
	---  One per network, made at its first use by SkynetIADS:getMapView().
	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------

	---------------------------------------------------------------------------------------------------
	---  CTOR
	function SkynetIADSMapView:create(iads)
		local this = {
			iads = iads,
			settings = SkynetIADSMapViewSettings:create(),
			taskId = nil, -- the timer's, while shown
			drawnItems = {}, -- item key -> SkynetIADSMapViewDrawnItem
			drawnCoalition = nil, -- the coalition the marks on the map are drawn for, nil when nothing is drawn
			lastKnown = {}, -- element -> { position =, name = }, what it last answered, for once it is gone
		}

		setmetatable(this, self)
		self.__index = self

		return this
	end

	---------------------------------------------------------------------------------------------------
	--- Showing and hiding

	--- Starts the timer that keeps the drawing current, from the next tick.
	function SkynetIADSMapView:show()
		if self.taskId == nil then
			local period = SkynetIADSMapView.refreshPeriod
			self.taskId =
				SkynetIADSUtils.scheduleFunction(SkynetIADSMapView.update, { self }, timer.getTime() + period, period)
		end
	end

	--- Stops the timer and erases the drawing.
	function SkynetIADSMapView:hide()
		SkynetIADSUtils.removeFunction(self.taskId)
		self.taskId = nil
		self:erase()
	end

	function SkynetIADSMapView:isShown()
		return self.taskId ~= nil
	end

	--- Switches a layer in the settings, and brings the drawing up to date at once when shown.
	function SkynetIADSMapView:toggleLayer(layer)
		self.settings:toggleLayer(layer)
		if self:isShown() then
			self:update()
		end
	end

	---------------------------------------------------------------------------------------------------
	--- Update

	--- What the timer runs: bring the drawing up to date, by redrawing the items that changed and erasing
	--- the ones that are gone. A change of coalition redraws everything, since each mark carries it.
	function SkynetIADSMapView:update()
		local targetCoalition = self.settings.targetCoalition or SkynetIADSMapView.allCoalitions
		if self.drawnCoalition ~= targetCoalition then
			self:erase()
			self.drawnCoalition = targetCoalition
		end
		local listed = {}
		for _, item in ipairs(self:listItems()) do
			listed[item.key] = true
			local ok, err = pcall(self.updateItem, self, item)
			if not ok then
				env.warning(
					SkynetIADSMapView.logPrefix .. string.format("drawing %s failed: %s", item.name, tostring(err))
				)
			end
		end
		for key, drawn in pairs(self.drawnItems) do
			if not listed[key] then
				drawn:erase()
				self.drawnItems[key] = nil
			end
		end
	end

	--- Draw one item again if its state changed or it moved; leave its marks alone otherwise.
	function SkynetIADSMapView:updateItem(item)
		local state = item:getState()
		local drawn = self.drawnItems[item.key]
		if drawn and drawn.state == state and not drawn:hasMoved(self) then
			return
		end
		if drawn then
			drawn:erase()
		end
		-- filed before drawing, so marks drawn by a draw that fails half way are still erased later
		drawn = SkynetIADSMapViewDrawnItem:create(self, item, state)
		self.drawnItems[item.key] = drawn
		item:draw(drawn)
	end

	--- Erases every mark of this view.
	function SkynetIADSMapView:erase()
		for _, drawn in pairs(self.drawnItems) do
			drawn:erase()
		end
		self.drawnItems = {}
		self.drawnCoalition = nil
	end

	---------------------------------------------------------------------------------------------------
	--- Items: what the network holds, and what the settings let through

	--- Every item the view should draw now.
	function SkynetIADSMapView:listItems()
		local items = {}
		local layers = SkynetIADSMapView.layers
		local settings = self.settings
		local iads = self.iads
		local samSites = iads:getSAMSites() or {}
		local withElements = settings:hasLayer(layers.elements)

		if withElements or settings:hasLayer(layers.rangeCircles) then
			for _, ew in ipairs(iads:getEarlyWarningRadars() or {}) do
				table.insert(items, SkynetIADSMapViewRadarItem:create(self, ew, true))
			end
			-- point defences are SAM sites too
			for _, sam in ipairs(samSites) do
				table.insert(items, SkynetIADSMapViewRadarItem:create(self, sam, false))
			end
		end

		local kinds = SkynetIADSMapView.relationKinds
		if withElements then
			for _, commandCenter in ipairs(iads:getCommandCenters() or {}) do
				table.insert(items, SkynetIADSMapViewCommandCenterItem:create(self, commandCenter))
				for _, powerSource in ipairs(commandCenter:getPowerSources() or {}) do
					table.insert(items, SkynetIADSMapViewPowerSourceItem:create(self, powerSource))
					table.insert(
						items,
						SkynetIADSMapViewRelationItem:create(self, kinds.power, commandCenter, powerSource)
					)
				end
			end
		end

		if settings:hasLayer(layers.coverage) then
			for _, sam in ipairs(samSites) do
				for _, parent in ipairs(SkynetIADSMapView.coveringParentsOf(sam)) do
					table.insert(items, SkynetIADSMapViewRelationItem:create(self, kinds.coverage, parent, sam))
				end
			end
		end

		if settings:hasLayer(layers.pointDefence) then
			for _, list in ipairs({ iads:getEarlyWarningRadars() or {}, samSites }) do
				for _, protected in ipairs(list) do
					for _, pointDefence in ipairs(protected:getPointDefences() or {}) do
						local kind = pointDefence:getIsPointDefending() and kinds.pointDefending or kinds.pointDefence
						table.insert(items, SkynetIADSMapViewRelationItem:create(self, kind, pointDefence, protected))
					end
				end
			end
		end

		return items
	end

	---------------------------------------------------------------------------------------------------
	--- Elements

	function SkynetIADSMapView:lastKnownOf(element)
		local known = self.lastKnown[element]
		if known == nil then
			known = {}
			self.lastKnown[element] = known
		end
		return known
	end

	--- Where an element is; the last known position once it is gone, nil if it never answered.
	function SkynetIADSMapView:positionOf(element)
		local ok, position
		if element.getElementPosition then
			ok, position = pcall(element.getElementPosition, element)
		else -- a power source, which Skynet holds as its DCS object
			ok, position = pcall(function()
				return element:isExist() and element:getPosition().p or nil
			end)
		end
		local known = self:lastKnownOf(element)
		if ok and position then
			known.position = position
		end
		return known.position
	end

	--- An element's name; the last known one once it is gone, "?" if it never answered.
	function SkynetIADSMapView:nameOf(element)
		local ok, name = pcall(element.getDCSName or element.getName, element) -- getName: a power source
		local known = self:lastKnownOf(element)
		if ok and name then
			known.name = name
		end
		return known.name or "?"
	end

	---------------------------------------------------------------------------------------------------
	--- Radio menu

	--- The view's commands, added to `menu`, the network's radio menu.
	function SkynetIADSMapView:addRadioCommands(menu)
		local layers = SkynetIADSMapView.layers
		missionCommands.addCommand("Map - Show/hide", menu, SkynetIADSMapView.radioToggleShown, self)
		local layerCommands = {
			{ "Map - Show/hide coverage lines (EW -> SAM)", layers.coverage },
			{ "Map - Show/hide range circles", layers.rangeCircles },
		}
		for _, command in ipairs(layerCommands) do
			missionCommands.addCommand(
				command[1],
				menu,
				SkynetIADSMapView.radioToggleLayer,
				{ view = self, layer = command[2] }
			)
		end
	end

	function SkynetIADSMapView.radioToggleShown(view)
		if view:isShown() then
			view:hide()
		else
			view:show()
		end
	end

	--- `params`: { view =, layer = <one of SkynetIADSMapView.layers> }
	function SkynetIADSMapView.radioToggleLayer(params)
		params.view:toggleLayer(params.layer)
	end

	---------------------------------------------------------------------------------------------------
	--- What a network holds (static: they read Skynet, not the view)

	--- The parents of a site that cover it, by Skynet's own rule: the parent list is geometry only.
	function SkynetIADSMapView.coveringParentsOf(site)
		local covering = {}
		for _, parent in ipairs(site:getParentRadars() or {}) do
			local ok, covers = pcall(site.isCoveredBy, site, parent)
			if ok and covers then
				table.insert(covering, parent)
			end
		end
		return covering
	end

	--- Where Skynet wakes the site, in metres: the range of its longest-reaching launcher in the kill zone,
	--- of its longest-reaching search radar in the search range, scaled by the go-live percentage, as
	--- isInHorizontalRange() scales them. 0 when it has none. In the kill zone, Skynet also wants a
	--- tracking radar in range: the circle is the deciding radius, not the whole rule.
	function SkynetIADSMapView.goLiveRange(samSite)
		local units = samSite:getLaunchers()
		if samSite:getEngagementZone() == SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE then
			units = samSite:getSearchRadars()
		end
		local range = 0
		for _, unit in ipairs(units or {}) do
			local ok, unitRange = pcall(unit.getMaxRangeFindingTarget, unit)
			if ok and unitRange and unitRange > range then
				range = unitRange
			end
		end
		return range / 100 * samSite:getGoLiveRangeInPercent()
	end

	function SkynetIADSMapView.powerSourceIsAlive(powerSource)
		local asked, alive = pcall(powerSource.isExist, powerSource)
		return asked and alive == true
	end

	--- How far this element may move before what is drawn for it is drawn again.
	function SkynetIADSMapView.moveThresholdOf(element)
		local representation = element.getDCSRepresentation and element:getDCSRepresentation() or element
		local asked, airborne = pcall(representation.inAir, representation)
		if asked and airborne then
			return SkynetIADSMapView.airMoveThreshold
		end
		return SkynetIADSMapView.groundMoveThreshold
	end

	--- How far an element's shape reaches from its centre, to keep lines clear of it.
	function SkynetIADSMapView.footprintOf(element)
		local sizes = SkynetIADSMapView.sizes
		if getmetatable(element) == SkynetIADSCommandCenter then
			return sizes.commandCenterHalfWidth
		elseif not element.getElementPosition then
			return sizes.powerSource
		elseif element:getIsAPointDefence() then
			return sizes.pointDefence
		end
		return math.max(sizes.sam, sizes.ew)
	end

	---------------------------------------------------------------------------------------------------
	--- Styles: { shape =, size =, fill =, outline =, dashed = }, colours from SkynetIADSMapView.colours

	function SkynetIADSMapView.radarElementStyle(element, isEwRadar)
		local shapes = SkynetIADSMapView.shapes
		local colours = SkynetIADSMapView.colours
		local style = {}
		if isEwRadar or element:getActAsEW() then
			style.shape = shapes.square
			style.size = SkynetIADSMapView.sizes.ew
		elseif element:getIsAPointDefence() then
			style.shape = shapes.invertedTriangle
			style.size = SkynetIADSMapView.sizes.pointDefence
		else
			style.shape = shapes.triangle
			style.size = SkynetIADSMapView.sizes.sam
		end
		-- destroyed first: a site killed with missiles in flight is never told to go dark, so Skynet
		-- still reports it live
		if element:isDestroyed() then
			style.fill = colours.grey
		elseif element:isDefendingHARM() then
			style.fill = colours.black
		elseif element:getIsPointDefending() then
			style.fill = colours.purple -- held live to shoot down a HARM aimed at the site it protects
		elseif element:isActive() then
			style.fill = style.shape == shapes.square and colours.blue or colours.red
		else
			style.fill = colours.grey
		end
		if style.shape ~= shapes.square and element:getAutonomousState() then
			style.outline = colours.orange
		else
			style.outline = style.fill
		end
		style.dashed = element:isDestroyed() == true
		return style
	end

	function SkynetIADSMapView.commandCenterStyle(commandCenter)
		local colours = SkynetIADSMapView.colours
		local style = { dashed = false }
		if commandCenter:isDestroyed() then
			style.fill, style.dashed = colours.red, true
		elseif not commandCenter:hasWorkingPowerSource() then
			style.fill = colours.orange
		else
			style.fill = colours.green
		end
		style.outline = style.fill
		return style
	end

	--- A style as a string, for an item's state: two equal strings draw the same.
	function SkynetIADSMapView.styleState(style)
		local function colourState(colour)
			return colour and table.concat(colour, ",") or "-"
		end
		return table.concat({
			tostring(style.shape),
			tostring(style.size),
			colourState(style.fill),
			colourState(style.outline),
			tostring(style.dashed),
		}, "/")
	end

	---------------------------------------------------------------------------------------------------
	--- Drawing primitives: each draws marks filed in `drawn`, a SkynetIADSMapViewDrawnItem, for its coalition

	--- One of SkynetIADSMapView.colours as DCS wants it, with an alpha.
	function SkynetIADSMapView.colour(rgb, alpha)
		rgb = rgb or SkynetIADSMapView.colours.grey
		return { rgb[1], rgb[2], rgb[3], alpha or 1 }
	end

	function SkynetIADSMapView.getLineType(dashed)
		return dashed and SkynetIADSMapView.lineTypes.dashed or SkynetIADSMapView.lineTypes.solid
	end

	--- Rectangle centred on `centre`, `halfHeight` north-south (x) and `halfWidth` east-west (z).
	function SkynetIADSMapView.drawRectangle(drawn, centre, halfWidth, halfHeight, style)
		trigger.action.rectToAll(
			drawn.coalition,
			drawn:newMarkId(),
			{ x = centre.x + halfHeight, y = centre.y, z = centre.z - halfWidth },
			{ x = centre.x - halfHeight, y = centre.y, z = centre.z + halfWidth },
			SkynetIADSMapView.colour(style.outline),
			SkynetIADSMapView.colour(style.fill, SkynetIADSMapView.fillAlpha),
			SkynetIADSMapView.getLineType(style.dashed),
			true
		)
	end

	--- Triangle on a circle of radius `radius` around `centre`, apex north (south when `inverted`).
	function SkynetIADSMapView.drawTriangle(drawn, centre, radius, style, inverted)
		local points = {}
		for i = 0, 2 do
			local angle = i * 2 * math.pi / 3 + (inverted and math.pi or 0)
			points[i + 1] =
				{ x = centre.x + radius * math.cos(angle), y = centre.y, z = centre.z + radius * math.sin(angle) }
		end
		trigger.action.markupToAll(
			SkynetIADSMapView.freeformPolygon,
			drawn.coalition,
			drawn:newMarkId(),
			points[1],
			points[2],
			points[3],
			SkynetIADSMapView.colour(style.outline),
			SkynetIADSMapView.colour(style.fill, SkynetIADSMapView.fillAlpha),
			SkynetIADSMapView.getLineType(style.dashed),
			true
		)
	end

	function SkynetIADSMapView.drawShape(drawn, centre, style)
		local shapes = SkynetIADSMapView.shapes
		if style.shape == shapes.triangle or style.shape == shapes.invertedTriangle then
			SkynetIADSMapView.drawTriangle(drawn, centre, style.size, style, style.shape == shapes.invertedTriangle)
		else
			SkynetIADSMapView.drawRectangle(drawn, centre, style.size, style.size, style)
		end
	end

	function SkynetIADSMapView.drawLine(drawn, from, to, colour, dashed)
		trigger.action.lineToAll(
			drawn.coalition,
			drawn:newMarkId(),
			from,
			to,
			SkynetIADSMapView.colour(colour),
			SkynetIADSMapView.getLineType(dashed),
			true
		)
	end

	function SkynetIADSMapView.drawCircle(drawn, centre, radius, colour)
		trigger.action.circleToAll(
			drawn.coalition,
			drawn:newMarkId(),
			centre,
			radius,
			SkynetIADSMapView.colour(colour),
			SkynetIADSMapView.colour(colour, 0),
			SkynetIADSMapView.lineTypes.solid,
			true
		)
	end

	--- A label south of a shape of size `size` centred on `centre`.
	function SkynetIADSMapView.drawLabel(drawn, centre, size, colour, text, fontSize)
		trigger.action.textToAll(
			drawn.coalition,
			drawn:newMarkId(),
			{ x = centre.x - size - SkynetIADSMapView.labelOffset, y = centre.y, z = centre.z },
			SkynetIADSMapView.colour(colour),
			SkynetIADSMapView.colour(colour, 0),
			fontSize or SkynetIADSMapView.labelFontSizes.small,
			true,
			text
		)
	end

	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------
	---  SkynetIADS API
	---------------------------------------------------------------------------------------------------
	---------------------------------------------------------------------------------------------------

	--- This network's map view, made at its first use.
	function SkynetIADS:getMapView()
		if self.mapView == nil then
			self.mapView = SkynetIADSMapView:create(self)
		end
		return self.mapView
	end

	--- Show (true) or erase (false) this network's drawing on the F10 map. Showing starts the timer that
	--- keeps it current, from the next tick; hiding stops it.
	function SkynetIADS:displayMap(bDisplay)
		if bDisplay then
			self:getMapView():show()
		else
			self:getMapView():hide()
		end
		return self
	end

	function SkynetIADS:isMapDisplayed()
		return self:getMapView():isShown()
	end

	--- The map's settings, a SkynetIADSMapViewSettings, read at every tick.
	function SkynetIADS:getDisplayMapSettings()
		return self:getMapView().settings
	end

	--- The map's commands in the network's radio menu; addRadioMenu() calls it.
	function SkynetIADS:addMapRadioCommands()
		self:getMapView():addRadioCommands(self.radioMenu)
	end
end
