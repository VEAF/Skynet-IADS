# FEAT-LAST-LINE-OF-DEFENSE — a dark site can notice what flies over it, and coverage follows what moves

Status: ✅ done — both tickets implemented and tested, and both mechanisms measured in DCS on
2026-09-19: a dark battery woken by proximity alone and silent again 45 s later, and a battery
handed back the moment the AWACS covering it flew out of range

Origin: The Reaper, 2026-09-17, on a VEAF mission built with veaf-tools:

> *"J'ai configuré Skynet sur une mission avec les outils VEAF. J'ai un problème, quand il y a des
> EWR rouge à portée, les SAM ne s'allument pas même si on est à portée voire très proche. Quand il
> n'y a plus d'EWR rouge, les SAM deviennent autonomes et actifs."*

Diagnosed from his `dcs.log` and the code, settled with Flogas and the historical IADS developers on
2026-09-19, then grilled on the design the same day. The VMCT half of the work — a helper cleanup,
the documentation and the vendoring — is in that repository's `FIX-SKYNET-HELPER-AND-VENDORING`.

## What is wrong

A SAM covered by one live EWR is pulled under network control: `setToCorrectAutonomousState` →
`resetAutonomousState` → `goDark()` → `enableEmission(false)`. **The site is then blind.** Its only
route back to life is `SkynetIADS.evaluateContacts`: an EWR **that covers this site** must hold the
target, and the target must pass the site's `isTargetInRange`. When the first half fails, the second
is never evaluated — proximity to the site is not an input anywhere in the cycle, because the only
sensor that could measure it is the one that was just switched off.

Lose every covering EWR and `goAutonomous()` hands the site back to the DCS AI, which lights up and
engages. Hence the inversion: killing the EWRs makes the batteries *more* dangerous.

And "covered" is weaker than it sounds. Coverage is a flat 2D distance between the EWR's radar and
the battery's, compared against the EWR's detection range — no horizon, no terrain, no altitude. It
says the EWR is **near** the battery, never that it is **feeding** it. One 55G6 listed 18 batteries
under its coverage in the reported log; three A-50s listed 16, 2 and 0 while detecting nothing at
all.

### Measured on the reporting log, 24 minutes of 5 s cycles

| measure | value |
|---|---|
| SAM status lines `ACTIVE:false / AUTONOMOUS:false` | 7 933 |
| SAM status lines `ACTIVE:true / AUTONOMOUS:false` | **0** |
| SAM status lines `ACTIVE:true / AUTONOMOUS:true` | 30 |
| `GOING LIVE` after coverage was built | only the 2 sites with no EWR parent |

Every network SAM went live once at startup — before coverage existed — then `GOING DARK`, then
never again.

**Stated honestly**: the closest contact to any network EWR in that log is 51.85 NM, so the
reporter's own close pass is *not* in this log. The mechanism is proven from the code.

## What was decided

Three shapes were weighed. **B**, waking on the whole kill zone, cancels the IADS for long-range
systems — a SA-10 would light up at 75 km. **C**, reverting the 2022 VEAF change that stopped
forcing large systems into EW watch, makes SEAD trivial. **A** was chosen: a *last line of defense*.

A site held dark keeps a short **virtual** detection radius of its own — Skynet's, no DCS radar
involved — and a hostile aircraft inside it makes the site go live with no radar contact anywhere.

The design was then grilled. What came out:

| Point | Decision |
|---|---|
| Radius | 10–15 km, **drawn once per site** at build time. Drawn per cycle, an aircraft loitering near the mean makes the site blink every 5 s |
| Distance | **2D**, as Skynet measures everything else |
| Persistence | The site stays lit **45 s** after the last pass, then falls silent on the normal cycle. Without it a fast pass lights the site for one cycle and nothing more |
| Filtering | **None** — no altitude ceiling, no aircraft-type list. Known and accepted trade-off: a short-range piece can light up for an aircraft it cannot reach, because the radius deliberately ignores the firing envelope. Requiring the kill zone would mean a Shilka, useful range ~2.5 km, never wakes inside a 10–15 km radius — and short-range pieces are the whole point |
| Default | **On**. Off means nobody finds it and the same report returns in six months. It changes existing missions; the PR body says so |
| Settings scope | Global to both coalitions for now; per network only if someone needs it |
| Public entry point | The wake-up is exposed as a **public API of this project**, used by this feature first, because VEAF's spotter network must wake a site from outside Skynet and the alternative is external code writing into internal state every cycle |

## Tickets

| # | Ticket | Status |
|---|---|---|
| 01 | [Last line of defense: a dark site wakes on close proximity](tickets/01-last-line-of-defense.md) | ✅ |
| 02 | [Refresh radar coverage for whatever moves](tickets/02-refresh-coverage-for-what-moves.md) | ✅ |

## How this is verified

**Not by unit tests alone.** The failure mode that matters here is a wake-up that is perfectly
tested and never called by the cycle — four bugs of this family already shipped green on the VEAF
side and were found in flight, because the tests called the handler and never what wires it.

So: a test mission under `demo-missions/`, with a SAM and a deliberately badly placed EWR, driven
through VEAF's DCS bridge. The check must be able to fail both ways — the site lights up when the
target crosses the radius, **and** falls silent once the persistence has run out. Note that the
bridge has to be injected into a mission that carries no `veaf-scripts.lua`, so the usual VEAF
injection path does not apply.

This also answers the open question at the end of `docs/evolutions.md`, which asks whether an MCP
exists to talk to a running DCS mission. It does: VEAF's `dcs-bridge`.

## Definition of done

- A dark site goes live when a hostile aircraft enters its drawn radius, and falls silent 45 s after
  the last pass.
- The radius is stable for a given site across a mission.
- Coverage follows what moves: an AWACS in transit loses the batteries it left behind, a mobile SAM
  site's parents follow it, and a live site whose parents did not change is never sent dark by a
  sweep.
- **A site silenced to evade an anti-radiation missile does not wake on proximity.** `goLive()`
  already guards on `harmSilenceID == nil`, but this becomes an explicit test: the last line of
  defense must not cancel HARM evasion, which is the subtlest behaviour in this project. Same for a
  site out of ammunition — it would light up for nothing and be killed for it.
- The public entry point exists, is documented in the README, and this feature is its first caller.
- `lua5.1 test/lua/run.lua` green; the in-sim check run and reported.

## Where this stands

Both tickets are written, tested and built. What is done, and how it was checked:

| Item | Where |
|---|---|
| Last line of defense, its four settings and its guards | `skynet-iads.lua`, `skynet-iads-sam-site.lua` |
| `SkynetIADS:reportContact(dcsUnit, samSite)`, the public door | `skynet-iads.lua`, documented in `documentation/api.md` |
| Periodic coverage sweep, individual link removal, per-element position and range | `skynet-iads.lua`, `skynet-iads-abstract-radar-element.lua` |
| 31 tests, almost all driving the real cycle | `test/lua/test_skynet_iads_last_line_of_defence.lua`, `test/lua/test_skynet_iads_coverage_refresh.lua` |

One deliberate departure from ticket 02's wording: it says to compare each site's **parent list**
before and after the sweep. The code compares its **autonomy** instead, which is strictly better —
a site that gains a second parent while keeping its first has a changed list and an unchanged
situation, and switching it off over that is the very defect the ticket is guarding against, the one
`3a94937` fixed on the other path. Found by `/pr-code-review` on this work, not by a test.

Checked by mutation rather than by the count: disabling the cycle hook, the persistence guard, the
coalition filter, the airborne filter, the parent-list comparison or the link removal each turns at
least one test red. The suite also caught a real defect while being written — the reference point a
sweep measures movement against was laid down by the first sweep, i.e. *after* the element had
moved, so the move that mattered measured zero and was missed. `markCoverageUpdated()` is that fix.

**The in-sim check: run, and both mechanisms hold.** 2026-09-19, on
`demo-missions/skynet-insim-last-line-of-defence.miz`, driven through VEAF's dcs-bridge, with the
scenario kept in readable form beside it as `demo-missions/skynet-insim-last-line-of-defence.lua`.
Every run below was flown from that file as the mission loads it — nothing hand-injected.

### What was measured

**Run 1, the last line of defense.** A battery the network held dark lit up on proximity alone and
fell silent again:

| | first run | replayed after a reload |
|---|---|---|
| radius drawn for the site | 10.9 km | **14.1 km** |
| lit up at | 9.27 km | 13.06 km |
| left the radius → report expired | **45 s** | **45 s** |
| went dark at | 27.29 km | 27.21 km |

At the moment it lit up: `ACTIVE=true` with `targetsInRange=false` — **no radar had designated
anything**, the EWR 106 km away saw nothing of an aircraft at 150 m — and `freshReport=true`, so it
was `reportContact` that woke it, not another path. `AUTONOMOUS=false` throughout: the battery
lights up *while staying in the network*, which is the behaviour this lot wanted and not the
inversion the report described.

Two things the second run settles that the first could not. The radius is **drawn once per site and
stable**: a single value across the mission's 75 samples, and a different one after a reload, which
is the per-site draw doing its job rather than a hard-coded distance. And the persistence is
**45 s to the second**, twice.

The site then stays lit for another ~45 s after the report expires. That is not the persistence
overrunning: `goDark()` has always refused to switch off a radar that is holding a target with
ammunition left, and Skynet's own status line shows the contact
(`CONTACT: TEST-INTRUDER-1 | DISTANCE NM: 8.56`). Pre-existing behaviour, and the right one — a
battery that can see its attacker has no business going back to sleep.

**Run 2, coverage follows what moves.** A battery whose only parent was an AWACS, and an AWACS
flying away from it. The geometry was built on two measured numbers: the A-50's real detection
range, read back in game (**204.5 km**), and the sweep's movement threshold, 10 NM. Starting at
190 km, the link was dropped at **211.0 km** — the same value on both runs — with `AUTONOMOUS`,
`parents` and the radar's own child count all flipping together: 1 → 0. Before this lot the
incremental rebuild never purged, and that battery would have stayed non-autonomous for the rest of
the mission with the aircraft at the other end of the map.

The 25 s between crossing the range and dropping the link is the movement threshold, not a delay:
the sweep only rebuilds for an element that has moved more than 18.5 km since its last rebuild, and
the reference point dated from enrolment at 190.1 km.

No script error in the log across any run.

### What the mission is

A SA-6 (`TEST-SAM-SA-6`) and a 55G6 early warning radar (`TEST-EW-far`) **106 km apart**. That
distance is the whole point: it is well inside the EWR's detection range, so Skynet's flat 2D
coverage declares the battery covered and the network holds it dark — while an aircraft on the deck
at 106 km is far under that radar's horizon. It is the reported situation, built on purpose.

It is a copy of `skynet-test-persian-gulf.miz`, which brings a working trigger chain (mist, the
compiled artifact, then the setup script) and terrain already known to carry these units. The demo's
own IADS would ruin the measurement — an SA-10 would down the intruder two hundred kilometres out —
so the scenario **destroys every group whose name does not begin with `TEST-`** at startup, and the
setup script embedded in the `.miz` is the scenario itself, replacing the demo's. `dcs-bridge.lua`
is embedded as a second startup trigger, which is the answer to this mission carrying no
`veaf-scripts.lua`.

### Flying it

Nobody has to fly. Start `dcs-serve`, load the mission, and drive it through the bridge's
`exec_lua`:

| Call | What it does |
|---|---|
| `SKYNET_TEST.geometry()` | separation, the EWR's detection range, the radius drawn for this site, how many parents it has, and what each group is standing on |
| `SKYNET_TEST.status()` | the line a run is read from: `ACTIVE`, `AUTONOMOUS`, `targetsInRange`, `freshReport`, and how far the intruder is |
| `SKYNET_TEST.launchIntruder()` | an A-10A from 40 km south to 40 km north at 150 m AGL and 200 m/s, crossing the radius in about two minutes. It is told to do nothing, hold fire and ignore threats, and it is made immortal — all four keep it on the straight track the measurement assumes, since a woken SA-6 fires and an intruder that attacks, evades or dies leaves its run. 150 m rather than the deck because at 106 km it stays under the radar horizon up to roughly 400 m, and there is no reason to spend that margin flying an AI into a ridge |
| `SKYNET_TEST.startWatch(5)` | on from the start; writes the status line into `dcs.log` every five seconds, so both edges of the run survive in the log |
| `SKYNET_TEST.startCoverageRun()` | run 2, on demand: spawns a battery and an AWACS 190 km from it in a second network, and starts its own watch. Not started at load — it builds a whole second IADS, which has no business happening in a mission somebody opened to look at run 1 |
| `SKYNET_TEST.coverageStatus()` | that run's line: the AWACS's distance and range, the battery's autonomy and parent count, and how many sites the AWACS covers |

### What the runs have to show

**Run 1**: `ACTIVE=false` while the intruder is far, `ACTIVE=true` while it is inside the radius,
and `ACTIVE=false` again once the persistence has run out. A run showing only the first two proves
nothing: the persistence expiring is half the check.

**Run 2**: `AUTONOMOUS=false parents=1` while the AWACS covers the battery, then
`AUTONOMOUS=true parents=0` once it has flown past its own detection range. Same rule — the
handing back is the half that the old code got wrong.

Prerequisites, on the machine running DCS: `dcs-serve` listening, and the bridge's own
[prerequisites](https://veaf.github.io/dcs-bridge/guide/prerequisites/) — `MissionScripting.lua`
must not be sanitised, or the bridge cannot open its socket.
