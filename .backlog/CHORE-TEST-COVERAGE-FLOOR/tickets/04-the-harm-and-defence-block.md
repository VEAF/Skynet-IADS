# 04 — the HARM and defence block of the radar element

Status: ⬜ ready — **the work lives in `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04**, this one
measures it. At the lot's 90% target it is also the ticket the target depends on.

`skynet-iads-abstract-radar-element.lua` is **71.25%** — 184 lines never executed, the second worst
block in the project, in the class that carries `goLive`, `goDark`, autonomy and HARM evasion.

| Function | Lines never run |
|---|---:|
| `informOfHARM` | 22 |
| `jam` | 16 |
| `getElementPosition` | 13 |
| `setGoLiveRangeInPercent` | 9 |
| `cleanUpOldObjectsIdentifiedAsHARMS` | 8 |
| `weaponFired` · `updateMissilesInFlight` · `goSilentToEvadeHARM` · `shallIgnoreHARMShutdown` | 7 each |
| `getDetectedTargets` · `getSecondsToImpact` · `calculateAspectInDegrees` | 6 each |
| `pointDefencesHaveRemainingAmmo` · `hasEnoughLaunchersToEngageMissiles` | 5 each |

## The tests already exist

`unit-tests/test-skynet-iads-abstract-radar-element.lua` is 50 legacy in-sim tests, of which 8 are
ported — the autonomy / coverage cluster, ported by `FEAT-LAST-LINE-OF-DEFENSE`. The 42 that remain
are listed in `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04 as *"HARM timing and defence states, point
defence, the SA-2 range tests, ammo and missiles-in-flight, parent/child bookkeeping, cached targets
and aspect"*.

Put that list beside the table above and they are the same list. **The 184 lines are not untested
behaviour, they are behaviour whose tests only run inside DCS** — which means they have not run at
all since the standalone suite became the gate.

## What to do

Nothing new. Take the next slices of `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04, in its own lot and
its own pull requests, under its own rules — in particular *"porting a test is not copying it"*:
these tests ran against real DCS objects and will need the stub extended deliberately, with the real
behaviour written down.

This ticket exists for two reasons only:

1. So the climb to 90% accounts for it. It is worth 184 lines — and with ticket 03's 310, the two
   together are 494 of the 473 needed. **Either one alone falls short**: the logger alone stops at
   83.19%, this block alone at 78.
2. So the number gets recorded. Each ported slice raises the floor by what it bought, in the pull
   request that ported it.

Which makes this the one ticket of the lot that is not self-contained, and the one to watch. If the
legacy port stalls, this lot stalls at 83% with ticket 06's 120 lines as its only way forward — and
that is a lot blocked on another lot, to be said out loud rather than left sitting at 🔄.

Close this ticket as *done* when the legacy port is complete, or as *no longer needed* in the
unlikely case the lot reaches 90 without it.

## Definition of done

- `skynet-iads-abstract-radar-element.lua` above 85%.
- The floor has been raised once per ported slice, not once at the end.
- No behaviour is covered twice by a legacy and a standalone suite — that rule belongs to the other
  ticket and this one does not relax it.
