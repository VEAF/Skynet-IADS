# A site protected by a point defence flaps under a HARM

Status: open

## The problem

A SAM site whose point defence can take the inbound HARM is meant to stay live while the point
defence engages: `shallIgnoreHARMShutdown()` answers true, and `informOfHARM` wakes the point
defence through `pointDefencesGoLive()`. In DCS, the site and its point defence instead go dark and
live again at every cycle, about once a second, for the whole time the HARM is in flight.

Seen in the in-sim scenario `harm-point-defence` (`test/insim/scenarios/`), on `insim-ca-main`: an
SA-6 acting as an EW radar, an SA-15 as its point defence, both under a 1L13; one AGM-88C fired by an
invisible, immortal F-16 at the SA-6; HARM detection chance 100 %.

- `shallIgnoreHARMShutdown()` read every second: true throughout (1 HARM identified, the SA-15 with
  1 launcher and 8 missiles, then 7, then 6).
- Skynet's debug log, every cycle until impact: `POINT DEFENCES GOING LIVE FOR: …/SAM-SA6 | TTI: 51`,
  then `GOING DARK` for the SA-15 and for the SA-6, then `GOING LIVE` for both; the same at TTI 48,
  47, 43, 39, 35…
- The SA-15 still fired twice.

Nothing in `informOfHARM` silences the site while `shallIgnoreHARMShutdown()` is true, so the dark
comes from another caller of `goDark()` in the same cycle. Which one is to be found.

## What to build

- The cause, and the fix: the site stays live for the whole engagement, its point defence live
  while the HARM is inbound, and dark again once it is gone.
- A standalone test in `test/lua/` that reproduces the cycle.
- `harm-point-defence` passes; it asserts the site stays live (`site = { true }`) and is the
  regression test in DCS.

## Out of scope

- HARM identification itself: `fix-harm-identified-by-seeker`.
