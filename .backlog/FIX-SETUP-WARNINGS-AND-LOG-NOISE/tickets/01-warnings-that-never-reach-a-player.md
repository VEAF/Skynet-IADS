# 01 — the warnings a mission maker never sees

Status: ⬜ ready

Three call sites build a warning and hand it to a function that cannot carry one.

| Where | Message |
|---|---|
| `SkynetIADS:addSAMSite()` | *you have added an SAM Site that does not exist, check name of Group in Setup and Mission editor: …* |
| `SkynetIADS:addEarlyWarningRadar()` | *you have added an EW Radar that does not exist, check name of Unit in Setup and Mission editor: …* |
| `SkynetIADS:setCoalition()` | *element: … has a different coalition than the IADS* |

Each passes `true` as a second argument. `printOutputToLog(output)` takes one.

There is a fourth message of the same family, and it is **not** built as a warning:
*you have added an SAM site that Skynet IADS can not handle: …*, in `addSAMSite()` when the group's
NATO name comes back `UNKNOWN`. It deserves the same treatment — a prefix pointed at a truck convoy
is exactly as much a setup mistake as a mistyped name — but decide that deliberately rather than by
copying the line above it.

## What to build

Keep the log line and add the screen warning. Not one or the other:

- the `dcs.log` line is what the `skynet-runtime-debug` skill reads, and it carries the `SKYNET:`
  prefix that makes it findable at all;
- the screen warning is what reaches the person who can fix it, while they are still in the mission
  editor loop.

So each site ends up calling both `printOutputToLog(message)` and `printOutput(message, true)`.
Resist the temptation to make `printOutputToLog` accept a warning flag: it writes to the log, where
`WARNING:` on a line that is already prefixed `SKYNET:` buys nothing, and the `warnings` setting is
about what players see.

## Watch out for

**Two tests pin the current behaviour on purpose and will go red.** They say so in their own
comments — *"if this goes red because the warning now reaches the players, the fix is right and this
test is what to update"*:

- `testAddingASAMSiteThatIsNotInTheMissionEnrolsNothing`
- `testAddingAnEarlyWarningRadarThatIsNotInTheMissionEnrolsNothing`

and `testAnElementOfTheWrongCoalitionIsReported` asserts `#printed.screen == 0` for the same reason.
Update them to assert the warning a player now sees, and delete the notes that say the behaviour is
pinned rather than endorsed.

**`warnings` is on by default**, so this changes what every existing mission shows on screen the
moment it loads a build with this in. That is the point, but it is a visible change and the
changelog entry should say so plainly.

Add a test that the `warnings` setting still silences them, because that is the escape hatch for a
mission that knows about its own warnings and does not want them on players' screens.

## Definition of done

- All four setup-mistake messages reach both the log and, subject to `warnings`, the screen.
- `WARNING: ` prefixes the screen copy and does not appear in the log copy.
- The three tests above assert the new behaviour, and a fourth asserts that `warnings = false`
  silences the screen copy while the log copy stays.
