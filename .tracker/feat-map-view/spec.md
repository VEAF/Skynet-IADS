# A map view of the network on the F10 map

Status: in-progress

## The problem

A mission maker has no way to see what Skynet is doing with a network: which sites are live or dark,
which radar covers which site, what a point defence protects, whether the command center still has
power. The debug settings print messages, which do not show how the network is laid out on the map.

## What to build

- **`iads:displayMap(true)`** draws the network on the F10 map and starts the network's timer that keeps
  the drawing current; **`iads:displayMap(false)`** stops it and erases the drawing. It is the only way
  to show or hide the map, so a timer never runs for a map that is hidden. `iads:isMapDisplayed()`
  answers which.
- **`iads:getDisplayMapSettings()`** answers the network's map settings, a table read on each tick, so a
  change made while the map is shown appears within a tick:
  - `layers`: the parts to draw, values defined in the map-view file: `elements`, `coverage`,
    `pointDefence`, `rangeCircles`, `labels`; all of them by default.
  - `coalition`: the coalition that sees the drawing, or `nil` for every coalition (the default). One
    value, because each DCS mark goes to one coalition or to all; two coalitions would draw every mark
    twice. A change redraws everything.
- **The radio menu.** `iads:addRadioMenu()` adds three commands, each switching its state at every call,
  under a label that does not change:
  - `Map - Show/hide`: `displayMap()`.
  - `Map - Show/hide coverage lines (EW -> SAM)`: `coverage` in `layers`.
  - `Map - Show/hide range circles`: `rangeCircles` in `layers`.

  The existing pairs, `show IADS Status` / `hide IADS Status` and `show contacts` / `hide contacts`,
  become one switching command each, the same way. A change players see in the menu: changelog and
  documentation follow.

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
- **Destroyed elements stay drawn**, dashed, at their last known position. With no timer while the map
  is hidden, a position is known from the ticks of a displayed map only: an element first drawn after
  it was destroyed is not drawn.

## Decided

1. **The view is a source file of its own, merged into the deliverable**, as
   `skynet-iads-last-line-of-defence.lua` is, and leaves the files that run the network as untouched
   as it can. Turned down: the ~15 change hooks below spread through the network logic; and a script
   shipped beside Skynet, which a mission has to load apart.
2. **Change detection is polling, not hooks.** On each tick the view compares every shown network's
   item state with what it drew, and redraws only what differs, as the prototype already does once a
   network is dirty. Turned down: the prototype's wraps of ~15 Skynet functions, which make internal
   method names an API and miss an override silently (`SkynetIADSEWRadar.setToCorrectAutonomousState`
   had to be wrapped apart); and direct `markMapViewDirty()` calls in the source, which spread the view
   through the core. Reading state each second is cheap; the only cost measured in IADS-Caucasus-Mk2,
   where the prototype runs, was drawing and the mark events it fires. A change shows up to one tick
   late, which a debug view can afford.
3. **The coverage rule lives in the core, once.** `SkynetIADSAbstractRadarElement:hasValidParentRadar()`
   exposes its per-parent half as a method of its own, and loops over it; the view calls that method
   instead of restating it (`coversSite`, `canBeCovered`). A refactor without change of behaviour; with
   the radio menu, the only change this work makes to the files that run the network.
4. **The cost of mark events is left as it is.** Every element is an event handler
   (`world.addEventHandler` in `SkynetIADSAbstractElement`), so any mark reaches all of them. The view
   draws no more marks than the prototype, since polling changes when the comparison runs, not what is
   redrawn. Marks from other scripts cost Skynet the same and are out of its control, so dispatching
   events once per network is not pursued.
5. **Menu labels.** `IADS Status - Show/hide` and `Contacts - Show/hide`, the existing pairs once they
   switch, worded as the map's commands are.
6. **Mark ids are counted from a fixed first id, `7300000` by default, which a mission can change.** DCS
   allocates no mark ids: every script picks its own, so a collision cannot be ruled out, only moved
   away from. One counter serves every network, so two networks never draw over each other's ids; the
   first id is therefore one value for all, `SkynetIADSMapView.firstMarkId`, not a per-network setting.
7. **No reload guard.** The map-view file defines its tables plainly, as the logger does its debug
   settings; the prototype's `SkynetIADSMapView = SkynetIADSMapView or {}` served reloading it in a
   running mission, which the deliverable does not do.
8. **Verification.** Lua tests for the decisions (styles from state, coverage, item state, what is
   redrawn, the switching menu commands), with `trigger.action.*ToAll` and `removeMark` stubbed. No
   in-sim check of the drawing: the in-sim tests display the map of every network they build
   (`S.iads` in `test/insim/dcs-hotload/user-lib/insim-skynet.lua`), add its radio menu, and turn on
   the debug settings `radarWentLive`, `radarWentDark` and `harmDefence`, so a run can be watched. A
   documentation page with the legend; a changelog entry.
9. **`iads:deactivate()` stops the map's timer and erases the drawing**, as `displayMap(false)` does. A
   deactivated network keeps no drawing of a state that no longer runs. One line in
   `SkynetIADS:deactivate()`.
10. **`iads:deactivate()` removes the radio menu too**, for the same reason: a deactivated network
    leaves nothing behind, and each in-sim scenario's network would otherwise leave its submenu. Only
    when a menu exists: what `missionCommands.removeItem(nil)` does is not verified. A change a
    mission can see: changelog.

## Out of scope

- Drawing contacts, or anything Skynet does not hold about its own network.
- Menu commands for `pointDefence`, `labels` or the coalition: a mission sets them through
  `getDisplayMapSettings()`.
