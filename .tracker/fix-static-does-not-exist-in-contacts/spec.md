# Skynet raises every ~14 s on a static that no longer exists

Status: in-progress

## The problem

Measured on 2026-10-12, in the `dcs.log` of a dedicated server running a mission that vendors the compiled script (a Sinai mission, Skynet 3.5.x as shipped by VMCT 6.29.0): 523 lines `SkynetIADS: error in scheduled function … skynet-iads-compiled.lua:2745: Static doesn't exist`, one every ~14 s, from 20 s after the mission load — before any shot — to the end of a 2 h 12 min session. The Caucasus mission loaded on the same server the same day logged none.

The line is written at `INFO`, so a filter on `ERROR` does not see it.

Line 2745 is `instance.typeName = dcsRepresentation:getTypeName()` in `SkynetIADSAbstractDCSObjectWrapper:create`, called on a static that no longer exists.

## Suspected path, not measured

`SkynetIADSAbstractRadarElement:getDetectedTargets` tests `target.object` before `SkynetIADSContact:create`, and no more. If a radar reports a static that is gone, the exception escapes the scheduled function and the radar loses the rest of its detection cycle: it would detect nothing else for as long as that object is in its list.

Another place that builds a wrapper and could be the one: `skynet-iads.lua` where `SkynetIADSContact:create({ object = dcsUnit }, samSite)` is called.

The listings `SkynetIADSUtils.getUnitNames()` and `getGroupNames()` are not a lead: both enumerate `coalition.getGroups()` and the groups' units, so they cannot return a static. The comments in `addEarlyWarningRadarsByPrefix` and `addSAMSitesByPrefix` that say otherwise date from MiST, whose database did contain statics ([#49](https://github.com/VEAF/Skynet-IADS/issues/49)).

## What to build

1. **Skip what does not exist.** In `getDetectedTargets`, a target whose object answers `isExist()` false is skipped before anything else is read from it — which is what the comment above the loop already intends. The `pcall` around `getCoalition()` goes: the same check covers the ended weapon it was there for.
2. **The radar was losing its cycle**, read from the code: the error escaped the loop over the detected targets, so every target after the static went unreported that cycle.
3. Tests in `test/lua/`, with objects shaped as measured below: a removed static between two aircraft, an ended weapon, a wreck.
4. **Correct the two listing comments** ([#49](https://github.com/VEAF/Skynet-IADS/issues/49)): in `addEarlyWarningRadarsByPrefix`, the `Unit.getByName` guard covers a unit that disappears between the enumeration and the lookup; in `addSAMSitesByPrefix`, `getGroupNames()` returns group names only.
5. A `CHANGELOG.md` entry under `[Unreleased]`.

## Decisions

- **The static is not identified.** The mission places none dead, so it is created and removed during play by another script, which is outside Skynet; the error did not reproduce in a local run of the same mission. Knowing which static it is would not change the fix.
- **`getDetectedTargets` is the path.** The other candidate, `SkynetIADS:reportContact`, is called inside Skynet only by the last line of defence, which hands it units of groups that exist and are in the air — never a static.
- **The guard is `isExist()`, not a `pcall`.** A `pcall` would hide any error in what it wraps, and leave the getters read later in the loop unguarded. `isExist()` covers the whole loop: nothing can remove an object between two calls in it.

What DCS 2.9 answers once an object is gone, measured in a running mission:

| | `isExist()` | `getName()` | other getters |
|---|---|---|---|
| a static removed by `destroy()` | `false` | answers | raise `Static doesn't exist` (`getPosition()`: `Object doesn't exist`) |
| a unit removed by `destroy()` | `false` | answers | raise `Unit doesn't exist` |
| a weapon that has ended (a Mk-82) | `false` | answers | raise `Weapon doesn't exist` |
| a static or a unit destroyed by an explosion | `false` | answers | answer: the wreck stays |

`isExist()` never raised, and turned false at the poll where the other getters started raising; right after `destroy()`, every getter still answers until the next frame. The removed static matches the log: `getName()` answers, `getTypeName()` raises.

## Out of scope

Regenerating the vendored script in the consumers' repositories: it follows the release.

## Related

[VEAF/VEAF-Mission-Creation-Tools#946](https://github.com/VEAF/VEAF-Mission-Creation-Tools/issues/946), in the repository that vendors the script: a different entry point for the same family of errors. Its loop over `coalition.getGroups` did not check `isExist()`, and enrolled as SAM sites groups a combat zone had just destroyed.

## Comments
