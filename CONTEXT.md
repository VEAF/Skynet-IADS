# Skynet — domain vocabulary

The words this codebase uses, and what they actually mean. Several of them are narrower than they
sound, and confusing them produces bugs that raise no error — only a battery that does not fire.

## The idea

A real integrated air defence system does not leave every radar emitting. Search radars watch, they
pass tracks down a chain of command, and a firing battery only lights up when it is about to shoot.
That is what makes it survivable against anti-radiation missiles.

Skynet models that: **a site under network control has its emission switched off**, and is turned
back on only when the network hands it something to engage. Everything below serves that sentence.

## The elements

| Term | Meaning |
|---|---|
| **IADS** | One network, one coalition. `SkynetIADS`. A mission usually runs two, one per side. |
| **SAM site** | A DCS group holding launchers and radars. `SkynetIADSSamSite`. Dark by default under network control. |
| **EWR** | An early-warning radar. `SkynetIADSEWRadar`. Permanently lit, feeds contacts to the network. |
| **AWACS** | An airborne or shipborne radar. `SkynetIADSAWACSRadar`, chosen by DCS category rather than by type. It is an EWR that moves, which is the source of most of its special cases. |
| **Command centre** | An optional unit the network depends on. Destroy them all and every element goes autonomous. A network with **no** command centre declared is considered to have a working one. |
| **Point defence** | A short-range site attached to another, to cover it while it hides from an anti-radiation missile. |
| **Contact** | A detected target, wrapped in `SkynetIADSContact`, with an age and a HARM state. |

## The words that mislead

### "Covered" does not mean "informed"

An EWR **covers** a SAM site when the flat 2D distance between their radars is smaller than the
EWR's detection range. No horizon, no terrain, no altitude. It says the EWR is **near** the battery
— never that it is feeding it anything. A single long-range radar can "cover" eighteen batteries it
will never usefully serve, and a blind AWACS covers everything within its nominal range while
detecting nothing at all.

Coverage decides **autonomy**, not designation. They are separate questions and the code treats
them separately.

### "Autonomous" means abandoned, not independent

A site is **autonomous** when no valid parent radar covers it. It is then handed back to the DCS AI,
which lights it up and engages on its own. So autonomy makes a battery *more* dangerous, not less —
destroying every EWR in a sector wakes up everything that was hiding behind them. This surprises
players, and it is the intended behaviour.

A parent is valid when it exists, has power, has a connection node, is not destroyed, and **acts as
EW**.

### "Acting as EW" is a role, not a type

`actAsEW` is a flag on any radar element. An EWR is given it when it joins. A **SAM site** can be
given it too, and then it stays lit permanently and feeds the network like a radar would — it is the
lever for a site that must watch its own sector. The cost is that it is visible and targetable.

### "Go live" and "go dark" are about emission

`goLive()` turns the emitter on, sets alarm state red and weapons free. `goDark()` turns the emitter
off — but refuses while the site is tracking, has missiles in flight, or is hiding from an
anti-radiation missile. Neither is a simple setter; both carry conditions worth reading before
calling.

## The cycle

Every `contactUpdateInterval` seconds (5 by default), `SkynetIADS.evaluateContacts` runs:

1. every SAM site is told a cycle is starting, which clears its "I have a target" flag;
2. each usable EWR — plus every SAM site acting as EW — is lit and asked what it detects;
3. the contacts are merged into one list, aged out after `maxTargetAge` seconds;
4. each battery **covered by an EWR that holds a contact** is offered every contact, and lights up
   for the first one inside its firing envelope;
5. every site whose flag is still clear at the end of the cycle goes dark.

Step 4 is where the design shows: a battery cannot notice anything itself, because step 2 never asks
a dark site what it sees. It is blind by construction, and that is the point — until it is not, which
is what the last line of defense addresses.

## Radar ranges are read once

`setupRangeData` reads a radar's detection range from `getSensors()` at the moment the element is
built, and nothing reads it again. A bad answer at that instant fixes the range for the whole
mission: the site detects nothing and never lights up. VEAF's helper carries a re-read for exactly
this reason.

## What the project is not

Skynet does not spawn anything, does not manage missions, and does not know about VEAF. Group
enrolment, mission configuration and radio menus belong to the consumer — in VEAF's case,
`veafSkynetIadsHelper.lua`. When a behaviour looks like it should be here, check whether it is
actually theirs: automatic AWACS enrolment, for instance, is VEAF's, not this project's.
