# A dark site told of a HARM latches its point defence live for good

Status: in-progress

## The problem

A SAM site that is dark when the network tells it of a HARM wakes its point defences, and they never
stand down. A gun point defence (a C-RAM) stays live for the rest of the mission; a missile one stays
live until it is out of missiles.

Seen in DCS on 3.6.0, in a mission that vendors it: an AI F/A-18C fired four AGM-88 at a dark SA-2.
One of the HARMs was identified, and the network told every site of it. An SA-11, dark, 36 km from
the SA-2 and protected by a C-RAM point defence, found the HARM inside its own cone
(`HARM_TO_SAM_ASPECT`, `HARM_LOOKAHEAD_NM`). Its C-RAM went live and was still live twenty minutes
later, read live from the running mission:

- point defence: `isActive() == true`, `getIsPointDefending() == true`, no target, no missile in
  flight, ammunition left;
- protected SA-11: dark (`aiState == false`), `isScanningForHARMs() == false`, one HARM in
  `objectsIdentifiedAsHarms`, aged 684 s against an `objectsIdentifiedAsHarmsMaxTargetAge` of 60 s.

A second run of the same attack reached much further. About 100 s after the last HARM was fired, 18
SAM sites of the network were silenced at once, many of them tens of kilometres from the SA-2
attacked; five
point defences were point defending; and 24 sites held at least one HARM in
`objectsIdentifiedAsHarms`, all of them dark, 18 of them with no scan running. Every point
defence of those 18 is latched for good the same way. The parents that did have a scan running
(they had been live at some point before) release theirs as designed.

## The cause

`fix-point-defence-flapping-under-harm` replaced `actAsEW` with a latch: `informOfHARM` sets it
through `pointDefencesGoLive()`, and `cleanUpOldObjectsIdentifiedAsHARMS()` releases it once the last
HARM has aged out. That clean-up runs only in the protected site's HARM scan,
`evaluateIfTargetsContainHARMs`, and the scan is started by `goLive()` alone, through
`scanForHarms()`.

A site that is live when the HARM comes has its scan running, and the latch is released as designed.
A site that is dark when the HARM comes has none: `informOfHARM` records the HARM and latches the
point defences, and nothing ever ages the HARM out or releases them. `goDark()` then keeps the
latched point defence live, as it should while a HARM is inbound, for as long as it has power and
ammunition.

The HARM silence itself is not affected. A dark site told of a HARM inside its cone goes silent
too (`goSilentToEvadeHARM`; the SA-2 attacked did, while dark), and that silence ends on its own
timer, `finishHarmDefence`. Only the point defence release depends on the scan.

The same missing scan leaves a second, quieter fault, point defence or not: a dark site never forgets
a HARM, so `objectsIdentifiedAsHarms` only grows. `shallIgnoreHARMShutdown()` weighs that count
against the point defences' missiles and launchers, so a site holding stale HARMs goes silent for
its next real one when its point defence could have taken it.

## Proposed fix

In `informOfHARM`, once the HARM is recorded (`addObjectIdentifiedAsHARM`), start the site's scan if
it is not running:

```lua
if self:isScanningForHARMs() == false then
	self:scanForHarms()
end
```

The scan then ages the HARM out, releases the point defences, and stops itself on a dark site
(`cleanUpOldObjectsIdentifiedAsHARMS` already does both). A live site's scan is left as it is.

`SkynetIADSAWACSRadar:scanForHarms()` is empty, so an AWACS is unchanged.

The guard matters: `scanForHarms()` restarts the timer, and the HARM detection informs a site of the
same HARM every cycle, so without it the scan of a live site would be pushed back each time.

The scan starts in `informOfHARM`, not in `pointDefencesGoLive()`, so that a dark site with no point
defence forgets its HARMs too.

## Tests

- Unit: a dark site with a point defence, told of a HARM inside its cone, is scanning for HARMs
  afterwards; once the HARM is older than `objectsIdentifiedAsHarmsMaxTargetAge`, the next scan
  releases the point defence, forgets the HARM and stops the scan. A live site's scan is not
  restarted by a HARM.
- In sim, `harm-point-defence-dark-site`: a dark site cannot be a HARM's target, since it emits
  nothing, so the HARM is fired at a live SA-6 acting as EW and passes over the protected site on
  its way. The protected site is an SA-2, 2.5 km east of the SA-6 (`ZONE-SITE-2`), under the
  HARM's path from the east, not acting as EW, with an SA-15 point defence; the attacker is
  invisible, so it never has a target. The site stays dark throughout, its point defence goes live
  then dark again, and its HARM count falls back to 0.
  The protected site must be one that cannot engage a HARM. A first run with an SA-10 failed for
  that reason alone: the network woke the SA-10 to shoot at the HARM, and a site gone live has its
  scan running, fix or not. For the same reason the attacker is removed once its HARM is gone:
  invisible as it is, it became a contact the network woke the SA-2 for once it reached the end of
  its route, about 280 s after it spawned, which released the point defence of the build without
  the fix. Removed straight after its shot, it took its HARM with it.
  Flown on 2026-11-18: without the fix the point defence was still live 6 min after the HARM, and
  the HARM never forgotten; with it, the point defence stood down once the HARM was forgotten.

## Out of scope

- A HARM that flies past a site while still tracked keeps the site's memory of it fresh
  (`IDEAS.md`, "A HARM that has flown past is remembered as long as a radar sees it"). This fix
  ages HARMs on a dark site the same way as on a live one, no differently.

## Open

- Whether a site that is not the HARM's target should latch its point defences at all. The cone test
  in `informOfHARM` is the only filter, and a HARM flying towards one site passes others along the
  way; the C-RAM above may have defended a site the HARM was never aimed at. That is the cone's
  behaviour, not this bug, and is left as it is here.
