# Skynet raises every ~14 s on a static that no longer exists

Status: open

## The problem

Measured on 2026-10-12, in the `dcs.log` of a dedicated server running a mission that vendors the compiled script (a Sinai mission, Skynet 3.5.x as shipped by VMCT 6.29.0): 523 lines `SkynetIADS: error in scheduled function … skynet-iads-compiled.lua:2745: Static doesn't exist`, one every ~14 s, from 20 s after the mission load — before any shot — to the end of a 2 h 12 min session. The Caucasus mission loaded on the same server the same day logged none.

The line is written at `INFO`, so a filter on `ERROR` does not see it.

Line 2745 is `instance.typeName = dcsRepresentation:getTypeName()` in `SkynetIADSAbstractDCSObjectWrapper:create`, called on a static that no longer exists.

## Suspected path, not measured

`SkynetIADSAbstractRadarElement:getDetectedTargets` tests `target.object` before `SkynetIADSContact:create`, and no more. If a radar reports a static that is gone, the exception escapes the scheduled function and the radar loses the rest of its detection cycle: it would detect nothing else for as long as that object is in its list.

Other places that build a wrapper and could be the one: `skynet-iads.lua` where `SkynetIADSContact:create({ object = dcsUnit }, samSite)` is called, and the listings whose comments say they "can contain StaticObjects".

## What to build

1. **Find the static.** Wrap the `getTypeName` call in `SkynetIADSAbstractDCSObjectWrapper:create` so that a failure logs the object's name and the caller's stack once. Load the Sinai mission and read the log. Because the error starts before any shot, the static is present or already gone at load time.
2. **Skip what does not exist.** A contact whose object does not exist, or whose `getTypeName` fails, is not added — which is what the comment above `getDetectedTargets` already intends.
3. **Say whether the radar was losing its cycle**, measured: a SAM's contacts with the error, then without.
4. A test for the failing case in `test/lua/`.
5. A `CHANGELOG.md` entry under `[Unreleased]`.

## Out of scope

Regenerating the vendored script in the consumers' repositories: it follows the release.

## Related

`fix-skynet-adds-destroyed-groups` (archived): a different entry point for the same family of errors.

## Comments
