# Inventory of the legacy in-sim tests

Every test in `unit-tests/skynet-unit-tests.miz`, `unit-tests/highdigitsams/highdigitsams-unit-tests.miz`
and every check of `build-tools/run-smoke.py`, with its fate. This is the working baseline: what is
ported, into which scenario, and what is dropped and why.

## How a fate is decided

- **The in-sim suite covers what a stub cannot answer.** A legacy test that mocks DCS away —
  `getDCSRepresentation()`, `getController()`, `getDetectedTargets()` overridden, a `dead` event
  faked — is a logic test running in a mission. It is dropped. Whether `test/lua/` covers that logic
  is a `test/lua/` question, not this one.
- **Behaviour before API.** A DCS call is proven by the scenario whose behaviour depends on it: a site
  that goes dark and stays quiet proves `enableEmission` and `setOnOff`. A call is checked on its own
  only where a broken behaviour would not say which call broke.
- **Two runs are ported as they are**: last line of defence and coverage following an AWACS. They are
  recent, and they were built to fail both ways.

## The missions

| Mission | Map | Holds |
|---|---|---|
| `insim-ca-main` | Caucasus | every scenario but the last line of defence |
| `insim-pg-llod` | Persian Gulf | `last-line-of-defence`, its geometry taken from the legacy mission |

`insim-ca-main` is `insim01` renamed: the template, its sortie name (set in the Mission Editor, since
a mission is known by it), and the `mission` field of the scenarios and of `test/insim/README.md`.
The engine already runs the scenarios of whichever mission DCS has open and lists the others as
skipped, so a full run is one run per mission.

`insim-ca-main` carries a catalogue of late-activated fixtures — each SAM type a scenario uses, point
defences, EW radars, AWACS on predefined routes, command centres, power sources and connection
nodes. Ground fixtures are placed in the Mission Editor on vetted ground; a scenario copies what it
needs with `ctx:add`, where the fixture stands. Aircraft are placed or routed by the scenario.
Named trigger zones give vetted slots: where a scenario drops a copy, where attackers start, and what
`clearWrecks` sweeps.

The fixtures and zones are placed with the `building-dcs-missions` tooling, writing into the
template, then checked and adjusted by eye in the Mission Editor. `test/insim/README.md` says the
template is edited in the Mission Editor only, never in the archive: that rule changes to allow this.

This needs fixture names that do not belong to one scenario: today `ctx:add(role)` resolves
`FIXTURE-<scenario>-<role>`.

## Ported

Tiers are proposals.

### `iads-builds` — exists; the basic layer goes here

Proves that Skynet reads a real DCS world: `coalition.getGroups`, `isActive`, `getSensors`, `getAmmo`,
`getDesc().category`. A failure here explains the failures of every behavioural scenario, which is
why it is checked on its own. Proposed tier: `minimal`.

| Check | From |
|---|---|
| A site with search radar, tracking radar and launchers is classified with the right counts and NATO name | `CheckSA10Group…`, `CheckSA6Group…`, and the rest of the red and blue composition tests, reduced to one site |
| A one-unit site — radar and launcher in the same unit — is both | `SamSiteGroupContainingOfOneUnitOnlySA8` |
| A group that is no SAM gives `UNKNOWN` and no element | `CreateSamSiteFromInvalidGroup` |
| A ground EW radar has a working radar | `test1L13EWRBoxSpring` and the other EW composition tests, reduced to one |
| An AWACS is read as an aircraft and gets the AWACS class | `A50AWACSAsEWRadar`, `KJ2000AWACSAsEWRadar` |
| Prefix discovery takes the groups, not a unit or a static carrying the same prefix, and not a late-activated group | `CaclulateNumberOfSamSitesAndEWRadars`, `OnlyLoadGroupsWithPrefixForSAMSite…` (×2), `OnlyLoadUnitsWithPrefixForEWSite…` |

### `ew-detects-aircraft` — exists

An EW radar sees an aircraft through `getDetectedTargets(Controller.Detection.RADAR)`. No legacy test
to absorb. Proposed tier: `minimal`.

### `sam-engages`

An EW radar sees an aircraft heading for a dark SAM site under its coverage. The site goes live, stays
live while the target is covered, fires, and goes dark again once the target has gone. Proposed tier:
`minimal`.

| Proves | From |
|---|---|
| The network wakes a dark site for a contact in range, and puts it back to sleep | `EvaluateContacts1EWAnd1SAMSiteWithContactInRange`, `SA2InformOfContactTargetInRangeMethod` |
| A live site under covered target stays live across cycles — the regression read in game as launchers raised and lowered every few seconds | `SAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage` |
| A site woken by the network sees the target with its own radar — DCS returns nothing on the first `getDetectedTargets` after `setOnOff(true)` | `CacheInvalidatedFirstfewSecondsAfterControllerIsActivated` |
| A launch is seen (`S_EVENT_SHOT`) and a site with a missile in flight does not go dark | `SA2WillNotGoDarkIfOutOfMisslesAndMissilesAreStillInFlight`, `UpdateMissilesInFlight` |
| `enableEmission`, `setOnOff` and the AI options take effect: the site fires when live, not when dark | `GoLive`, `GoDark` |

### `autonomous-site-engages`

A SAM site with no EW radar and the default autonomous behaviour engages an aircraft on its own.
Proposed tier: `full`.

| Proves | From |
|---|---|
| An IADS made of autonomous sites leaves them live, under DCS AI | `BuildIADSWithAutonomousSAMS` |

### `harm-defence`

An aircraft fires an anti-radiation missile at a live site protected by a point defence. The site
identifies the missile, goes dark, and comes back; the point defence goes live while it is dark.
Proposed tier: `full` — it needs an attacker with a HARM, and several minutes.

| Proves | From |
|---|---|
| A real anti-radiation missile is identified as one, from what DCS reports on the weapon object | `GoDarkDueToHARMTestIfAIisOff`, `HARMDefenceStates`, `SA2WillGoDarkWithTargetsInRangeAndHARMDetected` |
| Time to impact uses the slant range over real terrain (`land.getIP`) | `SlantRangeCalculationForHARMDefence` |
| The site comes back once the defence is over | `FinishHARMDefence`, `WillGoLiveWhenAutonomousAndHARMDefenceFinished`, EW `FinishHARMDefence` |
| A point defence goes live while the site it protects is dark, and stops acting as EW afterwards | `PointDefenceActiveWhenSAMGoesDarkDueToHARMDefence`, `SetPointDefence` |

### `munitions-wake-sites` — new

No legacy test: it covers `feat-munition-aware-wake` (archived 2026-10-17), whose classifier reads
what DCS reports on a weapon object — `category`, `missileCategory`, `guidance` — and whose standalone
tests can only feed it the descriptions they assume.

An invisible attacker (`SetInvisible`, as the feature's own measurements were taken) releases a
munition toward three dark sites under one EW radar: one that engages bombs and missiles, one that
engages missiles only, one that engages neither. The attacker being invisible is what makes the
munition, not the aircraft, the only contact that can wake anything. Proposed tier: `full`.

| Munition | Must wake | Must stay dark |
|---|---|---|
| A bomb (Mk-82 or GBU-38) | the bomb-capable site | the missile-only site, the incapable one |
| An air-to-ground missile (AGM-65 or AGM-154) | the bomb-capable and the missile-only sites | the incapable one |

Both halves in each row: a site that wakes for everything passes the first column and nothing else.

Proves that an EW radar reports a real munition, that a real weapon's description lands in the class
the classifier expects, and that the wake reads it. The coalition filter is not testable here: DCS
reports no friendly object today.

### `infrastructure-destroyed`

A power source, a connection node, a command centre and an EW radar are destroyed with
`trigger.action.explosion`, and the network reacts to the real `S_EVENT_DEAD`. Every legacy test of
this faked the event, because it arrived too late for a synchronous test: the in-sim suite can wait
for it, which is the point. Proposed tier: `minimal` for one of them, `full` for the rest.

| Proves | From |
|---|---|
| A SAM site that loses its power source goes dark and leaves the usable sites, even with a missile in flight | `SAMSiteLoosesPower`, `WillSAMShutDownWhenItLoosesPowerAndAMissileIsInFlight` |
| A SAM site that loses its connection node goes autonomous | `SAMSiteSA6LostConnectionNodeAutonomusStateDCSAI` |
| An EW radar that loses its connection node or power source leaves its SAM sites autonomous | `SAMSiteAndEWRadarLoosesConnectionAndPowerSourceThenAddANewOneAgain` (the destruction halves; re-adding a node is logic) |
| An EW radar destroyed leaves its SAM sites autonomous | `CompleteDestructionOfEarlyWarningRadar` |
| A command centre destroyed, or its power source or connection node, makes the network unusable and every element autonomous | `OneCommandCenterIsDestroyed`, `OneCommandCenterLoosesPower`, `OneCommandCenterHasNoConnectionNode` |

### `last-line-of-defence` — ported as it is

Run 1 of `unit-tests/last-line-of-defence/`, smoke check `last-line-of-defence`. A dark battery,
covered on Skynet's 2D geometry by an EW radar that cannot see an aircraft on the deck. An intruder
flies in low: the battery must light up when it crosses the radius, **and** go quiet once the
persistence has run out. Proposed tier: `full` — about seven minutes of flight.

Mission `insim-pg-llod`: the geometry depends on the terrain hiding the intruder from the EW radar,
and the legacy layout is on the Persian Gulf map. It moves as it is.

### `coverage-follows-awacs` — ported as it is

Run 2 of `unit-tests/last-line-of-defence/`, smoke check `coverage-follows-what-moves`. A battery whose
only parent is an AWACS that flies away: it must be held while covered, **and** handed back once the
AWACS has left. Also absorbs `AWACSHasMovedAndThereforeRebuildAutonomousStatesOfSAMSites`, whose
remaining point was the distance between two real units. Proposed tier: `full`.

Mission `insim-ca-main`: it needs no terrain, only an AWACS flying away from a battery it covers
alone. If the layout does not carry over, it goes to `insim-pg-llod` or a Persian Gulf mission of
its own.

## The smoke checks against the demo mission

| Check | Fate |
|---|---|
| `artifact-loaded` | Dropped: every scenario loads the current build, and none runs if it does not load |
| `networks-built` | Dropped: prefix discovery is in `iads-builds`; what the demo builds is the demo's business, `chore-demo-missions-carry-their-script` |
| `named-elements-found` | Dropped: a property of the demo's script, same owner |
| `jammer-alive` | Dropped: a regression of the demo's script, same owner |
| `no-mist` | Dropped: the demo's dependencies, same owner |

## Dropped

### Logic behind mocks: the DCS part is replaced by a stub in the test itself

- Go live and go dark: `GoDark`, `GoLive` (their mocked halves; the behaviour is in `sam-engages`),
  `SetToCorrectAutonomousState`, `ShutDownTimes`, `GoLiveFailsWhenInHARMDefenceMode`,
  `GoDarkWhenAutonomousByDefault`
- Options and chaining: `DaisychainSAMOptions`, `SetOptionsForSAMSiteType`,
  `SetOptionsForAllAddedSamSitesByPrefix`, `SetOptionsForAllAddedSAMSites`,
  `SetOptionsForAllAddedEWSitesByPrefix`, `SetOptionsForAllAddedEWSites`, `SetMaxAgeOfCachedTargets`,
  `CanEngageAirWeapons`, `CanEngageHARM`
- Parents, children and coverage: `AddParentRadarAndClearParentRadars`,
  `AddChildRadarAndClearChildRadars`, `GetUsableChildRadars`, `InformChildrenOfStateChange`,
  `BuildRadarCoverage`, `BuildRadarCoverageForSingleEarlyWarningRadar`,
  `BuildRadarCoverageForSingleSAMSite`,
  `AddSingleEWRadarAndSAMSiteWhenIADSIsActiveWillTriggerCorrectRadarCoverageUpdates`,
  `AddRadarsToCommandCenter`, `AddCommandCenter`, `EarlyWarningRadarHasWorkingPowerSourceByDefault`
- Contacts: `MergeContacts`, `CleanAgedTargets`, `CacheDetectedTargets`, `InformOfContactInRangeWhenEarlyWaringRadar`
- Acting as EW: `ActAsEarlyWarningRadar`
- Ammunition: `ShutDownShilkaWhenOutOfAmmo`, `ShutDownWhenOutOfMissiles`,
  `SA2WillgoDarkIfOutOfAmmoNoMissilesAreInFlightAndTargetStillInRange`,
  `SA2OutOfMissilesNoMissilesInFlightIsInformedOfTargetByIADSHasNotDetectedTargetWithOwnRadar` — the
  shape of `getAmmo()` is in `iads-builds`; the decision is logic
- SA-2 and SA-8 engagement zones: `SA2WillNotGoDarkIfTargetIsInRange`,
  `SA2GoLiveRangeInPercentInKillZone`, `SA2GoLiveRangeInPercentSearchRange`, `SA8GoLiveRangeInPercent`
  — the ranges are ED's figures, in `test/lua/dcs-figures.lua`; comparing them is logic
- HARM decisions: `ShallIgnoreHARMShutdown`, `CleanUpOldObjectsIdentifiedAsHARMS`,
  `PointDefencesGoLive`, `PointDefencesAreNotActivatedWhenNoHARMSRemoved`,
  `PointDefenceWillGoDarkWhenSAMItIsProtectingGoesDark`
- Arithmetic: `HARMTimeToImpactCalculation`, `CalculateAspectInDegrees`
- Prefix matching on a string: `CaclulateNumberOfSamSitesAndEWRadarsWhenAddMethodsCalledTwice`,
  `WrongCaseStringWillNotLoadSAMGroup`, `WrongCaseStringWillNotLoadEWRadars`, `GetSAMSitesByPrefix`
- MOOSE: `AddMooseSetGroup`, `GetEarlyWarningRadarGroupNames`, `GetSAMSitesGroupNames`,
  `AddMooseSetGroupAndUpdate` — the in-sim mission carries no MOOSE, and the connector is logic

### Per-type composition, reduced to one sample in `iads-builds`

Whether `samTypesDB` names types that exist is checked against ED's database by
`test/lua/test_dcs_figures.lua`, weekly. What is left — that a live group is read through
`getSensors()` and `getAmmo()` — is the same mechanism for every type.

- Red: `CheckSA3Group…`, `CheckSA11Group…`, `ShilkaGroup…`, `SA15Launchers…`, `SA13Launchers…`,
  `HQ7LauncherAndRadar`, `SA5`, `SA5P19`, `CP9S80M1SborkaDogEar`, `55G6EWRTalRack`, `EWP19FlatFace`,
  `SA10BigBird`, `SA10ClamShell`, `SA11SnowDrift`, `SA6StraightFlush`, `HQ7`
- Blue: `HawkSTR`, `PatriotSTR`, `RolandEWR`, `RolandLauncherAndRadar`, `NASAMS`,
  `RapierLauncherAndRadar`, `PatriotLauncherAndRadar`, `LPWSCRAM`, `EWRANFPS117Domed`, `EWRANFPS117`,
  `OliverHazzardPerryClassShip`

### High Digit SAMs: the mod is not part of the in-sim suite

`SA20AGargoyle`, `SA20BGargoyle`, `BigBird`, `ClamShell`, `ClamShell2`, `BillBoardC`, `HighScreenB`,
`SnowDrift`, `UnnamedRadar`, `SA23GladiatorOrGiant`, `SA10BGrumble`, `EDDefaultSA10GrubleWith55VRUD`,
`SA10BGrumbleWith55VRUD`, `SA20AGargoyleWith55VRUD`, `SA17Grizzly`, `SA2GuidelineWithV7595V23`,
`SA3GoaWithV601P5V27`, `SA2GuidelineWithHQ2`, `SA12GladiatorGiant`

### Nothing left to test

- `DCSContstantsHaveNotChanged`: Skynet refers to the constants by name, never by value
- `PointDefenceWhenOnlyOneEWRadarIsActiveAndAmmoIsStillAvailable`: empty
- `CallMethodOnTableElements`, `ControllerNotDisabledWhenGoingDarkAndOutOfAmmo`,
  `ControllerDisabledWhenGoingDarkAndHasRemainingAmmo`, `DontPassShipsGroundUnitsAndStructuresToSAMSites`:
  commented out in the legacy suite
