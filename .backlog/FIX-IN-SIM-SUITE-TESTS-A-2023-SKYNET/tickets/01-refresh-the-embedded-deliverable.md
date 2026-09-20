# 01 — Refresh the deliverable the mission carries, and keep it fresh

Status: ✅ done — 2026-09-20

`unit-tests/skynet-unit-tests.miz` holds its own copy of `skynet-iads-compiled.lua`, loaded first by
the mission's opening trigger (`ResKey_Action_822`). That copy says:

```
SKYNET VERSION: 3.3.0-develop | BUILD TIME: 29.12.2023 2304Z
```

The build on `develop` is 3.5.0. So every one of the 118 tests that ran in DCS on 2026-09-20
measured code from December 2023.

## What to build

**Put the current artifact in the mission**, and make the refresh something that happens rather than
something somebody remembers.

`build-tools/miz-suite.py` already opens the archive, rewrites members and re-checks the wiring
afterwards. It needs one more command — `replace <member> <file>`, or a purpose-made
`refresh-artifact` — rather than a second tool that knows the same zip layout.

Then decide how it stays current. Two candidates, and they are not exclusive:

- **A CI check that fails when the two differ.** Cheap, needs no simulator, and turns a silent
  three-year drift into a red build. It cannot fix anything by itself.
- **The build writes both.** `build-tools/build-compiled-script.ps1` produces the artifact; having it
  also refresh the copy in the `.miz` means the two cannot diverge. Heavier, and it makes a binary
  file change on every build, which is noise in every diff.

Recommendation: the CI check first. It is the one that would have caught this, and it does not
commit anyone to a workflow.

## Watch out for

**This is the ticket that may open a large hole.** The suite has never run against 3.5.0 — three
years of source changes sit between the two versions, including `fe40c4a` (run without MiST), the
`SkynetIADSUtils` extraction, the coverage-sweep work of `FEAT-LAST-LINE-OF-DEFENSE`, and the renames
`docs/evolutions.md` already records (`lastUpdatePosition` → `lastCoverageUpdatePosition` at
`test-skynet-iads.lua:163` and `:174`). Expect red, possibly a lot of it, and read each one:

- a **real regression** in Skynet — the valuable case, and the reason this lot exists;
- an **API that moved**, where the test needs updating;
- an expectation that was **always** about 3.3.0 behaviour.

Do not fix them in this ticket. Record what turned red and why, and let that shape what comes next —
a pile of blind fixes to a suite nobody has read in three years is how the drift started.

**A `.miz` is judged in DCS.** Run the mission after the swap; `miz-suite.py check` and the CI job
prove the archive is well-formed, not that the mission loads.

## What the run said

`unit-tests/skynet-unit-tests.miz` in DCS, 2026-09-20 09:04, against the artifact built that morning:

```
--- SKYNET VERSION: 3.5.0 | BUILD TIME: 20.09.2026 0847Z ---
Ran 119 tests in 1.801 seconds, 114 successes, 5 failures
```

| | before (3.3.0) | after (3.5.0) |
|---|---|---|
| tests | 118 | 119 |
| successes | 114 | 114 |
| failures | 4 | 5 |

The budget for a wall of red was not spent. Read one by one:

- **Four failures are the same four**, line for line and value for value, as the 3.3.0 run an hour
  earlier: the ED figures in `test-skynet-iads-red-sam-sites-and-ew-radars.lua`. Ticket 03.
- **One is new**, and it is the third kind this ticket listed — an API that moved.
  `test-skynet-iads.lua:165` asserts 763 and got 0, because `0ebbc01` renamed `lastUpdatePosition` to
  `lastCoverageUpdatePosition` on 2026-08-23 and the test still wrote the old name. It had been green
  for a month only because the mission ran the 2023 build. Ticket 04.
- **The extra test passes.** `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage` was added to the
  loose copy on 2026-08-23 and never baked in, so it had never run; the sync put it in.
- **No regression in Skynet.** Three years of source changes, and nothing the refresh exposed is a
  defect in the shipped code.

## Two archives, not one

`unit-tests/highdigitsams/highdigitsams-unit-tests.miz` had the same defect — Skynet 3.3.0 built
29.12.2023 2059Z, untouched since 2023-12-29 — and is not in this ticket's text. It is handled here
rather than left behind: every `miz-suite.py` command works on both archives, `--miz <path>` narrows
it to one.

**It cannot be run.** It needs the HighDigitSAMs mod, which David does not have, so DCS refuses to
load it. Its artifact is current and CI checks its wiring and parses its scripts, which is more than
it had; nobody can say it runs.

## Definition of done

- The `.miz` carries the artifact built from `develop`, and the build date in its first line says so.
  ✅ both archives.
- `miz-suite.py` gained the command that did it, rather than a throwaway script. ✅ `sync`.
- Something fails when the two drift again. ✅ `check` compares every script against the file it
  copies, in both directions, and CI runs it after building the deliverable.
- The mission has been loaded once in DCS, and what turned red is written down here. ✅ above, for
  `skynet-unit-tests.miz`; `highdigitsams-unit-tests.miz` cannot be loaded here.
