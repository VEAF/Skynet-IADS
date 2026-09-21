# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[semantic versioning](https://semver.org/).

**Every pull request that changes `skynet-iads-source/` adds an entry**, appended at the **end** of
the `[Unreleased]` section. Appending rather than prepending: two pull requests landing the same day
conflict far less that way.

This matters more here than in most projects. The consumer of this repository is another repository
— [VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools) vendors the
built artifact — and until now nothing told it what had changed between two copies.

## A note on version numbers

The inherited tags stop at `v2.0.1`, from walder's lineage, while the compiled script has long
identified itself as `3.4.0RP-VEAF`. Settled on 2026-09-19: this project continues the **artifact's**
lineage, since that is the number anyone reads in a log. The first release under joint maintenance
is **3.5.0**, tagged `v3.5.0`, and the `RP` suffix is dropped — not because the Regroupement has
stepped back, but because the number now belongs to both communities and has no reason to carry
either name.

Until that release is cut, the build date in the artifact's first line remains the real identifier.

## [Unreleased]

**The first release under joint maintenance.** VEAF and the Regroupement de Patrouilles (BFR,
NAWACS) carry Skynet-IADS on together, in this repository. This release brings a **last line of
defense** — a battery held dark by the network now wakes on proximity alone — three fixes to radar
coverage that each left a site mute for the rest of a mission, and a repository put back on its
feet: continuous integration, published documentation, an in-sim smoke gate, and a standalone test
suite at 94% coverage. It is also why the number jumps from `3.4.0RP-VEAF` to `3.5.0`.

### What changes for your missions

- **The last line of defense is on by default.** A battery the network holds dark keeps a short
  *virtual* detection radius of its own — no DCS radar involved — drawn once per site between 10 and
  15 km and kept for the mission. A hostile aircraft inside it wakes the site with no radar contact
  anywhere, and the site stays live 45 s after the last pass. A short-range piece such as a Shilka
  can therefore light up for an aircraft it cannot reach: accepted trade-off. Turn it off with
  `setLastLineOfDefence(false)`.
- **An AWACS that goes home now has the same effect as one shot down.** The coverage sweep purges
  where the old path only ever added, so the batteries that AWACS alone covered become autonomous.
  That is the right answer for a battery no ground radar covers, and it is visible in mission.
- **Sites no longer go dark when one is added or respawned.** Declaring that a radar covers a
  battery used to switch that battery off; a bulk `addSAMSitesByPrefix()` left the elements it
  discarded wired into the coverage graph; and a site torn down mid-HARM-evasion stayed deaf for the
  rest of the mission. All three are reached by the `*ByPrefix` calls VEAF's helper makes on
  respawn.
- **The `.miz` files in this repository are no longer playable on their own.** They hold a
  placeholder for every script now, so a committed demo can no longer go stale in silence. A
  playable demo comes from this release's assets or from `python build-tools/miz-suite.py build`.
  MIST is out of the demos and out of the repository with them.

### What to do when upgrading

- **Expect setup warnings on screen.** Four messages — a group name that is not in the mission, a
  unit name that is not in the mission, an element of the other coalition, a group with no SAM data
  — only wrote a line to `dcs.log` between November 2020 and now. They are shown to the players
  again, prefixed `WARNING:`. A mission that has quietly carried a typo for years will announce it
  the first time it loads this build; that is the point. The escape hatch is
  `redIADS:getDebugSettings().warnings = false`, which silences the screen copy and keeps the log.
- **Decide about the last line of defense.** Leaving it on is a valid choice, but it is a choice:
  `setLastLineOfDefence`, `setLastLineOfDefenceRadius` and `setLastLineOfDefencePersistence` are the
  three settings.
- **`SkynetIADS:addJammer()` is gone.** It raised *table expected, got nil* on every call ever made
  to it, so no mission can have used it successfully — but a setup script that still calls it now
  fails differently. Attach a jammer the documented way:
  `SkynetIADSJammer:create(Unit.getByName("F-4 AI"), redIADS)`, plus `jammer:addIADS(blueIADS)` for
  a second network.
- **MIST is no longer needed for Skynet.** The current build makes no MIST call at all. A mission
  that loaded `mist_4_5_107.lua` only for Skynet can drop it — 312 KB, and one `DEAD` event handler
  that put an error popup on the players' screens. Only if nothing else in the mission uses MIST,
  which is rarely the case in VEAF missions.

### Added

- A backlog under `.backlog/`, with the two lots VEAF has decided on: `FEAT-LAST-LINE-OF-DEFENSE`
  and `CHORE-PROFESSIONALIZE-THE-REPO`.
- `CLAUDE.md`, `CONTEXT.md` and `docs/agents/`, so the project's conventions and vocabulary are
  written down rather than rediscovered.
- Two agent skills: `skynet-runtime-debug`, for diagnosing an in-game report from a `dcs.log`, and
  `release`, which documents the release as it is actually done today — by hand.
- This changelog.
- `SkynetIADS.version`, the single source of truth for the shipped artifact's version, read by the
  build rather than passed to it as an argument.
- `build-tools/listToMerge.txt`, the commented merge manifest replacing the twenty hard-coded paths
  on one line in the build script.
- `build-tools/check-artifact.lua`: the build proves the sources concatenate, this proves the
  result runs, by loading and executing the artifact against `test/lua/dcs-stub.lua`.
- `.github/workflows/build.yml`, which builds and checks the artifact on every push and pull
  request — the build is now pure PowerShell and runs on the Linux CI runner.
- `.github/workflows/release.yml`: a tag matching `v*` builds, verifies and publishes a GitHub
  release carrying the artifact and this section's contents, marked as a pre-release unless the tag
  is a plain `vX.Y.Z`.
- A published documentation site under `documentation/`, built with MkDocs Material and versioned
  with `mike` (`.github/workflows/docs.yml`), deployed to <https://veaf.github.io/Skynet-IADS/>.
  `develop` publishes as `dev` (the site default until a stable release exists), `master` as
  `latest`, and a tag as its own version — plus `latest` if the tag is a plain `vX.Y.Z`.
- `luacheck` and `stylua`, gating `skynet-iads-source/` and `test/lua/` in CI
  (`.github/workflows/lint.yml`). `.luacheckrc` declares the DCS Scripting Engine's globals and
  this project's own (no module system in DCS; see `build-tools/listToMerge.txt`), and pins the
  first run's remaining warnings to their exact file and code — a ratchet to erode, not a floor
  to sit on.
- `test/lua/test_skynet_iads_abstract_radar_element.lua`: the first slice of the legacy
  `unit-tests/test-skynet-iads-abstract-radar-element.lua`, 8 of its 50 tests — the autonomy and
  coverage cluster (`goDark`/`goLive`, `setToCorrectAutonomousState`, the connection-node and
  power-source chain, `setActAsEW`). That is the class both tickets of `FEAT-LAST-LINE-OF-DEFENSE`
  modify, so it now has a standalone regression net. Each ported test was checked by mutation:
  six deliberate breakages of the source each turn at least one of them red. `test/lua/README.md`
  tracks what is ported and what the remaining 42 tests cover.
- **A last line of defense** (`FEAT-LAST-LINE-OF-DEFENSE` ticket 01). A SAM site held dark by the
  network is blind: its emission is off, and the only route back to life is an EW radar that covers
  it holding the target, so proximity to the site is an input nowhere in the cycle. It now keeps a
  short **virtual** detection radius of its own — Skynet's, no DCS radar involved — drawn once per
  site between 10 and 15 km and kept for the mission, measured flat like everything else here. A
  hostile aircraft inside it wakes the site with no radar contact anywhere, and the site stays live
  45 s after the last pass. The kill-zone test is deliberately bypassed: requiring it would mean a
  Shilka, useful range ~2.5 km, never wakes inside that radius — so a short-range piece can light up
  for an aircraft it cannot reach, which is the accepted trade-off. A site defending against a HARM,
  out of ammunition, without power or destroyed does not wake, and the site's own go-live
  constraints are still honoured. **On by default: it changes existing missions.** Settable with
  `setLastLineOfDefence`, `setLastLineOfDefenceRadius` and `setLastLineOfDefencePersistence`.
- `SkynetIADS:reportContact(dcsUnit, samSite)`, a **public entry point**: it wakes a site on a DCS
  unit as if something had reported that aircraft to the network. The last line of defense is its
  first caller, and it is public because VEAF's spotter network has to wake a site from outside
  Skynet — the alternative being external code writing into `targetsInRange` on every cycle.
- `SkynetIADS:refreshRadarCoverage()`, a periodic coverage sweep, interval settable with
  `setCoverageRefreshInterval` and 10 s by default (`FEAT-LAST-LINE-OF-DEFENSE` ticket 02). It
  re-evaluates only the elements that have travelled more than 10 NM since the last sweep, and calls
  `setToCorrectAutonomousState` only on the sites whose **autonomy** actually changed — a blanket
  call means `resetAutonomousState()` and therefore `goDark()`, and `goDark()`'s guards do not
  protect a site that has just gone live on designation and not yet locked on. Autonomy rather than
  the parent list, because a site that gains a second parent while keeping its first has not changed
  sides, and switching it off over that is the same defect `3a94937` fixed on the other path —
  triggered by nothing more than an AWACS arriving on station.
- Individual removal of a parent or child radar (`removeParentRadar`, `removeChildRadar`) and an
  addition that does not fire a state change (`addParentRadarWithoutStateChange`). Until now it was
  all-or-nothing: `clearParentRadars` and `clearChildRadars` were the only tools, and there was no
  function at all to remove a single link.
- `SkynetIADSAbstractRadarElement:getElementPosition()` and `:getMaxDetectionRange()`: one point and
  one range per element. A site is a point.
- `SkynetIADSAbstractRadarElement:hasValidParentRadar()`, the autonomy question asked as a *query*.
  `setToCorrectAutonomousState()` is now that query plus the action it implies, so the coverage
  sweep can ask whether a site's answer has changed before acting on it.
- Two test suites, `test/lua/test_skynet_iads_last_line_of_defence.lua` (18 tests) and
  `test/lua/test_skynet_iads_coverage_refresh.lua` (13 tests). Almost all of them drive the real
  `SkynetIADS.evaluateContacts()` rather than calling the wake-up directly, because the failure mode
  that matters here is a wake-up that is perfectly tested and never called by the cycle. Checked by
  mutation: disabling the cycle hook, the persistence guard, the coalition filter, the airborne
  filter, the autonomy comparison or the link removal each turns at least one of them red.
- The DCS stub gained `coalition` (with `side` and `getGroups`), `Group.Category` and
  `Unit.inAir()`, and the fixtures gained hostile aircraft, an AWACS, and positioned and
  coalition-aware SAM groups.
- `test/lua/test_skynet_iads_logger.lua` (26 tests), pinning the status page the
  `skynet-runtime-debug` skill reads back out of a `dcs.log`. It asserts each line field by field —
  their names, their order and their values — over a network whose damage is known and whose every
  counter is non-zero, so a printer stuck at zero cannot pass. The separators' own spacing is
  deliberately left out of the contract. Checked by mutation: renaming a field, swapping two, and
  freezing a counter each turn it red, naming the field. This takes
  `skynet-iads-source/skynet-iads-logger.lua` from 10% to 95% test coverage, and the project from
  70% to 83%.
- The DCS stub records `trigger.action.outText` into `dcsStub.screenText`, the way `env.*` is
  already recorded into `dcsStub.logs`. It was a no-op until now, so every summary line the logger
  has ever emitted went nowhere in this suite.
- The network facade a mission maker writes against is under test, in
  `test/lua/test_skynet_iads.lua` (34 tests, up from 1): every call `documentation/api.md` shows
  on the `SkynetIADS` object is now executed by at least one suite, including
  `getSAMSiteByGroupName`, which eleven examples on that page depend on and which the suite had
  never run. What a getter gives back on a miss is asserted, and `api.md` now says the same
  thing. `skynet-iads-source/skynet-iads.lua` goes from 82% to 98% test coverage, and the project
  from 83% to 86%.
- The long tail of the suite, which takes the project past its 90% test-coverage target:
  the jammer (100%), the anti-radiation-missile decision and who it warns (98%), how a battery
  learns its own range from its sensors and its ammunition (`test_skynet_iads_range_data.lua`,
  new), the geometry helpers the HARM aspect calculation is built on, and the table delegator
  that makes `getSAMSitesByNatoName('SA-10'):setActAsEW(true)` reach every site. Eleven of the
  eighteen measured files are now at 100%; the project reads **91.17%** and the floor moves to
  **91**. What stays uncovered, and why, is written down in `test/lua/README.md`.
- The DCS stub provides `missionCommands` (`addSubMenu`, `addCommand`, `removeItem`) and keeps
  the resulting menu in `dcsStub.radioItems`, so a test can ask what a player would find under
  F10 and invoke a command the way clicking it would. What DCS does with `removeItem(nil)`, or
  with two submenus sharing a name, is not modelled: neither is verified here, and the stub
  raises rather than inventing an answer a test could come to depend on.

- `documentation/api.md` now says what `getSAMSiteByGroupName` and `getEarlyWarningRadarByUnitName`
  return when nothing matches -- no value at all, so chaining off the call fails with *attempt to
  index a nil value*, which is what a mistyped group name looks like -- and that a prefix has to
  start the group name rather than merely appear in it.

- `unit-tests/last-line-of-defence/skynet-insim-last-line-of-defence.miz`, the in-sim check for the
  last line of defense: a SA-6 and an early warning radar 106 km apart, so the network holds the battery dark
  while an aircraft on the deck stays under that radar's horizon -- the reported situation, built
  on purpose. It is driven from outside through VEAF's `dcs-bridge`, so nobody has to fly: one call
  puts an immortal intruder on a run across the site, another prints what the network is doing, and
  the status line goes into `dcs.log` every five seconds. A second run, started on demand, covers
  the other half of the feature: a battery whose only parent is an AWACS, and an AWACS that flies
  out of its own detection range. Its scenario is kept in readable form next to it as
  `skynet-insim-last-line-of-defence.lua`.

  Both were measured in DCS 2.9.29.27468 on 2026-09-19. A battery held dark lit up on proximity
  with no radar contact anywhere, stayed in the network while lit, and fell silent 45 s after the
  intruder left its radius -- to the second, on two runs whose drawn radii differed (10.9 km and
  14.1 km), which also shows the radius is drawn per site and stable: one value across 107 samples.
  The covered battery was handed back at 211.0 km on both runs. That is what the standalone suite
  could not show: that the cycle really calls this code. The timings, the montage and the limits of
  what was covered are written up in
  [`.backlog/FEAT-LAST-LINE-OF-DEFENSE/in-sim-test-report-2026-09-19.md`](.backlog/FEAT-LAST-LINE-OF-DEFENSE/in-sim-test-report-2026-09-19.md).
- Slice 2 of the same port, fifteen more tests: the HARM timing and defence states (how long a
  battery hides, the slant range it measures the threat at, the whole truth table of
  `shallIgnoreHARMShutdown()`), the two engagement flags, and the parent / child radar
  bookkeeping. Two of those tests replace .miz originals that could not fail -- the order
  assertions on `addParentRadar`/`addChildRadar` compared bare `{}` mocks, which luaunit finds
  equal to one another, and the clean-up test never called the method it was named after. Test
  coverage 92% -> 93%.
- Slice 3 of the same port, sixteen more tests: what a battery has left to shoot with and when it
  falls silent because of it (missiles, a gun's shells, a missile still in the air, a dead power
  source), and the engagement zone -- which of the search radar, the tracking radar and the
  launcher has to reach a contact before the site lights up, and what `setGoLiveRangeInPercent()`
  does to that. What did **not** come across is the DCS figures those .miz tests assert (the Flat
  Face's 53499.2265625 m detection range and the like): those belong to ED, and a standalone test
  would only prove the fixture repeats itself. `test/lua/README.md` now carries a "needs the
  simulator" list saying so. Test coverage 93.97%.
- Slice 4 of the same port, the last seven tests: point defence -- a short-range battery lights up
  while the site it protects hides from a HARM, and is stood down when the site comes back or the
  last remembered HARM ages out -- and the detected-target cache, including the window after a
  `goLive()` where it is deliberately bypassed so a site does not cache the empty answer a
  just-switched-on controller gives. That completes the port: all 46 live tests of
  `unit-tests/test-skynet-iads-abstract-radar-element.lua` now run standalone. Test coverage
  93.97% -> 94.63%, floor 93 -> 94.
- `build-tools/miz-suite.py`, for the one file in this repository nothing could safely edit. A
  `.miz` is a zip, and a script baked into one is wired in **four** places: the file itself, its
  `mapResource` key, the compiled `a_do_script_file(...)` call in the mission's `trig.actions`, and
  the Mission Editor's own structured copy of the same trigger in `trigrules`, whose indices have to
  stay contiguous. Missing the fourth leaves the two copies of the trigger disagreeing, so the
  mission runs the script while the editor shows an empty trigger, or the reverse. `check` asserts
  all four agree, entry for entry and in order; `remove` re-checks the result and refuses to write
  if anything is off.
- A CI job for the in-sim mission archive (`.github/workflows/lua-tests.yml`, *In-sim mission
  archive*). It cannot run the `.miz` -- that needs the simulator -- but it runs `miz-suite.py
  check`, assembles both missions and parses every Lua file in them, `mission` and `mapResource`
  included. (It parsed the committed archives when this job was first written; since the missions
  became assembled, parsing those would only be parsing placeholders.) Until
  now nothing checked that file at all: it is the one file in this repository no gate looked at,
  and a hand edit that broke it was found by opening DCS, or not at all. Verified against three
  deliberate breakages -- a `trigrules` entry removed, a `mapResource` line removed, a script
  truncated -- each caught.

- `miz-suite.py build`: the in-sim missions are **assembled** now, not committed complete. Both
  archives hold a placeholder for every script and `build` puts the real files in, writing to the
  git-ignored `build/missions/`. A copy of the code committed beside the code it copies goes stale
  without a sound -- which is the defect below -- and an assembled mission cannot; one opened
  unbuilt prints a message on screen instead of quietly measuring the wrong thing. `check` fails if
  git is holding a copy of anything, in either direction, so a suite added to the repository and
  never wired in is reported too. Both archives are covered,
  `unit-tests/skynet-unit-tests.miz` and `unit-tests/highdigitsams/highdigitsams-unit-tests.miz`;
  `--miz <path>` narrows any command to one.

- `test/lua/dcs-figures.lua` and `build-tools/dcs-figures.py`: a record of what Eagle Dynamics says
  about the units Skynet models -- missile reach, firing ceiling, radar detection distance -- read
  from a pinned commit of the `Quaggles/dcs-lua-datamine` dump. CI regenerates it against the pin and
  fails on any difference, and `.github/workflows/dcs-data-drift.yml` bumps the pin weekly and opens
  a pull request whose diff names the figure that moved. It is the only thing in this project that
  can say a battery changed behaviour in game: the SA-11's missile went from 35000 m to 46000 m
  between December 2023 and September 2026 -- 11 km further out before a Buk wakes -- and the only
  reason anyone found out was running the in-sim mission after three years.
- `build-tools/run-smoke.py`, an in-sim smoke gate: it sends small pieces of Lua into a running DCS
  through VEAF's dcs-bridge, reads back one word per check, and prints a table. Seven checks across
  two missions -- five that interrogate the Persian Gulf demo without touching it, and two that fly
  the last-line-of-defence scenario and now answer with a verdict instead of log lines a human had
  to read. Stdlib only, like `miz-suite.py`. It is **consultative and local**: GitHub runners have no
  DCS, no licence and no GPU, so it informs a release rather than gating one, and it skips with an
  explanation when there is nothing to talk to. Every defect flying found this month -- a 2023
  artifact in the in-sim suites, Skynet 3.2 in the demos, MiST putting a popup on screen, both demos
  destroying their own jammer -- was invisible to every gate the project had. See
  `unit-tests/README.md`.
- `python build-tools/miz-suite.py build --with-bridge`, which wires `dcs-bridge.lua` into every
  archive it assembles that does not already carry one -- the inverse of `remove`, across the same
  four places a script is wired in. It is what lets the smoke gate reach the demo missions, and it is
  opt-in and confined to the git-ignored `build/missions/`: the demos are release assets, and a
  mission somebody downloads to learn what Skynet does must not open a socket on their machine. A
  plain `build` is unchanged, so what a release attaches is unchanged.

### Changed

- `develop` is the default branch, and the Lua suite runs on it.
- `contributing.md` rewritten around what this repository actually does. The previous guide was
  upstream's: it pointed at walder's Discord, told contributors to add tests to a `.miz`, and said
  nothing about the standalone suite, the branching model, or the fact that two files are generated.
- The build no longer takes the version as an argument, no longer resolves paths from the working
  directory, and no longer regenerates `README.md` — that file is now hand-written.
  `demo-missions/skynet-iads-compiled.lua` is generated and no longer committed.
- `README.md` rewritten short: what the project is, who maintains it, where the documentation is,
  how to get the script, where to report a problem. It is hand-written and no longer generated.
- `skynet-iads-source/README_source.md`'s prose split across `documentation/*.md` along its natural
  seams (setup concepts and the mission editor, tactics, the public API, the FAQ), reorganised
  rather than rewritten. `images/` moved to `documentation/images/`, its only consumer.
- `stylua` run once over `skynet-iads-source/` and `test/lua/` (formatting only; excludes the
  vendored `test/lua/luaunit.lua`) — mostly re-indenting each file's top-level `do...end` body,
  which the source never actually indented.
- Radar coverage is measured **element to element** instead of radar pair to radar pair. Iterating
  every pair of radars of two elements cost a factor of four for the few metres that separate the
  units inside one group, and it is what made a periodic sweep too expensive to run. The initial
  build and the sweep now go through the same helper, so a borderline association cannot flip
  between the two.
- The "has this moved far enough to matter" check is no longer an AWACS method. It was
  `SkynetIADSAWACSRadar:isUpdateOfAutonomousStateOfSAMSitesRequired()`, guarded by a `getmetatable`
  test on the class, so a SA-15, a SA-8 or a Shilka driving in a convoy kept the parents it had when
  it spawned for the whole mission. It is now
  `SkynetIADSAbstractRadarElement:hasMovedSinceLastCoverageUpdate()`, on every element; the old name
  still answers, since it is part of the script's public surface.
- `evaluateContacts` no longer rebuilds an AWACS's coverage when it has travelled 10 NM. That path
  routed to `buildRadarCoverageForAbstractRadarElement`, which only ever **adds** — so an AWACS in
  transit accumulated every battery it had ever flown near and held them all non-autonomous from
  hundreds of kilometres away. The periodic sweep replaces it and purges. Accepted consequence,
  decided on 2026-09-19: an AWACS that goes home now has the same effect as one shot down, and the
  batteries it alone covered become autonomous — which is the right answer for a battery no ground
  radar covers.

- **The demo missions are assembled, not committed, and a release carries them.** Three of the four
  archives under `demo-missions/` held `SKYNET VERSION: 3.2 | BUILD TIME: 29.12.2023 1905Z` and had
  not been touched since — so the worked example a newcomer downloads demonstrated a build from
  before two minor versions of behaviour changes, including everything `FEAT-LAST-LINE-OF-DEFENSE`
  and `FIX-COVERAGE-UPDATE-DARKENS-SITES` added. Nothing went red, because nothing there is a test.
  They now hold a placeholder for every script like the in-sim archives do, `miz-suite.py build`
  assembles them, and `.github/workflows/release.yml` attaches the three demos to a release beside
  `skynet-iads-compiled.lua`. **Consequence for anyone cloning this repository**: the committed
  `.miz` files are no longer playable on their own, and a playable demo comes from a release or
  from running the build. The Quick start says so.

  Their setup scripts had drifted too, three of four disagreeing with their loose copy; the loose
  copy is the only one now. What that dropped, measured rather than assumed: one deprecated no-op
  call (`setIgnoreHARMSWhilePointDefencesHaveAmmo`) the Persian Gulf archive had and its loose copy
  did not, and a typo the loose MOOSE copy had already fixed.

- `build-tools/miz-suite.py` covers six archives instead of two, and reads a `mission` written by
  either DCS or VEAF's mission editor — the two serialise the same Lua table differently, and
  assuming DCS's shape made the tool read `skynet-insim-last-line-of-defence.miz` as having an empty
  `mapResource`. `test/python/test_miz_suite.py` covers both shapes, run in CI: a pattern that
  matches the wrong block does not raise, it rewrites the wrong trigger and writes the archive.

- `skynet-insim-last-line-of-defence.miz` moved from `demo-missions/` to
  `unit-tests/last-line-of-defence/`, with its scenario script. It was never a demo: it is driven
  from outside through VEAF's `dcs-bridge`, it carries no player task, and its own script opens with
  *"In-sim checks for the last line of defense and the coverage refresh"*. It sat among the demos
  because that is where it was written, on 2026-09-19, and the directory now says what it is — which
  is also what keeps it out of the release assets, since those are the `demo-missions/` archives and
  nothing else.

### Removed

- `build-tools/bin/gh-md-toc.exe`, the 6 MB Windows binary that needed network access and was the
  only reason the build could not run on the CI runner.
- `skynet-iads-source/README_source.md`, superseded by the pages under `documentation/`.
- `tmp/skynet-iads-compiled.lua`, a 76-byte stub committed by an interrupted build.
- **Six legacy in-sim test suites**, both copies of each -- the loose `unit-tests/*.lua` and the one
  baked into `unit-tests/skynet-unit-tests.miz`: `abstract-dcs-object-wrapper`, `abstract-element`,
  `contact`, `harm-detection`, `jammer` and `sam-site`. Every test each of them asserted now runs in
  `test/lua/` on a plain Lua interpreter, and none of them asserted anything only DCS can answer --
  no terrain, no real detection, no figure a DCS unit reports about itself. Two copies that drift
  are worse than one, and they had: `test-skynet-iads.lua` carries a regression test its `.miz` copy
  never had, so the in-sim suite has never run it. David's call, 2026-09-19.

  The suites that stay are the ones a stub cannot answer for: the `iads`, `early-warning-radar` and
  `red`/`blue-sam-sites-and-ew-radars` suites, which enumerate the demo world; two of the three
  `moose-a2a-connector` tests, for the same reason; and `abstract-radar-element`, whose port is
  complete but which still asserts the ranges DCS reports for the units it models.

- **MIST is out of the demo missions, and out of this repository.** All four archives loaded
  `mist_4_5_107.lua`, 312 KB of it, because the Skynet they carried was the December 2023 build and
  it made 33 MIST calls. The current one makes none — `fe40c4a` wrote `SkynetIADSUtils` to replace
  it on 2026-08-30 — and across the loose setup scripts there was exactly one call left,
  `mist.scheduleFunction(outputNames, self, 1, 2)` in the MOOSE connector demo, now
  `SkynetIADSUtils.scheduleFunction(outputNames, nil, 1, 2)`. `self` was nil at that point in the
  script, so the argument it passed was never a table and never reached `outputNames`.

  `demo-missions/mist_4_5_107.lua` is deleted with them: nothing in this repository used it. The one
  file in any archive that still names MIST is `dcs-bridge.lua`, vendored from
  [VEAF/dcs-bridge](https://github.com/VEAF/dcs-bridge), which needs it only for a `spawn` command
  the mission carrying it never calls — and guards every use (`if mist then`, `if not mist or not
  mist.dynAdd then`).

  This also takes away the popup: MIST installs a `DEAD` event handler, and an object it does not
  know about put a message on the player's screen in the in-sim missions.

### Fixed

- The build was documented wrong in three places written the day before. The deliverable is
  `demo-missions/skynet-iads-compiled.lua`, not a file at the repository root; the build script
  takes the version as a **mandatory** argument and resolves its paths relative to `build-tools/`;
  and the root `README.md` is **generated** from `skynet-iads-source/README_source.md`, so editing
  it is lost. Corrected in `CLAUDE.md`, the `release` skill and the backlog.

  Two of those are now scheduled to disappear: the build is being redone on the CTLD model, and the
  README is coming out of it — it becomes a short hand-written door, and the documentation is what
  gets generated.
- Three accidental globals `luacheck`'s first run caught, none reachable from outside the
  function or file that set them: `samElement` in
  `SkynetIADSAbstractRadarElement:buildSingleUnit`, `testMarkerFunction` in a
  `test_skynet_iads_sam_site.lua` test method, and two of the highdigitsams file's
  local-redeclared-three-times chains left shadowing instead of reusing the local. Zero
  behaviour change; verified against the DCS stub and the full suite under a real Lua 5.1.
- `.gitignore` now covers `Thumbs.db`, `/.vscode/`, `/.idea/` and `/tmp/`, alongside the build
  and documentation output already ignored above — every rule checked with `git check-ignore -v`.
- A SAM site torn down while it was evading an anti-radiation missile was deaf for the rest of the
  mission ([issue #3](https://github.com/VEAF/Skynet-IADS/issues/3)). `cleanUp()` cancelled the two
  HARM tasks but left `harmSilenceID` set, and `goLive()` refuses while that field is there — so
  the site could no longer be woken by the network, by autonomy, by the last line of defense, or by
  `SkynetIADS:reportContact()`, and nothing was left to clear the field: the task that would have
  is the one `cleanUp()` had just removed. Reached by any `addSAMSitesByPrefix()`, which is what
  VEAF missions call on respawn, and by `SkynetIADS:deactivate()` followed by `activate()` — that
  pair empties no list, so the very same objects go back to work. `cleanUp()` now clears
  `harmScanID`, `harmSilenceID` and
  `harmShutdownTime` alongside cancelling their timers. It does **not** call `finishHarmDefence()`,
  which ends in `goAutonomous()` — a site being torn down would light its radar up on the way out.
  Covered by `test/lua/test_skynet_iads_harm_silence_cleanup.lua`, which drives the three doors a
  mission actually uses rather than asserting the field is nil.
- A bulk re-add left the elements it discarded wired into the coverage graph, for the rest of the
  mission. `addSAMSitesByPrefix()` and `addEarlyWarningRadarsByPrefix()` replace their whole list,
  and nothing removed an association: the per-element rebuild only ever adds, and
  `refreshRadarCoverage()` walks the *current* elements, which a discarded object is no longer
  among. A discarded EW radar still passed every test a parent is given — its DCS unit exists, it
  has power, a connection node, it acts as EW — so a battery went on believing it was covered by a
  radar the IADS no longer polls, stayed non-autonomous and stayed dark under nobody's watch; and a
  discarded SAM site stayed a child of its EW radar, still driving the controller of the DCS group
  the live site now owns. Both functions now rebuild the coverage once the list is repopulated,
  under the same "only if the IADS is running" guard the incremental rebuild already carries.
  Found while checking the premise of the fix above; covered by
  `test/lua/test_skynet_iads_bulk_re_add.lua`.
- Declaring that a radar covers a battery switched the battery off. `buildRadarAssociation()`
  recorded the link through `addParentRadar()`, which ends in `informChildrenOfStateChange()` ->
  `resetAutonomousState()` -> `goDark()` — so writing down a fact of geometry handed an extinction
  order to every battery in range. `goDark()`'s own guards protect a site that has acquired a track
  or has missiles in flight, but not one that has just gone live on network designation and not yet
  locked on, which is exactly the symptom commit `3a94937` is about: launchers raised, slew onto the
  target, back to travel state, no shot. In game this is reached by adding an early warning radar or
  a SAM site to a running mission, including the `*ByPrefix` calls VEAF's helper uses, and the gap
  lasts until the next contact cycle — 5 s by default, long enough for a fast pass to be over. The
  same oversight did the work N², at 250 notifications per `activate()` on three EW radars and ten
  SAM sites where 10 are needed. `buildRadarAssociation()` now uses
  `addParentRadarWithoutStateChange()`, added by the last line of defense for this very hazard and
  applied then to `refreshRadarCoverage()` only, and the two incremental entry points notify what
  actually changed, under the criterion `refreshRadarCoverage()` already uses: a site's state is
  touched only when its autonomy has really changed. `addEarlyWarningRadar()` also sets `actAsEW`
  before building the coverage rather than after — `setActAsEW(true)` is itself a state change, so
  running it after the rebuild darkened the batteries the radar had just picked up, and running it
  before means the radar already counts as a valid parent when the rebuild asks whose autonomy
  moved. `addParentRadar()` is unchanged and still public. Covered by
  `test/lua/test_skynet_iads_coverage_update_notification.lua`, whose leading test drives a real
  `evaluateContacts()` cycle rather than counting calls.
- A battery enrolled on a running IADS with no valid radar covering it stayed dark for the rest of
  the mission instead of being handed back to the DCS AI. Found by reviewing the fix above, which
  introduced it: the "only act when the autonomy has actually changed" test reads `isAutonomous`,
  and on a site `addSAMSite()` has just built that field is the constructor's default — it says
  `true` although `goAutonomous()` has never run, so the comparison weighed a value that never meant
  anything and skipped. It was reached whenever the only element in range was no use to the battery,
  a neighbouring SAM site not acting as EW being the ordinary case, and nothing came back for it
  afterwards: the last line of defense skips an autonomous DCS-AI site, the contact cycle never
  offers it anything because it is no usable radar's child, and the coverage sweep carries the same
  test. The state is now applied unconditionally to the site that has just joined, the way
  `activate()` applies it to every site — the site is one statement old and dark, so there is no
  designation to lose. The same call also used to refresh the MOOSE A2A dispatcher connector, at the
  end of `informChildrenOfStateChange()`; a mission using `addMooseSetGroup()` went on dispatching
  from the list it held before the battery joined, so the refresh is now asked for explicitly.
- An early warning radar added while a mission runs never reached MOOSE's A2A dispatcher.
  `addEarlyWarningRadar()` puts the radar into `self.earlyWarningRadars` at the very end, after
  everything that could have refreshed the connector has run, so the radar entered the `SET_GROUP`
  only by accident — if a battery happened to be enrolled after it. MOOSE scrambles interceptors on
  what that set detects, so the radar was watching for an IADS that could not act on it. Longstanding,
  found while measuring the entry above. The refresh is now a single method called wherever
  `self.samSites` or `self.earlyWarningRadars` changes, after the insert rather than before; it does
  nothing when no connector exists, and the documented setup registers its `SET_GROUP` last, so
  enrolling a whole mission still costs nothing.
- **Setup mistakes are shown on screen again, and every existing mission will see them.** Four
  messages — a group name that is not in the mission, a unit name that is not in the mission, an
  element belonging to the other coalition, and a group Skynet has no SAM data for — wrote one line
  to `dcs.log` and stopped there. The first is the most common setup mistake there is, a typo in a
  name, and its only symptom in game was a battery that never appeared, which reads as a Skynet bug
  rather than a typo.

  All four used to be shown on screen. The logging refactor of November 2020 (`9437df1`, *"moved
  output to dcs.log console for multiple log events"*) moved them to the log along with the two
  "added to IADS" lines, and left the *"this is a warning"* flag behind in a call that has no
  argument for it — which is why the source looks like a mistake rather than a decision. So this
  reverses a deliberate choice of walder's rather than repairing an accident, and VEAF takes it:
  a mission maker does not read `dcs.log`, and these four are the mistakes they can still fix while
  they are in the mission editor.

  The messages now reach the players prefixed `WARNING:` and still leave their line in the log.
  Expect a mission that has quietly carried one of them for years to start announcing it the first
  time it loads this build — that is the point. The escape hatch is
  `redIADS:getDebugSettings().warnings = false`, which silences the screen copy and keeps the log;
  `documentation/api.md` had that setting filed under log output and now says what it does.
- A line saying `New Object Spawned` was written to `dcs.log` for **every** unit that appeared —
  spawned groups, respawns, and a player taking a slot — once per network, so twice in a mission
  running a red and a blue one. It named nothing, nobody could act on it, and it was the one Skynet
  line written without the `SKYNET:` prefix, so it could not even be filtered out of a log. The
  enrolment it was written to support was commented out in December 2023, ten months after it was
  added, leaving the line behind. Both are gone. `SkynetIADS:onEvent()` is still registered as a world event handler, so the next
  event feature has its place.
- A battery with more than one radar was jammed once per radar instead of once per battery: each
  call rolled the dice again and overwrote the previous one, so whichever radar happened to come
  last decided. No mission behaved differently — the radars of one group are tens of metres apart,
  so the rolls were on the same odds — but a battery is now one decision per cycle, taken against
  the nearest radar the jammer can actually see.
- `SkynetIADS:addJammer()` is **removed**. It raised *table expected, got nil* on every call ever
  made to it, taking the mission's setup script down with it, and nothing anywhere read what it
  tried to store. Attach a jammer to a network the documented way, by handing the network to the
  constructor — `SkynetIADSJammer:create(Unit.getByName("F-4 AI"), redIADS)` — and a second network
  with `jammer:addIADS(blueIADS)`. The source says so where the method used to be.
- Calling `redIADS:addRadioMenu()` twice built the whole F10 menu twice, and left the first copy
  beyond the reach of `removeRadioMenu()` for the rest of the mission. A mission that re-runs its
  setup on a respawn did exactly that. The second call now does nothing; removing the menu and
  adding it again still works.
- Documented, rather than changed: a jammed battery is handed back about ten seconds after the
  jammer stops jamming it — shot down, switched off, out of range, or line of sight lost. That has
  always worked, through a timeout on the anti-radiation-missile scan every live battery runs, but
  no test covered it and `documentation/api.md` never mentioned it. Both now do.
- Both in-sim mission archives carried **Skynet 3.3.0, built 29 December 2023**, while `develop` had
  moved to 3.5.0. Neither `.miz` had been touched since 30 December 2023, so every in-sim run for
  close to three years measured code this project had stopped shipping -- including the 118-test run
  of 2026-09-20, which is what turned this up. The division of labour `test/lua/` was built on --
  the standalone suite leans on the in-sim one for what a stub cannot answer -- only holds if the
  in-sim half runs the code we ship, and it did not. Both archives now carry the current build, and
  `miz-suite.py check` fails if they drift again.
- Three tests written during 2026 had never run: `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage`
  (added 2026-08-23) in `test-skynet-iads.lua`, and `testHighScreenB`, `testClamShell2` and
  `testSA10BGrumble` in `test-skynet-high-digit-sam-sites.lua`. Each was added to the loose copy and
  never baked into the archive, which is the same drift running the other way. All are now in.
- MiST is out of both in-sim mission archives, and the popup it put on the player's screen with it.
  `fe40c4a` took MiST out of Skynet on 2026-08-30, but the missions still loaded
  `mist_4_5_107.lua` -- 312 KB -- because the 2023 artifact they carried still called it 33 times.
  Loading MiST installs MiST's own world event handler, and a `DEAD` event for an object it has no
  record of ends in `Object.getPosition` on something already gone:
  `ERROR SCRIPTING (Main): ... mist_4_5_107.lua:1350: Object doesn't exist`, which DCS shows the
  player. The suites that blow objects up are what set it off. The harness's own five MiST calls
  become their `SkynetIADSUtils` equivalents -- `round` is the same function character for
  character, `get2DDist` differs only by a nil warning, and `random` draws from the same
  distribution. The leak check at the end of `skynet-unit-tests.lua` still works: task ids come
  from a counter starting at 1, and `removeFunction` still answers whether there was one, so
  walking the integers is the same sweep.
- `testAWACSHasMovedAndThereforeRebuildAutonomousStatesOfSAMSites` had been measuring nothing since
  2026-08-23. `0ebbc01` renamed `lastUpdatePosition` to `lastCoverageUpdatePosition`; the in-sim test
  kept writing the old name, so it set a field nothing reads and
  `getDistanceTraveledSinceLastUpdate()` answered 0 where the test asserts 763. It stayed green
  because the mission ran the December 2023 build, where the old name was still the real one --
  `docs/evolutions.md` had predicted this exact failure on 2026-09-19 and could not prove it.
  Refreshing the artifact proved it, in one line of the DCS log.
- 125 assertions pinning a figure that belongs to Eagle Dynamics are out of the in-sim suites --
  missile reach, firing ceiling, radar detection distance, initial ammunition. They are recorded in
  `test/lua/dcs-figures.lua` instead, where a change arrives as a pull request rather than as a red
  test nobody sees for three years. What stays in the `.miz` is what a stub cannot answer: terrain,
  real detection geometry, how a DCS group is composed, and Skynet's own decisions -- along with the
  assertions on figures a test fabricates through a mocked `getDCSRepresentation()`, which are not
  ED's, and the handful asserting that the S-300's radars report no range at all, which is Skynet
  coping with a unit DCS ships without sensor data.
- The same in-sim AWACS test also counted calls to `buildRadarCoverageForEarlyWarningRadar` to prove
  that a moved AWACS triggers a coverage rebuild. `0ebbc01` moved that deliberately -- movement is
  `refreshRadarCoverage()`'s job now, because the incremental rebuild only ever added, so an AWACS in
  transit accumulated every battery it had ever flown near -- so the test was counting a function no
  longer on that path. The behaviour is covered standalone by
  `test/lua/test_skynet_iads_coverage_refresh.lua`; what stays in the mission is the part that needs
  the simulator, the distance between two real DCS units.
- Both Persian Gulf demos destroyed the jammer aircraft they had just armed, on every single load --
  `skynet-test-persian-gulf.miz` and `skynet-test-persian-gulf-stress-test.miz` share one setup
  script and carry the same two units, so the defect and its fix are the same in both. The
  setup script ends its jammer section with a guard of walder's that removes the AI F-4E when nobody
  occupies the `Hornet SA-11-2 Attack` slot -- but it runs at `triggerStart`, and that slot is a
  client slot, which has no `Unit` until a player takes it. `Unit.getByName` therefore always
  returned nil and the guard always fired, so the F10 `Jammer:` menu was created and immediately
  removed, and `runCycle` found its emitter dead and disarmed without a word. Not a regression: the
  group is
  byte-identical in the December 2023 archive and the guard predates VEAF, so the demonstration has
  only ever worked by luck of timing. The guard is gone -- if nobody takes the Hornet slot the F-4E
  now flies its route alone and jams the red network anyway, which for a demo about jamming is the
  better failure.
