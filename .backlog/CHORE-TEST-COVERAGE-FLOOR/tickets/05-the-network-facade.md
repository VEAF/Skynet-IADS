# 05 — the network facade's getters and radio menu

Status: ✅ done — merged in [PR #23](https://github.com/VEAF/Skynet-IADS/pull/23). `skynet-iads.lua` went from 81.95% to **98.19%**, the project from 83.35% to 86.81%, and the floor from 83 to **86**. All 25 calls `api.md` shows on the `SkynetIADS` object are executed by at least one suite, checked one by one rather than assumed. Four latent defects were found on the way and are listed at the end of this ticket

`skynet-iads.lua` is at 81.95%, which sounds fine until you read which 98 lines never run.

| Function | Lines never run | |
|---|---:|---|
| `addRadioMenu` | 17 | documented, `api.md` line 15 |
| `getSAMSitesByPrefix` | 8 | documented, `api.md` line 263 |
| `getCoalitionString` | 8 | used by every status line the debug skill reads |
| `addSAMSite` | 7 | the enrolment path VEAF missions call on respawn |
| `updateDisplay` | 7 | |
| `getSAMSitesByNatoName` | 6 | documented, `api.md` line 242 |
| `getDestroyedSAMSites` · `getDestroyedEarlyWarningRadars` | 6 each | |
| `getActiveSAMSites` | 5 | |
| `evaluateContacts` | 5 | |
| `getSAMSiteByGroupName` | 4 | documented, `api.md` lines 254, 508, 710-730 — the most used call in the whole documentation |
| `addEarlyWarningRadar` | 4 | |
| `onEvent` · `mergeContact` | 2 each | |

## Why this one is not about a percentage

**These are the calls a mission maker writes.** `getSAMSiteByGroupName` appears eight times in
`documentation/api.md`; it is how every example reaches a battery before configuring it. The suite
has never run it.

That is a different kind of gap from the logger's. A logger line that breaks makes a diagnosis
wrong; a `getSAMSiteByGroupName` that breaks makes every documented example fail in someone's
mission, and they have no way to tell whether it is their fault. The published documentation is a
promise, and nothing checks it.

`getSAMSitesByPrefix` deserves a specific mention: `FIX-STALE-HARM-SILENCE` ticket 02 is a defect
found in exactly that path — a bulk re-add leaving discarded elements wired into the radar coverage
graph. The path has tests now, around the defect; the getter itself still does not.

## What to build

Extend `test/lua/test_skynet_iads.lua`, or a new suite beside it if it grows past reading.

- **One test per documented getter**, driven the way the documentation drives it: build a network
  with three batteries of two NATO types, then ask for one by group name, by NATO name, by prefix.
  Assert on what comes back *and* on what does not — a prefix getter that returns everything passes
  a naive test.
- **The empty and the wrong answer**: a name that matches nothing, a prefix that matches nothing.
  What these return on a miss is part of the contract and the documentation does not say.
- **`getDestroyedSAMSites` / `getDestroyedEarlyWarningRadars` / `getActiveSAMSites`** against a
  network with a known mix — destroyed, dark, lit.
- **`getCoalitionString`** for both coalitions, because every status line the debug skill parses
  starts with it.
- **`addRadioMenu`**, at least to the point of proving it builds the menu without throwing and that
  a second call does not duplicate it. The stub will need `missionCommands`; extend it deliberately
  and write down what it stands in for.

## Watch out for

Test through the public API, as `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage` already
does — `addEarlyWarningRadar` / `addSAMSite` / `activate` — not by reaching into the tables. A getter
test that builds its own fixture table proves the fixture, not the getter.

## Definition of done

- Every call `documentation/api.md` shows on the `SkynetIADS` object is executed by at least one
  test.
- What a getter returns when nothing matches is asserted, and the documentation says the same thing.
- The floor is raised in this pull request.

## Found on the way, not fixed here

Four defects the tests walked into. Three are pinned as they behave today, with a comment saying so; the fourth cannot be called at all. None was fixed: this was a test-coverage ticket, and two of the four need a design decision rather than a patch.

1. **`addJammer()` throws.** `self.jammers` is never initialised in `create()`, and nothing anywhere reads that field. Initialising it would make the call succeed while still doing nothing, so what a registered jammer is meant to do has to be decided first.
2. **An enrolment failure never reaches a player.** `addSAMSite`, `addEarlyWarningRadar` and the coalition-mismatch check each build their message as a warning — they pass `true` as a second argument — and hand it to `printOutputToLog()`, which takes one argument and drops it. The intent was clearly `printOutput(msg, true)`, which prefixes `WARNING:` and is gated by the `warnings` setting that is on by default precisely so a mission maker sees this. As written, a mistyped group name leaves one line in a log nobody opens until something is already wrong.
3. **`addRadioMenu()` has no idempotence guard.** A second call re-issues every menu call and overwrites `self.radioMenu`. What DCS shows a player then is unverified — two submenus built with the same name carry the same path — which is the point: the caller cannot reason about it either.
4. **A birth event only writes `New Object Spawned` to the log**, with no `SKYNET:` prefix, and does nothing else — the enrolment it was meant to do is commented out. A mission running a red and a blue network writes two of those per spawning unit, player slots included, and the debug skill's `SKYNET:` grep cannot filter them away.

2 and 4 are small and scoped. 1 and 3 are design questions. Awaiting David's call on how to split them between a lot and `docs/evolutions.md`.
