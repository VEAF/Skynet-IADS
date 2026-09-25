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

| Lot | What | Status |
|-----|------|--------|
| [FEAT-BILINGUAL-DOCUMENTATION](FEAT-BILINGUAL-DOCUMENTATION/PRD.md) | The documentation site in French and English, French by default — the VMCT model, copied down to its gate | ✅ |
| [CHORE-DOCS-MANUAL-REPUBLISH](CHORE-DOCS-MANUAL-REPUBLISH/PRD.md) | Republish a released version's pages without moving its tag, so a documentation fix does not wait for the next release | ✅ |
| [CHORE-DOCS-RECENT-BEHAVIOUR](CHORE-DOCS-RECENT-BEHAVIOUR/PRD.md) | What 3.5.0 changed, moved from the API reference into the guide; the original author's donation block retired | ✅ |
| [CHORE-REPOSITORY-CONVENTIONS](CHORE-REPOSITORY-CONVENTIONS/PRD.md) | Every rule a contributor or an agent follows, in exactly one place; `CONTRIBUTING.md` becomes the source, `CLAUDE.md` keeps what prevents damage, and `docs/` disappears | 🔄 |

## Archive

Compacted on 2026-09-21: eleven lots, 59 files and 5 199 lines, down to one record each.

What a record keeps: the defect or the goal, the **decisions and why the alternatives were refused**,
the figures that were measured, the pull requests, and the notes that say *do not reopen this without
a new reason*. What it drops: the ticket-by-ticket working material, the definition-of-done
checklists and the process scaffolding — all still in git history, and most of it restated in
`CHANGELOG.md` and in the commit messages.

| Lot | Closed | Pull requests |
|-----|--------|---------------|
| [CHORE-PROFESSIONALIZE-THE-REPO](archive/CHORE-PROFESSIONALIZE-THE-REPO.md) — gitflow, backlog, changelog, agent instructions, the build and release workflows, static analysis, the published documentation site, and the migration of the legacy suites | 2026-09-20 | #10–#14, #16, #29–#31 |
| [FEAT-LAST-LINE-OF-DEFENSE](archive/FEAT-LAST-LINE-OF-DEFENSE.md) — a battery held dark by the network could not notice the aircraft overhead, and coverage was never refreshed. Adds a short virtual detection radius and a periodic coverage sweep. **Changes existing missions: on by default** | 2026-09-19 | #17 |
| [FIX-STALE-HARM-SILENCE](archive/FIX-STALE-HARM-SILENCE.md) — a site cleaned up while evading an anti-radiation missile stayed deaf for the rest of the mission, to every route back to life including the one just built. Closes issue #3 | 2026-09-19 | #18 |
| [FIX-COVERAGE-UPDATE-DARKENS-SITES](archive/FIX-COVERAGE-UPDATE-DARKENS-SITES.md) — recording that a radar covers a battery switched the battery off, including one designated onto an intruder | 2026-09-19 | #19 |
| [CHORE-TEST-COVERAGE-FLOOR](archive/CHORE-TEST-COVERAGE-FLOOR.md) — the suite ran in CI and measured nothing. 70.22% → **91.17%**, with a floor that only goes up | 2026-09-19 | #20–#24 |
| [FIX-SETUP-WARNINGS-AND-LOG-NOISE](archive/FIX-SETUP-WARNINGS-AND-LOG-NOISE.md) — a mistyped group name reached nobody, and every spawn wrote an unfilterable line. The first turned out to reverse a deliberate 2020 choice rather than repair an accident | 2026-09-19 | #25 |
| [FIX-JAMMER-SILENCE-OUTLIVES-THE-JAMMER](archive/FIX-JAMMER-SILENCE-OUTLIVES-THE-JAMMER.md) — **the defect did not exist**; the release path had always worked and simply had no test. Three agreed clean-ups shipped with the proof | 2026-09-19 | #27 |
| [FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET](archive/FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET.md) — the in-sim mission had been exercising Skynet 3.3.0 from December 2023 for three years. Missions are assembled now, and ED's own figures left the suite | 2026-09-20 | #32 |
| [FIX-DEMO-MISSIONS-SHIP-A-2023-SKYNET](archive/FIX-DEMO-MISSIONS-SHIP-A-2023-SKYNET.md) — the missions newcomers download ran Skynet 3.2. Nothing went red, because nothing there is a test | 2026-09-20 | #33 |
| [FIX-DEMO-DESTROYS-ITS-JAMMER](archive/FIX-DEMO-DESTROYS-ITS-JAMMER.md) — both Persian Gulf demos destroyed the jammer aircraft they had just armed, on every load since 2020, because a guard tested a client slot before any client could exist | 2026-09-21 | #34 |
| [FEAT-IN-SIM-SMOKE-TESTS](archive/FEAT-IN-SIM-SMOKE-TESTS.md) — seven checks driven into a running DCS through VEAF's dcs-bridge, one word per verdict. Consultative and local: a GitHub runner has no simulator | 2026-09-21 | #35 |

One measurement report is kept in full beside the records:
[FEAT-LAST-LINE-OF-DEFENSE, in-sim test report of 2026-09-19](archive/FEAT-LAST-LINE-OF-DEFENSE-in-sim-test-report-2026-09-19.md).
The montage, the protocol, every timing, and — as much to the point — what the runs do **not** cover.
Kept in full because it is a measurement nobody can re-run cheaply.
