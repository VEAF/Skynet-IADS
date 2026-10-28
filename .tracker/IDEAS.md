# Skynet-IADS — Notes, ideas and future evolutions

## Possible issues detected to check

Neither was requested work and neither is a confirmed bug — they are latent-robustness questions worth a look, especially because this exact failure class (one bad object aborting a whole loop) already bit the project once, in David's `458b64f` "a destroyed group truncated prefix-based discovery".

### A site already dark keeps its AI on through a HARM silence

HARM defence silences a site whatever its state: `informOfHARM` calls `goSilentToEvadeHARM` on every
usable site a HARM is heading for, live or dark. The AI is turned off inside `goDark()`, and only
for a site that is live: `goDark()` does nothing when `aiState` is already false. So a site that went
dark normally — its target left the envelope at the end of a cycle — and is then aimed at by a HARM
sits through the whole silence with emission off and its AI **on**.

That is exactly the state the AI-off guard exists for: the comment in `goDark()` cites a DCS
multiplayer bug where a HARM still finds an emitter whose emission alone is off. A HARM launched
while the site was live and arriving after it went dark is the common case.

Its point defences are unaffected: `informOfHARM` wakes them itself, before the silence.

**Shape if taken**: `goSilentToEvadeHARM` turns the AI off itself when the site is already dark, or
`goDark()` applies the HARM branch whatever `aiState` is. Either way `finishHarmDefence` already
turns it back on. Not measured: whether the multiplayer bug still exists in current DCS.

### Adding EW radars by prefix takes late-activated units too

`addSAMSitesByPrefix` skips a group whose first unit is not active (`isActive()`).
`addEarlyWarningRadarsByPrefix` has no such check: it adds every unit whose name starts with the
prefix and that `Unit.getByName` finds. A mission that keeps late-activated radars under the same
prefix, to activate later, gets them in the IADS from the start, before they exist in the world.

**Shape if taken**: the same `isActive()` check in `addEarlyWarningRadarsByPrefix`. Not measured:
what Skynet does with an inactive radar it holds, and whether `getUnitNames()` lists late-activated
units at all in DCS.

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

## Every unit type in `samTypesDB` checked against the datamine

`samTypesDB` is maintained by hand: it maps DCS unit type names to NATO names, to the role each unit
plays in a site, and to `harm_detection_chance`. When ED renames a unit, the site that places it is
classified without that unit, and nothing says so.

Part of this is already guarded. `build-tools/dcs-figures.py` resolves every `searchRadar` and
`trackingRadar` type of `skynet-iads-supported-types.lua` against `_G/db/Units/` at the pinned
datamine commit, and fails on one it cannot find — so the weekly bump in `dcs-data-drift.yml` fails
on a renamed radar too.

**Not guarded:**

- the `launchers` of `samTypesDB`, which no figure reads;
- the types added by `highdigitsams/skynet-iads-high-digit-sams-suported-types.lua`, which the
  generator does not read at all.

**Shape if taken**: `dcs-figures.py check` asserts that every unit type either file names, in every
role, exists under `_G/db/Units/` at the pin. The weekly bump then fails on a rename rather than
opening no pull request. It catches a type that disappeared; it cannot catch a unit placed in the
wrong role, nor anything Skynet decides for itself — NATO names and `harm_detection_chance`.

Open question: the high-digit SAMs are a mod, so their types may not be in ED's dump at all. If they
are not, that file stays unguarded.

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

Eleven lines in `skynet-iads-source/` and twenty-eight in the published documentation still say
*battery* (*batterie* in French) where the log lines, the classes, `CONTEXT.md` and the skills say
*SAM site*. Fifteen more are in the tooling and guidance: `.github/` — the weekly figures pull
request among them — `build-tools/`, `CONTRIBUTING.md` and `test/lua/README.md`.

## Lua 5.1 fetched like the lint tools

`build-tools/lint.sh` needs nothing installed: it downloads pinned release binaries of luacheck and
stylua into `.tools/`, checks each against a SHA-256, and falls back to `PATH` where no binary is
pinned. The standalone suite still asks a Windows contributor to install *Lua for Windows*, and
`CLAUDE.md` carries its default path as a fallback.

**Shape if taken**: a `build-tools/test.sh` built the same way. On Windows it fetches a pinned Lua
5.1.5 into `.tools/lua-5.1.5/`; elsewhere it takes `lua5.1` from `PATH`, as CI already installs it
with apt. It passes its arguments on to `test/lua/run.lua`. That removes the install step from
`CONTRIBUTING.md` and the hard-coded path from `CLAUDE.md`.

**What makes it harder than the lint tools:**

- lua.org publishes source only. The usual Windows build is *LuaBinaries* on SourceForge
  (`lua-5.1.5_Win64_bin.zip`: `lua5.1.exe` and `lua5.1.dll`), whose download URLs redirect and have
  been less stable than GitHub release assets. The hash check turns a bad download into a failure
  rather than a wrong interpreter. The asset name and hash are still to be checked.
- Lua for Windows ships `luacov`; LuaBinaries does not. `luacov` is pure Lua, so a pinned source
  tarball in `.tools/`, reached through `LUA_PATH`, would serve `SKYNET_TEST_COVERAGE=1`. The plain
  suite does not need it.
- On Linux a pin is optional: the lua.org 5.1.5 tarball builds in seconds with `make posix`, which
  needs only a C compiler.

`run.lua` starts each suite with `arg[-1]`, the interpreter it was launched with, so a fetched
interpreter is used for every child process with no change to the runner.

## `can_engage_harm` says "wake for it" and "stay live against it"

The flag decides two things: whether a HARM wakes the site, and whether HARM defence lets the site
stay live to engage it (`shallIgnoreHARMShutdown`, which also counts launchers and missiles left
against the number of HARMs inbound). The second assumes the site shoots each HARM down. In DCS
2.9.30, two flagged types do not:

- **Patriot** fires one missile per engagement, at the first of several munitions, and lets the
  rest through — with or without Skynet. Against four HARMs it stays live on the strength of its
  launchers and missiles, and fires once.
- **IRIS-T SLM** engages HARMs, bombs and missiles, but rarely stops them: 26 missiles fired for 2
  kills in one series; every Maverick and bomb it shot at still hit in another.

**Open for discussion**: a separate capability for "stays live under HARM attack", or a
per-type cap on how many HARMs a site is trusted to stop.

## Should an air-to-air missile wake a SAM site?

The work on weapon contacts gives each SAM site the classes of munition it can engage, and a weapon
contact wakes only a site that can engage its class. Air-to-air missiles are excluded from those
classes: an AMRAAM crossing a Pantsir's envelope at another aircraft wakes nothing.

The reasoning is practical, not measured: an air-to-air missile is usually too fast, too high, or in
flight too briefly for a SAM site to engage it. Whether DCS lets a Pantsir, a Tor M2 or a C-RAM
shoot one down has not been flown.

**Open for discussion**: is the exclusion right, and is it worth a measurement? If a system does
engage them, the change is one more class in that system's entry in the supported-types table.

## The in-sim driver core moves to dcs-hotload

The in-sim engine's driver core (`test/insim/engine/`) goes to dcs-hotload, as `feat-insim-test-suite`
designed it to; hotload first — its own ideas hold the detail — then this repository vendors that
release and drops what moved.

## The release skill repeats `CONTRIBUTING.md`

`.claude/skills/release/SKILL.md` walks through the release steps that `CONTRIBUTING.md` already
states, and its flight before the version bump runs the smoke gate that
`test-port-unit-tests-to-insim` removes. Two things in it are not said anywhere else:

- what the release notes must call out: anything that changes behaviour for existing missions, and
  anything a mission maker has to do differently after upgrading — Skynet changes are felt in
  flight, not read in a diff, and a new default left unsaid is filed as a bug;
- bringing `develop` up to date (`git pull --ff-only`) before preparing the release.

**Shape if taken**: those two go into the release steps of `CONTRIBUTING.md`, and the skill is
deleted.

## Dropped

### A comment saying `setupRangeData` reads a radar's range once

Search and tracking radars read `getSensors()` once, when the element is built; launchers re-read
their ammunition, and their range, on every ammo query. A comment was proposed to say so. Dropped:
the call sites show it at once, and the failure it would have warned about — DCS answering badly at
spawn — has never been observed. If a log ever shows it, that is a bug report, not a comment.
