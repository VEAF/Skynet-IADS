# A map view of the network on the F10 map

Status: open

## The problem

A mission maker has no way to see what Skynet is doing with a network: which sites are live or dark,
which radar covers which site, what a point defence protects, whether the command center still has
power. The debug settings print messages, which do not show how the network is laid out on the map.

## What to build

`iads:setMapView(true)` draws a network on the F10 map and keeps the drawing current;
`iads:setMapView(false)` erases it. `iads:setMapViewOption(name, enabled)` leaves part of it out:
`coverage`, `pointDefence`, `rangeCircles`, `labels`, all on by default.

A working prototype is beside this spec, in `prototype.lua`. It runs as a mission script loaded after
Skynet, and has been used in a mission. Its header holds the legend: a shape per kind of element, a colour
per state, and a line per relation (coverage, point defence, power).

What the prototype already does, and what is worth keeping:

- **It redraws only what changed.** The drawing is split into items (an element with its label and range
  circle, a power source, a relation line), each with its own marks. A one-second timer updates only the
  networks marked dirty, and within those only the items whose state changed or that moved past a
  threshold. DCS marks cannot be edited, so a change means erase and draw again.
- **Why it must.** Every mark added or removed fires `S_EVENT_MARK_ADDED` / `S_EVENT_MARK_REMOVED` to every
  event handler, and each Skynet element is one. On one network a full redraw (607 marks out, 607 in) cost
  121,400 Skynet handler calls and froze the game for about a second.
- **A failure in one drawing step is logged and the rest goes on.**
- **Destroyed elements stay drawn**, dashed, at their last known position.

## To decide

1. **Change detection.** The prototype wraps about fifteen Skynet functions to mark the network dirty. In
   the source, each becomes a direct `markMapViewDirty()` call. A wrap on an inherited method misses an
   override silently: `SkynetIADSEWRadar.setToCorrectAutonomousState` had to be wrapped apart.
2. **The coverage rule is duplicated.** `coversSite` and `canBeCovered` restate
   `SkynetIADSAbstractRadarElement:hasValidParentRadar()`, because Skynet's parent list is geometry only.
   In the source, that function should expose its per-parent half, and the map view should call it, so
   the two cannot drift apart.
3. **The cost of mark events.** Every element receiving every mark event is a Skynet cost of its own,
   beyond this view. Whether elements drop those events early, and whether that is this work or a fix of
   its own.
4. **Who sees the drawing.** The prototype draws for every coalition (`-1`). Whether one coalition only
   should be an option, and whether the view belongs with `getDebugSettings()` or stands apart.
5. **Mark ids.** The prototype starts at a fixed `7300000`, which another script's marks could collide
   with. Configurable, or allocated otherwise.
6. **What is mission tooling.** The prototype survives being reloaded in a running mission
   (`SkynetIADSMapView = SkynetIADSMapView or {}`, originals kept so a reload never wraps a wrap). That
   serves hotload, and may not belong in the deliverable.
7. **Its place in the build.** A source file of its own in `build-tools/listToMerge.txt`, or part of an
   existing one.
8. **Verification.** Lua tests for the decisions (styles from state, coverage, item state, what is
   redrawn), with `trigger.action.*ToAll` and `removeMark` stubbed; an in-sim check that the drawing
   follows the network; a documentation page with the legend; a changelog entry.

## Out of scope

- Drawing contacts, or anything Skynet does not hold about its own network.
- An F10 radio menu to toggle the view: a mission can add one with the API.
