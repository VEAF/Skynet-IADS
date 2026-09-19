# Backlog — Skynet-IADS (VEAF)

Per-lot backlog. Active lots are directories under `.backlog/<LOT-ID>/`, each holding a `PRD.md` and
one file per ticket under `tickets/`. Completed lots are compacted into
`.backlog/archive/<LOT-ID>.md`. This index is the source of truth for **scope and status**, and it
is maintained by hand.

The convention is the one used by [VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools)
and [CTLD](https://github.com/VEAF/CTLD), so that anyone moving between the three repositories finds
the same shape.

## Legend

- **Status**: ⬜ ready · 🔄 in-progress · 🧑 waiting-human · ⏸ paused · ✅ done · 🚫 wontfix
- ⏸ **paused** is *deliberately parked*, not blocked: unlike 🧑 nothing is expected of anyone, and
  unlike ⬜ an agent should not pick it up.

## Active lots

| Lot | Status |
|-----|--------|
| [FEAT-LAST-LINE-OF-DEFENSE](FEAT-LAST-LINE-OF-DEFENSE/PRD.md) — **a SAM held by the network cannot notice the aircraft overhead, and coverage is never refreshed.** Reported from a live VEAF session on 2026-09-17: fly under the EWRs' radar horizon and no battery reacts whatever the distance, then destroy the EWRs and everything reverts to the DCS AI and engages. Measured on that log: 7 933 SAM status lines dark under network control, **zero** ever lit in 24 minutes. Adds a short virtual detection radius that wakes a dark site on close proximity, and a periodic coverage refresh — because the incremental rebuild used for a moving AWACS never purges, so an aircraft in transit accumulates every battery it has flown near and holds them all non-autonomous. **Both tickets are done**: the code, its 28 tests and the documentation are written; the in-sim check through VEAF's DCS bridge is what is left | 🔄 |
| [FIX-STALE-HARM-SILENCE](FIX-STALE-HARM-SILENCE/PRD.md) — **a site cleaned up while it is evading an anti-radiation missile is deaf for the rest of the mission.** `cleanUp()` cancels the HARM timers but leaves `harmSilenceID` set, and nothing will ever clear it — the task that would have is the one just removed. `goLive()` refuses while that field is set, so the site is closed to network designation, to autonomy, **and to the last line of defense and `reportContact` added in FEAT-LAST-LINE-OF-DEFENSE**. Reached by any `addSAMSitesByPrefix()` call, which VEAF missions make on respawn. From [issue #3](https://github.com/VEAF/Skynet-IADS/issues/3), in walder's original. **Ticket 02 was added while checking that premise**: a `*ByPrefix` call leaves every element it discards wired into the coverage graph, so a battery keeps a dead EW radar as a valid parent and stays dark under nobody's watch. Merged as [PR #18](https://github.com/VEAF/Skynet-IADS/pull/18), issue #3 closed | ✅ |
| [FIX-COVERAGE-UPDATE-DARKENS-SITES](FIX-COVERAGE-UPDATE-DARKENS-SITES/PRD.md) — **declaring that a radar covers a battery switches the battery off.** `buildRadarAssociation()` records the link through `addParentRadar()`, which ends in `informChildrenOfStateChange()` and therefore `goDark()` — so adding an EW radar during a mission darkens every battery in its range, including one designated onto an intruder and not yet locked on, for one contact cycle. It is also 250 state notifications during an `activate()` where 10 are needed. `FEAT-LAST-LINE-OF-DEFENSE` wrote `addParentRadarWithoutStateChange()` for exactly this and converted the other caller; this is the one it missed. Found while instructing FIX-STALE-HARM-SILENCE ticket 02 | 🔄 |
| [CHORE-PROFESSIONALIZE-THE-REPO](CHORE-PROFESSIONALIZE-THE-REPO/PRD.md) — **bring this repository up to the standard of the other two VEAF projects.** It already has a Lua 5.1 test suite and a CI that runs it; it has no backlog, no changelog, no agent instructions, no automated release, no static analysis, no published documentation, and its build script cannot run on the CI runner. The legacy in-sim suites are still waiting to be migrated | ⬜ |
