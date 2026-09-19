# 06 — the long tail

Status: ✅ done — merged in [PR #24](https://github.com/VEAF/Skynet-IADS/pull/24). It was not the margin, it was the whole remaining gap: the project went 86.81% → **91.17%** and the floor 86 → **91**, which closes the lot. The jammer, the launcher, the contact, the table delegator, the abstract element and the MOOSE connector are at 100%; the HARM decision is at 98%. Nothing was deleted — see below

What is left once tickets 03, 04 and 05 have landed: 119 lines across nine files, none of them a
block.

| File | Lines never run | The shape of it |
|---|---:|---|
| `skynet-iads-jammer.lua` | 29 | `addRadioMenu` (9), `create` (6), `updateMasterArm` (6), line of sight and distance helpers |
| `skynet-iads-utils.lua` | 26 | `getDir` (6), `getHeadingPoints` (6), `makeVec3` (5), `runScheduledTask` (4), 5 at top level |
| `skynet-iads-harm-detection.lua` | 21 | `evaluateContacts` (13), `informRadarsOfHARM` (4) |
| `skynet-iads-abstract-dcs-object-wrapper.lua` | 13 | 10 of them in the `inheritsFrom` helper — `isa`, `create`, `class` |
| `skynet-iads-sam-launcher.lua` | 9 | `setupRangeData` (5) |
| `skynet-iads-sam-search-radar.lua` | 7 | `setupRangeData` (4) |
| `skynet-iads-contact.lua` | 5 | five one-line getters |
| `skynet-iads-abstract-element.lua` | 5 | five one-line getters |
| `skynet-iads-table-delegator.lua` | 4 | `create` |
| `skynet-mooose-a2a-dispatcher-connector.lua` | 1 | `addIADS` |

## What is worth taking, and what is not

**Worth it.** `SkynetIADSHARMDetection:evaluateContacts` (13 lines) is the decision of whether a
contact is an anti-radiation missile and who to warn — real logic, and
`FIX-STALE-HARM-SILENCE` exists because that area is easy to get wrong. The jammer's
`updateMasterArm` and line-of-sight helpers are real branches. `setupRangeData` on the launcher and
the search radar reads the type database and is what makes a battery know its own range.

**Not worth a test.** The 10 lines in `inheritsFrom`'s `isa` / `class` helpers are an inheritance
utility nothing in the sources calls; the one-line getters on `contact` and `abstract-element` are
`return self.field`. A test there buys percentage points and no safety.

But *not worth a test* is not the same as *leave it*. Where the helper is genuinely dead, **delete
it** — that raises the number honestly, by shrinking the denominator instead of padding the
numerator, and it is the better outcome of the two. Where it is public surface a mission maker
might call, leave it uncovered and write down that the decision was taken.

## How much room there is

90% of 2 391 leaves **239 lines** that may stay uncovered for good. This ticket's tail is 120 of
them. So:

- If tickets 03, 04 and 05 all land complete, the project sits at 94.98% and this ticket is free to
  take only what is worth taking.
- If ticket 04 stalls on the legacy port, the project sits at 83% and **these 120 lines are the only
  ones left to take** — and they are not enough on their own. That is the situation where the lot is
  blocked, and no amount of tail work fixes it.

Read the current measurement before starting, not this paragraph.

## Definition of done

- `evaluateContacts`, the jammer's master arm and both `setupRangeData` are covered.
- Every remaining uncovered function is either covered, deleted as dead, or listed here with the
  reason it stays uncovered — no function is left in the report with nobody having looked at it.
- The floor reads 90 or better, or the lot says in writing what is holding it below.

## What was done, and what was decided instead

The ticket said to read the current measurement rather than its own estimate, and the measurement had moved: 77 lines short of 90%, with **118 reachable lines** outside the file ticket 04 is waiting on. The 27-line difference between that and the 145 uncovered is continuation lines of multi-line expressions, which Lua 5.1 attributes to the first line of the expression — no test can ever reach them, and counting them as work makes a target unreachable for no reason.

Taken, in the ticket's own order of value: the anti-radiation-missile decision (the half that says *no*, the identification taken back when a track manoeuvres, and the handing of a confirmed missile to every usable element); the jammer entire; both `setupRangeData` implementations and the delegation between them, in a new `test_skynet_iads_range_data.lua`; the geometry the HARM aspect is built on; and the table delegator that makes every one-liner in `api.md` work.

**Nothing was deleted.** `inheritsFrom`'s `class()`, `isa()` and default `create()` are dead inside this repository — checked across the sources, `test/lua` and `unit-tests` — but they are methods on every Skynet object and the artifact is vendored by VEAF-Mission-Creation-Tools. Deleting undocumented public surface from a vendored deliverable is VEAF's decision, not a side effect of a coverage ticket.

**Every remaining uncovered line is accounted for**, in `test/lua/README.md` rather than here so it sits where the next person writing a test will read it: the block waiting on the legacy port (173), continuation lines (34), the inheritance helper (11), a Lua 5.2 compatibility shim that cannot run under 5.1 (5), and `SkynetIADS:addJammer()` (1), which cannot be called at all because `self.jammers` is never initialised.

## Found on the way, not fixed here

The jammer probability curves **rise with distance**. Measured: an SA-2 reads 91 at 0 NM, 119 at 10 NM and 4x10^14 at 100 NM, and `SkynetIADSAbstractRadarElement:jam()` compares that figure with `math.random(1, 100)`, so anything at or above 100 jams with certainty. A jammer is therefore at its weakest sitting on top of the battery and unbeatable from a hundred miles away, until it crosses the 200 NM cutoff in `maximumEffectiveDistanceNM` and stops working entirely.

That looked inverted. **It is not** — investigated 2026-09-19, and the conclusion is *no change*.

The spreadsheet the comment at the top of `skynet-iads-jammer.lua` links to is public and still up. It holds one sheet, seven systems, columns *Distance NM (x)* and *Jammer probability (Y)*. Its values match the formulas in the code to within 0.51% once both are capped at 100, so it is a plot of the code rather than a specification the code was meant to meet — there is no independent intent recorded anywhere to check the formulas against.

It settles two things all the same.

**The rising shape is deliberate, and it is right.** Seven curves, all rising, tabulated on purpose. It also matches how jamming works: the jammer rides the aircraft, so the radar's echo off that aircraft falls as 1/R^4 while the jammer's own signal only falls as 1/R^2. The jammer therefore dominates at range and the radar burns through as the aircraft closes. A curve that rises with distance is the expected shape, not an inversion.

**What is genuinely unbounded is the range, not the direction.** walder's tables stop at 35 NM (60 for the SA-10, 18 for the SA-15) and he left the saturation visible — his SA-8 column reads 434 at 20 NM and 36,478 at 35 NM. The code applies those same formulas out to the 200 NM in `maximumEffectiveDistanceNM`, which nobody ever plotted. The hierarchy he was aiming for is legible at contact (SA-2 91%, SA-3 81%, SA-8 31%, SA-6 24%, SA-11 16%, SA-10 and SA-15 6% — older systems jammable, modern ones not) and has vanished by 20 NM, where everything but the SA-10 and the SA-15 is certain.

Three options were put to David on 2026-09-19 — bound the range per system, flatten the curves so none reaches 100%, or leave it and document it. **He chose to leave the jammer alone.** `setMaximumEffectiveDistance()` is already there for a mission that wants a shorter reach. Reopening this needs a new reason, not a rereading of the curves.

`testTheCurvesRiseWithDistanceAsJammingDoes` pins the shape — renamed from `…WhichIsSurprising`, because it is not. The shape is now endorsed rather than merely recorded.
