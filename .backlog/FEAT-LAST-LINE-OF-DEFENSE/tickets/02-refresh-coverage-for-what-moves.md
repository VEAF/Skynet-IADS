# 02 — Refresh radar coverage for whatever moves

Status: ⬜ ready

## Problem

Coverage — which battery sits under which radar — is computed geometrically and then treated as if
it never changed. Two holes.

### The incremental rebuild never purges

When an AWACS has moved 10 NM, `evaluateContacts` calls `buildRadarCoverageForEarlyWarningRadar`,
which routes to `buildRadarCoverageForAbstractRadarElement` — and that one only ever **adds**,
through `insertToTableIfNotAlreadyAdded`. Only the global `buildRadarCoverage()` clears anything
(`clearChildRadars` + `clearParentRadars`), and there is **no function at all** to remove a single
parent or child.

So an AWACS in transit accumulates. It keeps every battery it has ever flown near, and those
batteries keep it as a parent for the rest of the mission — held non-autonomous by a tutor hundreds
of kilometres away that will never feed them anything.

The comment above `buildRadarCoverage` says where the mistake came from: *"during runtime it is
sufficient to call buildRadarCoverageForSAMSite or buildRadarCoverageForEarlyWarningRadar … this
saves script execution time"*. True for an **addition** — a new SAM, a fixed EWR. False for an
element that **moves**, and the AWACS is the only one it was applied to.

### Mobile SAM sites are refreshed by nothing at all

The 10 NM check tests `getmetatable(ewRadar) == SkynetIADSAWACSRadar`, so it covers AWACS and
nothing else. A SA-15, a SA-8 or a Shilka driving in a convoy keeps the parents it had when it
spawned, for the whole mission. VEAF missions carry a lot of mobile content.

### Honest about the evidence

The accumulation is **not** visible in the reporting log: over 24 minutes the three A-50s hold a
constant coverage (16, 2 and 0 sites). That is consistent with tight orbits —
`getDistanceTraveledSinceLastUpdate` measures straight-line distance from the last reference point,
not distance flown, so an aircraft going round in circles never trips the threshold. The defect is
established by reading the code. It bites AWACS that **transit**: climbing to station, changing
zone, going home.

## The three constraints — part of the decision, not later optimisations

### 1. Sweep what moves, not everything

`buildRadarCoverage()` is O(N²), and each pair tests every combination of the two elements' radars.
On the reported network — 20 SAM sites and 8 EWRs, 28 elements — that is roughly 3 000
`isInRadarDetectionRangeOf` calls, ~12 000 radar pairs and ~48 000 DCS API calls, all in one frame.
Estimated from the code, not measured in game; a 100-element campaign is twelve times that.

Two changes take it out of the danger zone:

- **only mobile elements are re-evaluated** — the geometry between two fixed elements never changes.
  M × N instead of N²: 84 pairs instead of 784 here, 300 instead of 10 000 on 100 elements;
- **one position and one max range per element**, not per radar. A site is a point; iterating over
  radar pairs costs a factor of four and buys nothing.

Together, ~80 tests instead of ~12 000 on that network. At that price the sweep runs every 10 s.

### 2. Only touch the state of what actually changed

`buildRadarCoverage()` ends with `informChildrenOfStateChange()` on every SAM →
`setToCorrectAutonomousState` → for a covered site, `resetAutonomousState()` → **`goDark()`**. Run
periodically as-is, that sends an extinction order to the whole network on every sweep. `goDark`'s
guards protect a site that has acquired a track or has missiles in flight — but **not** one that has
just gone live on designation and not yet locked on.

So: compare each site's parent list before and after, and call `setToCorrectAutonomousState` **only**
on those whose list actually changed.

### 3. Keep the immediate reaction to an EWR's death

The sweep makes the death-driven path redundant in theory. Keep it: it costs nothing and frees a
battery **at once** instead of at the next sweep. An EWR killed in a SEAD run has to hand its
batteries their autonomy immediately — that is a moment of play. Remove the event path later, only
if it ever becomes a nuisance.

## Accepted consequence

After this, an AWACS that goes home has the same effect as one that is shot down: the batteries it
alone covered become autonomous and light up. Decided on 2026-09-19 — it is coherent, and it only
touches batteries no ground radar covers, for which autonomy is the right answer.

## What has to be written

- Individual removal of a parent and of a child radar. Neither exists; today it is all-or-nothing.
- A per-element "has moved since the last sweep" notion, so fixed elements are skipped outright. The
  existing AWACS distance check is the model, generalised beyond AWACS — same 10 NM threshold.
- The sweep itself, interval settable, default 10 s.

## Definition of done

- An AWACS that transits loses the batteries it left behind, and they revert to autonomous.
- A mobile SAM site's parents follow it.
- **A live site whose parents did not change is not sent dark by a sweep** — this is the test that
  matters, because a site that relights on the next cycle hides the regression in play.
- Killing an EWR still frees its batteries without waiting for a sweep.
- `lua5.1 test/lua/run.lua` green.
