# FIX-DEMO-MISSIONS-SHIP-A-2023-SKYNET — the missions newcomers open run Skynet 3.2

Status: ✅ done — merged 2026-09-20 as [PR #33](https://github.com/VEAF/Skynet-IADS/pull/33)

Origin: found on 2026-09-20 while closing `FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET`. That lot fixed the
same defect in the *test* missions; this one is about the *demo* missions, which are worse placed —
they are what somebody downloads to learn what Skynet does.

## The defect

Three of the four missions under `demo-missions/` carry their own copy of the deliverable, and it is:

```
SKYNET VERSION: 3.2 | BUILD TIME: 29.12.2023 1905Z
```

| mission | Skynet inside | last touched |
|---|---|---|
| `skynet-test-persian-gulf.miz` | **3.2**, 29.12.2023 | 2023-12-29 |
| `skynet-test-persian-gulf-stress-test.miz` | **3.2**, 29.12.2023 | 2023-12-29 |
| `moose_a2a_connector/skynet-and-moose-a2a-dispatcher.miz` | **3.2**, 29.12.2023 | 2023-12-29 |
| `skynet-insim-last-line-of-defence.miz` | 3.5.0, 19.09.2026 | 2026-09-19 |

`develop` is on 3.5.0. So a newcomer who opens the Persian Gulf demo to see how an IADS behaves is
watching **Skynet 3.2, from December 2023** — not the version they just downloaded, and not the one
the documentation describes. Three years and two minor versions of behaviour changes are missing,
including everything `FEAT-LAST-LINE-OF-DEFENSE` and `FIX-COVERAGE-UPDATE-DARKENS-SITES` added.

Worse than the test suite, in one respect: nothing here is a test, so nothing goes red. A demo that
behaves unlike the shipped code is indistinguishable from a demo that behaves like it.

### The setup scripts drifted too, in both directions

Each mission also carries a copy of its setup script, and those copies are not the loose files
either — measured 2026-09-20, line endings normalised:

| mission | its copy of the setup script |
|---|---|
| `skynet-test-persian-gulf.miz` | **differs** from `demo-missions/skynet-iads-setup-persian-gulf.lua` |
| `skynet-test-persian-gulf-stress-test.miz` | same |
| `moose_a2a_connector/…` | **differs** from its loose copy |
| `skynet-insim-last-line-of-defence.miz` | **differs** from the loose copy it uses |

Three out of four. Somebody edited the loose file, or the one inside the archive, and the other never
followed — the same drift `FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET` found in the test missions, where it
turned out four tests had never run once.

### MiST is still in all four

Every one loads `mist_4_5_107.lua`, 312 KB of it. Skynet stopped needing MiST on 2026-08-30
(`fe40c4a`), and the loose setup scripts make **zero** MiST calls — except
`moose_a2a_connector/skynet-and-moose-a2a-dispatcher-setup.lua:69`, which has exactly one:

```lua
mist.scheduleFunction(outputNames, self, 1, 2)
```

`SkynetIADSUtils.scheduleFunction` is the drop-in replacement, and it is the same swap ticket 02 of
the previous lot made in the test harness.

The 2023 artifact still calls MiST 33 times, so MiST cannot leave until the artifact is current —
same ordering as before.

## Why it matters

The deliverable is vendored by
[VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools), and the published
documentation tells people to load `skynet-iads-compiled.lua` into their mission. The demo missions
are the worked example beside that instruction. When the example runs a three-year-old build, every
difference a reader notices between the demo and their own mission is noise they cannot explain —
and the first thing anyone does with a demo is copy it.

`FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET` ticket 05 built the machinery that fixes this:
`build-tools/miz-suite.py` assembles a mission from placeholders. Pointing it at `demo-missions/` is
mostly configuration. **Mostly** — see ticket 03.

## What this lot does not decide

**Whether a demo mission may stop being playable straight out of the repository.** The test missions
became templates, which is fine: only developers open those. A demo is different — somebody clones
or downloads this repository to *run* it. Three readings are written up in ticket 03 and they lead
to different work. That is David's call, not something to settle while doing the rest.

## Tickets

| # | Title | Status |
|---|-------|--------|
| 01 | [Assemble the demo missions instead of committing a copy of the code](tickets/01-refresh-what-the-demos-carry.md) | ✅ |
| 02 | [Take MiST out of the demo missions](tickets/02-take-mist-out-of-the-demos.md) | ✅ |
| 03 | [Decide whether a demo may need assembling](tickets/03-decide-if-a-demo-may-need-assembling.md) | ✅ |

Order: **03 first** — it decided the shape of 01, and 01 was rewritten to match. Then 01, then 02,
because MiST cannot leave while the artifact in the mission still calls it.

## Watch out for

**Two files inside these archives are not in the repository at all**: `Moose.lua` (in the MOOSE demo)
and `dcs-bridge.lua` (in the last-line-of-defence demo). Whatever 01 does, it has to keep them —
`miz-suite.py` has `NO_SOURCE_IN_REPO` for exactly this, and it is currently empty. Vendoring MOOSE
into this repository is not proposed; it is 1.1 MB and belongs to another project.

**These are judged in DCS, and more subjectively than a test suite.** A test mission answers with a
pass count. A demo answers with "does it still demonstrate what it is for", which needs somebody to
fly it. `skynet-test-persian-gulf.miz` is the one the documentation points at; the stress test is the
one where a wrong answer is least visible.

**`skynet-insim-last-line-of-defence.miz` is current and was built on 2026-09-19.** It is in this lot
for MiST and for its drifted setup script, not for a stale artifact. Do not "refresh" it into
something nobody has run.

## Blocked on nobody, and worth saying out loud

**This repository has published no GitHub release** — `gh release list` on `VEAF/Skynet-IADS` is
empty, and cutting one is manual (`CHORE-PROFESSIONALIZE-THE-REPO` ticket 03). Under (b) the playable
demos are release assets, so until a first release exists there is nowhere to download one from:
somebody who wants to fly a demo has to clone and run the build. Ticket 01 says so in the page a
newcomer reads first rather than leaving them to find out.

Cutting that release is not this lot's work. It is the thing that closes the gap, and it is the
reason to cut it.
