# In-sim HARM scenarios: a smoke suite

Status: in-progress

Answers GitHub issue #75 (https://github.com/VEAF/Skynet-IADS/issues/75).

## Why

The five in-sim HARM scenarios grew one fix at a time, so they don't match each other:

- two kinds of attacker, one of them copied into three `run.lua` files;
- four different rules for when to stop watching;
- some `verify.lua` files check exact sequences, others only the first values.

GitHub issue #75 is one result of this: `harm-point-defence` stops watching at the first match, so
a site that held for two seconds and then flapped would still pass.

The in-sim suite is a **smoke suite**. It proves what a stub cannot: in DCS, a real HARM is seen and
identified, and the sites react to it over real time without flapping. The HARM logic itself, such
as saturation, a site with targets in range still going silent, and the point-defence paths, has
Lua tests in `test/lua/` and stays there. A suite too long to run would not get run, so each
scenario checks one thing.

## Goals

- Five scenarios with a common `harm-` prefix, each checking one behaviour.
- One shared library, `insim-harm`, holding the aircraft and the rule for when to stop watching.
  The `test/README.md` rule is that a helper two scenarios need is not copied between them.
- Every scenario watches until the engagement is over, then checks exact sequences. Any extra
  dark/live flip fails the scenario it happens in, so flapping needs no scenario of its own.
- Closes #75.

## Non-goals

- New HARM logic, or any change to `skynet-iads-source/`.
- Covering every case in-sim. The edge cases (saturation, a second HARM extending a silence, the
  detection chances of several radars combining, running out of missiles) stay with the Lua tests.
- `munitions-wake-sites`, which is about waking sites, not HARM reaction.
- The other gaps listed under *In-sim suite: three small gaps* in `.tracker/IDEAS.md`. Only the
  timeout gap of `harm-point-defence` goes away with it.

## Anti-goals

- A scenario that passes whatever happens. A check stops only once the engagement is over.
- A scenario whose result depends on how fast the site uses up its missiles.
- A framework next to the existing engine.

## The scenarios

The only aircraft used are these two, from `insim-harm`:

- **The shooter.** An invisible, immortal F-16C bl.52d with one AGM-88C, given a target group and
  the direction it attacks from. Invisible, so that only its HARM is ever a contact.
- **The waker.** A visible, immortal aircraft that orbits beyond the site's missile range but inside
  its search radar's range. The site under test is set to
  `setEngagementZone(GO_LIVE_WHEN_IN_SEARCH_RANGE)`, so the network wakes it on the waker, and it is
  live with a real track and no EW role. The DCS AI holds fire at that distance, so no missiles are
  spent before the HARM arrives.

| Scenario | Tier | Sites | The HARM aimed at | Asserted, exactly |
|---|---|---|---|---|
| `harm-silences-site` | minimal | SA-6, unprotected, acting as EW | the SA-6 | `activeSite = {true, false, true}`, `harm = {false, true, false}` |
| `harm-dark-site-point-defence` | minimal | Dog Ear EW radar, SA-2 dark under it, SA-15 as the SA-2's point defence | the Dog Ear, its line passing over the SA-2 | `activeSite = {false}`, `activePointDefence = {false, true, false}`, `pointDefenceLatched = {false, true, false}`, `harm = {false, true, false}` |
| `harm-site-engages-harm` | full | SA-10, unprotected, under a 1L13; the waker | the SA-10 | `activeSite = {false, true}`, `defending = {false}`, `harm = {false, true, false}` |
| `harm-point-defence-ew` | full | SA-6 acting as EW, SA-15 as its point defence, 1L13 | the SA-6 | `activeSite = {true}`, `activePointDefence = {false, true, false}`, `pointDefenceLatched = {false, true, false}`, `harm = {false, true, false}` |
| `harm-point-defence-engaging` | full | SA-2 under a 1L13, SA-15 as its point defence; the waker | the SA-2 | `activeSite = {false, true}`, `defending = {false}`, `activePointDefence = {false, true, false}`, `pointDefenceLatched = {false, true, false}`, `harm = {false, true, false}` |

### The probes

A scenario watches its elements through `insim-watch` probes, each sampled once a second. A probe is
named after what it reads, the same way in every scenario:

| Probe | Reads | Meaning |
|---|---|---|
| `activeSite` | the judged site's `isActive()` | Skynet has set the site live |
| `activePointDefence` | the point defence's `isActive()` | Skynet has set the point defence live |
| `activeEwr` | the EW radar's `isActive()` | Skynet has set the EW radar live. Reported, not judged |
| `pointDefenceLatched` | the point defence's `getIsPointDefending()` | the latch holds the point defence live for a HARM. It is set by `pointDefencesGoLive()` and released by `cleanUpOldObjectsIdentifiedAsHARMS()` once the last HARM is gone |
| `harm` | the judged site's `getNumberOfObjectsItentifiedAsHARMS() > 0` | the site remembers at least one HARM aimed at it |
| `defending` | the judged site's `isDefendingHARM()`, that is `harmSilenceID ~= nil` | a HARM silence timer is running. `goSilentToEvadeHARM()` turns the DCS AI off when it starts one, and `finishHarmDefence()` turns it back on |

"Live" in the `active*` probes is Skynet's own `aiState` flag. `goLive()` sets it when it calls
`enableEmission(true)` and `setOnOff(true)`; `goDark()` clears it with `enableEmission(false)`. The
probe records what Skynet ordered, not what DCS reports of the radar. In
`harm-dark-site-point-defence` the Dog Ear is only the HARM's target and the network's EW radar, so
`activeEwr` is reported, not judged.

### Where they come from

| Today | Becomes |
|---|---|
| `harm-defence` | `harm-silences-site` |
| `harm-point-defence-dark-site` | `harm-dark-site-point-defence`, with the Dog Ear as both target and EW radar in place of the SA-6 and the 1L13 |
| (none) | `harm-site-engages-harm` |
| `harm-point-defence` | `harm-point-defence-ew` |
| `harm-engaging-defended` | `harm-point-defence-engaging`, with the waker in place of the attacker that waits to be engaged |
| `harm-engaging-undefended` | removed: the silence of a site with targets in range is covered by the Lua test `testSA2WillGoDarkWithTargetsInRangeAndHARMDetected` |

`insim-harm.attackOnceEngaged` has no user left and is removed. `firedBy` stays if a scenario still
needs it.

### When a scenario stops watching

One function in `insim-harm`, used by every scenario. It waits, each wait bounded, until:

1. the HARM object no longer exists: shot down, on the ground, or flown past;
2. every judged site has forgotten it, meaning `harm` is back to false (up to
   `objectsIdentifiedAsHarmsMaxTargetAge`, 60 s, after it was last seen) and any silence is over
   (`isDefendingHARM()` false);
3. a short settling time has passed, long enough for a late flip to show.

Then it returns the watch's report. A wait that times out is a measurement, as the engine already
treats it. Each scenario's `timeout` keeps a 20–30 s margin over the sum of its waits, as the rest of
the suite does.

### Judged as `invalid`, not `fail`

- the shooter never fired;
- the network never woke the site on the waker (C, E);
- the site fired at the waker (C, E): the hold-fire assumption failed, and the run proves nothing.

## Approaches considered

1. **The scenarios share one library, `insim-harm`.** Chosen. It removes the duplication without
   adding anything to the engine.
2. **One generic scenario driven by data**, a single runner playing case tables. Turned down: a
   framework next to the engine, and a failing run is harder to read.
3. **Keep the five scenarios and only fix the waits and checks.** Turned down: it leaves the copies
   and the two kinds of attacker in place.

## Decided along the way

- One check per scenario. A scenario holds only the sites its check needs.
- When an EW radar is present, the shooter is invisible, and what wakes the network is a separate
  immortal aircraft.
- The missile timing is solved by keeping the site from firing at the waker at all, not by timing
  the HARM after a first shot.
- For `harm-dark-site-point-defence`, the HARM is aimed at the EW radar, so it has to be one the DCS
  AI can target. In the dcs-lua-datamine (`_G/db/Units/Cars/Car/`), `1L13 EWR`, `55G6 EWR` and
  `FPS-117` carry no `RADAR_BAND*_FOR_ARM` attribute; `Dog Ear radar` carries
  `RADAR_BAND1_FOR_ARM` and `RADAR_BAND2_FOR_ARM`, and Skynet supports it as an `ewr`
  (`skynet-iads-supported-types.lua`). Reading those attributes as "a valid target for an ARM" is an
  inference that a run in DCS confirms.
- Tiers: `harm-silences-site` and `harm-dark-site-point-defence` are `minimal`, the other three
  `full`.

## Left to the build

- **One HARM in `harm-silences-site`**, where `harm-defence` fires two. A second HARM extending the
  silence is an edge case for the Lua tests.
- **The settling time** in the stop rule: about one contact cycle plus margin, set from what a run
  shows.
- **The waker's type and orbit.** It must be inside the SA-10's and SA-2's search radar range and
  the 1L13's detection range, and outside their missile range. The ranges come from the datamine and
  Skynet's range data, not from memory, and the first run checks them.
- **Where the SA-10 stands**: a catalogue zone the shooter can reach with the HARM's line clear of
  any other site. It is alone in its scenario, so `ZONE-SITE-2` will do unless a run says otherwise.
- **The verdict cases** in `test/insim-tools/test_scenario_verdicts.py` are rewritten for the five
  scenarios. Each gets a pass case and a fail case for every assertion, a late flip among them.
- `test/README.md`'s `insim-harm` table is rewritten to match the library.

## Constraints

- **The mission template changes**: a catalogue fixture `FIXTURE-EW-DOGEAR` goes into
  `test/insim/miz/insim-ca-main.template.miz`, following `CONTRIBUTING.md` and `test/README.md` on
  `.miz` files.
- **Only DCS can show it works.** Every scenario has to pass in DCS before the pull request, and
  the pull request says so. Things to check on the first run:
  - the AI fires a HARM at the Dog Ear;
  - the waker draws no fire;
  - `goDark()`'s guard counts the waker as an engageable target in search-range mode;
  - the HARM's line to the Dog Ear passes close enough to the SA-2 to be identified by it (within
    15° and 20 NM).
- No change to `skynet-iads-source/`, so no `CHANGELOG.md` entry.
- Branch `test/insim-harm-scenarios`. The pull request carries `Closes #75`.
