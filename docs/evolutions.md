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

## In-sim test tier

The original "smoke tests" idea — make the legacy `unit-tests` usable, and find a way to talk
to a running DCS mission without grepping the log — is **designed**, in
[2026-09-15-insim-test-tier-design.md](superpowers/specs/2026-09-15-insim-test-tier-design.md).
No MCP-style bridge or external process is involved: the mission loads everything from disk and
reports on screen, to `dcs.log` and to a results file.

Everything below was deliberately cut from that design's scope. None of it blocks the tier.

### Migrating the legacy suite

The long-term intent is for `test/insim/` to replace and extend the *entire* `unit-tests/*.miz`
suite — every `unit-tests/test-*.lua` that genuinely needs live DCS behavior is a migration
candidate. Scoped incrementally, file by file, once the tier exists.

This is not one-tier-per-scenario. `test/lua/` and `test/insim/` serve different purposes:
`test/lua/` is fast and CI-friendly, `test/insim/` is heavier but proves the same behavior in a
real DCS context. The same underlying scenario can legitimately be covered in both — a mocked
port for quick feedback, an in-sim scenario for real-context confidence.

Note that some legacy suites do not belong in `test/insim/` at all. VEAF issue #3
(`harmSilenceID` cleanup, above) is internal-state testing — arm a timer, call `cleanUp()`,
assert nil — with no live DCS behavior involved, so it belongs in `test/lua/` once
`abstract-radar-element` is ported there.

### Scenarios the tier unlocks

Recorded as motivation, not as planned work:

- **Coalition check on weapon contacts** (see above) — whether `Controller.getDetectedTargets`
  ever surfaces friendly ordnance is an empirical question about DCS that a mock cannot answer.
- **SAM-goes-dark** (`f6d77e6`) — worth revisiting in-sim if its current test mocks
  `getDCSRepresentation()`/emission state rather than exercising real detection.
- **Power sources and connection nodes** — destroy a power plant static, assert the SAM goes
  dark and recovers. Newly practical: destroyed statics keep a queryable handle reporting
  `isExist() == false`, which is exactly what `genericCheckOneObjectIsAlive` reads, so the
  `S_EVENT_DEAD` path can be exercised against real destruction.

### In-cockpit checks

`skynet-insim.miz` ships with one Neutral Game Master slot. Further playable slots may be added
as needed: some mechanics are only observable from a cockpit — RWR indications when a SAM goes
active, lock and launch warnings, HARM seeker behavior. Nothing in the design depends on the
slot type, so adding an aircraft costs nothing.

The limit is worth stating: a scenario cannot read the RWR, so this is **human observation, not
an assertion**, and the tier's automated pass/fail will never cover it. The workable pattern is
a scenario that drives the IADS into the state of interest while the tester watches — automation
for the setup, eyes for the verdict.

### CI and a terminal reader

Running DCS unattended needs a licensed, GPU-capable machine, so whether this tier ever runs in
CI is a separate decision. The design leaves the door open cheaply: `results/last-run.lua` is
machine-readable, and a reader that prints a `test/lua`-shaped report and sets an exit code is
roughly 40 lines whenever someone wants it.

Triggering a run from outside the sim would be the other half. The runner already ticks on
`timer.scheduleFunction` and already has `lfs`, so it could watch for a `run.trigger` file,
run, and delete it — input-only, no response file or handshake, so it would not resurrect the
external-driver architecture the design rejects. Not needed while runs are triggered by hand
from the F10 menu, which is confirmed working.