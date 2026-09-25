# SkynetIADS — context

## Premise

Air defences in DCS are always live, radars permanently emitting. That is neither realistic nor good
gameplay:

- they are always visible on passive enemy sensors;
- they are easily attacked with HARMs.

## What is SkynetIADS

Skynet is a script that makes DCS air defences behave like a real integrated air defence network.
It governs how the air defence groups a mission already contains behave. Everything upstream of
that — creating those groups, enrolling them, the mission's own logic — belongs to the script that
calls Skynet.

### Minimum emissions

EWRs stay on and watch the airspace from afar; SAM sites keep their radars off. Each cycle the
network collects what the EWRs have detected and offers those contacts to the sites they cover. A
site that finds one inside its own firing envelope goes live and engages it. Until that moment it is
hidden, which makes it both more survivable and more effective.

### HARM defence

Skynet takes a SAM site or an EWR dark when it believes a HARM is homing on it, to break the
missile's guidance.

## Vocabulary

| Term | Meaning |
|---|---|
| DCS | Digital Combat Simulator, the military flight simulator SkynetIADS is designed for. |
| IADS | Integrated Air Defence System. SkynetIADS builds IADS networks in DCS missions, usually one per coalition. |
| SAM site | A DCS group holding launchers and radars. Dark by default under SkynetIADS control. |
| EWR | An early-warning radar. Permanently lit, feeds contacts to the network. |
| AWACS | An airborne or shipborne radar. An EWR that moves. |
| HARM | High speed anti radiation missile — a missile that homes on a radar's emissions. |
| Command centre | An optional unit the network depends on. Destroy them all and every element goes autonomous. A network with **no** command centre declared is considered to have a working one. |
| Point defence | A short-range SAM site attached to another, to cover it while it hides from a HARM. |
| Contact | A target detected by the network, with an age and a HARM state. |
| Acting as EW | A SAM site set to feed the network as an EWR does. It then stays live permanently, and is visible and targetable in exchange. |
| Live / Dark | Emission state of an air defence radar. This is the lever SkynetIADS uses to simulate IADS network behaviour. |

## Notable concepts

### The cycle

Every `contactUpdateInterval` seconds (5 by default), `SkynetIADS.evaluateContacts` runs:

1. every SAM site is told a cycle is starting, which clears its "I have a target" flag;
2. each usable EWR — plus every SAM site acting as EW — is lit and asked what it detects;
3. the contacts are merged into one list, aged out after `maxTargetAge` seconds;
4. each battery **covered by an EWR that holds a contact** is offered every contact, and lights up
   for the first one inside its firing envelope;
5. every site whose flag is still clear at the end of the cycle goes dark.

Step 4 is where the design shows: a battery cannot notice anything itself, because step 2 never asks
a dark site what it sees. It is blind by construction, and that is the point — until it is not, which
is what the last line of defence feature addresses.

### Covered SAM sites

An EWR feeds the SAM sites it **covers**. An EWR covers a SAM site when the flat 2D distance between
their radars is smaller than the EWR's detection range: no horizon, no terrain, no altitude, only
whether the EWR is near the battery. So a mission can be built in which a site is covered by an EWR
that cannot see anything in that site's engagement range.

### Autonomous SAM sites

An autonomous SAM site is still part of the IADS but has been handed back to the DCS AI, which runs
it on its own radar. This happens when no EWR covers it any more — an isolated site, or one whose
covering EWRs have been destroyed.

What it does then is a per-element setting: by default it goes live and fights on its own, but it can
be configured to stay dark instead.

### "Go live" and "go dark"

`goLive()` and `goDark()` are not simple setters. Both refuse in circumstances that protect the site
or the network, so calling one is a request, never a guarantee — read the conditions before relying
on either.

Going dark under HARM defence is also not the same state as going dark on standby: the DCS AI is
switched off entirely, not merely the radars.
