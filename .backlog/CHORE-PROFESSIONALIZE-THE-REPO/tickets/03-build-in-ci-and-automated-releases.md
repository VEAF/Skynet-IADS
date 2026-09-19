# 03 — Rebuild the build on the CTLD model, and release automatically

Status: ✅ done

The ticket with the most leverage in this lot. Without a release, every consumer copies a file by
hand and nobody knows which version they hold — which is exactly what happened: the artifact
vendored in VEAF-Mission-Creation-Tools identifies itself as `build 05.09.2026` while the sources
had moved a month further on, and nothing anywhere said so.

## Decision

David, 2026-09-19: **redo the build on the VMCT/CTLD model — it is the same job — and take the
README out of it.** The README becomes a short hand-written entry point; the *documentation* is what
gets generated, as in the other two repositories ([ticket 06](06-publish-the-documentation.md)).

## What the current build does, and what is wrong with it

`build-tools/build-compiled-script.ps1`, 60 lines, does four things: it concatenates the sources,
stamps a version banner, writes `demo-missions/skynet-iads-compiled.lua`, and regenerates the root
`README.md` through `bin/gh-md-toc.exe`.

| | Today | CTLD |
|---|---|---|
| Source order | **twenty paths hard-coded on one `cat` line** | `tools/build/listToMerge.txt`, one path per line, with `--` comments explaining *why* the order is what it is |
| Path resolution | `../skynet-iads-source/…`, relative to the **working directory** — run it from the repository root and it fails | resolved from the script's own location, so it runs from anywhere |
| Version | a **mandatory argument**; forget it and the script prints `No Version supplied` and stops | read from a single source of truth in the code, and stamped from there |
| Output | `demo-missions/skynet-iads-compiled.lua`, committed | repository root, **git-ignored**, rebuilt by CI and attached to releases |
| Portability | ends with a 6 MB **Windows** binary that needs network access | pure PowerShell, runs on the Linux runner under `pwsh` |

The hard-coded list is the worst of them: adding a source file means editing a 900-character line,
and the load order — which matters, since these files define classes that depend on each other — is
nowhere explained.

## What to build

1. **A merge manifest.** `build-tools/listToMerge.txt`, one source per line, in load order, with
   comments saying why the order is what it is. Copy CTLD's shape: it is the same job and a
   contributor moving between the two repositories should recognise it.
2. **Resolve paths from the script**, not from the working directory.
3. **One source of truth for the version**, read by the build rather than passed in. Which file
   holds it is an open choice — a dedicated constant in `skynet-iads-source/skynet-iads.lua` is the
   obvious candidate. The banner keeps its current shape, since that line is how anyone identifies
   what a mission is running.
4. **Take the README out of the build**, and drop `bin/gh-md-toc.exe` with it. That binary is the
   only reason the build cannot run on the CI runner, and once the documentation is a published site
   a generated table of contents on a short README buys nothing.
5. **Decide where the artifact lives** and whether it stays committed. CTLD ignores it and lets CI
   produce it, which is what makes "never hand-edit the artifact" enforceable rather than a request.
   Note that `demo-missions/*.miz` load it from its current path — moving it means touching them.

## Check the artifact, do not merely build it

Building proves the files concatenate. It does not prove the result runs. `assert(loadfile(f))`
parses and says nothing about a main chunk that raises — that is precisely how a CTLD release passed
the gate on the VEAF side and killed every radio menu in the mission. So the CI **executes** the
built artifact against the DCS stub already present in `test/lua/dcs-stub.lua`, and fails if it
raises.

## Release

David, 2026-09-19: **tag-triggered only**, not on every merge to `master` — so a pre-release tag
(`v3.5.0-rc1`) can be cut without it ever being the tip of `master`, as on CTLD. A tag not shaped
like a plain `vX.Y.Z` publishes as a GitHub pre-release.

On a tag:

- build the artifact;
- attach it to a GitHub release, named by version;
- take the release notes from the `[Unreleased]` section of the changelog;
- the version and build date are already stamped into the artifact's first line.

Versioning is settled: **3.5.0**, tagged `v3.5.0`, continuing the artifact's lineage rather than the
inherited `v2.0.1` tags, and without the `RP` suffix. See `CHANGELOG.md`.

## Definition of done

- The source list lives in a commented manifest, not in the script.
- The build runs from any working directory, and on the Linux CI runner.
- CI builds on every pull request and fails if the build fails.
- CI loads **and runs** the built artifact against the DCS stub.
- The build no longer touches `README.md`, and `gh-md-toc.exe` is gone.
- Merging to `master` publishes a release carrying the artifact and the changelog extract.
