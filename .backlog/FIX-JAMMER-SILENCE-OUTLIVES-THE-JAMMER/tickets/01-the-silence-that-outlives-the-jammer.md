# 01 — the silence that outlives the jammer

Status: 🚫 wontfix — **the defect does not exist.** Established 2026-09-19, during implementation.

## What this ticket claimed

That a battery put on `WEAPON_HOLD` by a jammer was never handed back when the jammer stopped
jamming it — destroyed, switched off, out of range, line of sight lost — because the only code
restoring `WEAPON_FREE` was `goLive()`, which runs on an element that *was dark*. An autonomous
battery, never going dark, would therefore hold fire for the rest of the mission.

## Why that is wrong

`SkynetIADSAbstractRadarElement.evaluateIfTargetsContainHARMs` has done it all along, and says so:

```lua
--if an emitter dies the SAM site being jammed will revert back to normal operation:
if self.lastJammerUpdate > 0 and (timer:getTime() - self.lastJammerUpdate) > 10 then
    self:jam(0)
    self.lastJammerUpdate = 0
end
```

`jam(0)` is a probability no roll can beat, so it sets `WEAPON_FREE`. `goLive()` schedules that scan
**every two seconds** on every live element, autonomous ones included. Measured against `develop`,
with no new code: an autonomous battery, jammed, emitter destroyed, is back on `WEAPON_FREE` twelve
seconds later.

## How the wrong conclusion was reached, twice

Worth writing down, because both mistakes are easy to repeat here.

1. **The first measurement only ran the jammer's own cycle.** `SkynetIADSJammer.runCycle` is not
   where the release lives, so it never fired. The site stayed held, which looked like proof.
2. **The second measurement ran the scan, and still showed the site held.** The stub's clock starts
   at 0, so `jam()` stamped `lastJammerUpdate = 0`, and the guard `lastJammerUpdate > 0` can never
   pass. A mission is never at t=0 when a jammer acts. With the clock advanced first, it works.

A measurement that does not exercise the mechanism says nothing about the mechanism.

## What was done instead

The release path had **no test at all** — which is why reading the jammer did not reveal it. Two
now cover it, in `test/lua/test_skynet_iads_abstract_radar_element.lua`:
`testAJammedSiteIsReleasedTenSecondsAfterTheJammerStops` and `testTheReleaseHappensOnceNotOnEveryScan`.
Three deliberate mutations of the block above each turn one of them red.

`documentation/api.md` now states the ten-second delay, which it never mentioned.
