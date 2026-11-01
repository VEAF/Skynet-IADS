# The demo missions carry their Skynet script

Status: open

## The problem

The demo missions under `demo-missions/` hold a placeholder where every script goes — Skynet's and each
demo's setup script. `build-tools/miz-suite.py build` assembles playable copies into `build/missions/`,
and CI checks that git holds no copy of a script. A demo opened from a checkout does not run, and the
tool behind all this — wiring, extraction, stubbing, removal — is far heavier than what the demos need.

## The target

- **The demos are client demos, not tests.** What tests Skynet lives in `test/insim/` or `test/lua/`.
- **The demos are stable.** They are committed whole, scripts included, and a demo opened from a
  checkout runs. Only the Skynet script inside them changes, and only for a release, so a demo carries
  the released Skynet.
- **Nothing checks a demo beyond its Skynet script's hash.**
- The demos are `demo-missions/skynet-test-persian-gulf.miz` and
  `demo-missions/moose_a2a_connector/skynet-and-moose-a2a-dispatcher.miz`, under their current names.

## What to build

### The updater

`demo-missions/update-skynet-script.py`, replacing `build-tools/miz-suite.py`:

- `update`: replaces the embedded `l10n/DEFAULT/skynet-iads-compiled.lua` of each demo with an
  in-memory build (`chore-build-in-python`), leaving every other member of the archive as it is, and
  writes `demo-missions/skynet-script.sha256`: one line per demo, the hash of its embedded script and
  the demo's path. It refuses a demo with no such member.
- `check`: each demo's embedded script matches its line in `skynet-script.sha256`.
- `check --against-build`: the same, and the embedded script equals an in-memory build.

It never rewires a mission: it only replaces the content of a script already wired in. Its tests are in
`test/demo-missions/`, replacing `test/build-tools/test_miz_suite.py`.

### The demos

- The placeholders go. Each demo embeds the current build and its setup script as it stands —
  `demo-missions/skynet-iads-setup-persian-gulf.lua`, and
  `demo-missions/moose_a2a_connector/skynet-and-moose-a2a-dispatcher-setup.lua` — and
  `skynet-script.sha256` is committed with them.
- The loose setup scripts stay in the repository, for reading and diffing. No tool keeps them in step
  with the embedded copies: a developer who edits one edits the `.miz` too.
- `demo-missions/skynet-test-persian-gulf-stress-test.miz` moves to `.tracker/test-insim-stress-scenario/`.

### CI and the release

- The `mission-archives` job of `.github/workflows/lua-tests.yml` becomes a demos job: `check` on every
  push and pull request, `check --against-build` on pull requests to `master` and pushes to `master`.
  Its wiring check, its assembly and its parse step go. The Python tests it runs stay in some job.
- *Releasing* in `CONTRIBUTING.md`: step 1, on the `release/<x.y.z>` branch, runs `update` after the
  version bump and commits the demos and `skynet-script.sha256` with it.
- `.github/workflows/release.yml` attaches the committed demos. It assembles nothing.
- `.claude/skills/release/SKILL.md` follows.

### Removed

- `build-tools/miz-suite.py` and `test/build-tools/test_miz_suite.py`; `build/missions/`.

### The guidance and documentation

- `CONTRIBUTING.md`: *The missions are assembled, not committed* becomes a short passage saying the
  demos are committed whole, a release refreshes their Skynet script, and the loose setup scripts are
  kept in step by hand. *Layout* names the updater. The "never edit a `.miz` by hand" rule goes.
- `CLAUDE.md`: the `miz-suite.py build` command and the rule against editing a `.miz` by hand go, and
  so does the paragraph on placeholders.
- `.gitignore`: the comment on assembled missions.
- `test/lua/README.md`: the passages on the mission wiring and `miz-suite.py`.
- `documentation/index.md` and `index.en.md`: a demo opened from a clone runs, with the Skynet of the
  last release; the passage on assembling missions goes.

## Decided

| Decision | Turned down | Why |
|---|---|---|
| The demos are committed with every script inside | placeholders assembled on demand | a demo opened from a checkout or downloaded from GitHub runs as it is |
| The Skynet script is refreshed in the release's preparation | on every build; on the tag | a demo carries the released Skynet, which is what it demonstrates. Refreshed on the tag, the demos would land after the tagged commit, and the workflow would have to push to `master` |
| The setup scripts are embedded once, then kept in step by hand | the updater embedding them on every refresh | the demos are stable; a loose copy is a convenience for reading, not a source |
| A demo is checked by its Skynet script's hash only | a wiring check; parsing every script; checking in DCS | the updater never rewires; a script equal to a tested build is proven. The demos went stale for years without a complaint |
| On `develop`, the hash file; towards `master`, a fresh build too | a fresh build everywhere | between releases a demo carries the last release, which `develop` cannot rebuild |
| The stress-test mission leaves the demos | keeping it | it is a test, not a demo; an in-sim scenario may replace it |
| The smoke checks the in-sim port left here — `networks-built`, `named-elements-found`, `jammer-alive`, `no-mist` — do not come back | porting them | what they caught in a demo is the demo's; what is Skynet's behaviour belongs in `test/insim/` |
| The names stay | `skynet-demo-…` | the name is what the documentation and earlier releases call it |

## Out of scope

- The in-sim suite's missions, which embed no Skynet script and are handled by `test/insim/run.py`.
- The build itself: `chore-build-in-python`, which this needs first.
- A stress scenario: `test-insim-stress-scenario`.
