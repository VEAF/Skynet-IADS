# 03 — Build on the CI runner, and release automatically

Status: ⬜ ready

The ticket with the most leverage in this lot. Without a release, every consumer copies a file by
hand and nobody knows which version they hold — which is exactly what happened: the artifact
vendored in VEAF-Mission-Creation-Tools identifies itself as `build 05.09.2026` while the sources
had moved a month further on, and nothing anywhere said so.

## Build on the runner

`build-tools/build-compiled-script.ps1` is PowerShell; the CI runs Ubuntu. So **nothing checks that
the sources still concatenate into a usable artifact** — the one thing a consumer depends on.

Two ways, to be weighed when doing it:

- **run it with `pwsh`**, which is available on the GitHub Ubuntu runners. No rewriting, and the
  local and CI paths stay identical;
- **port it** to Lua or to a shell script. One language less in the project, at the cost of
  rewriting something that works and that Flogas knows.

Recommendation: `pwsh` first, because it is one line of CI and it closes the hole today; port later
if the script grows.

## Check the artifact, do not merely build it

Building proves the files concatenate. It does not prove the result runs. `assert(loadfile(f))`
parses and says nothing about a main chunk that raises — that is precisely how a CTLD release passed
the gate on the VEAF side and killed every radio menu in the mission. So the CI **executes** the
built artifact against the DCS stub already present in `test/lua/dcs-stub.lua`, and fails if it
raises.

## Release

On a merge to `master`, or on a tag:

- build the artifact;
- attach it to a GitHub release, named by version;
- take the release notes from the `[Unreleased]` section of the changelog;
- stamp the version and build date into the artifact's first line, as the current one already does.

Versioning: the project declares semantic versioning in `contributing.md`, the inherited tags stop
at `v2.0.1`, and the artifact calls itself `3.4.0RP-VEAF`. Reconcile the two and say plainly in the
changelog where VEAF numbering starts.

## Definition of done

- CI builds the artifact on every pull request and fails if the build fails.
- CI loads **and runs** the built artifact against the DCS stub.
- Merging to `master` publishes a release carrying the artifact and the changelog extract.
- A consumer can tell, from the artifact alone, which version it is.
