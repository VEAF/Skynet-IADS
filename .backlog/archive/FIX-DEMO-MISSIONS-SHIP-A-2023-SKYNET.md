# FIX-DEMO-MISSIONS-SHIP-A-2023-SKYNET — the missions newcomers open ran Skynet 3.2

Closed 2026-09-20. [PR #33](https://github.com/VEAF/Skynet-IADS/pull/33).

The same defect as the lot above, one shelf lower and worse placed: these are what somebody downloads
to learn what Skynet does, and what `documentation/` points at.

## The defect

Three of the four missions under `demo-missions/` carried `SKYNET VERSION: 3.2 | BUILD TIME:
29.12.2023`, untouched since 2023-12-29, while `develop` shipped 3.5.0 — two minor versions of
behaviour changes missing, including everything `FEAT-LAST-LINE-OF-DEFENSE` and
`FIX-COVERAGE-UPDATE-DARKENS-SITES` added. **Nothing went red, because nothing here is a test.** A
demo that behaves unlike the shipped code is indistinguishable from one that does not.

Their setup scripts had drifted too — three of four disagreeing with their loose copy — and all four
still loaded MiST for a single call with a drop-in replacement.

## The decision, taken first (ticket 03)

**(b): the demos are assembled by `miz-suite.py` like the test missions, and the playable copies
become release assets.** The caveat David took with it: this repository has published no release yet,
so until one is cut a demo is only reachable by cloning and running the build — which the Quick start
page now says.

## What was not mechanical

Pointing the tool at four more archives exposed four defects in it: `NO_SOURCE_IN_REPO` had never
been exercised and `stub` did not honour it; the loose-script scan ran per archive where several
share a folder; one member was named after a script it did not hold; and
`skynet-insim-last-line-of-defence.miz` is written in **VEAF's mission editor's serialisation**
rather than DCS's, which the tool read as an empty `mapResource`. It now reads both, with
`test/python/test_miz_suite.py` covering each shape.

## Measured in DCS, 2026-09-20

Artifact `3.5.0 | 20.09.2026 1704Z`, no script error, no MiST. The network lit `SAM-SA-11` at
17:44:20 on a contact held by `EW-east-2` and returned it to the dark at 17:45:28.

## Two findings recorded rather than fixed

The demo destroyed its own jammer at mission start — taken up and fixed by
[FIX-DEMO-DESTROYS-ITS-JAMMER](FIX-DEMO-DESTROYS-ITS-JAMMER.md) on 2026-09-21, which also found it
affected **both** Persian Gulf demos rather than one. And the last-line-of-defence check moved to
`unit-tests/`, since it was never a demo.
