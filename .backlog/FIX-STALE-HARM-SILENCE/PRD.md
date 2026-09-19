# FIX-STALE-HARM-SILENCE — a site cleaned up mid-HARM-evasion is deaf for the rest of the mission

Status: ⬜ ready

Origin: [issue #3](https://github.com/VEAF/Skynet-IADS/issues/3), opened by davidp57 on 2026-08-31,
re-read on 2026-09-19 once `FEAT-LAST-LINE-OF-DEFENSE` had merged. The defect is unchanged since;
what changed is how much it now costs.

## What is wrong

`SkynetIADSAbstractRadarElement:cleanUp()` cancels the two HARM tasks but leaves `harmSilenceID`
set:

```lua
function SkynetIADSAbstractRadarElement:cleanUp()
	for i = 1, #self.pointDefences do
		local pointDefence = self.pointDefences[i]
		pointDefence:cleanUp()
	end
	SkynetIADSUtils.removeFunction(self.harmScanID)
	SkynetIADSUtils.removeFunction(self.harmSilenceID)
	--call method from super class
	self:removeEventHandlers()
end
```

`finishHarmDefence` — the only other place that cancels the same timer — clears the field as well,
and zeroes `harmShutdownTime`. `cleanUp` does neither, so the site keeps believing it is evading a
missile whose timer no longer exists. Nothing will ever clear it: the task that would have is the
one that was just removed.

**This is in walder's original**, unchanged by the Regroupement-Patrouille fork and unchanged by the
MiST removal. It is not a regression introduced here.

## Why it is worse than it reads

`harmSilenceID` is not bookkeeping. It is a gate on **every route a site has back to life**:

| Route | Guard |
|---|---|
| network designation (`informOfContact` → `goLive`) | `goLive()` refuses while `harmSilenceID ~= nil` |
| autonomy (`goAutonomous` → `goLive`) | same |
| **last line of defense** (`reportContact` → `goLive`) | same |
| **spotter network, any external caller** (`reportContact`) | same |

The last two are new as of `FEAT-LAST-LINE-OF-DEFENSE` (merged 2026-09-19, PR #17). That lot exists
precisely so that a battery is never left with no way to notice an aircraft — and this defect
closes that door too, silently. `test_skynet_iads_last_line_of_defence.lua`'s
`testSiteDefendingAgainstAHARMDoesNotWake` asserts that refusal, correctly: HARM evasion must win.
The problem is a site that is not evading anything and believes it is.

So the issue has moved from *"a site stays dark"* to *"a site is permanently deaf, including to the
safety net we just built for exactly this"*.

On top of that, `goDark()` reads the field to decide what else to do — it brings the point defences
live and switches the controller off. A site with a stale field does that for a missile that is not
coming, every time it goes dark.

## How it is reached

Any call to `addSAMSitesByPrefix()` while a HARM timer is armed: it starts with
`deativateSAMSites()`, which calls `cleanUp()` on every site. VEAF missions call that path on
respawn, so this is not a laboratory case.

Observed on the Persian Gulf demo mission, from the issue:

1. `site:goSilentToEvadeHARM(12)` → `harmSilenceID = 44`, shutdown time 126 s
2. `redIADS:addSAMSitesByPrefix("SAM")` a couple of minutes later
3. at t+157 s, well past the deadline: `isDefendingHARM() == true`, `harmSilenceID == 44`,
   `harmShutdownTime == 126` — and `removeFunction(44)` answers `false`, so the task really is gone

The site never comes back, and nothing in the log says why.

## Tickets

| # | Ticket | Status |
|---|---|---|
| 01 | [cleanUp() clears what it cancels](tickets/01-cleanup-clears-what-it-cancels.md) | ⬜ |

## How this is verified

**Not by asserting that the field is nil.** That test passes on a fix that clears the field and
leaves the site broken some other way, and it says nothing to a reader about why anyone cared. The
test that matters drives the behaviour: a site cleaned up while evading a HARM must still be able to
go live afterwards — through the network, and through the last line of defense.

The stale-field assertion is worth having too, as the narrow unit check, but it is the second test,
not the first.

## Definition of done

- A site cleaned up while a HARM timer is armed goes live again on the next designation.
- The same site wakes on proximity, and answers `reportContact`.
- `isDefendingHARM()` answers `false` after `cleanUp()`.
- `lua5.1 test/lua/run.lua` green; issue #3 closed referencing this lot.
