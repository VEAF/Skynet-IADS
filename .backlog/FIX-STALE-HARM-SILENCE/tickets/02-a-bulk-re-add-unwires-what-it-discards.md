# 02 — a bulk re-add unwires what it discards

Status: 🔄 in-progress — `fix/stale-harm-silence-on-cleanup`

## Why this is in this lot

Found while checking ticket 01's premise. The PRD says the stale `harmSilenceID` is reached by
`addSAMSitesByPrefix()`, and it is — but not the way it reads. That function builds **fresh** site
objects for `self.samSites`, so the IADS's own list never carries the stale field. What carries it
is the object it threw away, which is still wired into the coverage graph and still drives the same
DCS group. Ticket 01 disarms the HARM half of that; this ticket removes the wiring.

## What is wrong

`addSAMSitesByPrefix()` and `addEarlyWarningRadarsByPrefix()` both replace their whole list:

```lua
self:deativateSAMSites()
self.samSites = {}
```

Nothing unwires the discarded objects. `addSAMSite()` / `addEarlyWarningRadar()` only ever *add*
(`insertToTableIfNotAlreadyAdded`), and `refreshRadarCoverage()` walks `getAbstracRadarElements()`,
which reads the two current lists — a discarded object is in neither, so it is never visited. The
only code that clears anything is `buildRadarCoverage()`, and that runs at `activate()` alone.

Measured on the DCS stub, one EW radar and one SA-2, IADS already activated:

| after | observed |
|---|---|
| `addSAMSitesByPrefix("SAM")` | the EW radar holds **2** child radars — the discarded site and the new one |
| `addEarlyWarningRadarsByPrefix("EW")` | the SA-2 holds **2** parent radars, and `hasValidParentRadar()` is `true` for the discarded one |

Both halves bite, and the EW half is the worse of the two. A discarded EW radar object still passes
every validity test a parent is given — its DCS unit exists, it has power, it has a connection node,
it acts as EW — so the battery believes it is covered by a radar the IADS no longer polls. It stays
non-autonomous and dark, watched by nobody. That is the shape of the report
`FEAT-LAST-LINE-OF-DEFENSE` came from, though nothing says it is the same cause.

The SAM half is what ticket 01 tripped over: the discarded site object is still a child of the EW
radar, so every `informChildrenOfStateChange()` calls `setToCorrectAutonomousState()` on it, and it
drives the controller of the DCS group the *live* site also owns.

## What to build

In both `*ByPrefix` functions, rebuild the coverage once the list has been repopulated, guarded the
way the incremental rebuild already is:

```lua
	if self.ewRadarScanMistTaskID ~= nil then
		self:buildRadarCoverage()
	end
```

`buildRadarCoverage()` is the only function that purges, and it purges all three holders — SAM
sites' children and parents, EW radars' children, and the command centres', through
`addRadarsToCommandCenters()`. A bulk replacement is exactly the case it was written for; this makes
the two `*ByPrefix` functions do what `activate()` already does.

**Accepted cost**: the per-element incremental rebuild still runs inside the loop, so the O(n²)
sweep is paid twice for one call. On sixty elements that is a few thousand distance comparisons,
once per respawn. Suppressing it would mean threading a "bulk in progress" flag through
`addSAMSite()`, which is more state in the largest class in the project for no measurable gain.

### What this does *not* cost

`buildRadarCoverage()` ends in `informChildrenOfStateChange()` on every SAM site, which for a
covered site means `goDark()` — so on paper this switches off a battery that had just been
designated and not yet locked on, the hazard written up at `refreshRadarCoverage()`. Measured
against the unfixed source, that turns out to be **no cost at all**, because it already happens
without this change:

| call | site lit before | still lit after, **without** this fix | **with** it |
|---|---|---|---|
| `addSAMSitesByPrefix()` | yes | no | no |
| `addEarlyWarningRadarsByPrefix()` | yes | no | no |

Two different reasons, neither of them this ticket's:

- `addSAMSitesByPrefix()` rebuilds its sites from scratch, and `addSAMSite()` ends in `goDark()`.
  The lit site was lost to the rebuild before the coverage was ever touched.
- `addEarlyWarningRadarsByPrefix()` darkens it inside the loop, long before the new rebuild runs —
  traced to `buildRadarAssociation()` → `addParentRadar()` → `informChildrenOfStateChange()` →
  `resetAutonomousState()` → `goDark()`. That is the very path
  `addParentRadarWithoutStateChange()` was added for in `FEAT-LAST-LINE-OF-DEFENSE`;
  `buildRadarAssociation()` still uses the informing one. **Pre-existing defect, left alone here**:
  it is bounded to one contact cycle (the next cycle relights the site), and `buildRadarAssociation`
  is shared with `activate()`, where darkening is what is wanted. Written up as
  [FIX-COVERAGE-UPDATE-DARKENS-SITES](../../FIX-COVERAGE-UPDATE-DARKENS-SITES/PRD.md).

Also measured: a SAM site set to act as EW is already switched off by `activate()` today and relit
by the next cycle, so this changes nothing for it either.

## Definition of done

Tests in `test/lua/`, driving the real `*ByPrefix` API:

1. After `addSAMSitesByPrefix()` on a running IADS, the EW radar's children are exactly the sites
   the IADS holds — no discarded object among them.
2. After `addEarlyWarningRadarsByPrefix()` on a running IADS, a SAM site's parents are exactly the
   EW radars the IADS holds.
3. A re-add before `activate()` still works, and still costs no rebuild — the guard holds.

Two deliberate stub extensions this needs, both standing in for real DCS behaviour:

- `Unit.isActive()` on `dcsStub.makeUnit` — `addSAMSitesByPrefix()` calls it to skip a group that is
  in the mission but not yet activated. Real DCS answers `false` for a late-activation group before
  its trigger fires.
- an EW radar fixture that lives **in a group**. In DCS every unit belongs to one, and
  `SkynetIADSUtils.getUnitNames()` enumerates units through groups — so the existing
  `F.earlyWarningRadarUnit`, which registers a bare unit, is invisible to prefix discovery.

- `lua5.1 test/lua/run.lua` green, `CHANGELOG.md` updated under `[Unreleased]`.
