# A release is prepared and packaged by one script, and checks its own tag

Status: done

## The problem

A release takes five steps, and nothing checks that they fit together.

- **The changelog is frozen after the tag.** `.github/workflows/release.yml` takes its notes from
  `## [Unreleased]` as it stands, so `[Unreleased]` can only be renamed to `[x.y.z]` once the
  release is out, in a pull request of its own. Any pull request merged to `develop` between the tag
  and that freeze appends its entry to a section already holding the released notes, and the freeze
  then files it under a version that does not contain it.
- **Nothing checks the tag.** A `v3.6.0` pushed on a commit whose `SkynetIADS.version` is still
  `3.5.0` publishes a release named 3.6.0 whose artifact announces 3.5.0 in every log. A tag pushed
  on `develop` or a feature branch publishes too; only the demo check might catch it, and only if
  the demos happen to differ from that commit's build. `master` has no branch protection.
- **The release runs one test.** It builds and runs `test_compiled_script` against the DCS stub, and
  relies on `master`'s CI having been green before the tag.
- **The release is first seen once public.** Nothing shows the files and the notes a tag would
  publish before the tag is pushed.

The preparation is three hand edits — the version, the changelog's headings, the demos — and the
release workflow's checks are shell inside a workflow, which nothing tests. The procedure is also
stated twice: in `CONTRIBUTING.md` and in `.claude/skills/release/SKILL.md`, which also says to
bring `develop` up to date before preparing.

## What to build

### `build-tools/release.py`

One script does the release's work, and runs twice: by the developer on the release branch, to
prepare and see what the release will be; by CI on the tag, to check that and publish it. Both runs
end with `build/release/` holding exactly what the release attaches.

**`release.py X.Y.Z`** prepares, on the `release/<x.y.z>` branch the developer has created:

- sets `SkynetIADS.version` in `skynet-iads-source/skynet-iads.lua` to `X.Y.Z`. It refuses a version
  that is not three numbers, `X.Y.Z`; one lower than the code's; and one that already has a `vX.Y.Z`
  tag, which is a published release. The code's own version, not yet tagged, is accepted: it is a
  second run of the same preparation. The tag is looked up in the local repository: a tag belongs to
  no branch, and `git pull` on `develop` fetches the tags of every branch it fetches, `master`'s
  included;
- renames `## [Unreleased]` in `CHANGELOG.md` to `## [X.Y.Z] — YYYY-MM-DD`, today's date, and opens
  an empty `## [Unreleased]` above it. When `## [X.Y.Z]` already exists it leaves the changelog
  alone, so a second run changes nothing — unless `[Unreleased]` holds entries again, merged since
  the first run: it then refuses, naming them, since they ship in this release and belong in
  `[X.Y.Z]`, a move made by hand. When `[Unreleased]` is empty and there is no `[X.Y.Z]`, it
  refuses;
- refreshes the demos' Skynet script and `demo-missions/skynet-script.sha256`, through
  `demo-missions/update-skynet-script.py`'s `update`;
- then packages, as below.

**`release.py`**, with no version, packages and checks, changing no committed file:

- takes the version from `SkynetIADS.version`, read the way the build reads it;
- with `--tag vX.Y.Z`, refuses a tag that is not `vX.Y.Z`, or whose version is not the code's;
- empties `build/release/`, then writes:
  - `skynet-iads-compiled.lua`, the build;
  - both demos, copied as committed, after checking that each carries that build — `check
    --against-build`. It never refreshes them: a release ships what was reviewed;
  - `notes.md`, the body of `## [X.Y.Z]` — the lines between that heading and the next `## [` — the
    version matched literally. A missing or empty section is an error with `--tag`, a warning
    without;
- runs `test_compiled_script` through `test/common/run.lua`. When no Lua 5.1 interpreter is found it
  says so and skips it — an error with `--tag`, since CI always has one.

The asset names do not change: `skynet-iads-compiled.lua`, `skynet-test-persian-gulf.miz`,
`skynet-and-moose-a2a-dispatcher.miz`. A repository that fetches one by its release URL keeps
working.

Its tests are in `test/build-tools/`.

### The release workflow

`.github/workflows/release.yml`, on a `v*` tag:

- **runs the Lua and Python tests first**: `.github/workflows/lua-tests.yml` gains a `workflow_call`
  trigger, and the release job `needs` it;
- **checks the tag is on `master`**: `git merge-base --is-ancestor "$GITHUB_SHA" origin/master`, with
  a full-history checkout. It stays in the workflow: it needs the remote's history;
- **runs `release.py --tag "$GITHUB_REF_NAME"`**;
- **publishes `build/release/`**: `gh release create --verify-tag`, the artifact and the demos as
  assets, `notes.md` as the notes;
- **publishes only `vX.Y.Z`**: today a tag that is not a plain `vX.Y.Z`, such as `v3.6.0-rc1`, is
  published as a GitHub pre-release, one never marked *Latest*. That step goes, and `release.py`
  refuses such a tag.

### The documentation workflow

`.github/workflows/docs.yml` drops its pre-release path too: today a tag that is not a plain
`vX.Y.Z` deploys its version without moving `latest`. A tag deploys its version and `latest`. The
manual republish accepts `X.Y.Z` only.

### The procedure

The *Releasing* section of `CONTRIBUTING.md` becomes:

1. **Prepare**, on a `release/<x.y.z>` branch from an up-to-date `develop`: run
   `python build-tools/release.py <x.y.z>`. The new `## [x.y.z]` section already holds the
   entries each pull request added: it is the release notes as they stand. Editing it is optional —
   a summary above the entries, a reordering. `python build-tools/release.py` again shows the
   release as it will be published, in `build/release/`. Commit the version, the changelog, the
   demos and the hash file; pull request to `develop`.
2. **Promote**: a pull request from `develop` to `master`, merged with a merge commit. A source
   change merged to `develop` after the preparation fails its demo check: prepare again.
3. **Tag** `v<x.y.z>` on `master` and push it. The release workflow runs the tests and `release.py`
   on the tag, and publishes. It refuses a tag off `master`, a version that is not the code's, a
   changelog with no section for it, or demos that do not carry the build.

The old last step, *tell whoever vendors the script*, goes: it names nobody and nothing to do.
*Changelog and versioning* already says why a release reaches no mission by itself.

The in-sim run before the first step stays as it is. The build is reproducible and the promotion
gives `master` the tree of `develop`, so what the tag publishes is byte for byte what step 1 showed.

Elsewhere in `CONTRIBUTING.md`: the `release/<x.y.z>-freeze` branch goes from *Git flow*; the
pre-release sentences go from *The build* and *Documentation*; *The demo missions are committed
whole* says the demos are refreshed by step 1.

### The skill

`.claude/skills/release/` is deleted. `CONTRIBUTING.md` is the only place the procedure lives.

### IDEAS

*The release workflow reads `[Unreleased]` literally* and *The release skill repeats
`CONTRIBUTING.md`* leave `IDEAS.md`: this work takes both up.

## Decisions

| Decision | Turned down | Why |
|---|---|---|
| One script prepares and packages, run on the release branch and again on the tag | checks written as workflow shell; a separate check script | the same code makes the preview and the release, and has tests |
| The demos are refreshed in the preparation, only checked on the tag | refreshed on the tag; embedded into copies at packaging | refreshed on the tag, the demos would land after the tagged commit and the workflow would have to push to `master`; embedded into copies, a checkout's demos would lag behind the releases |
| The preparation is a branch and a pull request | a commit on `develop` | it changes `skynet-iads-source/`, and the pull request is where the notes are read before they are public |
| Loose assets in `build/release/` | a zip | the release is one script and two missions; a zip would break every URL that fetches the script directly |
| No manual dry run in the workflow | `workflow_dispatch` | the build is reproducible: a local `release.py` gives the files CI would publish |
| No pre-releases | `vX.Y.Z-rcN` tags | none has ever been cut, and keeping them means deciding what version an rc's artifact announces and which section it reads |
| The tag must equal the code's version | a tag that only parses | the artifact's first line is what people read in a log, and it must say what the release page says |
| The skill is deleted | a thin walkthrough | its confirmations are what any agent does before an irreversible step; bringing `develop` up to date moves into step 1 |
| The release notes are the entries the pull requests added | a callout written at preparation | every change to `skynet-iads-source/` already carries its entry, written by the one who knows what it changes for a mission |
| A version is refused once tagged, not only when lower | lower only | the code's version is still 3.5.0 on `develop`, under a `[3.5.0]` section: accepted, it would label unreleased code with a published number |

## Out of scope

- **Pruning the current `[Unreleased]`** of entries that only concern contributors, and sorting it
  for 3.6.0: that is the release's own preparation.
- **The changelog's format** — the Keep a Changelog headings, or a `Behaviour change:` prefix in
  place of them.
- **Branch protection on `master`**: a repository setting, not a file.
- **The git and GitHub steps** — branches, pull requests, the tag, the push: irreversible, and the
  maintainer's call.
