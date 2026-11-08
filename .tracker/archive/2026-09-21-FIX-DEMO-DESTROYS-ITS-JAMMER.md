# FIX-DEMO-DESTROYS-ITS-JAMMER — the demo killed the aircraft it had just armed

Closed 2026-09-21. [PR #34](https://github.com/VEAF/Skynet-IADS/pull/34).

Found 2026-09-20 flying the refreshed demo for `FIX-DEMO-MISSIONS-SHIP-A-2023-SKYNET`, recorded
rather than fixed so that lot stayed on its subject, reopened 2026-09-21 before cutting the first
release.

## The defect

`skynet-iads-setup-persian-gulf.lua` ended its jammer section with a guard of walder's
(`5561910e`, 2020-03-23) that removes the AI F-4E when nobody occupies the `Hornet SA-11-2 Attack`
slot. Reasonable intent — the jammer takes off in formation with the player.

Never honoured. The script runs at `triggerStart`, and that slot is a **client slot**
(`["skill"] = "Client"`), which has no `Unit` until a player occupies it — impossible before the
mission has started. So `Unit.getByName` returned nil on every load and the guard always fired.

**Two missions, not one.** `skynet-test-persian-gulf.miz` and its stress-test sibling load the same
setup script and carry the same two units, so one deletion repaired both. Not a regression: the
Hornet group is byte-identical in the December 2023 archive and was already `Client`.

## The decision

Three options: delay the guard, drop it, or hook it to `S_EVENT_BIRTH`. **David chose to drop it**
(2026-09-21). A delay stays a bet — a long briefing loses the race again, silently, which is how this
survived six years — and the event-handler version means twenty lines of DCS plumbing in a file whose
job is to be read as an example. walder's own comment says the block has nothing to do with the IADS.

What it costs, stated: with no player in the slot, the F-4E flies its route alone and jams the red
network anyway. For a demo about jamming, the better failure.

## Measured in DCS, 2026-09-21, both directions

Through the `jammer-alive` check of the smoke gate built in the sibling lot: **`emitter-gone`** on a
build without this fix — measured *while David occupied the `Hornet SA-11-2` slot*, which settles
from the simulator that the guard never depended on the slot it tests — and **`alive`** with it, 5/5
checks green, the network then reporting the F-4E as a contact at 53 NM.

## One piece of evidence withdrawn

An earlier draft cited *"zero `SKYNET: JAMMER:` lines in the log"* as proof the jammer was dead.
Measured on the **fixed** build, jammer alive and tracked: still zero, because the jammer only logs
within `maximumEffectiveDistanceNM` of a *live* radar, a geometry that run never reached. Consistent
with both states, so it proves neither. What discriminates: the F10 `Jammer:` submenu missing between
two that are present, and `Unit.getByName` returning nil in flight.
