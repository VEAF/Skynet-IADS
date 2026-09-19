# FIX-COVERAGE-UPDATE-DARKENS-SITES — declaring that a radar covers a battery switches the battery off

Status: 🔄 in-progress — `fix/coverage-update-darkens-sites`

Origin: found on 2026-09-19 while instructing `FIX-STALE-HARM-SILENCE` ticket 02, by tracing which
step of a bulk re-add darkened a designated site. It turned out not to be the step under review:
the site was already dark before that code ran. It is not a regression — it has been there since
walder's original — but `FEAT-LAST-LINE-OF-DEFENSE` wrote the fix for exactly this and applied it
to one of the two callers.

## What is wrong

`SkynetIADS:buildRadarAssociation()` is how the IADS records that a radar covers a battery:

```lua
	function SkynetIADS:buildRadarAssociation(parent, child)
		--chilren should only be SAM sites not EW radars
		if getmetatable(child) == SkynetIADSSamSite then
			parent:addChildRadar(child)
		end
		--Only SAM Sites should have parent Radars, not EW Radars
		if getmetatable(child) == SkynetIADSSamSite then
			child:addParentRadar(parent)
		end
	end
```

`addParentRadar()` does not only record the link. It ends in `informChildrenOfStateChange()`, which
recomputes the battery's autonomy and calls `goDark()`. **So writing down a fact about geometry
switches off a radar.**

Traced live, from a site lit by network designation:

```
goDark ← resetAutonomousState ← setToCorrectAutonomousState
       ← informChildrenOfStateChange ← addParentRadar
       ← buildRadarAssociation ← buildRadarCoverageForAbstractRadarElement
       ← buildRadarCoverageForEarlyWarningRadar ← addEarlyWarningRadar
```

## Why it is an oversight

`FEAT-LAST-LINE-OF-DEFENSE` added `addParentRadarWithoutStateChange()` for this, and the comment it
carries names the hazard: a sweep going through `addParentRadar` would *"hand an extinction order to
the whole network"*. `refreshRadarCoverage()` was converted. `buildRadarAssociation()` was not, and
it is now the **only** caller of the informing version left in the sources.

A smaller sign the same corner has not been read in a long while: the two `if` above test the same
condition under two different comments.

## What it costs

**In game.** Adding an early warning radar during a mission — `addEarlyWarningRadar()`, or a re-add
by prefix — darkens every battery in its range, including one that was designated onto an intruder
and has not locked on yet. `goDark()`'s guards cover a site that has acquired a track or has
missiles in flight; they do not cover that one. The symptom is the one commit `3a94937` is about:
launchers raised, slew onto the target, back to travel state, no shot. The next contact cycle
relights the site, so the gap is bounded by `contactUpdateInterval` — 5 s by default — which is
exactly long enough for a fast pass to be over.

**In work done.** Counted on three EW radars and ten SAM sites, during one `activate()`:

| `informChildrenOfStateChange()` calls | |
|---|---|
| actually made | **250** |
| strictly needed | **10** |

`buildRadarCoverage()` already ends with an explicit loop that notifies every SAM site once —
commented *"we call this once on all sam sites"*. The other 240 are noise generated inside it, in
N², and each one walks the element's children and calls `getMooseConnector():update()`.

## How it is reached

Any incremental coverage update on a running IADS: `addSAMSite()`, `addEarlyWarningRadar()`, and the
two `*ByPrefix` calls that go through them. VEAF's helper enrols groups this way as a mission runs.
`activate()` reaches it too, but there it is only the wasted work — nothing is lit yet.

## Tickets

| # | Ticket | Status |
|---|---|---|
| 01 | [record the coverage quietly, and tell only what changed](tickets/01-record-the-coverage-quietly.md) | 🔄 |

## How this is verified

**Not by counting notifications alone.** The test that matters drives the behaviour: a battery lit
by network designation must still be lit after a radar is added somewhere else in the mission. The
call count is the second test — it is what proves the N² noise is gone, and it is the one that
would catch a fix that moves the notification rather than removing it.

## Definition of done

- A site lit by designation is still lit after `addEarlyWarningRadar()` on a running IADS.
- Autonomy is still correct after any incremental coverage update — a site that has just lost its
  last covering radar goes autonomous, one that has just gained one stops being autonomous.
- `activate()` behaves exactly as before, and notifies each SAM site once.
- `lua5.1 test/lua/run.lua` green.
