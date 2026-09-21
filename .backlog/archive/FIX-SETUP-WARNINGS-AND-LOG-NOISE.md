# FIX-SETUP-WARNINGS-AND-LOG-NOISE — nothing to the one person who needs it, something to everyone that helps nobody

Closed 2026-09-19. [PR #25](https://github.com/VEAF/Skynet-IADS/pull/25).

Two defects, opposite failures of the same thing: what Skynet tells a human. Both found while
writing the tests for `CHORE-TEST-COVERAGE-FLOOR`, both pinned by tests that recorded the behaviour
and said in as many words that a fix is what would turn them red.

## 1. A mistyped group name was silent

`addSAMSite()`, `addEarlyWarningRadar()` and `setCoalition()` each built a setup-mistake message and
passed `true` as a second argument — this code base's convention for *"this is a warning"* — to
`printOutputToLog()`, which takes one argument and drops it. `printOutput()` is the function that
honours the flag: it prefixes `WARNING: ` and is gated by a debug setting that is **on by default**,
precisely so a mission maker sees this.

A group name that does not match the mission is the commonest setup mistake there is, and the symptom
— a battery that never appears — looks like a Skynet bug rather than a typo.

## 2. Every spawn wrote a line nobody could use

`onEvent()` answered a birth event with `env.info("New Object Spawned")`, without the `SKYNET:`
prefix that makes a line findable in a `dcs.log` (the `skynet-runtime-debug` skill greps for it).
The enrolment it was written for is commented out. A mission with a red and a blue network registers
two handlers, so that is two unfilterable lines per unit, player slot changes included.

## The finding that changed what the change was

Found by `git log -S` while implementing: **this reverses a decision, it does not repair an
accident.** All four messages were shown on screen until `9437df1` (2020-11-28, walder, *"loging
refactoring"*), which moved six calls from `printOutput` to `printOutputToLog` and left the warning
flag behind in a call that has no argument for it. The orphan flag is the whole reason the source
reads like a mistake.

The reversal stands, decided 2026-09-19: a mission maker does not read `dcs.log`.

## What it deliberately left out

Three defects found alongside, each needing a decision rather than an implementation, taken up by
`FIX-JAMMER-SILENCE-OUTLIVES-THE-JAMMER`: `addJammer()` unusable, `addRadioMenu()` without an
idempotence guard, and the jammer probability curves (investigated and closed *no change*).
