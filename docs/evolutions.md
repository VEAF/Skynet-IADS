# Skynet-IADS — Notes, ideas and future evolutions

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

## The in-sim suite drifts, and nothing says so

`unit-tests/*.miz` is the legacy suite. Nothing runs it — not the CI, not the default workflow — so
when a refactor renames something it touches, the test keeps its old spelling and no one finds out.
The failure is silent in the worst way: a test that writes to a field nobody reads still passes its
own setup and then measures the wrong thing.

**One confirmed case**, found on 2026-09-19 while closing `FIX-COVERAGE-UPDATE-DARKENS-SITES`.
`0ebbc01` (PR #17) renamed `lastUpdatePosition` to `lastCoverageUpdatePosition`.
`unit-tests/test-skynet-iads.lua:163` and `:174` still assign the old name, so they set a field
`getDistanceTraveledSinceLastUpdate()` no longer reads — it finds `lastCoverageUpdatePosition` nil,
adopts the current position and answers 0, where the test asserts 763.

**How far the drift goes is unknown.** A regex sweep of `unit-tests/` against the methods and fields
the sources actually define turned up that one and nothing else, but it is a sounding, not an audit:
it cannot see a test whose *expectation* has gone stale while its spelling is still valid, which is
the more likely kind. Running the suite is the only way to know, and that needs DCS.

**Worth considering, cheapest first:**

- A lint step that compares the symbols `unit-tests/` uses against those `skynet-iads-source/`
  defines, and fails on a name that no longer exists. It would have caught this one, it runs in CI,
  and it needs no simulator. It catches nothing about stale expectations.
- Fix the two lines and leave the rest, accepting that the suite is a reference to read rather than
  a gate.
- Retire `unit-tests/` as the migration to `test/lua/` advances, deleting each file as its behaviour
  is covered — `test/lua/README.md` already tracks what is ported and what is not. That is the only
  option that ends the drift rather than measuring it.

Related to *Smoke tests* below: both are about the same suite, from opposite ends — this one asks
what to do with it as it rots, that one asks what to replace it with.

## Smoke tests

Study how the legacy `unit-test` can be transformed into something more usable and build in-sim smoke tests. See if MCPs or such exists that can help communicate with a running DCS mission. Use of the log file is always possible but may be complex.