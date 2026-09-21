---
name: skynet-runtime-debug
description: Diagnose a Skynet runtime problem in DCS from a dcs.log — a SAM that never fires, a radar that detects nothing, a network that stays asleep. Use when someone reports in-game air-defence behaviour rather than a code defect.
---

# Diagnosing Skynet from a DCS log

Almost every Skynet report is *"the SAMs do not work"*, and almost every one of them is decidable
from the log alone — the status page carries the whole state of both networks, every five seconds.
Read it before theorising.

## Get the output

Skynet only prints when debug is on. Through VEAF:

```yaml
modules:
  SKYNET:
    enabled: true
    debug_red: true      # or debug_blue
```

Directly: the flags live in `SkynetIADSLogger`'s `debugOutput` table — `IADSStatus`, `contacts`,
`radarWentLive`, `radarWentDark`, `addedSAMSite`, `addedEWRadar`, `harmDefence`, `jammerProbability`.
`IADSStatus` is the one that prints the page; `radarWentLive`/`radarWentDark` give one line per
state change and are worth having together.

Log location: `%USERPROFILE%\Saved Games\DCS\Logs\dcs.log`. Everything is prefixed `SKYNET:`.

## Read the page, not the impression

One cycle prints a SAM block then an EW block per network:

```
SKYNET: GROUP: SA10 - Minevody | TYPE: SA-10
SKYNET: ACTIVE: false | AUTONOMOUS: false | IS ACTING AS EW: false | CAN ENGAGE AIR WEAPONS : true | CAN ENGAGE HARMS : true | HAS AMMO: true | DETECTED TARGETS: 0 | DEFENDING HARM: false | MISSILES IN FLIGHT: 0
SKYNET: NO CONNECTION NODES SET
SKYNET: NO POWER SOURCES SET
SKYNET: SAM SITES IN COVERED AREA: 3
...
SKYNET: CONTACT: Pilot #448 | TYPE: F-15C | DISTANCE NM: 81.63
```

What each field tells you:

| Field | Reading |
|---|---|
| `ACTIVE: false / AUTONOMOUS: false` | held dark by the network. Normal — and the state to count. |
| `ACTIVE: true / AUTONOMOUS: true` | no valid parent, handed to the DCS AI. It fires on its own. |
| `ACTIVE: true / AUTONOMOUS: false` | the network designated a target. **This is the line that proves the chain works.** |
| `IS ACTING AS EW: true` | this battery is a permanent watcher, lit on purpose. |
| `HAS AMMO: false` | it will never go live again — `goLive` refuses without ammunition. |
| `DEFENDING HARM: true` | deliberately silent, evading a missile. Do not read it as a failure. |
| `SAM SITES IN COVERED AREA: N` | how many batteries this element **covers**, which is a distance, not a promise. See `CONTEXT.md`. |
| `CONTACT: … DISTANCE NM:` | distance from **the element printing the block**, not from the player. |

## The measurements that decide

Counting across the whole log beats reading one cycle. These are the ones that have settled real
reports:

```bash
# Did any battery ever light up under network control? Zero here means the chain never closed.
grep -o "ACTIVE: [a-z]* | AUTONOMOUS: [a-z]*" dcs.log | sort | uniq -c

# Do the early-warning radars see anything at all?
grep -o "DETECTED TARGETS: [0-9]*" dcs.log | sort | uniq -c

# Which elements lit up, and when
grep -o "GOING LIVE: .*" dcs.log | sort | uniq -c
grep -c "GOING DARK" dcs.log

# Per-element detection rate and coverage over time (catches a blind AWACS, or coverage that grows)
```

A network where every site reads `ACTIVE: false / AUTONOMOUS: false` for the whole mission and no
`GOING LIVE` appears after start-up is not broken at the battery — the contacts never arrived.

## The three shapes a report takes

| What the log shows at the moment of the pass | Where the problem is |
|---|---|
| EWRs at `DETECTED TARGETS: 0` | nothing was detected. Terrain, radar horizon, a badly placed radar — tactics, usually, not code |
| An EWR holds contacts, the covered battery stays `ACTIVE: false` | the chain is broken between designation and go-live. This is the one worth reading code for |
| The battery is already `AUTONOMOUS: true` | no parent covers it; it is on its own and the question is something else |

## Traps that have cost time

- **A silent element is not necessarily a broken one.** Check `RADAR RANGE ZERO` lines (VEAF's
  helper emits them): a radar whose range was read as zero detects nothing for the whole mission and
  looks identical to one that is simply out of position.
- **Coverage grows and never shrinks** for a moving element, because the incremental rebuild only
  adds. An AWACS that has transited may "cover" batteries hundreds of kilometres behind it.
- **The distances in the page are element-relative.** A contact at 4 NM in a SAM block is 4 NM from
  that battery; in an EWR block, 4 NM from that radar. Do not compare them across blocks.
- **Correlate with the DCS lines, not only the Skynet ones.** `ASYNCNET`, `release unit` and slot
  changes sit in the same file and often explain the millisecond before an error.
- **Check the version first.** The first line of the compiled script prints its version and build
  date. A mission may be running a build that predates the fix you are looking for — the VEAF copy
  has run a month behind.
