# 01 — record the coverage quietly, and tell only what changed

Status: ⬜ ready

## What to build

Two changes, in `skynet-iads-source/skynet-iads.lua`.

**1. `buildRadarAssociation()` records the link and says nothing.**

```lua
		child:addParentRadarWithoutStateChange(parent)
```

in place of `child:addParentRadar(parent)`. `addChildRadar()` is already quiet, so after this the
function is pure bookkeeping, which is what its name says. The two `if` testing the same condition
collapse into one while you are there — that is the whole of the tidying this ticket does, no
further.

**Do not remove `addParentRadar()`.** It is part of the script's public surface and several tests
exercise it directly; it simply stops being used here, and `buildRadarAssociation` was its last
caller in the sources.

**2. Give the incremental path the notification it just lost.**

`buildRadarCoverage()` needs nothing — it already ends with an explicit loop that notifies every SAM
site once, which is where the 10 necessary calls come from. The incremental entry points have no
such loop, so without this they would stop updating autonomy at all:

- `buildRadarCoverageForSAMSite(samSite)` — the site that was just added is the only one whose own
  autonomy can have changed.
- `buildRadarCoverageForEarlyWarningRadar(ewRadar)` — the sites that radar now covers are the ones
  whose answer can have changed.

And apply the criterion `refreshRadarCoverage()` already uses rather than notifying flatly, so a
site whose situation did not change is not touched at all:

```lua
	if samSite:hasValidParentRadar() == samSite:getAutonomousState() then
		samSite:setToCorrectAutonomousState()
	end
```

That is what removes the extinction rather than moving it: a battery that was covered before and is
still covered keeps burning, and a battery whose coverage really did change is corrected.

## Watch out for

- **Order inside `addEarlyWarningRadar()`**: the radar is inserted into `self.earlyWarningRadars`
  *after* `buildRadarCoverageForEarlyWarningRadar(ewRadar)` runs, so during the rebuild it is not
  yet in `getAbstracRadarElements()`. It is passed explicitly, which is why that works today — keep
  reading the children off the argument, not off the list.
- **`addSAMSite()` is the mirror image**: it inserts first, then rebuilds. The two are not
  symmetrical and it is easy to write one as if it were the other.
- **`activate()` must not change at all.** It is the hottest path in the project and it cannot be
  checked in DCS from here. A test that pins its notification count is what keeps that honest.

## Definition of done

Tests in `test/lua/`, in that order of importance:

1. **Behaviour.** A SAM site lit by network designation, through a real
   `SkynetIADS.evaluateContacts()` cycle, is still lit after `addEarlyWarningRadar()` adds another
   radar to the running IADS. Fails today.
2. **Autonomy is still maintained.** A site that gains its first covering radar stops being
   autonomous; a site that loses its last one becomes autonomous. Both through the incremental
   path, not through `activate()` — that is the behaviour change 1 could silently buy at the cost
   of.
3. **The noise is gone, and `activate()` is untouched.** Count `informChildrenOfStateChange()`
   during `activate()` on a few radars and a few sites: one call per SAM site, no more. On the
   fixture used to find this — 3 EW radars, 10 SAM sites — that is 10 where it is 250 today.

Mutation check: reverting `buildRadarAssociation()` to `addParentRadar` must turn test 1 red, not
only test 3.

- `lua5.1 test/lua/run.lua` green.
- Rebuild the artifact (`pwsh -File build-tools/build-compiled-script.ps1`); `CHANGELOG.md` updated
  under `[Unreleased]`, appended at the end.
