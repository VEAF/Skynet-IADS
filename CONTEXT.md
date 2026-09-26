# SkynetIADS — context

The domain's vocabulary, and what to have in your head before reading the code. For how a feature
behaves or how to set one up, the published documentation is the reference; this file is for someone
about to read or change the code.

## What is SkynetIADS

Skynet makes DCS air defences behave like a real integrated air defence network. It governs how the
air defence groups a mission already contains behave. Everything upstream of that — creating those
groups, enrolling them, the mission's own logic — belongs to the script that calls Skynet.

### Minimum emissions

EWRs stay on and watch the airspace from afar; SAM sites keep their radars off until the network
gives them something to engage. A site that is not emitting is on nobody's RWR and cannot be homed
on, so the network's work is to keep as much of itself dark as it can and still shoot when it must.

### HARM defence

Skynet takes a SAM site or an EWR dark when it believes a HARM is homing on it, to break the
missile's guidance.

## Vocabulary

| Term | Meaning |
|---|---|
| DCS | Digital Combat Simulator, the military flight simulator SkynetIADS is designed for. |
| IADS | Integrated Air Defence System. One network, usually one per coalition. |
| SAM site | A DCS group holding launchers and radars. Dark by default under network control. |
| EWR | An early-warning radar. Lit by default — it goes dark only to evade a HARM — and feeds contacts to the network. |
| AWACS | An airborne or shipborne radar. An EWR that moves. |
| HARM | High speed anti radiation missile — a missile that homes on a radar's emissions. |
| Command centre | An optional unit the network depends on. Destroy them all and every element goes autonomous. A network with **no** command centre declared is considered to have a working one. |
| Connection node | An optional structure an element depends on to stay part of the network. |
| Point defence | A short-range SAM site attached to another, to cover it while it hides from a HARM. |
| Contact | Something the network has detected and is tracking: one target, as the network knows it, merged from whatever saw it. |
| Acting as EW | A SAM site set to feed the network as an EWR does. It then stays live permanently, and is visible and targetable in exchange. |
| Autonomous | Cut off from the network and handed back to the DCS AI. |
| Live / Dark | Emission state of a radar. This is the lever the whole design turns on. |

## Notable concepts

Four things the code does not say about itself. None of them lists what a function checks — read the
function for that; these are what to have in your head before you do.

### A SAM site cannot see for itself

The cycle never asks a dark site what it detects, so a SAM site under network control notices
nothing on its own. It is blind by construction, and that is the design rather than a gap in it: a
site that looked around for itself would have to emit, which is the one thing the network exists to
avoid. The last line of defence is the deliberate exception, and it is deliberate precisely because
the blindness is.

### "Covered" means near, not informed

Coverage says an EWR is within range of a SAM site. It never says the EWR is feeding it anything, or
that either can see a target. A mission can be built in which a site is covered by a radar that
cannot see anything in that site's engagement range.

### Autonomous means cut off, and that is a loss

An element goes autonomous when nothing connects it to the network any more, and it is then handed
back to the DCS AI — lit, uncoordinated, seeing only what its own radar sees. That is the behaviour
Skynet exists to improve on, so an autonomous element is a degraded one: visible, easy to home on,
and without the early warning that let it stay dark and still be ready.

The connection can break without a radar being touched. Command centres and connection nodes are
part of the chain, so a network can be pulled apart by attacking either of those instead.

What an autonomous element then does is a per-element setting: by default it goes live and fights on
its own, but it can be configured to stay dark.

### Going dark for a HARM is not going dark on standby

Standby dark stops the emissions. HARM dark also switches the DCS AI off entirely, because emissions
alone were not enough to break the missile's guidance. Two different states behind one word.
