# FIX-SETUP-WARNINGS-AND-LOG-NOISE — Skynet says nothing to the one person who needs it, and something to everyone that helps nobody

Status: ✅ done — merged as [PR #25](https://github.com/VEAF/Skynet-IADS/pull/25)

Origin: found while writing the tests for `CHORE-TEST-COVERAGE-FLOOR` tickets 05 and 06, on
2026-09-19. Both defects are pinned by tests that record today's behaviour and say, in as many
words, that a fix is what would turn them red. Four other defects were found the same way and are
**not** in this lot — they need a design decision first; see *What this lot deliberately leaves
out*.

Two defects, opposite failures of the same thing: what Skynet tells a human.

## 1. A mistyped group name is silent

`SkynetIADS:addSAMSite()`, `addEarlyWarningRadar()` and `setCoalition()` each build a message for a
setup mistake and pass `true` as a second argument — the convention in this code base for *"this is
a warning"*. They pass it to `printOutputToLog()`, which takes one argument and drops the second.

```lua
self:printOutputToLog(
    "you have added an SAM Site that does not exist, check name of Group in Setup and Mission editor: "
        .. tostring(samSiteName),
    true                                  -- <- goes nowhere
)
```

`printOutput(output, typeWarning)` is the function that honours it: it prefixes `WARNING: ` and is
gated by the `warnings` debug setting, which is **on by default** precisely so a mission maker sees
this. As written, the only trace of a group name that does not match the mission is one line in a
`dcs.log` nobody opens until something is already wrong — and the symptom is a battery that simply
never appears, which looks like a Skynet bug rather than a typo.

This is the most common setup mistake there is, and the one the code was clearly written to catch.

## 2. Every unit that spawns writes a line that helps nobody

`SkynetIADS:onEvent()` does one thing with a birth event:

```lua
if event.id == world.event.S_EVENT_BIRTH then
    env.info("New Object Spawned")
    --	self:addSAMSite(event.initiator:getGroup():getName());
end
```

The enrolment it was written for is commented out, so the line is all that is left. It is written
through `env.info` **without the `SKYNET:` prefix**, which is the one thing that makes a Skynet line
findable in a `dcs.log` — the `skynet-runtime-debug` skill greps for it. A mission running a red and
a blue network registers two handlers, so that is two unfilterable lines for every unit that
appears, player slot changes included.

## What to do

| | Ticket |
|---|---|
| 1 | [the warnings a mission maker never sees](tickets/01-warnings-that-never-reach-a-player.md) |
| 2 | [the birth event nobody reads](tickets/02-the-birth-event-nobody-reads.md) |

One branch, one pull request for the lot. Both tickets touch `skynet-iads-source/`, so the artifact
has to be rebuilt and `CHANGELOG.md` updated under `[Unreleased]`.

## What this lot deliberately leaves out

Three other defects were found alongside these two and are **not** here, because each needs somebody
to decide what the right behaviour is rather than how to write it. They are recorded at the end of
`CHORE-TEST-COVERAGE-FLOOR` tickets 05 and 06:

- **`SkynetIADS:addJammer()` cannot be called at all** — `self.jammers` is never initialised, so it
  throws, and nothing anywhere reads that field. Initialising the table would make the call succeed
  while still doing nothing.
- **`addRadioMenu()` has no idempotence guard** — a second call re-issues every menu call. What DCS
  then shows a player is not established, because two submenus built with the same name carry the
  same path.
- **The jammer probability curves rise with distance** — measured, and it reads inverted, but the
  intent lives in a spreadsheet this repository does not have.

## What implementing it taught us

Two things this PRD got wrong, found by `git log -S` while writing the fix. Recorded here rather
than silently corrected, because the second one changes what the change *is*.

**The fourth message was already built as a warning.** Ticket 01 said it was not, and asked for that
to be decided deliberately. It passes `true` like the other three — same defect, same fix, nothing
to decide.

**This reverses a decision, it does not repair an accident.** All four messages were shown on screen
until `9437df1` (2020-11-28, walder, *"loging refactoring"*, whose body reads *"moved output to
dcs.log console for multiple log events"*). That commit moved exactly six calls from `printOutput`
to `printOutputToLog` — these four plus the two *"added to IADS"* lines — and left the "this is a
warning" flag behind in a call that has no argument for it. The orphan flag is the whole reason the
source reads like a mistake.

The reversal stands, decided on 2026-09-19: a mission maker does not read `dcs.log`, walder no
longer maintains this project, and these four are mistakes that can still be fixed in the mission
editor. But the changelog says it is a reversal rather than a repair, and so does this.

## Definition of done

- A group or unit name that does not match the mission produces a `WARNING:` a player can see, and
  still leaves its line in `dcs.log`.
- No line is written on a birth event.
- The tests in `test/lua/test_skynet_iads.lua` that pin today's behaviour are updated rather than
  deleted, and say what changed.
- The artifact is rebuilt and `CHANGELOG.md` records both, in terms a mission maker understands.
