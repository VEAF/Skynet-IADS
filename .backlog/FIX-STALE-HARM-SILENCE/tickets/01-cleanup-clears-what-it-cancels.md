# 01 — cleanUp() clears what it cancels

Status: ⬜ ready

## What to build

In `SkynetIADSAbstractRadarElement:cleanUp()` (`skynet-iads-source/skynet-iads-abstract-radar-element.lua`),
clear the HARM state alongside cancelling its timers, the way `finishHarmDefence` already does:

```lua
	SkynetIADSUtils.removeFunction(self.harmScanID)
	self.harmScanID = nil
	SkynetIADSUtils.removeFunction(self.harmSilenceID)
	self.harmSilenceID = nil
	self.harmShutdownTime = 0
```

**Do not simply call `finishHarmDefence`**, tempting as it looks. That function ends with

```lua
	if self:getAutonomousState() == true then
		self:goAutonomous()
	end
```

and `goAutonomous()` on a DCS-AI site means `goLive()` — so a site being torn down would light its
radar up on the way out. `cleanUp` is the teardown path; it has to forget the HARM defence, not
finish it. Clearing the three fields is the whole change.

`harmScanID` is included for the same reason as `harmSilenceID`: `isScanningForHARMs()` reads it,
and `scanForHarms()` calls `stopScanningForHARMs()` first, so a stale id is harmless today — but
leaving one field stale next to two that are cleared is how this defect was born.

## Definition of done

Two tests in `test/lua/`, in that order of importance:

1. **Behaviour.** A site cleaned up while a HARM timer is armed can still go live afterwards. Drive
   it through what a mission actually does, not through `goLive()` directly:
   - the network path — a designation reaching `informOfContact`;
   - the last line of defense — a hostile aircraft inside the site's radius, through
     `SkynetIADS.evaluateContacts()`;
   - `SkynetIADS:reportContact()`, the public door.

   All three are gated by the same `harmSilenceID == nil` guard in `goLive()`, and all three are
   what a player would notice. A test that only calls `goLive()` proves the guard, not the bug.

2. **State.** After `cleanUp()` on a site that was evading a HARM: `isDefendingHARM() == false`,
   `getHARMShutdownTime() == 0`, `isScanningForHARMs() == false`.

And the regression this must not cause: **a site genuinely evading a HARM still refuses to wake.**
`test_skynet_iads_last_line_of_defence.lua:testSiteDefendingAgainstAHARMDoesNotWake` already asserts
it — check it still passes, and that it fails if the guard in `goLive()` is removed. The fix must
clear a *stale* field, never weaken the guard that reads it.

Mutation check: restoring the old `cleanUp()` body must turn test 1 red, not only test 2.

- `lua5.1 test/lua/run.lua` green.
- Rebuild the artifact (`pwsh -File build-tools/build-compiled-script.ps1`); `CHANGELOG.md` updated
  under `[Unreleased]`, appended at the end.
- Close [issue #3](https://github.com/VEAF/Skynet-IADS/issues/3) referencing the pull request.
