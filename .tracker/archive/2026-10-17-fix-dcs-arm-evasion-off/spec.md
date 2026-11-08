# DCS's own "Evasion of ARM" is turned off on every IADS group

Status: done

## The problem

DCS has a ground AI option, `AI.Option.Ground.id.EVASION_OF_ARM` (id 31, boolean). With it on, the
unit an anti-radiation missile is aimed at reacts on its own, outside Skynet:

- its radar goes dark 10–20 s after it detects the missile, and stays dark while missiles are
  inbound, blinking on for a second now and then;
- a mobile single vehicle drives off: an Osa and a Tor moved 250–400 m, with dispersal off;
- it may stop engaging: a Tor, which shoots HARMs down, fired nothing.

This competes with Skynet's HARM defence, which decides when a site goes dark and whether a
HARM-capable site stays up to engage. Unset, the option behaves as off; a mission maker can set it
in the Mission Editor.

## What to build

Each time a SAM site or an EW radar goes live, `goLive()` sets the option off on the element's
controller, beside `ALARM_STATE` and `ROE`, which it already sets there:

```lua
if AI.Option.Ground.id.EVASION_OF_ARM then
	controller:setOption(AI.Option.Ground.id.EVASION_OF_ARM, false)
end
```

The guard keeps older DCS builds, without the option, working.

The controller is the one `goLive()` already uses: the group's for a SAM site, the unit's for an EW
radar. DCS honours the option set on a ground unit's own controller.

An option holds whatever was set last, so setting it once when the element is added is not enough:
the mission can set it on afterwards — the editor's waypoint action when a late-activated group is
activated, a later waypoint, a trigger, or a Skynet started after the group's own setting. DCS reacts
to an ARM only while the radar emits, and `goLive()` is the only place Skynet turns emission on, so
re-asserting the option there takes it back each time the radar comes on.

Not for AWACS radars, airborne or naval: `SkynetIADSAWACSRadar` overrides the method that sets it
with a no-op, as it does `scanForHarms()`.

## Decisions

- **Off, always, overriding the Mission Editor.** Two systems deciding when the same radar emits
  contradict each other; Skynet's HARM defence is the one Skynet configures and documents.
- **No opt-out setter** until someone asks for one.
- **In `goLive()`, not once when the element is added**, nor every contact cycle. Once at add time
  loses to any setting the mission makes afterwards. Every cycle would also catch a setting changed
  while the radar is live, at one `setOption` per element every 5 s; that case is rare and is left
  until someone reports it.

## Out of scope

- An option set on by the mission while the radar is already live holds until the radar's next
  go-live. An EW radar is typically live all mission.

## Before merging

An in-sim check: on a group Skynet has added, the option set **on after** Skynet added it — as a
later waypoint or trigger would — is off again once the site has gone dark and live again, and the
site no longer goes dark or moves when a HARM is aimed at it.

## Tests to follow

- a SAM site, and an EW radar, going live sets the option off on its controller;
- going live again sets it again;
- an AWACS radar going live does not set it;
- with `AI.Option.Ground.id.EVASION_OF_ARM` absent from the stubs, going live does not fail.

## Documentation and changelog

A sentence in the HARM defence section of `documentation/` (both languages): Skynet turns DCS's
"Evasion of ARM" off each time a SAM site or EW radar goes live, whatever the mission sets. A
changelog entry saying the same.
