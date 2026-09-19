# 03 — Build on the CI runner, and release automatically

Status: ⬜ ready

The ticket with the most leverage in this lot. Without a release, every consumer copies a file by
hand and nobody knows which version they hold — which is exactly what happened: the artifact
vendored in VEAF-Mission-Creation-Tools identifies itself as `build 05.09.2026` while the sources
had moved a month further on, and nothing anywhere said so.

## Build on the runner

`build-tools/build-compiled-script.ps1` is PowerShell; the CI runs Ubuntu. So **nothing checks that
the sources still concatenate into a usable artifact** — the one thing a consumer depends on.

`pwsh` is available on the GitHub Ubuntu runners, so PowerShell alone is not the obstacle. **The
table-of-contents step is.** The script ends by regenerating the root `README.md` from
`skynet-iads-source/README_source.md` using `build-tools/bin/gh-md-toc.exe` — a 6 MB **Windows**
binary that also needs network access. On Linux it will not run at all.

So the work splits in two, and only the first half is needed to close the hole:

- **the concatenation** — pure PowerShell, runs under `pwsh` anywhere, and it is the part a consumer
  depends on. Do this first;
- **the table of contents** — either a Windows runner for the release job alone, or a portable
  replacement, or cut it from the build entirely and regenerate the README elsewhere. Decide when
  ticket 06 settles what the documentation becomes: if the README shrinks to an entry point, a
  generated table of contents may no longer be worth a 6 MB binary.

Two details the script imposes on whatever calls it: the **version is a mandatory argument**, and it
resolves its paths **relative to `build-tools`**. It writes `demo-missions/skynet-iads-compiled.lua`.

Flogas already guarded the failure mode worth knowing about (VEAF #4): `gh-md-toc.exe` exits 0 with
no network while emitting a header and no entries, which silently blanked the README's table of
contents. The build now bails instead.

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
