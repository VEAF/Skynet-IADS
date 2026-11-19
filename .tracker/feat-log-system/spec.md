# A log system that explains what Skynet decides

Status: open

## The problem

On complex missions, most often on public multiplayer servers, a network sometimes behaves in a way
nobody can explain: a site that never comes up, one that stays live, a network that goes quiet. The
server's `dcs.log` is all there is to go on afterwards, and it holds nothing from Skynet: its logging is
debug output, off on any server that is not being debugged, and even when on it says what happened, not
why.

## What there is today

`SkynetIADSLogger` (`skynet-iads-logger.lua`) and calls to it spread through the sources:

- **Two outputs, mixed.** `printOutput` writes to the screen, `printOutputToLog` to `dcs.log` under
  `SKYNET: `. Which one a message uses follows no rule.
- **Switches, not levels.** `getDebugSettings()` is a table of booleans, one per kind of message. Its
  defaults and its readers disagree: it sets `samWentDark`, the code reads `radarWentDark`; the code reads
  `samNoConnection` and `hasNoPower`, which it never sets. A key misspelled by a mission is silently
  ignored.
- **No reasons.** `GOING LIVE: <site>` and `GOING DARK: <site>` do not say which contact, which rule, or
  which state of the network led there.
- **Status dumps meant for the eye.** `printSAMSiteStatus` and its siblings write multi-line blocks,
  ruled with dashes, that a tool cannot read back.

## What to build

1. **One logger, with levels and categories.** Every message goes through it, with a level (error,
   warning, info, debug) and a category (network, site state, contacts, HARM, jammer, …). A mission
   chooses what is written by level and category. What is on by default is cheap enough for a public
   server.
2. **Decisions with their reasons, always on.** One line per state change of an element (live, dark,
   autonomous, silenced by a HARM, point defending, destroyed, powerless, disconnected), carrying the time,
   the network, the element and why: `live, contact <name> at 34 km`, `dark, no contact`, `autonomous,
   command center lost`.
3. **Lines a tool can read back.** A fixed prefix, a format version, and fields a parser can split
   reliably, readable by a person too.
4. **A startup report**, when a network is activated: what it holds, and what looks wrong. See below.
5. **A snapshot on demand** of a network: its elements, their state, and its relations (which radar covers
   which site, which point defence protects what, which power source feeds what). Called from the API, so
   a mission can bind it to an F10 command or a trigger.
6. **Recent history in memory.** A bounded buffer of the last decisions with more detail than the always-on
   lines (contact lists, distances), dumped to the log on demand. Detail around an incident, without
   paying for it all the session.
7. **An offline reader**, outside the deliverable: a script that pulls these lines out of a `dcs.log` and
   rebuilds a timeline per element.

## The startup report of VEAF-IADS-Caucasus-Mk2

That mission's `mission-iads.lua` writes a report to `dcs.log` once its networks are activated. What it
checks, and whether Skynet can do it itself:

| The mission reports | In Skynet? |
|---|---|
| per network, the count and names of EW radars and SAM sites | yes: Skynet holds them |
| each point defence and the site it protects; the command center and its power source | yes |
| a group or unit named with the network's prefix that Skynet did not take | yes, for the prefixes given to `addSAMSitesByPrefix` / `addEarlyWarningRadarsByPrefix`: Skynet knows them, and drops a group silently today |
| an EW radar Skynet took that has no search radar it knows | yes: Skynet takes any unit named as one |
| a group of the coalition, outside every network, holding a unit type in Skynet's database: probably a naming typo | yes: the database is Skynet's, the coalition is the network's |
| a point defence whose named parent site does not exist | no: the naming convention for point defences is the mission's |

Most of it is a check of the mission's set-up against what Skynet took. It is what a mission maker needs
first, and it costs nothing after start.

## To decide

1. **The line format**: `key=value` fields, a serialized Lua table, or another; how it is versioned.
2. **Which decision points carry a reason**, and the vocabulary of reasons. This is the bulk of the work:
   it instruments `goLive` / `goDark`, the autonomous logic, HARM defence, point defence and the command
   center checks.
3. **The volume** on a long session with a large network: what is on by default, what goes only to the
   buffer.
4. **`getDebugSettings()`**: kept as it is, mapped onto the new levels and categories, or deprecated. The
   missions that set it must keep working.
5. **The screen messages** (`trigger.action.outText`): a separate output of the logger, or left as they
   are.
6. **The status dumps**: rewritten as snapshots, or kept beside them.
7. **The offline reader**: in `build-tools/`, in its own folder, or later.
8. **Shared hooks with `feat-map-view`.** Both are called where an element changes state. If both are
   built, one "state changed" call in the source can feed both. Neither depends on the other.

## Out of scope

- A live view of the network outside DCS.
- Writing to a file of its own: that needs `io`, which a server's `MissionScripting.lua` keeps sanitized.
