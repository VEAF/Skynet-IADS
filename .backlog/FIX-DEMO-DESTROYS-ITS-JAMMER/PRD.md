# FIX-DEMO-DESTROYS-ITS-JAMMER — the Persian Gulf demo kills the aircraft it just armed

Status: 🔄 in-progress

Origin: found on 2026-09-20 while flying the refreshed demo for
`FIX-DEMO-MISSIONS-SHIP-A-2023-SKYNET`. David took the `Hornet SA-11-2 jammer support` slot and
nothing jammed anything. Recorded in `docs/evolutions.md` rather than fixed, so that lot stayed on
its subject. David reopened it on 2026-09-21, before cutting the first release: a demo that cannot
demonstrate its own jammer should not be what a newcomer downloads.

## The defect

`demo-missions/skynet-iads-setup-persian-gulf.lua` ends its jammer section with a guard whose own
comment says it "has nothing to do with the IADS":

```lua
--:77
local hornet = Unit.getByName('Hornet SA-11-2 Attack')
if hornet == nil then
	Unit.getByName('jammer-emitter'):destroy()
	jammer:removeRadioMenu()
end
```

The intent is walder's and it is reasonable: `jammer-emitter` is an **AI F-4E** that takes off in
formation with the player, so if nobody occupies the Hornet slot it would fly the mission alone.

The intent is never honoured. The setup script runs from the `Load SKYNET` trigger at
`triggerStart`, **t=0**, and `Hornet SA-11-2 Attack` is a **client slot** — confirmed in the mission
table, `["skill"] = "Client"`, unit 88 of group `Hornet SA-11-2 jammer support`. A client slot does
not exist as a `Unit` until a player occupies it, which cannot have happened before the mission has
started. So `Unit.getByName` returns `nil` on **every** load, whatever anyone does, and the demo
destroys its own jammer every single time.

**Not a regression.** The group definition is byte-identical in the December 2023 archive and the
guard predates VEAF. The jammer demonstration has only ever worked by luck of timing.

## The proof, from the run of 2026-09-20

Read from the F10 → Other menu and the order of the setup script:

| line | what it does | observed in the sim |
|---|---|---|
| 66 | `redIADS:addRadioMenu()` | **F1 present** |
| 72–74 | creates the jammer, arms it, adds its menu | would have raised on a nil emitter, so the emitter existed |
| 78–80 | the guard: destroys the emitter **and removes the menu** | **no `Jammer:` entry** |
| 89 | `blueIADS:addRadioMenu()` | **F2 present**, so the script ran to the end |

Two menus present and the third missing means the jammer menu was created and then removed, and the
guard is the only code that removes it. Measured alongside: `Unit.getByName('jammer-emitter')`
returns nil in flight. `runCycle` finds its emitter dead, calls `masterArmSafe()` and disarms
without a word.

> **One piece of evidence withdrawn, 2026-09-21.** The first draft also cited *"zero `SKYNET: JAMMER:`
> lines in the log"*. It does not discriminate: measured on the **fixed** build, with the F-4E alive
> and tracked by the network at 53 NM, the log still holds zero of them — because the jammer only
> writes one when it is within `maximumEffectiveDistanceNM` of a **live** radar, which takes a
> specific geometry this run never reached. Absence of those lines is consistent with the defect and
> with a perfectly healthy jammer, so it proves nothing. What does discriminate is the missing F10
> submenu between two present ones, and `Unit.getByName` returning nil in flight — both measured.

## The decision — 2026-09-21

Three options were put to David. **(b), drop the guard**, is what he chose.

| | option | why not |
|---|---|---|
| a | delay the guard ten to thirty seconds | keeps walder's intent, but stays a bet: a long briefing loses the race again, and silently |
| **b** | **drop the guard** | **chosen** |
| c | hook it to `S_EVENT_BIRTH`, cancel on the slot being taken | the correct behaviour, but twenty lines of event handling in a file whose job is to be read as an example |

The reasoning for (b): this mission is executable documentation, and its only reader is somebody who
wants to see Skynet work. The guard protects against an aesthetic annoyance — an AI F-4E flying
alone — and breaks the demonstration on 100% of loads. walder's own comment says the block has
nothing to do with the IADS.

What (b) costs, stated plainly: if nobody takes the Hornet slot, the F-4E flies its route on its own
and jams the red network anyway. For a demo whose point is to show jamming, that is closer to a
feature than a defect.

## What to do

| | Ticket |
|---|---|
| 1 | [drop the guard that destroys the jammer](tickets/01-drop-the-guard-that-destroys-the-jammer.md) |

One branch, one pull request. Nothing under `skynet-iads-source/` changes, so the artifact does not
need rebuilding — but `demo-missions/` is a release asset, so `CHANGELOG.md` records it.

## Two missions, not one

Worth stating because the first draft of this PRD got it wrong: **`skynet-test-persian-gulf.miz` and
`skynet-test-persian-gulf-stress-test.miz` load the same setup script**, and both archives carry the
same two units — a `Hornet SA-11-2 Attack` slot at `["skill"] = "Client"` and an AI `jammer-emitter`
F-4E at `["skill"] = "High"`. Verified by extracting both mission tables. So both demos have been
destroying their jammer on every load since 2023, and the single deletion below repairs both.

`python build-tools/miz-suite.py check` names the shared script for each archive, which is how the
overlap surfaced.

## What this lot does not touch

**The MOOSE A2A connector demo.** It loads its own setup script and has no jammer.

**The `.miz` archives.** The setup script is not committed inside them; `python
build-tools/miz-suite.py build` assembles the playable mission from the loose copy. Nothing to
re-bake.

## Definition of done

- The guard is gone, and nothing else in the file has moved.
- The entry in `docs/evolutions.md` is removed, because it recorded a deferred decision that has now
  been taken — the record of it lives here.
- `CHANGELOG.md` records what somebody downloading the demo will notice.
- **Verified in DCS on 2026-09-21**, both directions, through `build-tools/run-smoke.py`'s
  `jammer-alive` check: `emitter-gone` on a build without this fix — measured while David occupied
  the `Hornet SA-11-2` slot, which is the proof the guard does not depend on the slot at all — and
  `alive` on a build carrying it, 5/5 checks green. The network then reports the F-4E as a contact
  at 53 NM, which it cannot do for an aircraft that no longer exists. The stress-test demo shares
  the fix and is not flown separately: it differs only in how many sites it puts on the map.

The last point is the one this repository cannot check on its own, which is the subject of the lot
that follows this one, `FEAT-IN-SIM-SMOKE-TESTS`. Its first target is this very mission, and *"the
jammer is still alive at t+60s"* is one of its checks — so the defect fixed here is also what proves
the check can fail.
