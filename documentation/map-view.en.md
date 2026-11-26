# Map view

Skynet can draw a network on the F10 map and keep the drawing current: which sites are live or dark,
which EW radar covers which SAM site, what a point defence protects, whether a command center still
has power. It is a tool for building and checking a mission.

## Showing the map {#showing-the-map}

```lua
redIADS:displayMap(true)  -- draw the network, and keep the drawing current
redIADS:displayMap(false) -- erase it
redIADS:isMapDisplayed()  -- whether it is shown
```

The drawing appears a second after `displayMap(true)`, and follows the network every second from
then on. `redIADS:deactivate()` erases it.

The [radio menu](api.en.md#iads-configuration) of a network has three commands for its map. Each
switches at every click:

- `Map - Show/hide`
- `Map - Show/hide coverage lines (EW -> SAM)`
- `Map - Show/hide range circles`

## Settings {#settings}

```lua
local mapSettings = redIADS:getDisplayMapSettings()
```

The settings are read every second, so a change shows on a map already displayed.

What to draw: the layers below, every one shown by default. `setLayer()` shows or hides one, and
`hasLayer()` tells whether it is shown. A map with no layer shown draws nothing:

| Layer | What it draws |
|---|---|
| `elements` | the shapes, and the line from a command center to its power sources |
| `coverage` | the lines from an EW radar to the SAM sites it covers |
| `pointDefence` | the lines from a point defence to the site it protects |
| `rangeCircles` | the go-live range of live SAM sites |
| `labels` | the names under the shapes |

```lua
mapSettings:setLayer(SkynetIADSMapView.layers.labels, false)
mapSettings:setLayer(SkynetIADSMapView.layers.pointDefence, false)
```

Who sees the drawing, `targetCoalition`: `coalition.side.RED`, `coalition.side.BLUE`,
`coalition.side.NEUTRAL`, or `nil` for every coalition, the default:

```lua
mapSettings.targetCoalition = coalition.side.RED
```

Each mark on the F10 map has an id, and DCS leaves it to each script to choose its own. The map view
counts its marks from `7300000`, for every network. A mission whose own marks use that range moves
it, before any map is displayed:

```lua
SkynetIADSMapView.firstMarkId = 9000000
```

## Legend {#legend}

| Element | Shape | Colour |
|---|---|---|
| EW radar, or a SAM site acting as EW | square | blue live, grey dark, black silenced by a HARM |
| SAM site | triangle | filled red live, grey dark, black silenced by a HARM; outlined orange when autonomous |
| Point defence | small triangle, pointing down | as a SAM site, purple while defending against a HARM |
| Command center | rectangle | green powered, orange unpowered, red destroyed |
| Command center power source | small square | green, red destroyed |
| Destroyed element | dashed outline | at its last known position |
| Live SAM site | red circle | its go-live range: where Skynet wakes it, as its [engagement zone](api.en.md#engagement-zone) sets it |

| Line | Drawn |
|---|---|
| EW radar → SAM site | solid blue, while Skynet counts the site as covered by that radar |
| Point defence → protected site | dashed grey; solid purple while it is held live against a HARM |
| Command center → power source | dashed green |

Each shape carries the name of its unit or group in the mission.

## Cost {#cost}

Every mark DCS adds to the map or removes from it is an event, sent to every Skynet element. So the
map view draws again only what changed since the last second, and only where an element moved more
than 2 km (10 km in the air). A large network still costs a short freeze when it is first drawn: on a
network of some 600 marks, a full redraw froze the game for about a second.
