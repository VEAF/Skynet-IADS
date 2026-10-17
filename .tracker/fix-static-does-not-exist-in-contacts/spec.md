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

1. **Skip what DCS cannot describe.** In `getDetectedTargets`, a contact whose `SkynetIADSContact:create` raises is not added, and the loop goes on — which is what the comment above `getDetectedTargets` already intends.
2. **The radar was losing its cycle**, read from the code: the error escaped the loop over the detected targets, so every target after the static went unreported that cycle.
3. A test for the failing case in `test/lua/`: a static between two aircraft, which answers `getName()` and raises `Static doesn't exist` from `getTypeName()`, as the log shows.
4. **Correct the two listing comments** ([#49](https://github.com/VEAF/Skynet-IADS/issues/49)): in `addEarlyWarningRadarsByPrefix`, the `Unit.getByName` guard covers a unit that disappears between the enumeration and the lookup; in `addSAMSitesByPrefix`, `getGroupNames()` returns group names only.
5. A `CHANGELOG.md` entry under `[Unreleased]`.

## Decisions

- **The static is not identified.** The mission places none dead, so it is created and removed during play by another script, which is outside Skynet; the error did not reproduce in a local run of the same mission. Knowing which static it is would not change the fix.
- **`getDetectedTargets` is the path.** The other candidate, `SkynetIADS:reportContact`, is called inside Skynet only by the last line of defence, which hands it units of groups that exist and are in the air — never a static.
- **The guard is a `pcall` around the contact's creation**, not a check of `isExist()` or `getCoalition()` beforehand: the log shows only that `getName()` still answers and `getTypeName()` raises, and what the other two answer on such an object is not known. The `pcall` holds whatever they answer.

## Out of scope

Regenerating the vendored script in the consumers' repositories: it follows the release.

## Related

[VEAF/VEAF-Mission-Creation-Tools#946](https://github.com/VEAF/VEAF-Mission-Creation-Tools/issues/946), in the repository that vendors the script: a different entry point for the same family of errors. Its loop over `coalition.getGroups` did not check `isExist()`, and enrolled as SAM sites groups a combat zone had just destroyed.

## Comments
