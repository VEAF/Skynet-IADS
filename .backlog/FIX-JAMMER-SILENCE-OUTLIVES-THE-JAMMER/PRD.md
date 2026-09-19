# FIX-JAMMER-SILENCE-OUTLIVES-THE-JAMMER — shoot the jammer down and the batteries stay mute

Status: ⬜ ready

Origin: found on 2026-09-19 while explaining what `FIX-SETUP-WARNINGS-AND-LOG-NOISE` deliberately
left out. Three of the four were already recorded as *found on the way, not fixed*; the fourth came
out of measuring one of them and is the reason this lot exists.

## The defect that matters

`SkynetIADSJammer.runCycle` decides, every ten seconds and for every active SAM site in range, to
put that site's controller on `WEAPON_HOLD` or on `WEAPON_FREE`. While the jammer flies, the site is
rewritten on every cycle, so the roll is re-taken and nothing accumulates.

**When the cycle stops, the last state written stays.** The emitter is destroyed and `runCycle`
calls `masterArmSafe()` and returns; the jammer flies past 200 NM; a ridge comes between it and the
radar. In all three cases nothing hands the site back. Measured against the DCS stub:

```
jammer alive:     jam() called 1 time(s), ROE now WEAPON_HOLD
jammer destroyed: jam() called 0 time(s) over 6 cycles, ROE still WEAPON_HOLD
```

The only code that restores `WEAPON_FREE` is `SkynetIADSAbstractRadarElement:goLive()`, and it is
guarded by `aiState == false` — it runs on a site that was dark, not on a site that is already live.
So how long the silence lasts depends on what kind of site it is:

| Site | What happens |
|---|---|
| Under network control | goes dark and live again as contacts come and go, so it frees itself at the next `goLive()` — verified: `goDark()` then `goLive()` restores `WEAPON_FREE` |
| **Autonomous** (handed back to the DCS AI) | stays live for good, never passes through `goLive()` again, so it **holds fire for the rest of the mission** |

And an autonomous site is jammable: `isActive()` is `true` and it is in `getActiveSAMSites()`.
Verified.

In game this is the report that keeps coming back from sessions: *I shot the jammer down and the
battery still will not fire.*

## Three more, agreed at the same time

All three were already written down as found-but-not-fixed, in `CHORE-TEST-COVERAGE-FLOOR` ticket 06
and in `test/lua/README.md`. David decided on 2026-09-19 to take them with the defect above, since
they are in the same files.

## What to do

| | Ticket |
|---|---|
| 1 | [the silence that outlives the jammer](tickets/01-the-silence-that-outlives-the-jammer.md) |
| 2 | [addJammer cannot be called, and is removed](tickets/02-add-jammer-is-removed.md) |
| 3 | [addRadioMenu issues its menu twice](tickets/03-a-guard-on-the-radio-menu.md) |
| 4 | [one jam() per radar, where one per site is meant](tickets/04-one-jam-call-per-site.md) |

One branch, one pull request for the lot. Tickets 1, 2 and 4 touch `skynet-iads-source/`, so the
artifact has to be rebuilt and `CHANGELOG.md` updated under `[Unreleased]`.

## What this lot does not touch

**The probability curves.** They rise with distance, which is the right way round — a jammer rides
the aircraft, so the radar's echo falls as 1/R⁴ while the jammer's own signal only falls as 1/R², and
the radar burns through as the aircraft closes. Investigated on 2026-09-19 down to walder's
spreadsheet, and closed: *no change*. The reasoning is at the end of `CHORE-TEST-COVERAGE-FLOOR`
ticket 06, and `testTheCurvesRiseWithDistanceAsJammingDoes` holds the shape. Do not reopen this
without a new reason.

## Definition of done

- A site stops being held the moment the jammer stops jamming it, whatever the reason — emitter
  destroyed, out of range, line of sight lost.
- `SkynetIADS:addJammer()` is gone, and the source says where it went and why.
- A second `addRadioMenu()` call is a no-op, and `removeRadioMenu()` still works after it.
- One `jam()` call per site per cycle.
- The artifact is rebuilt and `CHANGELOG.md` records what a mission maker will notice.
