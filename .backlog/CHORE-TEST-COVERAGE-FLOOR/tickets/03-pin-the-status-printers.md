# 03 — pin the status printers the debug skill reads

Status: ⬜ ready

`skynet-iads-logger.lua` is **10.14%** — 35 lines run out of 345, the worst file in the project by a
wide margin and 44% of everything the suite never executes.

| Function | Lines never run |
|---|---:|
| `printSystemStatus` | 108 |
| `printSAMSiteStatus` | 85 |
| `printEarlyWarningRadarStatus` | 75 |
| `printCommandCenterStatus` | 27 |
| `getMetaInfo` | 10 |
| `printOutput` | 4 |
| `printOutputToLog` | 1 |

## Why this is worth testing, and not just formatting

Because those lines are a **contract with a consumer that already exists**. The
`skynet-runtime-debug` skill diagnoses a mission by reading them back out of a `dcs.log`: it counts
`SAM STATUS` lines, reads the active flag, the number of detected contacts, the autonomy state. A
lot in this backlog was instructed off exactly that — *7 933 SAM status lines dark under network
control, zero ever lit in 24 minutes*.

Nothing pins the shape of those lines today. Rename a field, drop a separator, reorder two counters
and every diagnosis written against them goes quietly wrong — the suite stays green, the skill
starts lying, and the first symptom is someone chasing a bug that is not there.

There is a second reason, smaller but real: these functions walk the whole network and call
`isExist`, `hasWorkingPowerSource`, `getRadars`, `getDetectedTargets` on every element. Half a
destroyed network is exactly the state where a printer throws on a nil, and it is exactly the state
where someone is reading the log.

## What to build

`test/lua/test_skynet_iads_logger.lua`, driving a small IADS through the real
`SkynetIADS:printSystemStatus()` path rather than calling the printers in isolation.

What to assert — the shape, not the prose:

- The header line of each section exists, once, and carries the coalition string.
- The counters are **right**, not merely present: build a network with a known number of destroyed
  command centres, of batteries without power, of EW radars with a cut connection node, and read
  them back off the line. A printer that always reports zero passes a presence check.
- A destroyed or half-destroyed network prints instead of throwing: a radar that no longer exists,
  an element with no power source, a site with no launcher.
- The debug settings actually gate: `IADSStatus` off prints nothing, `contacts` on prints contacts.
  `printSystemStatus` opens on that test and it is the cheapest branch in the file.

## Watch out for

**`trigger.action.outText` is a no-op in the stub** (`test/lua/dcs-stub.lua`), so everything
`printOutput` emits currently goes nowhere. `env.info` is already captured, into `dcsStub.logs`.
Extending the stub to capture `outText` the same way is the deliberate, documented extension this
ticket needs — record in the stub what real behaviour it stands in for: in DCS that call puts text
on the players' screen for 4 seconds, and this suite only cares that it was called and with what.

Do not assert on the full line by string equality. Pin the fields the skill reads and the ones a
human scans; a test that breaks on a changed dash teaches people to delete tests.

## Definition of done

- `skynet-iads-logger.lua` above **90%** on its own. At a 90% target for the project this file
  cannot be left half done: it is 14% of the whole denominator, and ticket 04 depends on another
  lot, so there is no slack to make up elsewhere.
- A renamed or reordered field in a status line fails a test, and the failure says which field.
- The stub's new capture is commented with the real behaviour it replaces.
- `build-tools/test-coverage-floor.txt` is raised, in this pull request, to the newly measured
  figure rounded down — 83 if the file is covered whole. The report names the figure it can be
  raised to, so there is nothing to compute by hand.
