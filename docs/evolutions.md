# Skynet-IADS — Notes, ideas and future evolutions

## Standalone Lua regression test for the SAM "goes dark" fix

The `3a94937` fix was implemented before the integration of the `test/lua/` test suite, so it only included a test in the legacy `unit-test` suite (destined to be reforged into a kind of smoke tests on a running DCS mission). The `test/lua/` fix for it has to be created.

**Rough steps:**
- Prototype the minimal fixture; decide minimal-vs-full-world
- Add any missing builders to `test/lua/dcs-fixtures.lua`
- Write `test/lua/test_skynet_iads.lua` (or a narrower file) — mirror `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage`: `evaluateContacts()` x3 with the target under coverage, assert the site stays `isActive()`
- Full suite green (`lua5.1 test/lua/run.lua`), commit
- Note whether VEAF's `.miz` copy can eventually retire, or stays as the in-sim smoke

## VEAF issue #3 — `cleanUp()` leaves `harmSilenceID` stale

**Issue:** https://github.com/VEAF/Skynet-IADS/issues/3

**Suggested fix (from the issue):** have `cleanUp()` clear what it cancels:

```lua
SkynetIADSUtils.removeFunction(self.harmScanID)
self.harmScanID = nil
SkynetIADSUtils.removeFunction(self.harmSilenceID)
self.harmSilenceID = nil
self.harmShutdownTime = 0
```

or simply call `finishHarmDefence`.

**Rough steps:**
- Apply the fix in `skynet-iads-abstract-radar-element.lua:75-82`
- Add a regression test. `abstract-radar-element` is NOT ported to `test/lua` yet (still on the DCS-only list). Decide: port a slice of that suite, or write a narrow standalone test that loads `SkynetIADSAbstractRadarElement`, arms a HARM silence, calls `cleanUp()`, asserts `isDefendingHARM() == false` and `harmSilenceID == nil`
- Full suite green, commit
- Close VEAF issue #3 referencing the fix

## Possible issues detected to check

Neither was requested work and neither is a confirmed bug — they are latent-robustness questions worth a look, especially because this exact failure class (one bad object aborting a whole loop) already bit the project once, in David's `458b64f` "a destroyed group truncated prefix-based discovery".

### No coalition check on weapon contacts

[skynet-iads.lua:348](../../../skynet-iads-source/skynet-iads.lua) carries a pre-existing note:

```lua
-- the DCS Radar only returns enemy aircraft, if that should change a coalition check will be required
```

`ad60e92` widened what `evaluateContacts` hands to SAM sites from "aircraft (and, by accident, missiles)" to "aircraft + weapons, minus SHELL/ROCKET" —
so **bombs and missiles are now deliberately passed**. Weapons transit friendly airspace far more than enemy aircraft do.

**Check:** does DCS radar detection (`Controller.getDetectedTargets`, which is what feeds `self.contacts`) ever surface *friendly* ordnance? If it can, a Phalanx / C-RAM could be told to engage a friendly bomb overflying the site.

**If confirmed:** gate the weapon branch on `contact:getDCSRepresentation():getCoalition()` (or check it once when the contact is built). The `ad60e92` essay in the source already flags this as "another matter" and "Note 1: we could enhance that by only turning the site on when they can indeed engage the target".

**Interesting because:** it's a behaviour change from this integration widening a surface the original author explicitly marked as coalition-unsafe.

### No `isExist()` / nil guard before `Object.getCategory` in the contact loop

[skynet-iads.lua:379-380](../../../skynet-iads-source/skynet-iads.lua):

```lua
local objectCategory = Object.getCategory(contact:getDCSRepresentation())
local category = contact:getDesc().category
```

Called bare, once per contact, inside `for j = 1, #self.contacts`. The sibling call site `SkynetIADSContact:getTypeName()` ([skynet-iads-contact.lua:77](../../../skynet-iads-source/skynet-iads-contact.lua)) guards it:

```lua
if self:getDCSRepresentation() ~= nil then
    local category = Object.getCategory(self:getDCSRepresentation())
```

and its comment explains why `Object.getCategory` is used instead of `rep:getCategory()`: the latter *raises* on a non-nil but destroyed unit.`getDesc()` on a destroyed unit can raise too.

**Check:** can a contact in `self.contacts` be nil-`getDCSRepresentation()` or already-destroyed at line 379? The loop runs right after `self:cleanAgedTargets()` ([:343](../../../skynet-iads-source/skynet-iads.lua) / `:405`), so aged ones are gone — but a unit destroyed *this* cycle (between `cleanAgedTargets` and the loop, or by a weapon impact mid-evaluation) would still be in the list. `dcsRepresentation` is set in `SkynetIADSContact:create` from `dcsRadarTarget.object` and never cleared, so the nil path looks unreachable today — but `getDesc()` on a fresh wreck is the real risk.

**If confirmed:** wrap the per-contact body in `if contact:getDCSRepresentation() and contact:getDCSRepresentation():isExist() then`, or `pcall` the classification. A raise here aborts the entire inform-the-SAM-sites loop for that cycle — every contact after the bad one is skipped, silently.

**Interesting because:** same shape as `458b64f` (one bad object, whole listing truncated, nothing in the log). If 2.1's weapon-passing makes mid-cycle destruction more common at this exact code point, the two interact.

## Smoke tests

Study how the legacy `unit-test` can be transformed into something more usable and build in-sim smoke tests. See if MCPs or such exists that can help communicate with a running DCS mission. Use of the log file is always possible but may be complex.