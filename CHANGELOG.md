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

### Changed

- `develop` is the default branch, and the Lua suite runs on it.
