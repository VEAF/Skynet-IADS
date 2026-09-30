# In-sim test report — FEAT-LAST-LINE-OF-DEFENSE

**Date**: 2026-09-19, 20:04–20:45 local
**Operator**: David (DCS), Claude (bridge)
**Verdict**: **both mechanisms of the lot behave as specified, measured in DCS.** No script error in
the log across any run.

This report exists because the lot's PRD says the check cannot be done by unit tests alone: *the
failure mode that matters here is a wake-up that is perfectly tested and never called by the
cycle.* The standalone suite proves the code is right; only a run inside DCS proves the cycle calls
it.

## Environment

| | |
|---|---|
| DCS World | 2.9.29.27468 (x86_64, MT, Windows NT 10.0.26200) |
| Skynet | **3.5.0**, build 19.09.2026 1946Z, as the mission's embedded artifact reports itself |
| Mission | `demo-missions/skynet-insim-last-line-of-defence.miz`, theatre Persian Gulf — moved to `unit-tests/last-line-of-defence/` on 2026-09-20, after this run |
| Scenario | `demo-missions/skynet-insim-last-line-of-defence.lua`, embedded in the mission and loaded by its startup trigger — same move |
| Driven by | VEAF [dcs-bridge](https://github.com/VEAF/VEAF-dcs-bridge), `dcs-serve` on 127.0.0.1:8080, `dcs-bridge.lua` as a second startup trigger |
| Evidence | `Saved Games/DCS/Logs/dcs.log`, status line written every 5 s by the scenario's own watch |

The mission is a copy of `skynet-test-persian-gulf.miz`; the scenario destroys every group whose
name does not begin with `TEST-` at startup — **28 groups removed**, confirmed in the log — so the
demo's own IADS cannot influence the measurement.

## Run 1 — the last line of defense

### Montage

A SA-6 (`TEST-SAM-SA-6`: one `Kub 1S91 str`, two `Kub 2P25 ln`) and a 55G6 EWR (`TEST-EW-far`),
**106.0 km apart**. Both on land, confirmed in game by `land.getSurfaceType`.

That distance is the montage. Read back from the running mission rather than assumed:

| Measured in game | Value | Why it matters |
|---|---|---|
| EWR detection range | **267.5 km** | 106 km is well inside it, so Skynet's flat 2D coverage declares the battery covered — and the network holds it dark |
| Parent radars of the battery | **1** | it really is under network control, which is the premise |
| Radius drawn for this site | 10.9 km / 14.1 km | the per-site draw from the 10–15 km setting |

An aircraft at 150 m AGL is far below that radar's horizon at 106 km. This is the reported
situation rebuilt on purpose: *fly under the EWR's horizon and no battery reacts*.

### Protocol

`SKYNET_TEST.launchIntruder()` spawns an A-10A 40 km south of the site, flying north across it at
150 m AGL and 200 m/s, then 40 km beyond. Four settings keep it on the track the measurement
assumes, all confirmed applied in the log (`[hold fire, ignore threats, immortal]`):

- **task "Nothing"** and **ROE weapon hold** — a CAS flight would break off to attack the very
  battery being measured;
- **no reaction to threat** — an evading aircraft leaves its track;
- **immortal** — a woken SA-6 fires, and an intruder shot down cannot demonstrate the silence
  coming back.

These are properties of the measurement, not of the feature. 150 m rather than the deck because at
106 km the aircraft stays under the radar horizon up to roughly 400 m, so there is no reason to
spend that margin flying an AI into a ridge.

### Results

Run A was flown with the scenario injected through the bridge; run B was flown after reloading the
mission, **from the versioned file as the mission loads it**, changing nothing else.

| | run A | run B |
|---|---|---|
| radius drawn for the site | 10.9 km | 14.1 km |
| **lit up** | 20:15:06 at **9.27 km** | 20:38:20 at **13.06 km** |
| closest approach | 0.05 km | 0.14 km |
| left the radius | 20:17:10 at 11.06 km | 20:40:50 at 14.65 km |
| **report expired** | 20:17:55 — **+45 s** | 20:41:35 — **+45 s** |
| went dark | 20:18:41 at 27.29 km | 20:42:00 at 27.21 km |
| total time lit | 215 s | 220 s |

At the moment it lit up, the four fields together are the demonstration:

```
ACTIVE=true  AUTONOMOUS=false  targetsInRange=false  freshReport=true  radius=10.9km  intruderAt=9.27 km
```

- `ACTIVE=true` with **`targetsInRange=false`**: no radar had designated anything. The network saw
  nothing, which is the whole point.
- `freshReport=true`: it was `reportContact` that woke it, not another path.
- `AUTONOMOUS=false`: the battery lights up **while staying in the network**. It is not handed back
  to the DCS AI, which is what the original report described as the inversion.

### What the second run settles that one run could not

- **The radius is drawn once per site and stable.** A single value across the mission's 107
  samples, and a different one after a reload. It is the per-site draw doing its job, not a
  distance hard-coded somewhere.
- **The persistence is 45 s to the second, twice**, on two runs whose radii differed by 3.2 km.
  Two independent measurements landing on the same figure.

### The extra delay before going dark, explained

The site stays lit past the report expiring — 46 s in run A, 25 s in run B. It is **not** the
persistence overrunning, and the difference between the two runs is the clue: it is not a fixed
delay at all.

`goDark()` has always refused to switch off a radar that is holding a target with ammunition left.
Skynet's own status line shows the battery tracking the intruder on its own radar, every 5 s, well
after the report expired — and the last one:

```
20:18:31  SKYNET: CONTACT: TEST-INTRUDER-1 | TYPE: A-10A | DISTANCE NM: 13.46
20:18:41  (went dark)
```

The contact disappears at 13.46 NM (24.9 km) and the site goes dark on the next cycle. Pre-existing
behaviour, older than this lot, and the right one: a battery that can still see its attacker has no
business going back to sleep. The last line of defense lights the site; what keeps it lit
afterwards is its own radar.

## Run 2 — coverage follows what moves

### Montage

A second network (`COVERAGE-TEST`), independent of the first and 700 km away, so neither check can
disturb the other. In it: a SA-6 whose **only** parent is an AWACS, and an A-50 flying straight
away from it.

The geometry rests on two numbers that were measured rather than guessed:

| | Value | Source |
|---|---|---|
| A-50 detection range | **204.5 km** | read back in game from the enrolled element |
| Sweep movement threshold | 10 NM (18.5 km) | `COVERAGE_UPDATE_MOVEMENT_NM` in the sources |
| Sweep interval | 10 s | `coverageRefreshInterval` default |

Hence the AWACS starting at **190 km**: inside its own range, therefore covering; the range is
crossed at 204.5 km and the movement threshold at 208.6 km, and the first sweep past both can drop
the link. The battery sits 633 km from `TEST-EW-far`, so the fixed radar cannot be a second
parent — a battery with two parents would not change autonomy when one of them leaves.

### Results

| | run A (injected) | run B (from the file) |
|---|---|---|
| start | 20:28:29 at 190.1 km — `AUTONOMOUS=false parents=1`, AWACS covers 1 site | 20:36:01, identical |
| range crossed | 20:29:54 at 205.5 km — still held | — |
| **link dropped** | 20:30:19 at **211.0 km** | 20:37:51 at **211.0 km** |
| after | `AUTONOMOUS=true parents=0`, AWACS covers 0 site | identical |

The same distance on both runs, to within 100 m. Autonomy, the battery's parent count and the
radar's own child count all flip together — the link is genuinely removed from both sides, which is
the purge the incremental rebuild never did. Before this lot, that battery would have stayed
non-autonomous for the rest of the mission with the aircraft at the other end of the map.

**The 25 s between crossing the range and dropping the link is the movement threshold, not a
delay.** The reference point dated from enrolment at 190.1 km, so the sweep only rebuilt once the
AWACS had flown 18.5 km, i.e. past 208.6 km.

## What this proves, and what it does not

Proved in DCS:

- a battery held dark by the network wakes on proximity alone, with no radar contact anywhere;
- it wakes **into** the network rather than being handed to the DCS AI;
- it falls silent 45 s after the last pass through its radius;
- the radius is per-site and stable for the duration of a mission;
- a battery covered only by a moving radar is handed back once that radar leaves;
- the cycle really calls all of the above — which is what no stub test can show.

**Not covered by this report**, and still resting on the standalone suite alone:

- a site silenced to evade an anti-radiation missile must not wake on proximity — asserted by
  tests, never flown;
- a site out of ammunition must not wake either — likewise;
- a **mobile SAM site** whose own parents follow it (a SA-15 or a Shilka in a convoy). Run 2 moved
  the radar, not the battery;
- one battery type (SA-6) and one EWR type (55G6) only, on one map;
- a single radial track through the centre of the radius. A tangential pass, or one that clips the
  edge, was not flown;
- the intruder was immortal and forbidden to fire, so nothing here says anything about an actual
  engagement — only about who is switched on.

## Reproducing this

On the DCS machine: `dcs-serve` running, and `MissionScripting.lua` not sanitised, or the bridge
cannot open its socket. Then load `skynet-insim-last-line-of-defence.miz` and, through the bridge's
`exec_lua`:

```lua
SKYNET_TEST.geometry()          -- montage sanity: separation, ranges, radius, parents, ground
SKYNET_TEST.launchIntruder()    -- run 1
SKYNET_TEST.startCoverageRun()  -- run 2, in its own network
```

Both write their status into `dcs.log` every 5 s on their own; the transitions are what to read
back. `SKYNET_TEST.status()` and `SKYNET_TEST.coverageStatus()` return the same lines on demand.
