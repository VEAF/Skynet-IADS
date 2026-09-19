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
- `.gitignore` now covers `Thumbs.db`, `/.vscode/`, `/.idea/` and `/tmp/`, alongside the build
  and documentation output already ignored above — every rule checked with `git check-ignore -v`.
