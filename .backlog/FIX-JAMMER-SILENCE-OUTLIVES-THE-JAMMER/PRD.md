# FIX-JAMMER-SILENCE-OUTLIVES-THE-JAMMER — it turned out not to, and three clean-ups around it

> The lot ID keeps the claim it was opened on, which was wrong. Renaming the directory would break
> every link to it; the correction is below and in ticket 01.

Status: ✅ done — merged as [PR #27](https://github.com/VEAF/Skynet-IADS/pull/27)

Origin: opened on 2026-09-19 while explaining what `FIX-SETUP-WARNINGS-AND-LOG-NOISE` deliberately
left out. Three of the four tickets were already recorded as *found on the way, not fixed*. The
fourth, which was the reason for the lot, turned out not to be a defect at all — see below.

## The defect that was thought to matter, and does not

This lot was opened on the claim that a battery put on `WEAPON_HOLD` by a jammer was never handed
back when the jammer stopped jamming it, and that an autonomous battery therefore held fire for the
rest of the mission.

**That is wrong**, established during implementation on 2026-09-19.
`SkynetIADSAbstractRadarElement.evaluateIfTargetsContainHARMs` has always released it, ten seconds
after the jammer goes quiet, on a scan `goLive()` schedules every two seconds for every live
element. Ticket 01 carries the proof, and how the wrong conclusion survived two measurements.

What was true, and is what ticket 01 delivered instead: **that release path had no test**, which is
exactly why reading the jammer did not reveal it and why a second release path was nearly built
beside it. It has two now, and `documentation/api.md` states the ten-second delay for the first
time.

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

- The existing release path — ten seconds after the jammer goes quiet, whatever the reason — is
  covered by tests and documented, rather than duplicated.
- `SkynetIADS:addJammer()` is gone, and the source says where it went and why.
- A second `addRadioMenu()` call is a no-op, and `removeRadioMenu()` still works after it.
- One `jam()` call per site per cycle.
- The artifact is rebuilt and `CHANGELOG.md` records what a mission maker will notice.
