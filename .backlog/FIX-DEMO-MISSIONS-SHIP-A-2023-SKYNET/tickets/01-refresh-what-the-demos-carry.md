# 01 — Assemble the demo missions instead of committing a copy of the code

Status: 🔄 in-progress — coded and flown 2026-09-20; see *Flown in DCS* below

Three of the four archives under `demo-missions/` carry `SKYNET VERSION: 3.2 | BUILD TIME: 29.12.2023
1905Z`, and none of them has been touched since 2023-12-29. `develop` is on 3.5.0.

Ticket 03 chose **(b)**: the committed archives become templates, `miz-suite.py build` assembles the
playable missions into `build/missions/`, and the release attaches them. Same design as the in-sim
test missions, which `FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET` ticket 05 converted on 2026-09-20.

## What to build

### The tool has to grow up to these four archives

`ARCHIVES` is a tuple of two paths; adding four more is the mechanical part. What is not mechanical,
measured 2026-09-20 by reading the archives rather than assuming:

1. **`source_of()` looks in the archive's own directory, then in `unit-tests/`.** That second folder
   is wrong for a demo. The two families reduce to the same rule — *the archive's own directory,
   then the top-level directory of its path* — which gives `unit-tests/` for
   `unit-tests/highdigitsams/…` and `demo-missions/` for `demo-missions/moose_a2a_connector/…`.

2. **`NO_SOURCE_IN_REPO` is declared and never exercised.** It is read by `check_sources` and
   `do_build`, and **not** by `do_stub`, which stubs every `.lua` member it finds. Put `Moose.lua`
   (5.6 MB in the MOOSE demo) in it as it stands and `stub` replaces MOOSE with a placeholder that
   `build` will never put back, because `build` skips exactly those names. `check_sources` also
   demands that every member be a placeholder, which `Moose.lua` must not be. Both have to learn the
   exception before the tuple gets its first entry.

3. **The loose-file scan runs per archive, and three archives share `demo-missions/`.** `check` would
   report `skynet-insim-last-line-of-defence.lua` as loaded by no trigger while checking the Persian
   Gulf archive, and the Persian Gulf setup as unloaded while checking the last-line one. The scan
   has to be folder-wide and run once, after every archive in that folder has been read. It also has
   to skip `skynet-iads-compiled.lua`, which is generated into `demo-missions/` and is nobody's
   loose script.

4. **`skynet-insim-last-line-of-defence.miz` is not written in DCS's own serialisation.** It was
   re-saved by VEAF's mission editor on 2026-09-19, which writes `trigrules = {` where DCS writes
   `["trigrules"] = `, `file = "X"` where DCS writes `["file"] = "X"`, and no `-- end of [n]`
   comments at all. It also carries a resource key that is not a `ResKey_Action_NNN` at all:
   `MCP_MapKey_dcs-bridge`. **Every regex in `miz-suite.py` assumes the DCS form**, so today the
   tool reads that archive as having an empty `mapResource` and four undefined keys. Both
   serialisations are real — DCS writes one, the editor writes the other — so the tool parses both
   or it cannot be pointed at this archive.

5. **One member's name lies about what it holds.** In `skynet-insim-last-line-of-defence.miz` the
   setup is baked in as `skynet-iads-setup-persian-gulf.lua`, and its bytes are
   `demo-missions/skynet-insim-last-line-of-defence.lua` — a file that exists under another name.
   `source_of` would find the Persian Gulf setup, put it in, and assemble a mission that loads the
   wrong script without one complaint from `check`, because the name it looked up does exist. The
   member is renamed to what it actually is, in `mapResource` and as an archive member, before
   anything else happens to that archive.

### What the loose scripts become

Under (b) the loose file is the only copy, so where the two disagree the loose file wins — but not
before reading what would be lost. Measured 2026-09-20, line endings normalised:

| archive | its setup copy vs the loose file |
|---|---|
| `skynet-test-persian-gulf.miz` | archive adds `:setIgnoreHARMSWhilePointDefencesHaveAmmo(true)` to the SA-10 |
| `skynet-test-persian-gulf-stress-test.miz` | identical (and it loads the *same* loose file) |
| `moose_a2a_connector/…` | loose is ahead: `Syknet` typo fixed, `samWentDark` → `radarWentDark` |
| `skynet-insim-last-line-of-defence.miz` | identical, under a different member name (see 5 above) |

The one call the Persian Gulf archive has and the loose file does not is a **deprecated no-op**:
`SkynetIADSAbstractRadarElement:setIgnoreHARMSWhilePointDefencesHaveAmmo` logs `DEPRECATED: …` and
returns `self`, and `documentation/api.md:525` says it will be removed. Dropping it loses a log line.
The MOOSE drift is a typo and a debug flag inside a `--[[ ]]` block. Nothing of substance is lost by
taking the loose copies.

### What the release ships

`.github/workflows/release.yml` builds the deliverable and attaches it. It now also assembles the
missions and attaches the **demo** ones. Not all six: `unit-tests/*.miz` is the developer suite, and
`skynet-insim-last-line-of-defence.miz` is not a demo either — see the open question below.

### What the documentation has to say

`documentation/index.md:37-40` is a Quick start that links the `.miz` by raw URL on `master`. Under
(b) that link hands a newcomer a template. It points at the Releases page instead, and the page says
how to assemble one from a checkout for anybody working from `develop`. `documentation/setting-up.md`
and `documentation/api.md` link `demo-missions/` as a directory to browse — that stays true, the
scripts are still there; what is no longer true is that the `.miz` beside them is playable.

`CLAUDE.md` and `test/lua/README.md` describe `miz-suite.py` as covering "both archives". Six now.

## Watch out for

**A demo is judged by flying it, not by a pass count.** The in-sim suite answered "119 tests, 0
failures"; a demo answers "does it still demonstrate what it is for". `skynet-test-persian-gulf.miz`
is the one `documentation/` points at, so it is the one that has to be flown. The stress test is
where a wrong answer hides best — it is meant to look busy.

**Expect the demos to behave differently, and that is the point.** Three years of changes sit between
3.2 and 3.5.0, including `FEAT-LAST-LINE-OF-DEFENSE` and `FIX-COVERAGE-UPDATE-DARKENS-SITES`. Sites
will wake and go dark at different moments than they used to. A difference is not a regression here;
what would be a regression is an error in the log, or a site that never lights at all.

**The setup scripts may not survive three years unchanged either.** They call into Skynet's public
API, and `documentation/api.md` is the record of what that API is now. If one of them calls something
that has been renamed, it fails at mission start — which is a genuine finding, and belongs in this
lot rather than being patched past.

**`miz-suite.py` has no tests, and this ticket rewrites the regexes that edit binary archives.** The
parsing and the trigrules surgery get a `unittest` file, covering both serialisations. The tool
re-checks its own output before writing, which has caught mistakes, but it cannot catch a regex that
matches the wrong thing consistently.

## Open question, for David

**`skynet-insim-last-line-of-defence.miz` is not a demo.** Its script opens with *"In-sim checks for
the last line of defense and the coverage refresh"*, it is driven from outside through VEAF's
dcs-bridge, and it "carries no player task". It sits in `demo-missions/` because that is where it was
written, on 2026-09-19. It should not be attached to a release as a demo, and arguably belongs beside
the in-sim suite. This ticket **leaves it where it is** and excludes it from the release assets;
moving it is a rename that touches the `FEAT-LAST-LINE-OF-DEFENSE` record and is David's call.

## Flown in DCS, 2026-09-20

David flew `skynet-test-persian-gulf.miz` as assembled from this branch, from the
`Hornet SA-11-2 jammer support` slot. Watched live through VEAF's build of dcs-fiddle -- a hook, so
nothing had to be injected into the mission under test -- and against the whole `dcs.log`.

**The mission carried the right Skynet**: `SKYNET VERSION: 3.5.0 | BUILD TIME: 20.09.2026 1704Z`,
the artifact built from these sources. **Zero** script errors in the log, **zero** placeholder
messages, **zero** mentions of MIST.

**It still demonstrates an IADS.** The cycle, from the `GOING LIVE` / `GOING DARK` lines:

| mission time | what happened |
|---|---|
| 17:40:45 | start -- 8 EW radars live, 13 SAM sites settle dark under network control |
| 17:40:46 | except the two SA-10s (`setActAsEW(true)`) and the SA-15 point defence |
| **17:44:00** | `EW-east-2` picks up one contact |
| **17:44:20** | `SAM-SA-11` **goes live** -- designated by the network, 20 s after the detection |
| **17:45:28** | `SAM-SA-11` **goes dark** |
| 17:45:30 | `EW-east-2` has lost the contact |
| 17:45:52 | `EW-west3` and `EW-Near-SA-11` pick it up in turn |

A battery woken on a contact it cannot see itself, and handed back to the dark when the contact
leaves. That is the thing the demo exists to show, and it still shows it.

**What this run does not answer**: how 3.5.0 differs from 3.2 *in the air*. No 3.2 baseline was
flown, so there is nothing to compare against -- only the assertion that the demo works, which is
what the lot needed. Writing down three years of difference would need the same profile flown twice,
and that is not what this session did. Said plainly rather than dressed up as a comparison.

**One defect found, and deliberately not fixed here.** The demo destroys its own jammer aircraft at
mission start: a guard in `skynet-iads-setup-persian-gulf.lua:77` checks for a client slot at `t=0`,
before it has spawned, and the `else` branch it falls into destroys the emitter and removes its radio
menu. Proven from the F10 menu and the setup script's ordering, measured as byte-identical in the
December 2023 archive, so not a regression. David's call, 2026-09-20: record it, keep the lot on its
subject. Written up in `docs/evolutions.md` under *The Persian Gulf demo destroys its own jammer at
mission start*.

## Definition of done

- The four demo archives hold placeholders, and `check` fails if one holds a script.
- `build` assembles all six missions, and CI proves it can on every pull request.
- `Moose.lua` and `dcs-bridge.lua` survive `stub` and `build` untouched, and `check` says why they
  are allowed to.
- The member name that lied has been corrected, and no assembled mission loads a script it is not
  named after.
- `release.yml` attaches the assembled demo missions.
- `documentation/index.md` no longer sends a newcomer to a raw `.miz` in the repository.
- `CLAUDE.md`, `test/lua/README.md` and the tool's own docstring describe six archives, not two.
- ✅ `skynet-test-persian-gulf.miz` has been flown in DCS and still demonstrates an IADS: sites wake,
  sites go dark, no error in the log. 2026-09-20, `SAM-SA-11` lit at 17:44:20 and dark at 17:45:28.
- 🚫 What changed in behaviour between 3.2 and 3.5.0, as observed. Dropped: it would need the same
  profile flown on both builds, and only 3.5.0 was flown. Claiming a comparison from one run would be
  the kind of unmeasured assertion this lot was opened over.
