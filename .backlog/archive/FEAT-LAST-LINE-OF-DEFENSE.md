# FEAT-LAST-LINE-OF-DEFENSE — a dark site can notice what flies over it

Closed 2026-09-19. [PR #17](https://github.com/VEAF/Skynet-IADS/pull/17).
Measurement report kept beside this file: [in-sim-test-report-2026-09-19.md](FEAT-LAST-LINE-OF-DEFENSE-in-sim-test-report-2026-09-19.md).

## The report, and the defect behind it

The Reaper, 2026-09-17, on a VEAF mission: *"quand il y a des EWR rouge à portée, les SAM ne
s'allument pas même si on est à portée voire très proche. Quand il n'y a plus d'EWR rouge, les SAM
deviennent autonomes et actifs."*

A SAM covered by one live EWR is pulled under network control and goes dark, and **its only route
back to life is an EWR that covers it holding the target**. Proximity to the site is an input
nowhere in the cycle, because the only sensor that could measure it is the one just switched off.
Kill every covering EWR and `goAutonomous()` hands the site to the DCS AI, which lights up and
engages — hence the inversion: destroying the EWRs makes the batteries *more* dangerous.

"Covered" is weaker than it sounds: a flat 2D distance against the EWR's detection range, no
horizon, no terrain, no altitude. It says the EWR is **near** the battery, never that it is
**feeding** it.

Measured on the reporting log, 24 minutes of 5 s cycles: **7 933** SAM status lines dark under
network control, **zero** ever lit under it, and `GOING LIVE` only for the two sites with no EWR
parent.

## What was decided, and why the alternatives were refused

Three shapes were weighed. **Waking on the whole kill zone** cancels the IADS for long-range
systems — a SA-10 would light at 75 km. **Reverting the 2022 VEAF change** that stopped forcing
large systems into EW watch makes SEAD trivial. Chosen instead: a **last line of defense** — a short
*virtual* radius, Skynet's own, no DCS radar involved.

Then grilled, and these are the answers that should not be re-derived:

| point | decision |
|---|---|
| radius | 10–15 km, **drawn once per site** at build time. Per cycle, an aircraft loitering near the mean makes the site blink every 5 s |
| distance | 2D, as Skynet measures everything else |
| persistence | 45 s after the last pass. Without it a fast pass lights the site for one cycle |
| filtering | **none**. Accepted trade-off: a short-range piece can light for an aircraft it cannot reach, because requiring the kill zone would mean a Shilka (useful range ~2.5 km) never wakes inside a 10–15 km radius — and short-range pieces are the point |
| default | **on**. Off means nobody finds it and the report returns in six months. It changes existing missions |
| public door | `SkynetIADS:reportContact()` is public because VEAF's spotter network must wake a site from outside Skynet; the alternative is external code writing internal state every cycle |

## Measured in DCS, 2026-09-19

Radius drawn 10.9 km on one load and **14.1 km** on another — the per-site draw doing its job, stable
across 75 samples within a mission. Lit at 9.27 km with `targetsInRange=false` (no radar had
designated anything) and `freshReport=true`, so `reportContact` woke it. `AUTONOMOUS=false`
throughout: it lights up **while staying in the network**. Persistence **45 s to the second**, twice.

Coverage sweep: an AWACS starting at 190 km dropped the link at **211.0 km**, same on both runs, with
autonomy, parent count and child count flipping together. The 25 s lag is the 10 NM movement
threshold, not a delay.

## One departure from the ticket, deliberate

Ticket 02 asked to compare each site's **parent list** before and after a sweep. The code compares
its **autonomy** instead — a site that gains a second parent while keeping its first has a changed
list and an unchanged situation, and darkening it over that is the very defect `3a94937` fixed on
the other path. Found by `/pr-code-review`, not by a test.
