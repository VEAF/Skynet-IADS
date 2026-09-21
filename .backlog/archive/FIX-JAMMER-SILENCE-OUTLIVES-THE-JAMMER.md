# FIX-JAMMER-SILENCE-OUTLIVES-THE-JAMMER — it turned out not to, and three clean-ups around it

Closed 2026-09-19. [PR #27](https://github.com/VEAF/Skynet-IADS/pull/27).

> The lot ID keeps the claim it was opened on, which was wrong. Renaming it would have broken every
> link to it.

## The defect that was thought to matter, and does not

The lot was opened on the claim that a battery put on `WEAPON_HOLD` by a jammer was never handed
back, so an autonomous battery held fire for the rest of the mission.

**Wrong**, established during implementation. `evaluateIfTargetsContainHARMs` has always released it
ten seconds after the jammer goes quiet, on a scan `goLive()` schedules every two seconds for every
live element. Ticket 01 carried the proof, and how the wrong conclusion survived two measurements.

What was true: **that release path had no test** — which is exactly why reading the jammer did not
reveal it, and why a second release path was nearly built beside the working one. It has two now,
and `documentation/api.md` states the ten-second delay for the first time. Ticket 01 closed
🚫 wontfix: there was nothing to fix.

## The three clean-ups taken with it

`addJammer()` removed (it could never be called — `self.jammers` was never initialised, and nothing
read the field), a guard on `addRadioMenu()`, and one `jam()` per site instead of one per radar.

## Do not reopen without a new reason

**The probability curves rise with distance, and that is correct.** A jammer rides the aircraft, so
the radar's echo falls as 1/R⁴ while the jammer's own signal falls as 1/R², and the radar burns
through as the aircraft closes. Investigated 2026-09-19 down to walder's spreadsheet, closed *no
change*. `testTheCurvesRiseWithDistanceAsJammingDoes` holds the shape.

## Found along the way

`luacov` **adds** to an existing stats file, so measuring twice without clearing it reports the union
of both runs. The coverage report was fixed here.
