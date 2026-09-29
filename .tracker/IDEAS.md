# Skynet-IADS — Notes, ideas and future evolutions

## Possible issues detected to check

Neither was requested work and neither is a confirmed bug — they are latent-robustness questions worth a look, especially because this exact failure class (one bad object aborting a whole loop) already bit the project once, in David's `458b64f` "a destroyed group truncated prefix-based discovery".

### No coalition check on weapon contacts

[skynet-iads.lua:348](../skynet-iads-source/skynet-iads.lua) carries a pre-existing note:

```lua
-- the DCS Radar only returns enemy aircraft, if that should change a coalition check will be required
```

`ad60e92` widened what `evaluateContacts` hands to SAM sites from "aircraft (and, by accident, missiles)" to "aircraft + weapons, minus SHELL/ROCKET" —
so **bombs and missiles are now deliberately passed**. Weapons transit friendly airspace far more than enemy aircraft do.

**Check:** does DCS radar detection (`Controller.getDetectedTargets`, which is what feeds `self.contacts`) ever surface *friendly* ordnance? If it can, a Phalanx / C-RAM could be told to engage a friendly bomb overflying the site.

**If confirmed:** gate the weapon branch on `contact:getDCSRepresentation():getCoalition()` (or check it once when the contact is built). The `ad60e92` essay in the source already flags this as "another matter" and "Note 1: we could enhance that by only turning the site on when they can indeed engage the target".

**Interesting because:** it's a behaviour change from this integration widening a surface the original author explicitly marked as coalition-unsafe.

## The in-sim suite drifts, and nothing says so

`unit-tests/*.miz` is the legacy suite. Nothing runs it — not the CI, not the default workflow — so
when a refactor renames something it touches, the test keeps its old spelling and no one finds out.
The failure is silent in the worst way: a test that writes to a field nobody reads still passes its
own setup and then measures the wrong thing.

**One confirmed case**, found on 2026-09-19 while closing `FIX-COVERAGE-UPDATE-DARKENS-SITES`.
`0ebbc01` (PR #17) renamed `lastUpdatePosition` to `lastCoverageUpdatePosition`.
`unit-tests/test-skynet-iads.lua:163` and `:174` still assigned the old name, so they set a field
`getDistanceTraveledSinceLastUpdate()` no longer reads — it finds `lastCoverageUpdatePosition` nil,
adopts the current position and answers 0, where the test asserts 763.

**Proved in DCS and fixed, 2026-09-20.** It was still green in the simulator, because the mission
carried the December 2023 build where `lastUpdatePosition` was the real name. Refreshing that
artifact (`FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET` ticket 01) turned it red — `expected: 763, actual:
0`, exactly as predicted here — and ticket 04 fixed it. A sweep of every field the in-sim suites
write against what the sources define found no second case, so the lint step proposed below has been
run once by hand and found one thing; what stands guard now is `miz-suite.py check`, which stops the
archive from carrying a build old enough to hide a rename.

**How far the drift goes: measured, 2026-09-20.** The suite was run in DCS on Persian Gulf while
closing `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04. **118 tests, 114 successes, 4 failures**, and
all four are the second kind of drift — a stale *expectation* whose spelling is still valid, which
the regex sweep could never have seen. All four are in
`test-skynet-iads-red-sam-sites-and-ew-radars.lua`, last touched **2023-12-29**, and every one of
them pins a figure DCS reports about its own units:

| test | asserts | DCS answers today |
|---|---|---|
| `testCheckSA11GroupNumberOfLaunchersAndSearchRadarsAndNatoName` | SA-11 launcher range 35000 | 46000 |
| `testHQ7LauncherAndRadar` | HQ-7 launcher range 12000 | 15000 |
| `testSA15LaunchersSearchRadarRangeAndHARMDefenceChance` | target height 1930 | 1929 |
| `testShilkaGroupLaunchersSearchRadarRangesAndHARMDefenceChance` | target height 1909 | 1908 |

Two missile ranges ED has changed since 2023, and two altitudes that moved by a metre. Nothing in
Skynet is wrong; the tests record what DCS said three years ago.

**So the open question was not "what are the numbers today".** It was whether Skynet's own suite
should pin ED's data at all — and the four were only what was visible that day. Across every in-sim
suite, **125 assertions** compared an ED figure to a literal, so the next patch decided which of them
went red. All 125 are gone, into `test/lua/dcs-figures.lua`.

**Answered, 2026-09-20.** David pointed at
[VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools), which answers the
same question **without a simulator**: `veaf_build/dcs_data/` sparse-clones
[`Quaggles/dcs-lua-datamine`](https://github.com/Quaggles/dcs-lua-datamine) at a pinned commit,
generates a committed artifact, and a CI guard regenerates against the pin and fails on a diff; a
weekly workflow bumps the pin and opens a pull request when upstream moves.

The datamine carries exactly the figures these tests pin — checked at that pin (DCS 2.9.29.27278):
`getRange()` is `_G/rockets/<missile>.Range_max` (SA-11 **46000**, HQ-7 **15000**, SA-15 12000),
`getMaximumFiringAltitude()` is its `H_max`, and `getMaxRangeFindingTarget()` is
`_G/db/Sensors/Sensor/<radar>.detection_distance` times `0.2 ^ 0.25` — detection range goes as the
fourth root of the reference target's radar cross-section, and both radar samples match to the
eighth decimal. The two figures the DCS log reported are the two the datamine holds.

So ED's data leaves the simulator entirely: it becomes a generated table and a standalone test.
`FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET` ticket 03 carries the work.


**Worth considering, cheapest first:**

- A lint step that compares the symbols `unit-tests/` uses against those `skynet-iads-source/`
  defines, and fails on a name that no longer exists. It would have caught this one, it runs in CI,
  and it needs no simulator. It catches nothing about stale expectations.
- Fix the two lines and leave the rest, accepting that the suite is a reference to read rather than
  a gate.
- Retire `unit-tests/` as the migration to `test/lua/` advances, deleting each file as its behaviour
  is covered — `test/lua/README.md` already tracks what is ported and what is not. That is the only
  option that ends the drift rather than measuring it. **Started, 2026-09-20**: six suites are gone
  from both copies, and `build-tools/miz-suite.py` plus a CI job now keep the `.miz` consistent —
  the archive itself was, until then, the one file no gate in this repository looked at. What is
  left in it is what a stub cannot answer for, which is exactly where the four failures above live.
  So this option ends the *silent* drift; it does not end this one.

Related to *Smoke tests* below: both are about the same suite, from opposite ends — this one asks
what to do with it as it rots, that one asks what to replace it with.

## One agent instruction file, read by Claude and Copilot alike

Raised 2026-09-22 by David, deferred out of `CHORE-REPOSITORY-CONVENTIONS` to keep that lot's diff
readable. The intent: the instructions an agent follows should not be Claude's alone.

**Copilot already reads this repository's `CLAUDE.md`.** GitHub's documented set is `AGENTS.md`
anywhere in the tree — nearest wins — plus `CLAUDE.md` or `GEMINI.md` at the root as alternatives.
So the cross-tool story is half true today, by accident and undocumented.

**The trap that makes the obvious move wrong.** Adding an `AGENTS.md` beside the existing
`CLAUDE.md` makes Claude ignore it: with a `CLAUDE.md` at or above the working directory, Claude
reads *"Your `CLAUDE.md` files only"*. The result is a file Copilot obeys and Claude never sees,
which is worse than either file alone and fails silently.

**The only mechanism this repository controls** is a `CLAUDE.md` that `@`-imports `AGENTS.md`;
Claude then reads the import, and it keeps working on Bedrock and in telemetry-disabled sessions
where reading `AGENTS.md` directly is unavailable. The settings alternative
(`claude-md-and-agents-md`) is user-level only — Claude Code ignores that key in project and local
settings files — so it cannot be shipped to contributors.

**A constraint on how it is written**: `@path` imports are Claude's own feature. Copilot would read
`@CONTRIBUTING.md` as literal text. So `AGENTS.md` has to *instruct* — "before changing a source
file, read CONTRIBUTING.md" — rather than import. Pointers as prose work everywhere.

**Shape if taken**: `AGENTS.md` carries the vendor-neutral instructions, `CLAUDE.md` shrinks to the
import plus what is genuinely Claude-only (skills, `.claude/rules/`).

**The risk to design against**, and the reason it is a lot rather than an afternoon: `AGENTS.md` and
`CONTRIBUTING.md` become a new pair that can drift — the failure `CHORE-REPOSITORY-CONVENTIONS`
exists to end. It only holds if `AGENTS.md` stays thin: every rule in it either prevents damage
before any file is read, or is a pointer.

**Do first**: `CHORE-REPOSITORY-CONVENTIONS`. It establishes `CONTRIBUTING.md` as the single source,
which is what this entry's `AGENTS.md` would point at. Taken in the other order, there is nothing to
point to.

## The commands could live in one place instead of two

`CHORE-REPOSITORY-CONVENTIONS` accepted that three command lines — the build, the suite, the lint
gate — appear in both `CLAUDE.md` and `CONTRIBUTING.md`, on the grounds that a command is an
identifier and drifting copies fail loudly rather than silently. That reasoning holds, and it is
still two copies.

The version with none is ordinary practice: the commands are defined once in a task runner and both
files say `make test`. The command string then exists exactly once, and what the two guidance files
repeat is a *name*, which cannot be wrong without the runner itself being wrong.

**Why it was not done in that lot**: it changes the build, which that lot's scope excluded, and it
needs `make` or `just` available on a Windows-first project. `build-tools/lint.sh` is a precedent
that a shell entry point is acceptable here — CI already calls it — so a `Taskfile` or a small set of
scripts may fit better than `make`.

**Worth doing only if a third caller appears.** With two files it is a wash; the runner is another
thing to install and keep working. A CI workflow that duplicated a command a third time, or a
contributor asking what the commands are, is the signal that it has stopped being a wash.

## Two facts that left CONTEXT.md and have not yet reached the code

`CONTEXT.md` was cut back on the rule that a fact with a home in the code belongs there, not in a
satellite file that drifts. Two entries were removed on that basis and their homes are still empty,
so for now they live nowhere.

**`setupRangeData` reads a radar's detection range once.** It reads `getSensors()` at the moment the
element is built and nothing reads it again, so a bad answer at that instant fixes the range for the
whole mission — the site detects nothing and never lights up. The name reads like a getter and the
behaviour is a one-shot cache. Its home is a comment on that function, or a name that says `cache`.

**`samTypesDB` is a hand-maintained truth source.** `skynet-iads-supported-types.lua` is 500 lines
mapping unit type names to NATO names, to which units count as search radar, tracking radar and
launcher, and to `harm_detection_chance`, assigned straight to `SkynetIADS.database`. A unit ED
renames, or a new variant, and a site is silently mis-classified. Nothing regenerates it and no gate
checks it — unlike ED's numeric figures, which left the suites for a generated table with a weekly
drift check. The filename reads like a capability list. Its home is a line at the top of that file
saying what it is and how it goes stale.

Both are source changes, which is why neither happened in `CHORE-REPOSITORY-CONVENTIONS`. Small
enough to ride along with the next lot that touches those files; the second one may deserve more than
a comment, since the drift is the same class the datamine work already solved once.

## A source comment names one consumer

`skynet-iads-source/skynet-iads.lua:94` explains why `wakeSamSiteOnDCSUnit` is public with "code
outside Skynet — VEAF's spotter network — has to be able to wake a site". Skynet has no consumer of
its own and should name none: the comment ships inside the compiled artifact that every consumer
downloads, VEAF's and otherwise.

**Resolution**: amend the comment to say the entry point is public so that external callers have
finer control than writing into `targetsInRange` and its friends on every cycle, without naming a
caller. The rest of that comment is sound and vendor-neutral — why the firing envelope is not
required, and the Shilka case that explains it — and stays as it is.

Minor, and a source change, so it rides along with the next lot that touches `skynet-iads.lua`
rather than earning one of its own.

## Nothing checks that CLAUDE.md's pointers still resolve

**Closed 2026-09-26.** Florent's call: `CLAUDE.md` names files, never headings, so there is nothing
left for a check to resolve. A heading gets reworded as a matter of course; a file is rarely renamed,
and never quietly. The analysis below is what the decision was made on.

`CLAUDE.md`'s *Before you do these, read* table is load-bearing: it survives compaction, and it is
the only route back to everything delegated out of that file. Each row names a section, `§ X`, in
another file.

Nothing verifies those names. One was already dead within a day of being written —
`§ The README is hand-written, the documentation is published` outlived the heading it named by a
single commit, because the section was renamed to `## Documentation` in the same lot. A row that
points nowhere fails silently and exactly when it is needed.

**The check is small**: extract every `§ <name>` from `CLAUDE.md`, resolve each against the headings
of the file named beside it, fail on one that does not match. `build-tools/docs-check.py` already
does the same kind of work for `documentation/`, and the repository has `test/python/` to put it in.

Worth doing the moment a second row goes stale; one occurrence is an anecdote.

## The test READMEs still argue from the backlog

Guidance files state their rules without citing a lot, a ticket, a person or a date, and without
naming a consumer. `CHORE-REPOSITORY-CONVENTIONS` applied that to the root instruction files, and left the two
READMEs inside the test directories as they were.

Noticed 2026-09-26, in its third review:

- `test/lua/README.md` justifies retiring six legacy suites by "David's call, 2026-09-19; done by
  `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04", and its coverage section is largely a record of which
  lot brought which tests. It also names the repository that vendors the artifact, and calls a
  decision about the artifact's public surface one for VEAF alone, where the project is maintained
  jointly.
- `unit-tests/README.md` justifies the smoke gate being consultative by "David's call, 2026-09-21",
  and supports it by two sibling projects.

**Why it was not done there**: `test/lua/README.md` is some 350 lines, and separating the reference a
contributor needs from the history of how the suite got here is a rewrite, not an edit. Each passage
has to be checked for whether its reason survives without its citation — most do.

The shape to aim for is the one the root files reached: the rule, and its reason in general form.
The history is already in the archived lot records.

## Four imprecisions in the guidance, each a one-line fix

Measured against the workflows and the source on 2026-09-27, in the fourth review of
`CHORE-REPOSITORY-CONVENTIONS`. None of them misleads about a rule; all four are facts stated slightly
wrong, and each is a single line to repair. Grouped here so that fixing them is one small pass rather
than four.

- `CONTRIBUTING.md` says CI runs the build "on every push and pull request". `build.yml` triggers on
  pushes to `master` and `develop` only, so a push to a feature branch runs nothing until a pull
  request exists. Worth being exact about: it is what an agent waits for after pushing.
- the same file names one stylua exclusion, `test/lua/luaunit.lua`. `.styluaignore` also excludes
  `test/lua/dcs-figures.lua`, and its own comment warns that `stylua --check` on that path fails *by
  design* — a generated file whose shape belongs to its generator.
- the build, lint, docs and release gates each name their workflow file; the standalone suite and the
  weekly figures check are described without naming `lua-tests.yml` or `dcs-data-drift.yml`.
- `CONTEXT.md` is titled `SkynetIADS` where every other root file writes `Skynet-IADS`. That spelling
  is the class name, which is the one thing the same ticket took out of that file.

## ADRs

Whether Architecture Decision Records would serve this repository better than stating lasting
decisions in `CONTEXT.md` and `CONTRIBUTING.md`. The current choice keeps one current statement of
each rule and leaves its history to the tracker and the pull requests; an ADR log keeps every past
decision as its own file. Worth revisiting if the guidance files start to fill with reasoning.

## The tracker on GitHub issues

The in-repository tracker is the starting point. Moving to GitHub issues — work and discussion
outside the repository, history reached through commit, pull request and issue — remains an option
once `.tracker/` has been used for a while, with the development records migrated as closed issues.

## The release workflow reads `[Unreleased]` literally

`.github/workflows/release.yml` takes its notes from the `## [Unreleased]` heading as it stands, so
the changelog can only be frozen after the tag, in a pull request of its own. A workflow that
accepted the version heading as well would let the freeze ride with the release preparation.

## *Battery* beside *SAM site*

Eleven comments in `skynet-iads-source/` and the published documentation still say *battery*
(*batterie* in French) where the log lines, the classes, `CONTEXT.md` and the skills say *SAM site*.
