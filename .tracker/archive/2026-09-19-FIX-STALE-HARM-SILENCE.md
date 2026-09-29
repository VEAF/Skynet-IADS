# FIX-STALE-HARM-SILENCE — a site cleaned up mid-HARM-evasion is deaf for the rest of the mission

Closed 2026-09-19. [PR #18](https://github.com/VEAF/Skynet-IADS/pull/18). Closes
[issue #3](https://github.com/VEAF/Skynet-IADS/issues/3).

## The defect

`cleanUp()` cancelled the two HARM timers but left `harmSilenceID` set. `finishHarmDefence` — the
only other place that cancels the same timer — clears the field as well; `cleanUp` did neither, so
the site kept believing it was evading a missile whose timer no longer existed, and nothing would
ever clear it: the task that would have is the one just removed.

`harmSilenceID` is not bookkeeping. It gates **every route a site has back to life** — network
designation, autonomy, the last line of defense, and any external `reportContact`. The last two
arrived the same week with `FEAT-LAST-LINE-OF-DEFENSE`, which exists precisely so a battery is never
left unable to notice an aircraft; this defect closed that door too, silently. In walder's original,
not a regression.

Reached by any `addSAMSitesByPrefix()` call while a HARM timer is armed, which VEAF missions make on
respawn.

## The correction that changed what the lot was

The first reading said the IADS's own site list carried the stale field. It does not:
`addSAMSitesByPrefix()` rebuilds **fresh** objects, and a fresh object has no `harmSilenceID`. The
object that carries it is the one thrown away — still reachable through the mission's own reference
*and* through the coverage graph, which nothing unwired. Measured on the stub: after a bulk re-add
the EW radar held **two** child radars, the discarded site among them, so
`informChildrenOfStateChange()` kept driving a dead object owning the same DCS group's controller.

That wiring became ticket 02, and the symmetrical case is worse: after
`addEarlyWarningRadarsByPrefix()`, a battery keeps a discarded EW radar as a parent that passes every
validity test, so it stays non-autonomous and dark under a radar the IADS no longer polls.

## How it was tested, and why not the obvious way

**Not by asserting the field is nil.** That passes on a fix that clears the field and leaves the site
broken some other way, and says nothing about why anyone cared. The test that matters drives the
behaviour: a site cleaned up while evading a HARM must go live again afterwards — through the
network, and through the last line of defense. The stale-field assertion is the second test.
