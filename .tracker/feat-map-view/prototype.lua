-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- F10 map view of a Skynet IADS: draws the elements of a network and their relations on the F10 map, and keeps the drawing current.
--
--   iads:setMapView(true)   -- show it (for every coalition)
--   iads:setMapView(false)  -- erase it
--   iads:setMapViewOption("coverage" | "pointDefence" | "rangeCircles" | "labels", false)  -- leave part of it out (all on by default)
--
-- Legend:
--   EW radar (or a SAM site acting as EW)   square          blue live, grey dark, black silenced by a HARM
--   SAM site                                triangle        fill red live, grey dark, black silenced by a HARM;
--                                                           outline orange when autonomous, else as the fill
--   point defence                           small triangle, pointing down: as a SAM site, purple while point defending
--   command center                          rectangle       green powered, orange unpowered, red destroyed
--   command center power source             small square    green alive, red destroyed
--   destroyed element                       dashed outline, at its last known position
--   live SAM site                           red circle: the engagement range of its longest-reaching launcher
--   coverage (EW radar -> SAM site)         solid blue line, only while Skynet counts the site as covered by it
--   point defence -> protected site         dashed grey line; solid red while held live against a HARM
--   command center -> power source          dashed green line
-- Each shape carries its DCS name.
--
-- The drawing is a set of items (an element with its label and range circle, a power source, a relation line), each with its own
-- marks. A short timer updates the networks that are shown and were marked dirty by a wrapped Skynet function: only the items whose
-- state changed, or that moved far enough, are erased and drawn again (DCS marks cannot be edited), and items that are gone are erased.
--
-- Load order: after Skynet (skynet-iads-vendored.lua), before any script that builds an IADS. Uses nothing from VEAF.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

-- guarded, so state (shown networks, the timer, mark ids) survives reloading this file
SkynetIADSMapView = SkynetIADSMapView or {}

SkynetIADSMapView.LogPrefix = "SKYNET MAP VIEW: "
SkynetIADSMapView.RefreshPeriod = 1 -- seconds between two checks for a dirty network
SkynetIADSMapView.FirstMarkId = 7300000
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
-- metres; halved after a first look in game, where the shapes swamped the sites
SkynetIADSMapView.Sizes = {
  ew = 700, -- square half-side
  sam = 800, -- triangle circumradius
  pointDefence = 500, -- inverted triangle circumradius, so it stands apart from the site it protects
  commandCenterHalfWidth = 800,
  commandCenterHalfHeight = 400,
  powerSource = 350, -- square half-side
}
SkynetIADSMapView.LineMargin = 200 -- metres between a line's end and the shape it points at, on top of the shape's size
SkynetIADSMapView.LabelOffset = 300 -- metres between a shape and its label, south of it
SkynetIADSMapView.LabelFontSizes = { large = 13, small = 10 } -- large: SAM sites, EW radars, command centers; small: point defences, power sources
SkynetIADSMapView.LineTypes = { solid = 1, dashed = 2 }
-- how each kind of relation is drawn
SkynetIADSMapView.RelationStyles = {
  coverage = { colour = "blue", dashed = false }, -- parent radar -> SAM site it covers
  pointDefence = { colour = "grey", dashed = true }, -- point defence -> site it protects
  pointDefending = { colour = "red", dashed = false }, -- the same, while held live against a HARM
  power = { colour = "green", dashed = true }, -- command center -> its power source
}

--- What a map view can leave out, per network (iads:setMapViewOption). All on by default.
SkynetIADSMapView.OptionDefaults = {
  coverage = true, -- coverage lines, EW radar -> SAM site
  pointDefence = true, -- point defence lines
  rangeCircles = true, -- engagement range of live SAM sites
  labels = true, -- names under the shapes
}

SkynetIADSMapView.shownIads = SkynetIADSMapView.shownIads or {}
SkynetIADSMapView.knownIads = SkynetIADSMapView.knownIads or {} -- every IADS that has marked itself dirty once, shown or not
SkynetIADSMapView.lastMarkId = SkynetIADSMapView.lastMarkId or (SkynetIADSMapView.FirstMarkId - 1)

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Tools
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function SkynetIADSMapView.warn(message)
  env.warning(SkynetIADSMapView.LogPrefix .. message)
end

function SkynetIADSMapView.colour(name, alpha)
  local rgb = SkynetIADSMapView.Colours[name] or SkynetIADSMapView.Colours.grey
  return { rgb[1], rgb[2], rgb[3], alpha or 1 }
end

function SkynetIADSMapView.newMarkId()
  SkynetIADSMapView.lastMarkId = SkynetIADSMapView.lastMarkId + 1
  return SkynetIADSMapView.lastMarkId
end

--- A new mark id, appended to `marks` (the list of the item being drawn) so that item can be erased on its own.
function SkynetIADSMapView.newMarkIdIn(marks)
  local id = SkynetIADSMapView.newMarkId()
  table.insert(marks, id)
  return id
end

--- Where a Skynet element (or a DCS object) is; the last known position once it is gone.
function SkynetIADSMapView.positionOf(iads, object)
  iads.mapViewPositions = iads.mapViewPositions or {}
  local ok, position
  if object.getElementPosition then
    ok, position = pcall(object.getElementPosition, object)
  else
    ok, position = pcall(function()
      return object:isExist() and object:getPosition().p or nil
    end)
  end
  if ok and position then
    iads.mapViewPositions[object] = position
    return position
  end
  return iads.mapViewPositions[object]
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Styles: what an element looks like, from its state
-------------------------------------------------------------------------------------------------------------------------------------------------------------
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
  -- destroyed first: a site killed with missiles in flight is never told to go dark, so Skynet still reports it live
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

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Drawing primitives (all coalitions, read-only)
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function SkynetIADSMapView.lineTypeOf(style)
  return style.dashed and SkynetIADSMapView.LineTypes.dashed or SkynetIADSMapView.LineTypes.solid
end

--- Rectangle centred on `centre`, `halfHeight` north-south (x) and `halfWidth` east-west (z).
function SkynetIADSMapView.drawRectangle(marks, centre, halfWidth, halfHeight, style)
  local corner1 = { x = centre.x + halfHeight, y = centre.y, z = centre.z - halfWidth }
  local corner2 = { x = centre.x - halfHeight, y = centre.y, z = centre.z + halfWidth }
  trigger.action.rectToAll(
    -1,
    SkynetIADSMapView.newMarkIdIn(marks),
    corner1,
    corner2,
    SkynetIADSMapView.colour(style.outline),
    SkynetIADSMapView.colour(style.fill, SkynetIADSMapView.FillAlpha),
    SkynetIADSMapView.lineTypeOf(style),
    true
  )
end

--- Triangle on a circle of radius `radius` around `centre`, apex north (south when `inverted`).
function SkynetIADSMapView.drawTriangle(marks, centre, radius, style, inverted)
  local points = {}
  for i = 0, 2 do
    local angle = i * 2 * math.pi / 3 + (inverted and math.pi or 0)
    points[i + 1] = { x = centre.x + radius * math.cos(angle), y = centre.y, z = centre.z + radius * math.sin(angle) }
  end
  trigger.action.markupToAll(
    7, -- freeform polygon
    -1,
    SkynetIADSMapView.newMarkIdIn(marks),
    points[1],
    points[2],
    points[3],
    SkynetIADSMapView.colour(style.outline),
    SkynetIADSMapView.colour(style.fill, SkynetIADSMapView.FillAlpha),
    SkynetIADSMapView.lineTypeOf(style),
    true
  )
end

function SkynetIADSMapView.drawShape(marks, centre, style)
  if style.shape == "triangle" or style.shape == "invertedTriangle" then
    SkynetIADSMapView.drawTriangle(marks, centre, style.size, style, style.shape == "invertedTriangle")
  else
    SkynetIADSMapView.drawRectangle(marks, centre, style.size, style.size, style)
  end
end

function SkynetIADSMapView.drawLine(marks, from, to, colourName, dashed)
  trigger.action.lineToAll(
    -1,
    SkynetIADSMapView.newMarkIdIn(marks),
    from,
    to,
    SkynetIADSMapView.colour(colourName),
    dashed and SkynetIADSMapView.LineTypes.dashed or SkynetIADSMapView.LineTypes.solid,
    true
  )
end

function SkynetIADSMapView.drawCircle(marks, centre, radius, colourName)
  trigger.action.circleToAll(
    -1,
    SkynetIADSMapView.newMarkIdIn(marks),
    centre,
    radius,
    SkynetIADSMapView.colour(colourName),
    SkynetIADSMapView.colour(colourName, 0),
    SkynetIADSMapView.LineTypes.solid,
    true
  )
end

--- A label south of a shape of size `size` centred on `centre`.
function SkynetIADSMapView.drawLabel(marks, centre, size, colourName, text, fontSize)
  local point = { x = centre.x - size - SkynetIADSMapView.LabelOffset, y = centre.y, z = centre.z }
  trigger.action.textToAll(
    -1,
    SkynetIADSMapView.newMarkIdIn(marks),
    point,
    SkynetIADSMapView.colour(colourName),
    SkynetIADSMapView.colour(colourName, 0),
    fontSize or SkynetIADSMapView.LabelFontSizes.small,
    true,
    text
  )
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- What a network holds
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Does this parent radar really cover its child site? Skynet's parent list is geometry only: any radar element whose radar reaches
--- the site, an SA-10 that does not act as EW included, and a dead parent stays in it. This is the per-parent half of Skynet's own
--- SkynetIADSAbstractRadarElement:hasValidParentRadar().
function SkynetIADSMapView.coversSite(parent)
  return parent:getActAsEW() == true and parent:isDestroyed() == false and parent:hasWorkingPowerSource() == true and parent:hasActiveConnectionNode() == true
end

--- Can this site be covered at all? The site's half of Skynet's hasValidParentRadar(): it is linked to its network, and the network's
--- command center works. When it does not (its power source blown up, say), every site goes autonomous and no radar covers any.
function SkynetIADSMapView.canBeCovered(site)
  return site:hasActiveConnectionNode() == true and site.iads:isCommandCenterUsable() == true
end

--- The parents of a site that really cover it.
function SkynetIADSMapView.coveringParentsOf(site)
  local covering = {}
  local asked, coverable = pcall(SkynetIADSMapView.canBeCovered, site)
  if not (asked and coverable) then
    return covering
  end
  for _, parent in ipairs(site:getParentRadars() or {}) do
    local ok, covers = pcall(SkynetIADSMapView.coversSite, parent)
    if ok and covers then
      table.insert(covering, parent)
    end
  end
  return covering
end

--- Every relation drawn as a line: { from = <element or DCS object>, to = <element or DCS object>, kind = <RelationStyles key> }.
function SkynetIADSMapView.relationsOf(iads)
  local relations = {}
  local samSites = iads:getSAMSites() or {}
  if iads:getMapViewOption("coverage") then
    for _, sam in ipairs(samSites) do
      for _, parent in ipairs(SkynetIADSMapView.coveringParentsOf(sam)) do
        table.insert(relations, { from = parent, to = sam, kind = "coverage" })
      end
    end
  end
  if iads:getMapViewOption("pointDefence") then
    for _, list in ipairs({ iads:getEarlyWarningRadars() or {}, samSites }) do
      for _, protected in ipairs(list) do
        for _, pd in ipairs(protected:getPointDefences() or {}) do
          table.insert(relations, { from = pd, to = protected, kind = pd:getIsPointDefending() and "pointDefending" or "pointDefence" })
        end
      end
    end
  end
  for _, cc in ipairs(iads:getCommandCenters() or {}) do
    for _, powerSource in ipairs(cc:getPowerSources() or {}) do
      table.insert(relations, { from = cc, to = powerSource, kind = "power" })
    end
  end
  return relations
end

--- Range of the site's longest-reaching launcher, in metres; 0 when it has none.
function SkynetIADSMapView.engagementRange(samSite)
  local range = 0
  for _, launcher in ipairs(samSite:getLaunchers() or {}) do
    local ok, launcherRange = pcall(launcher.getRange, launcher)
    if ok and launcherRange and launcherRange > range then
      range = launcherRange
    end
  end
  return range
end

--- How far a shape reaches from its centre, to keep lines and labels clear of it.
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

--- Name of a Skynet element or DCS object; the last known one once it is gone.
function SkynetIADSMapView.nameOf(iads, object)
  iads.mapViewNames = iads.mapViewNames or {}
  local getter = object.getDCSName or object.getName
  local ok, name = pcall(getter, object)
  if ok and name then
    iads.mapViewNames[object] = name
    return name
  end
  return iads.mapViewNames[object] or "?"
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Drawing a network, one item at a time
--
-- Every mark DCS adds or removes fires S_EVENT_MARK_ADDED / S_EVENT_MARK_REMOVED to every event handler of the mission, and Skynet
-- registers each of its elements as a handler: measured on the MAP network, one full redraw (607 marks out, 607 in) cost 121 400
-- Skynet handler calls and froze the game for about a second. So the drawing is split into items (an element with its label and range
-- circle, a power source, a relation line), each with its own marks, and a refresh redraws only the items that changed.
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Metres a ground element must move before it is redrawn where it is.
SkynetIADSMapView.GroundMoveThreshold = 2000
--- Metres an airborne element (an AWACS used as an EW radar) must move before it is redrawn: it never stops, and each move redraws its
--- square, its label and every coverage line it carries.
SkynetIADSMapView.AirMoveThreshold = 10000

function SkynetIADSMapView.drawRadarElement(iads, marks, element, isEwRadar)
  local position = SkynetIADSMapView.positionOf(iads, element)
  if position then
    local style = SkynetIADSMapView.radarElementStyle(element, isEwRadar)
    local range = SkynetIADSMapView.drawnEngagementRange(element, isEwRadar)
    if range > 0 then
      SkynetIADSMapView.drawCircle(marks, position, range, "red")
    end
    SkynetIADSMapView.drawShape(marks, position, style)
    if iads:getMapViewOption("labels") then
      local fontSize = style.shape == "invertedTriangle" and SkynetIADSMapView.LabelFontSizes.small or SkynetIADSMapView.LabelFontSizes.large
      SkynetIADSMapView.drawLabel(marks, position, style.size, style.outline, SkynetIADSMapView.nameOf(iads, element), fontSize)
    end
  end
end

function SkynetIADSMapView.drawCommandCenter(iads, marks, commandCenter)
  local position = SkynetIADSMapView.positionOf(iads, commandCenter)
  if position then
    local sizes = SkynetIADSMapView.Sizes
    local style = SkynetIADSMapView.commandCenterStyle(commandCenter)
    SkynetIADSMapView.drawRectangle(marks, position, sizes.commandCenterHalfWidth, sizes.commandCenterHalfHeight, style)
    if iads:getMapViewOption("labels") then
      SkynetIADSMapView.drawLabel(marks, position, sizes.commandCenterHalfHeight, style.outline, SkynetIADSMapView.nameOf(iads, commandCenter), SkynetIADSMapView.LabelFontSizes.large)
    end
  end
end

function SkynetIADSMapView.isAlive(dcsObject)
  local asked, alive = pcall(dcsObject.isExist, dcsObject)
  return asked and alive == true
end

function SkynetIADSMapView.drawPowerSource(iads, marks, powerSource)
  local position = SkynetIADSMapView.positionOf(iads, powerSource)
  if position then
    local style = SkynetIADSMapView.isAlive(powerSource) and { fill = "green", outline = "green", dashed = false } or { fill = "red", outline = "red", dashed = true }
    local size = SkynetIADSMapView.Sizes.powerSource
    SkynetIADSMapView.drawRectangle(marks, position, size, size, style)
    if iads:getMapViewOption("labels") then
      SkynetIADSMapView.drawLabel(marks, position, size, style.outline, SkynetIADSMapView.nameOf(iads, powerSource))
    end
  end
end

--- A relation's line, each end pulled back off the shape it touches; nothing when the two shapes overlap.
function SkynetIADSMapView.drawRelation(iads, marks, relation)
  local from, to = SkynetIADSMapView.positionOf(iads, relation.from), SkynetIADSMapView.positionOf(iads, relation.to)
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
    marks,
    { x = from.x + ux * fromGap, y = from.y, z = from.z + uz * fromGap },
    { x = to.x - ux * toGap, y = to.y, z = to.z - uz * toGap },
    style.colour,
    style.dashed
  )
end

--- The range circle drawn around a radar element, in metres: 0 for an EW radar, a dark site or a destroyed one, or when the network's
--- view leaves range circles out.
function SkynetIADSMapView.drawnEngagementRange(element, isEwRadar)
  if isEwRadar or (element.iads and not element.iads:getMapViewOption("rangeCircles")) or not element:isActive() or element:isDestroyed() then
    return 0
  end
  return SkynetIADSMapView.engagementRange(element)
end

--- Run one drawing step; a failure is logged and the rest of the update goes on.
function SkynetIADSMapView.guardedDraw(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    SkynetIADSMapView.warn(string.format("drawing %s failed: %s", tostring(what), tostring(err)))
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Items: what is drawn, and when it must be drawn again
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Everything the view draws for a network: { key, kind = "radar" | "commandCenter" | "powerSource" | "relation", object, isEwRadar,
--- relation, anchors = <the objects whose position the drawing depends on> }. A key is the element or DCS object itself, or a string for
--- a relation, so an item keeps its key from one update to the next.
function SkynetIADSMapView.itemsOf(iads)
  local items = {}
  for _, ew in ipairs(iads:getEarlyWarningRadars() or {}) do
    table.insert(items, { key = ew, kind = "radar", object = ew, isEwRadar = true, anchors = { ew } })
  end
  -- point defences are SAM sites too
  for _, sam in ipairs(iads:getSAMSites() or {}) do
    table.insert(items, { key = sam, kind = "radar", object = sam, isEwRadar = false, anchors = { sam } })
  end
  for _, cc in ipairs(iads:getCommandCenters() or {}) do
    table.insert(items, { key = cc, kind = "commandCenter", object = cc, anchors = { cc } })
    for _, powerSource in ipairs(cc:getPowerSources() or {}) do
      table.insert(items, { key = powerSource, kind = "powerSource", object = powerSource, anchors = { powerSource } })
    end
  end
  for _, relation in ipairs(SkynetIADSMapView.relationsOf(iads)) do
    local key = relation.kind .. ":" .. SkynetIADSMapView.nameOf(iads, relation.from) .. ">" .. SkynetIADSMapView.nameOf(iads, relation.to)
    table.insert(items, { key = key, kind = "relation", relation = relation, anchors = { relation.from, relation.to } })
  end
  return items
end

--- Everything an item's drawing depends on, its position aside, as a string: two equal states draw the same marks.
function SkynetIADSMapView.itemState(iads, item)
  if item.kind == "radar" then
    local style = SkynetIADSMapView.radarElementStyle(item.object, item.isEwRadar)
    return table.concat({
      style.shape,
      style.size,
      style.fill,
      style.outline,
      tostring(style.dashed),
      SkynetIADSMapView.drawnEngagementRange(item.object, item.isEwRadar),
      SkynetIADSMapView.nameOf(iads, item.object),
      tostring(iads:getMapViewOption("labels")),
    }, "|")
  elseif item.kind == "commandCenter" then
    local style = SkynetIADSMapView.commandCenterStyle(item.object)
    return table.concat({ style.fill, tostring(style.dashed), SkynetIADSMapView.nameOf(iads, item.object), tostring(iads:getMapViewOption("labels")) }, "|")
  elseif item.kind == "powerSource" then
    return table.concat({ tostring(SkynetIADSMapView.isAlive(item.object)), SkynetIADSMapView.nameOf(iads, item.object), tostring(iads:getMapViewOption("labels")) }, "|")
  end
  return item.kind -- a relation: its kind is in its key, its look depends only on where its ends are
end

function SkynetIADSMapView.drawItem(iads, item, marks)
  if item.kind == "radar" then
    SkynetIADSMapView.drawRadarElement(iads, marks, item.object, item.isEwRadar)
  elseif item.kind == "commandCenter" then
    SkynetIADSMapView.drawCommandCenter(iads, marks, item.object)
  elseif item.kind == "powerSource" then
    SkynetIADSMapView.drawPowerSource(iads, marks, item.object)
  else
    SkynetIADSMapView.drawRelation(iads, marks, item.relation)
  end
end

--- How far this object may move before what is drawn for it is redrawn.
function SkynetIADSMapView.moveThresholdOf(object)
  local representation = object.getDCSRepresentation and object:getDCSRepresentation() or object
  local asked, airborne = pcall(representation.inAir, representation)
  if asked and airborne then
    return SkynetIADSMapView.AirMoveThreshold
  end
  return SkynetIADSMapView.GroundMoveThreshold
end

--- Has any anchor of a drawn item moved past its threshold (or appeared, or gone) since it was drawn?
function SkynetIADSMapView.hasMoved(iads, item, drawn)
  for i, anchor in ipairs(item.anchors) do
    local now, then_ = SkynetIADSMapView.positionOf(iads, anchor), drawn.positions[i]
    if (now == nil) ~= (then_ == nil) then
      return true
    end
    if now then
      local dx, dz, threshold = now.x - then_.x, now.z - then_.z, SkynetIADSMapView.moveThresholdOf(anchor)
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

--- Redraw one item if its state changed or it moved; leave its marks alone otherwise.
function SkynetIADSMapView.updateItem(iads, item)
  local state = SkynetIADSMapView.itemState(iads, item)
  local drawn = iads.mapViewItems[item.key]
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
  -- stored before drawing, so marks drawn by a draw that fails half way are still erased later
  local redrawn = { state = state, positions = positions, markIds = {} }
  iads.mapViewItems[item.key] = redrawn
  SkynetIADSMapView.drawItem(iads, item, redrawn.markIds)
end

--- Bring the drawing of a network up to date: redraw the items that changed, erase the ones that are gone.
function SkynetIADSMapView.update(iads)
  iads.mapViewItems = iads.mapViewItems or {}
  local present = {}
  for _, item in ipairs(SkynetIADSMapView.itemsOf(iads)) do
    present[item.key] = true
    SkynetIADSMapView.guardedDraw(item.key, SkynetIADSMapView.updateItem, iads, item)
  end
  for key, drawn in pairs(iads.mapViewItems) do
    if not present[key] then
      SkynetIADSMapView.removeMarks(drawn.markIds)
      iads.mapViewItems[key] = nil
    end
  end
end

function SkynetIADSMapView.erase(iads)
  for _, drawn in pairs(iads.mapViewItems or {}) do
    SkynetIADSMapView.removeMarks(drawn.markIds)
  end
  iads.mapViewItems = {}
end

--- How many marks are on the map for this network.
function SkynetIADSMapView.markCount(iads)
  local count = 0
  for _, drawn in pairs(iads.mapViewItems or {}) do
    count = count + #drawn.markIds
  end
  return count
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Refresh loop
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Remember where every element of a network is, so one lost while the view is hidden is still drawn where it was.
function SkynetIADSMapView.rememberPositions(iads)
  for _, list in ipairs({ iads:getEarlyWarningRadars() or {}, iads:getSAMSites() or {}, iads:getCommandCenters() or {} }) do
    for _, element in ipairs(list) do
      SkynetIADSMapView.positionOf(iads, element)
    end
  end
  for _, cc in ipairs(iads:getCommandCenters() or {}) do
    for _, powerSource in ipairs(cc:getPowerSources() or {}) do
      SkynetIADSMapView.positionOf(iads, powerSource)
    end
  end
end

--- Update every shown network marked dirty; for a hidden one, only remember positions. Answers the time of the next check, so it can
--- be the timer's function.
function SkynetIADSMapView.tick()
  for iads in pairs(SkynetIADSMapView.knownIads) do
    if iads.mapViewDirty and not SkynetIADSMapView.shownIads[iads] then
      iads.mapViewDirty = false
      SkynetIADSMapView.guardedDraw(iads.name, SkynetIADSMapView.rememberPositions, iads)
    end
  end
  for iads in pairs(SkynetIADSMapView.shownIads) do
    if iads.mapViewDirty then
      iads.mapViewDirty = false
      SkynetIADSMapView.guardedDraw(iads.name, SkynetIADSMapView.update, iads)
    end
  end
  return timer.getTime() + SkynetIADSMapView.RefreshPeriod
end

--- What the timer calls: looks tick() up at each call, so a reload of this file replaces it under the running timer.
function SkynetIADSMapView.timerTick()
  local ok, nextTime = pcall(SkynetIADSMapView.tick)
  if not ok then
    SkynetIADSMapView.warn("refresh failed: " .. tostring(nextTime))
    return timer.getTime() + SkynetIADSMapView.RefreshPeriod
  end
  return nextTime
end

function SkynetIADSMapView.startTimer()
  if not SkynetIADSMapView.timerId then
    SkynetIADSMapView.timerId = timer.scheduleFunction(SkynetIADSMapView.timerTick, nil, timer.getTime() + SkynetIADSMapView.RefreshPeriod)
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- SkynetIADS API
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Show (true) or erase (false) this network's drawing on the F10 map, for every coalition.
function SkynetIADS:setMapView(bEnabled)
  if bEnabled then
    SkynetIADSMapView.shownIads[self] = true
    self:markMapViewDirty()
    SkynetIADSMapView.startTimer()
  else
    SkynetIADSMapView.shownIads[self] = nil
    SkynetIADSMapView.erase(self)
  end
  return self
end

function SkynetIADS:getMapView()
  return SkynetIADSMapView.shownIads[self] == true
end

--- Include (true) or leave out (false) part of the drawing: "coverage", "pointDefence", "rangeCircles" or "labels".
function SkynetIADS:setMapViewOption(name, bEnabled)
  if SkynetIADSMapView.OptionDefaults[name] == nil then
    SkynetIADSMapView.warn(string.format("%s: no map view option %s", tostring(self.name), tostring(name)))
    return self
  end
  self.mapViewOptions = self.mapViewOptions or {}
  self.mapViewOptions[name] = bEnabled == true
  self:markMapViewDirty()
  return self
end

--- Whether an option is on; nil for an option that does not exist.
function SkynetIADS:getMapViewOption(name)
  local chosen = self.mapViewOptions and self.mapViewOptions[name]
  if chosen ~= nil then
    return chosen
  end
  return SkynetIADSMapView.OptionDefaults[name]
end

--- Ask for an update at the next refresh. While the view is hidden, the refresh only remembers element positions.
function SkynetIADS:markMapViewDirty()
  self.mapViewDirty = true
  if not SkynetIADSMapView.knownIads[self] then
    SkynetIADSMapView.knownIads[self] = true
    SkynetIADSMapView.startTimer()
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Change detection: Skynet functions that change what the view shows are wrapped so they mark their IADS dirty.
--
-- Once this lives in Skynet, each wrap becomes a call to markMapViewDirty() at the end of the function it wraps.
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Skynet's own functions, keyed "<class>.<method>". Kept across reloads, so a reload wraps the original and never a previous wrap.
SkynetIADSMapView.originals = SkynetIADSMapView.originals or {}

function SkynetIADSMapView.pack(...)
  return { n = select("#", ...), ... }
end

function SkynetIADSMapView.iadsOfElement(element)
  return element.iads
end

function SkynetIADSMapView.iadsItself(iads)
  return iads
end

--- Every element receives every world event, shots included: only a death can change what the view shows.
function SkynetIADSMapView.isDeathEvent(_, event)
  return event ~= nil and event.id == world.event.S_EVENT_DEAD
end

--- Replace `<className>.<methodName>` by a function that runs Skynet's original, then marks the IADS dirty (when `filter`, if given,
--- agrees). Answers all the original's results. Only a function defined on that class itself is wrapped, not an inherited one.
function SkynetIADSMapView.wrap(className, methodName, iadsOf, filter)
  local key = className .. "." .. methodName
  local class = rawget(_G, className)
  if SkynetIADSMapView.originals[key] == nil then
    local original = class and rawget(class, methodName)
    if type(original) ~= "function" then
      SkynetIADSMapView.warn(string.format("cannot watch %s, it does not exist", key))
      return
    end
    SkynetIADSMapView.originals[key] = original
  end
  class[methodName] = function(self, ...)
    local results = SkynetIADSMapView.pack(SkynetIADSMapView.originals[key](self, ...))
    if filter == nil or filter(self, ...) then
      local iads = iadsOf(self)
      if iads and iads.markMapViewDirty then
        pcall(iads.markMapViewDirty, iads)
      end
    end
    return unpack(results, 1, results.n)
  end
end

function SkynetIADSMapView.installWraps()
  local element, iads = SkynetIADSMapView.iadsOfElement, SkynetIADSMapView.iadsItself
  -- state: live, dark, autonomous, silenced by a HARM, point defending
  for _, method in ipairs({ "goLive", "goDark", "setToCorrectAutonomousState", "goSilentToEvadeHARM", "finishHarmDefence", "setIsPointDefending", "addPointDefence" }) do
    SkynetIADSMapView.wrap("SkynetIADSAbstractRadarElement", method, element)
  end
  -- an override: the wrap of the base function does not reach it
  SkynetIADSMapView.wrap("SkynetIADSEWRadar", "setToCorrectAutonomousState", element)
  -- losses: an element, a power source, a command center
  SkynetIADSMapView.wrap("SkynetIADSAbstractElement", "onEvent", element, SkynetIADSMapView.isDeathEvent)
  -- coverage (also how moving elements are noticed) and membership
  for _, method in ipairs({
    "buildRadarCoverage",
    "buildRadarCoverageForSAMSite",
    "buildRadarCoverageForEarlyWarningRadar",
    "updateRadarAssociation",
    "addSAMSite",
    "addEarlyWarningRadar",
    "addCommandCenter",
    "deactivate",
  }) do
    SkynetIADSMapView.wrap("SkynetIADS", method, iads)
  end
end

SkynetIADSMapView.installWraps()

-- after a reload, shown networks are updated by the new code (their drawn items live on the IADS)
for shown in pairs(SkynetIADSMapView.shownIads) do
  shown:markMapViewDirty()
end
