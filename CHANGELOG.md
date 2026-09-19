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
identified itself as `3.4.0RP-VEAF`. Settled on 2026-09-19: VEAF continues the **artifact's**
lineage, since that is the number anyone reads in a log. The first VEAF release is **3.5.0**, tagged
`v3.5.0`, and the `RP` suffix is dropped — the Regroupement no longer maintains this project.

Until that release is cut, the build date in the artifact's first line remains the real identifier.

## [Unreleased]

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

### Removed

- `build-tools/bin/gh-md-toc.exe`, the 6 MB Windows binary that needed network access and was the
  only reason the build could not run on the CI runner.
- `skynet-iads-source/README_source.md`, superseded by the pages under `documentation/`.
- `tmp/skynet-iads-compiled.lua`, a 76-byte stub committed by an interrupted build.

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
