do
	-- The map view: a network drawn on the F10 map, kept current.
	--
	--   iads:displayMap(true | false)       show the map, or erase it
	--   iads:getDisplayMapSettings()        { layers = { ... }, coalition = nil }, read at every tick
	--   SkynetIADSMapView.firstMarkId       the first mark id the view draws under, for every network
	--
	-- Legend:
	--   EW radar (or a SAM site acting as EW)   square          blue live, grey dark, black silenced by a HARM
	--   SAM site                                triangle        fill red live, grey dark, black silenced by a HARM;
	--                                                           outline orange when autonomous, else as the fill
	--   point defence                           small triangle, pointing down: as a SAM site, purple while
	--                                                           point defending
	--   command center                          rectangle       green powered, orange unpowered, red destroyed
	--   command center power source             small square    green alive, red destroyed
	--   destroyed element                       dashed outline, at its last known position
	--   live SAM site                           red circle: where Skynet wakes it, its go-live range
	--   coverage (EW radar -> SAM site)         solid blue line, while Skynet counts the site as covered by it
	--   point defence -> protected site         dashed grey line; solid purple while held live against a HARM
	--   command center -> power source          dashed green line
	-- Each shape carries its DCS name.
	--
	-- Every mark DCS adds or removes is an S_EVENT_MARK_ADDED / S_EVENT_MARK_REMOVED sent to every event
	-- handler, and each Skynet element is one: one full redraw of a 600-mark network cost 121,400 handler
	-- calls and froze the game for a second. So the drawing is split into items (an element with its label
	-- and range circle, a power source, a relation line), each with its own marks, and a tick redraws only
	-- the items whose state changed or that moved far enough. DCS marks cannot be edited: a change is an
	-- erase and a draw.
	--
	-- Nothing in Skynet tells the view of a change: each tick reads the network and compares.
	SkynetIADSMapView = {}

	SkynetIADSMapView.LogPrefix = "SKYNET MAP VIEW: "
	SkynetIADSMapView.RefreshPeriod = 1 -- seconds between two ticks
	-- DCS allocates no mark ids: every script picks its own. One counter for every network, so two
	-- networks never draw under the same id; a mission whose own marks use this range moves it.
	SkynetIADSMapView.firstMarkId = 7300000
	SkynetIADSMapView.lastMarkId = nil -- nil until the first mark, then counted from firstMarkId

	-- What a map can draw, in getDisplayMapSettings().layers. All of them by default.
	SkynetIADSMapView.Layers = {
		"elements", -- the shapes: radars, SAM sites, command centers, power sources, and power lines
		"coverage", -- coverage lines, EW radar -> SAM site
		"pointDefence", -- point defence lines
		"rangeCircles", -- go-live range of live SAM sites
		"labels", -- names under the shapes
	}

	SkynetIADSMapView.FillAlpha = 0.35
	SkynetIADSMapView.Colours = {
		red = { 1, 0, 0 },
		grey = { 0.5, 0.5, 0.5 },
		blue = { 0, 0.45, 1 },
		orange = { 1, 0.55, 0 },
		purple = { 0.65, 0.2, 0.85 },
		green = { 0, 0.75, 0 },
		black = { 0, 0, 0 },
	}
	-- metres
	SkynetIADSMapView.Sizes = {
		ew = 700, -- square half-side
		sam = 800, -- triangle circumradius
		pointDefence = 500, -- inverted triangle circumradius, so it stands apart from the site it protects
		commandCenterHalfWidth = 800,
		commandCenterHalfHeight = 400,
		powerSource = 350, -- square half-side
	}
	SkynetIADSMapView.LineMargin = 200 -- metres between a line's end and the shape it points at, beyond the shape
	SkynetIADSMapView.LabelOffset = 300 -- metres between a shape and its label, south of it
	SkynetIADSMapView.LabelFontSizes = { large = 13, small = 10 }
	SkynetIADSMapView.LineTypes = { solid = 1, dashed = 2 }
	SkynetIADSMapView.FreeformPolygon = 7 -- markupToAll's shape id
	SkynetIADSMapView.AllCoalitions = -1
	-- how each kind of relation is drawn
	SkynetIADSMapView.RelationStyles = {
		coverage = { colour = "blue", dashed = false },
		pointDefence = { colour = "grey", dashed = true },
		pointDefending = { colour = "purple", dashed = false }, -- the colour of a point defence held live
		power = { colour = "green", dashed = true },
	}
	-- metres an element moves before it is drawn again where it is; more for an airborne one (an AWACS
	-- used as EW radar), which never stops, and each move redraws it and every coverage line it carries
	SkynetIADSMapView.GroundMoveThreshold = 2000
	SkynetIADSMapView.AirMoveThreshold = 10000

	-- Tools ----------------------------------------------------------------------------------------

	function SkynetIADSMapView.warn(message)
		env.warning(SkynetIADSMapView.LogPrefix .. message)
	end

	--- The map view's state on a network, made at its first use.
	function SkynetIADSMapView.stateOf(iads)
		if iads.mapView == nil then
			local layers = {}
			for i = 1, #SkynetIADSMapView.Layers do
				layers[i] = SkynetIADSMapView.Layers[i]
			end
			iads.mapView = {
				settings = { layers = layers, coalition = nil },
				taskId = nil,
				items = {}, -- key -> { state =, positions =, markIds = }
				positions = {}, -- object -> last known position
				names = {}, -- object -> last known name
				drawnCoalition = nil,
			}
		end
		return iads.mapView
	end

	function SkynetIADSMapView.hasLayer(iads, name)
		local layers = SkynetIADSMapView.stateOf(iads).settings.layers or {}
		for i = 1, #layers do
			if layers[i] == name then
				return true
			end
		end
		return false
	end

	--- Take a layer out of the list, or put it back at its end.
	function SkynetIADSMapView.switchLayer(iads, name)
		local settings = SkynetIADSMapView.stateOf(iads).settings
		local layers = {}
		local found = false
		for _, layer in ipairs(settings.layers or {}) do
			if layer == name then
				found = true
			else
				layers[#layers + 1] = layer
			end
		end
		if not found then
			layers[#layers + 1] = name
		end
		settings.layers = layers
	end

	function SkynetIADSMapView.colour(name, alpha)
		local rgb = SkynetIADSMapView.Colours[name] or SkynetIADSMapView.Colours.grey
		return { rgb[1], rgb[2], rgb[3], alpha or 1 }
	end

	--- A new mark id, appended to `marks`, the list of the item being drawn, so that item can be erased alone.
	function SkynetIADSMapView.newMarkIdIn(marks)
		SkynetIADSMapView.lastMarkId = (SkynetIADSMapView.lastMarkId or (SkynetIADSMapView.firstMarkId - 1)) + 1
		table.insert(marks, SkynetIADSMapView.lastMarkId)
		return SkynetIADSMapView.lastMarkId
	end

	--- Where a Skynet element or a DCS object is; the last known position once it is gone.
	function SkynetIADSMapView.positionOf(iads, object)
		local known = SkynetIADSMapView.stateOf(iads).positions
		local ok, position
		if object.getElementPosition then
			ok, position = pcall(object.getElementPosition, object)
		else
			ok, position = pcall(function()
				return object:isExist() and object:getPosition().p or nil
			end)
		end
		if ok and position then
			known[object] = position
			return position
		end
		return known[object]
	end

	--- Name of a Skynet element or a DCS object; the last known one once it is gone.
	function SkynetIADSMapView.nameOf(iads, object)
		local known = SkynetIADSMapView.stateOf(iads).names
		local ok, name = pcall(object.getDCSName or object.getName, object)
		if ok and name then
			known[object] = name
			return name
		end
		return known[object] or "?"
	end

	function SkynetIADSMapView.isAlive(dcsObject)
		local asked, alive = pcall(dcsObject.isExist, dcsObject)
		return asked and alive == true
	end

	-- Styles: what an element looks like, from its state ----------------------------------------

	function SkynetIADSMapView.radarElementStyle(element, isEwRadar)
		local style = {}
		if isEwRadar or element:getActAsEW() then
			style.shape = "square"
			style.size = SkynetIADSMapView.Sizes.ew
		elseif element:getIsAPointDefence() then
			style.shape = "invertedTriangle"
			style.size = SkynetIADSMapView.Sizes.pointDefence
		else
			style.shape = "triangle"
			style.size = SkynetIADSMapView.Sizes.sam
		end
		-- destroyed first: a site killed with missiles in flight is never told to go dark, so Skynet
		-- still reports it live
		if element:isDestroyed() then
			style.fill = "grey"
		elseif element:isDefendingHARM() then
			style.fill = "black"
		elseif element:getIsPointDefending() then
			style.fill = "purple" -- held live to shoot down a HARM aimed at the site it protects
		elseif element:isActive() then
			style.fill = style.shape == "square" and "blue" or "red"
		else
			style.fill = "grey"
		end
		if style.shape ~= "square" and element:getAutonomousState() then
			style.outline = "orange"
		else
			style.outline = style.fill
		end
		style.dashed = element:isDestroyed() == true
		return style
	end

	function SkynetIADSMapView.commandCenterStyle(commandCenter)
		local style = { dashed = false }
		if commandCenter:isDestroyed() then
			style.fill, style.dashed = "red", true
		elseif not commandCenter:hasWorkingPowerSource() then
			style.fill = "orange"
		else
			style.fill = "green"
		end
		style.outline = style.fill
		return style
	end

	-- Drawing primitives, read-only marks for the coalition the settings name ------------------

	function SkynetIADSMapView.lineTypeOf(dashed)
		return dashed and SkynetIADSMapView.LineTypes.dashed or SkynetIADSMapView.LineTypes.solid
	end

	--- Rectangle centred on `centre`, `halfHeight` north-south (x) and `halfWidth` east-west (z).
	function SkynetIADSMapView.drawRectangle(draw, centre, halfWidth, halfHeight, style)
		trigger.action.rectToAll(
			draw.coalition,
			SkynetIADSMapView.newMarkIdIn(draw.marks),
			{ x = centre.x + halfHeight, y = centre.y, z = centre.z - halfWidth },
			{ x = centre.x - halfHeight, y = centre.y, z = centre.z + halfWidth },
			SkynetIADSMapView.colour(style.outline),
			SkynetIADSMapView.colour(style.fill, SkynetIADSMapView.FillAlpha),
			SkynetIADSMapView.lineTypeOf(style.dashed),
			true
		)
	end

	--- Triangle on a circle of radius `radius` around `centre`, apex north (south when `inverted`).
	function SkynetIADSMapView.drawTriangle(draw, centre, radius, style, inverted)
		local points = {}
		for i = 0, 2 do
			local angle = i * 2 * math.pi / 3 + (inverted and math.pi or 0)
			points[i + 1] =
				{ x = centre.x + radius * math.cos(angle), y = centre.y, z = centre.z + radius * math.sin(angle) }
		end
		trigger.action.markupToAll(
			SkynetIADSMapView.FreeformPolygon,
			draw.coalition,
			SkynetIADSMapView.newMarkIdIn(draw.marks),
			points[1],
			points[2],
			points[3],
			SkynetIADSMapView.colour(style.outline),
			SkynetIADSMapView.colour(style.fill, SkynetIADSMapView.FillAlpha),
			SkynetIADSMapView.lineTypeOf(style.dashed),
			true
		)
	end

	function SkynetIADSMapView.drawShape(draw, centre, style)
		if style.shape == "triangle" or style.shape == "invertedTriangle" then
			SkynetIADSMapView.drawTriangle(draw, centre, style.size, style, style.shape == "invertedTriangle")
		else
			SkynetIADSMapView.drawRectangle(draw, centre, style.size, style.size, style)
		end
	end

	function SkynetIADSMapView.drawLine(draw, from, to, colourName, dashed)
		trigger.action.lineToAll(
			draw.coalition,
			SkynetIADSMapView.newMarkIdIn(draw.marks),
			from,
			to,
			SkynetIADSMapView.colour(colourName),
			SkynetIADSMapView.lineTypeOf(dashed),
			true
		)
	end

	function SkynetIADSMapView.drawCircle(draw, centre, radius, colourName)
		trigger.action.circleToAll(
			draw.coalition,
			SkynetIADSMapView.newMarkIdIn(draw.marks),
			centre,
			radius,
			SkynetIADSMapView.colour(colourName),
			SkynetIADSMapView.colour(colourName, 0),
			SkynetIADSMapView.LineTypes.solid,
			true
		)
	end

	--- A label south of a shape of size `size` centred on `centre`.
	function SkynetIADSMapView.drawLabel(draw, centre, size, colourName, text, fontSize)
		trigger.action.textToAll(
			draw.coalition,
			SkynetIADSMapView.newMarkIdIn(draw.marks),
			{ x = centre.x - size - SkynetIADSMapView.LabelOffset, y = centre.y, z = centre.z },
			SkynetIADSMapView.colour(colourName),
			SkynetIADSMapView.colour(colourName, 0),
			fontSize or SkynetIADSMapView.LabelFontSizes.small,
			true,
			text
		)
	end

	-- What a network holds ---------------------------------------------------------------------

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

	--- Every relation drawn as a line: { from =, to =, kind = <RelationStyles key> }.
	function SkynetIADSMapView.relationsOf(iads)
		local relations = {}
		local samSites = iads:getSAMSites() or {}
		if SkynetIADSMapView.hasLayer(iads, "coverage") then
			for _, sam in ipairs(samSites) do
				for _, parent in ipairs(SkynetIADSMapView.coveringParentsOf(sam)) do
					table.insert(relations, { from = parent, to = sam, kind = "coverage" })
				end
			end
		end
		if SkynetIADSMapView.hasLayer(iads, "pointDefence") then
			for _, list in ipairs({ iads:getEarlyWarningRadars() or {}, samSites }) do
				for _, protected in ipairs(list) do
					for _, pd in ipairs(protected:getPointDefences() or {}) do
						local kind = pd:getIsPointDefending() and "pointDefending" or "pointDefence"
						table.insert(relations, { from = pd, to = protected, kind = kind })
					end
				end
			end
		end
		if SkynetIADSMapView.hasLayer(iads, "elements") then
			for _, cc in ipairs(iads:getCommandCenters() or {}) do
				for _, powerSource in ipairs(cc:getPowerSources() or {}) do
					table.insert(relations, { from = cc, to = powerSource, kind = "power" })
				end
			end
		end
		return relations
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

	--- The range circle drawn around a radar element, in metres: 0 for an EW radar, a dark or a destroyed
	--- site, or when the range circles are left out.
	function SkynetIADSMapView.drawnEngagementRange(iads, element, isEwRadar)
		if
			isEwRadar
			or not SkynetIADSMapView.hasLayer(iads, "rangeCircles")
			or not element:isActive()
			or element:isDestroyed()
		then
			return 0
		end
		return SkynetIADSMapView.goLiveRange(element)
	end

	--- How far a shape reaches from its centre, to keep lines clear of it.
	function SkynetIADSMapView.footprintOf(object)
		local sizes = SkynetIADSMapView.Sizes
		if getmetatable(object) == SkynetIADSCommandCenter then
			return sizes.commandCenterHalfWidth
		elseif not object.getElementPosition then
			return sizes.powerSource
		elseif object:getIsAPointDefence() then
			return sizes.pointDefence
		end
		return math.max(sizes.sam, sizes.ew)
	end

	-- Drawing one item -----------------------------------------------------------------------------

	function SkynetIADSMapView.drawRadarElement(iads, draw, element, isEwRadar)
		local position = SkynetIADSMapView.positionOf(iads, element)
		if not position then
			return
		end
		local style = SkynetIADSMapView.radarElementStyle(element, isEwRadar)
		local range = SkynetIADSMapView.drawnEngagementRange(iads, element, isEwRadar)
		if range > 0 then
			SkynetIADSMapView.drawCircle(draw, position, range, "red")
		end
		if SkynetIADSMapView.hasLayer(iads, "elements") then
			SkynetIADSMapView.drawShape(draw, position, style)
			if SkynetIADSMapView.hasLayer(iads, "labels") then
				local fontSizes = SkynetIADSMapView.LabelFontSizes
				local fontSize = style.shape == "invertedTriangle" and fontSizes.small or fontSizes.large
				local name = SkynetIADSMapView.nameOf(iads, element)
				SkynetIADSMapView.drawLabel(draw, position, style.size, style.outline, name, fontSize)
			end
		end
	end

	function SkynetIADSMapView.drawCommandCenter(iads, draw, commandCenter)
		local position = SkynetIADSMapView.positionOf(iads, commandCenter)
		if not position then
			return
		end
		local sizes = SkynetIADSMapView.Sizes
		local style = SkynetIADSMapView.commandCenterStyle(commandCenter)
		SkynetIADSMapView.drawRectangle(
			draw,
			position,
			sizes.commandCenterHalfWidth,
			sizes.commandCenterHalfHeight,
			style
		)
		if SkynetIADSMapView.hasLayer(iads, "labels") then
			local name = SkynetIADSMapView.nameOf(iads, commandCenter)
			local fontSize = SkynetIADSMapView.LabelFontSizes.large
			SkynetIADSMapView.drawLabel(draw, position, sizes.commandCenterHalfHeight, style.outline, name, fontSize)
		end
	end

	function SkynetIADSMapView.drawPowerSource(iads, draw, powerSource)
		local position = SkynetIADSMapView.positionOf(iads, powerSource)
		if not position then
			return
		end
		local alive = SkynetIADSMapView.isAlive(powerSource)
		local colour = alive and "green" or "red"
		local style = { fill = colour, outline = colour, dashed = not alive }
		local size = SkynetIADSMapView.Sizes.powerSource
		SkynetIADSMapView.drawRectangle(draw, position, size, size, style)
		if SkynetIADSMapView.hasLayer(iads, "labels") then
			SkynetIADSMapView.drawLabel(draw, position, size, colour, SkynetIADSMapView.nameOf(iads, powerSource))
		end
	end

	--- A relation's line, each end pulled back off the shape it touches; nothing when the two shapes overlap.
	function SkynetIADSMapView.drawRelation(iads, draw, relation)
		local from = SkynetIADSMapView.positionOf(iads, relation.from)
		local to = SkynetIADSMapView.positionOf(iads, relation.to)
		if not from or not to then
			return
		end
		local dx, dz = to.x - from.x, to.z - from.z
		local length = math.sqrt(dx * dx + dz * dz)
		local fromGap = SkynetIADSMapView.footprintOf(relation.from) + SkynetIADSMapView.LineMargin
		local toGap = SkynetIADSMapView.footprintOf(relation.to) + SkynetIADSMapView.LineMargin
		if length <= fromGap + toGap then
			return
		end
		local ux, uz = dx / length, dz / length
		local style = SkynetIADSMapView.RelationStyles[relation.kind]
		SkynetIADSMapView.drawLine(
			draw,
			{ x = from.x + ux * fromGap, y = from.y, z = from.z + uz * fromGap },
			{ x = to.x - ux * toGap, y = to.y, z = to.z - uz * toGap },
			style.colour,
			style.dashed
		)
	end

	-- Items: what is drawn, and when it is drawn again ----------------------------------------------

	--- Everything the view draws for a network: { key, kind = "radar" | "commandCenter" | "powerSource" |
	--- "relation", object, isEwRadar, relation, anchors = <the objects whose position the drawing depends
	--- on> }. A key is the element or DCS object itself, or a string for a relation, so an item keeps its
	--- key from one tick to the next.
	function SkynetIADSMapView.itemsOf(iads)
		local items = {}
		local elements = SkynetIADSMapView.hasLayer(iads, "elements")
		if elements or SkynetIADSMapView.hasLayer(iads, "rangeCircles") then
			for _, ew in ipairs(iads:getEarlyWarningRadars() or {}) do
				table.insert(items, { key = ew, kind = "radar", object = ew, isEwRadar = true, anchors = { ew } })
			end
			-- point defences are SAM sites too
			for _, sam in ipairs(iads:getSAMSites() or {}) do
				table.insert(items, { key = sam, kind = "radar", object = sam, isEwRadar = false, anchors = { sam } })
			end
		end
		if elements then
			for _, cc in ipairs(iads:getCommandCenters() or {}) do
				table.insert(items, { key = cc, kind = "commandCenter", object = cc, anchors = { cc } })
				for _, powerSource in ipairs(cc:getPowerSources() or {}) do
					local item = { key = powerSource, kind = "powerSource", object = powerSource }
					item.anchors = { powerSource }
					table.insert(items, item)
				end
			end
		end
		for _, relation in ipairs(SkynetIADSMapView.relationsOf(iads)) do
			local from, to = SkynetIADSMapView.nameOf(iads, relation.from), SkynetIADSMapView.nameOf(iads, relation.to)
			local key = relation.kind .. ":" .. from .. ">" .. to
			table.insert(
				items,
				{ key = key, kind = "relation", relation = relation, anchors = { relation.from, relation.to } }
			)
		end
		return items
	end

	--- Everything an item's drawing depends on, its position aside, as a string: two equal states draw
	--- the same marks.
	function SkynetIADSMapView.itemState(iads, item)
		local layers = table.concat(SkynetIADSMapView.stateOf(iads).settings.layers or {}, ",")
		if item.kind == "radar" then
			local style = SkynetIADSMapView.radarElementStyle(item.object, item.isEwRadar)
			return table.concat({
				style.shape,
				style.size,
				style.fill,
				style.outline,
				tostring(style.dashed),
				SkynetIADSMapView.drawnEngagementRange(iads, item.object, item.isEwRadar),
				SkynetIADSMapView.nameOf(iads, item.object),
				layers,
			}, "|")
		elseif item.kind == "commandCenter" then
			local style = SkynetIADSMapView.commandCenterStyle(item.object)
			return table.concat(
				{ style.fill, tostring(style.dashed), SkynetIADSMapView.nameOf(iads, item.object), layers },
				"|"
			)
		elseif item.kind == "powerSource" then
			local alive = tostring(SkynetIADSMapView.isAlive(item.object))
			return table.concat({ alive, SkynetIADSMapView.nameOf(iads, item.object), layers }, "|")
		end
		return item.kind -- a relation: its kind is in its key, its look depends only on where its ends are
	end

	function SkynetIADSMapView.drawItem(iads, item, draw)
		if item.kind == "radar" then
			SkynetIADSMapView.drawRadarElement(iads, draw, item.object, item.isEwRadar)
		elseif item.kind == "commandCenter" then
			SkynetIADSMapView.drawCommandCenter(iads, draw, item.object)
		elseif item.kind == "powerSource" then
			SkynetIADSMapView.drawPowerSource(iads, draw, item.object)
		else
			SkynetIADSMapView.drawRelation(iads, draw, item.relation)
		end
	end

	--- How far this object may move before what is drawn for it is drawn again.
	function SkynetIADSMapView.moveThresholdOf(object)
		local representation = object.getDCSRepresentation and object:getDCSRepresentation() or object
		local asked, airborne = pcall(representation.inAir, representation)
		if asked and airborne then
			return SkynetIADSMapView.AirMoveThreshold
		end
		return SkynetIADSMapView.GroundMoveThreshold
	end

	--- Has any anchor of a drawn item moved past its threshold, or appeared, or gone, since it was drawn?
	function SkynetIADSMapView.hasMoved(iads, item, drawn)
		for i, anchor in ipairs(item.anchors) do
			local now, before = SkynetIADSMapView.positionOf(iads, anchor), drawn.positions[i]
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

	function SkynetIADSMapView.removeMarks(markIds)
		for _, id in ipairs(markIds or {}) do
			pcall(trigger.action.removeMark, id)
		end
	end

	--- Draw one item again if its state changed or it moved; leave its marks alone otherwise.
	function SkynetIADSMapView.updateItem(iads, item, coalitionId)
		local items = SkynetIADSMapView.stateOf(iads).items
		local state = SkynetIADSMapView.itemState(iads, item)
		local drawn = items[item.key]
		if drawn and drawn.state == state and not SkynetIADSMapView.hasMoved(iads, item, drawn) then
			return
		end
		if drawn then
			SkynetIADSMapView.removeMarks(drawn.markIds)
		end
		local positions = {}
		for i, anchor in ipairs(item.anchors) do
			positions[i] = SkynetIADSMapView.positionOf(iads, anchor)
		end
		-- filed before drawing, so marks drawn by a draw that fails half way are still erased later
		local redrawn = { state = state, positions = positions, markIds = {} }
		items[item.key] = redrawn
		SkynetIADSMapView.drawItem(iads, item, { coalition = coalitionId, marks = redrawn.markIds })
	end

	--- One drawing step; a failure is logged and the rest of the update goes on.
	function SkynetIADSMapView.guarded(what, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			SkynetIADSMapView.warn(string.format("drawing %s failed: %s", tostring(what), tostring(err)))
		end
	end

	--- What the timer runs: bring the drawing up to date, by redrawing the items that changed and erasing
	--- the ones that are gone. A change of coalition redraws everything, since each mark carries it.
	function SkynetIADSMapView.update(iads)
		local state = SkynetIADSMapView.stateOf(iads)
		local coalitionId = state.settings.coalition or SkynetIADSMapView.AllCoalitions
		if state.drawnCoalition ~= coalitionId then
			SkynetIADSMapView.erase(iads)
			state.drawnCoalition = coalitionId
		end
		local present = {}
		for _, item in ipairs(SkynetIADSMapView.itemsOf(iads)) do
			present[item.key] = true
			local name = type(item.key) == "string" and item.key or SkynetIADSMapView.nameOf(iads, item.key)
			SkynetIADSMapView.guarded(name, SkynetIADSMapView.updateItem, iads, item, coalitionId)
		end
		for key, drawn in pairs(state.items) do
			if not present[key] then
				SkynetIADSMapView.removeMarks(drawn.markIds)
				state.items[key] = nil
			end
		end
	end

	function SkynetIADSMapView.erase(iads)
		local state = SkynetIADSMapView.stateOf(iads)
		for _, drawn in pairs(state.items) do
			SkynetIADSMapView.removeMarks(drawn.markIds)
		end
		state.items = {}
		state.drawnCoalition = nil
	end

	--- What a radio command runs: { self = <iads>, action = "map" | <a layer> }.
	function SkynetIADSMapView.radioCommand(params)
		local iads = params.self
		if params.action == "map" then
			iads:displayMap(not iads:isMapDisplayed())
		else
			SkynetIADSMapView.switchLayer(iads, params.action)
		end
	end

	-- SkynetIADS API -------------------------------------------------------------------------------

	--- Show (true) or erase (false) this network's drawing on the F10 map. Showing starts the timer that
	--- keeps it current, from the next tick; hiding stops it.
	function SkynetIADS:displayMap(bDisplay)
		local state = SkynetIADSMapView.stateOf(self)
		if bDisplay then
			if state.taskId == nil then
				local period = SkynetIADSMapView.RefreshPeriod
				state.taskId = SkynetIADSUtils.scheduleFunction(
					SkynetIADSMapView.update,
					{ self },
					timer.getTime() + period,
					period
				)
			end
		else
			SkynetIADSUtils.removeFunction(state.taskId)
			state.taskId = nil
			SkynetIADSMapView.erase(self)
		end
		return self
	end

	function SkynetIADS:isMapDisplayed()
		return SkynetIADSMapView.stateOf(self).taskId ~= nil
	end

	--- The map's settings, read at every tick: { layers = <SkynetIADSMapView.Layers to draw>, coalition =
	--- <the coalition that sees the drawing, nil for every coalition> }.
	function SkynetIADS:getDisplayMapSettings()
		return SkynetIADSMapView.stateOf(self).settings
	end

	--- The map's commands in the network's radio menu; addRadioMenu() calls it.
	function SkynetIADS:addMapRadioCommands()
		local commands = {
			{ "Map - Show/hide", "map" },
			{ "Map - Show/hide coverage lines (EW -> SAM)", "coverage" },
			{ "Map - Show/hide range circles", "rangeCircles" },
		}
		for _, command in ipairs(commands) do
			missionCommands.addCommand(
				command[1],
				self.radioMenu,
				SkynetIADSMapView.radioCommand,
				{ self = self, action = command[2] }
			)
		end
	end
end
