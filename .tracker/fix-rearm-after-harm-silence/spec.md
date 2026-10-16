# A site silenced by HARM defence gets its AI back, so it can be rearmed

Status: in-progress

## The problem

A DCS ammo truck does not rearm a unit whose AI is off. It rearms it within 30–60 s once the AI is
back on. Emission off, Skynet's dark state and a partial load do not prevent a rearm; only the AI
being off does. (DCS 2.9.30, Tor M2 and Ural-375: drained, AI off, not rearmed in 900 s on two
pairs; AI back on, full in 75 s.)

Skynet turns a site's AI off in one place: `goDark()` while HARM defence is silencing it
(`harmSilenceID` set), against a DCS multiplayer bug where a HARM still finds an emitter whose
emission alone is off. Only `goLive()` turns it back on:

- `finishHarmDefence()` clears the silence but leaves the AI off;
- `goLive()` refuses a site with no ammunition left.

So a site that ran out of missiles and was then silenced is off for the rest of the mission: no
truck will ever rearm it, and without ammunition it never goes live again. A site that still has
missiles stays off, unrearmable, until its next contact. An autonomous site is no different:
`goAutonomous()` calls `goDark()` or `goLive()`, and neither turns the AI back on for an empty site.

`cleanUp()` clears `harmSilenceID` the same way, so a site discarded mid-silence — by
`addSAMSitesByPrefix` re-adding the IADS's sites — leaves its DCS group off, and the site created
for the same group starts with `goLive()`, which refuses it if it is empty.

## What to build

When a silence ends, the AI goes back on and emission stays off — the state a dark site is in
outside HARM defence:

```lua
function SkynetIADSAbstractRadarElement.finishHarmDefence(self)
	SkynetIADSUtils.removeFunction(self.harmSilenceID)
	self.harmSilenceID = nil
	self.harmShutdownTime = 0
	if self:isDestroyed() == false then
		self:getController():setOnOff(true)
	end

	if self:getAutonomousState() == true then
		self:goAutonomous()
	end
end
```

`cleanUp()` does the same where it clears `harmSilenceID`, when a silence was under way.

`goSilentToEvadeHARM()` no longer calls `finishHarmDefence()`: it cancels the silence under way,
if any, with `SkynetIADSUtils.removeFunction(self.harmSilenceID)`, then starts the new one.
`finishHarmDefence()` runs only when a silence ends.

## Decisions

- **AI on, emission off.** It is a dark site's normal state: a Skynet site under the network sits
  that way between contacts, and in it DCS rearms the site and its radar does not emit. The silence
  itself keeps the AI off, as now, for the multiplayer bug.
- **No change to `goLive()`'s ammunition check.** An empty site has no reason to emit; it needs its
  AI only to be rearmed.
- **A new silence does not finish the one under way.** A second HARM can silence a site already
  silent. Through `finishHarmDefence()`, the AI would come back on, and `goDark()`, which does
  nothing for a site already dark, would not turn it off again: the site would sit through the new
  silence with its AI on. All the new silence needs from the old one is that its timer stops. The
  `goAutonomous()` it also ran is dropped with it: on an autonomous DCS-AI site it lit the radar and
  `goDark()` put it out in the same frame. Turning the AI back off in `goSilentToEvadeHARM()`
  instead was turned down: it switches the AI on and off in the same frame for nothing.

## Tests to follow

Standalone suite:

- `finishHarmDefence` turns the controller back on, for a site with and without ammunition;
- it does not touch the emission;
- an autonomous site in either behaviour ends the silence with its controller on;
- `cleanUp` mid-silence turns the controller back on; outside a silence it does not call `setOnOff`;
- a destroyed site: no call;
- a second silence during the first keeps the controller off until the second one ends.

## Before merging

In DCS: a site under Skynet, drained, with a truck beside it, then silenced by HARM defence (HARM
detection on, a HARM fired at it). Without the fix it is never rearmed; with it, it is rearmed within
a minute or two of the silence ending, and goes live for its next contact.

## Changelog

A fix: a site that HARM defence silenced after it ran out of missiles is rearmed again by nearby
ammo trucks.
