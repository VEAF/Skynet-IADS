# SkynetIADS — context

What to have in your head before reading or changing the code: what Skynet is for, and four things
that look like bugs and are not. The terms themselves are defined in the published documentation, and
what a function checks is in the function.

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

## Notable concepts

Four things the code does not say about itself. None of them lists what a function checks — read the
function for that; these are what to have in your head before you do.

### A SAM site cannot see for itself

Every few seconds the network collects what its EWRs detect and offers it to the SAM sites they
cover. It never asks a dark site what it detects, so a SAM site under network control notices nothing
on its own. It is blind by construction, and that is the design rather than a gap in it: a site that
looked around for itself would have to emit, which is the one thing the network exists to avoid. The
last line of defence — a short radius around a dark site inside which an intruder wakes it anyway —
is the deliberate exception, and it is deliberate precisely because the blindness is.

### "Covered" means near, not informed

Coverage says an EWR is within range of a SAM site. It never says the EWR is feeding it anything, or
that either can see a target. A mission can be built in which a site is covered by a radar that
cannot see anything in that site's engagement range.

### Autonomous means cut off, and that is a loss

An element goes autonomous when nothing connects it to the network any more, and it is then handed
back to the DCS AI: uncoordinated, seeing only what its own radar sees, and lit by default. That is
the behaviour Skynet exists to improve on, so an autonomous element is a degraded one — without the
early warning that let it stay dark and still be ready.

The connection can break without a radar being touched. Command centres and connection nodes —
optional objects a mission declares, which the network then depends on — are part of the chain, so a
network can be pulled apart by attacking either of those instead.

What an autonomous element then does is a per-element setting: by default it goes live and fights on
its own, but it can be configured to stay dark.

### Going dark for a HARM is not going dark on standby

Standby dark stops the emissions. HARM dark also switches the DCS AI off entirely: in multiplayer, a
HARM still finds an emitter whose emissions alone are off, and the code works around that DCS bug.
Two different states behind one word.
