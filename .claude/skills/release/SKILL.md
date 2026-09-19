---
name: release
description: Cut a Skynet release — build the artifact, prove it runs, freeze the changelog, tag, and publish the GitHub release. Use when the user wants to ship a version.
disable-model-invocation: true
---

# Release

Interactive, step by step. **Wait for the user's confirmation at each step.** Never push a tag or
publish a release without an explicit go: both are irreversible and both are visible to everyone who
consumes this project.

## Read this first: building and publishing are automated, the rest is not

`CHORE-PROFESSIONALIZE-THE-REPO` ticket 03 added `.github/workflows/release.yml`: pushing a tag
matching `v*` builds the artifact, runs it against the DCS stub, and publishes a GitHub release
carrying it — attaching whatever is currently under `## [Unreleased]` in `CHANGELOG.md` as the
release notes. A tag that is not a plain `vX.Y.Z` (a pre-release like `v3.5.0-rc1`) publishes as a
pre-release, matching the CTLD model.

That last point reorders one thing versus a hand-rolled release: **do not rename `[Unreleased]` to
the version heading before tagging** — the workflow reads that heading literally, and a renamed
section would ship an empty release. Freeze the changelog *after* the tag is pushed and the release
is out, as a follow-up commit on `develop`. Everything else below is still done by hand.

## Why it matters more than usual here

The consumer of this repository is another repository:
[VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools) vendors
`demo-missions/skynet-iads-compiled.lua` into `src/scripts/community/`. Nothing reaches a mission until they
re-vendor, and that copy has run a month behind without anyone noticing. **A release is the signal
that makes the copy possible** — so the release notes are written for them as much as for players,
and a release without a changelog entry is a release nobody can act on.

## Versioning — settled 2026-09-19

Two numbering schemes had coexisted without ever being reconciled: the inherited tags stop at
`v2.0.1` (walder's lineage), while the artifact has long called itself `3.4.0RP-VEAF`.

**David's decision**: continue the artifact's lineage, because that is the number anyone actually
reads in a log. The first VEAF release is **`3.5.0`**, tagged **`v3.5.0`** — the shape of the
existing tags, colliding with none of them. The `RP` suffix is dropped: the Regroupement no longer
maintains this project.

Semantic versioning from there, as `contributing.md` already states. A change to what a mission sees
at runtime is at least a minor.

## Steps

1. **Sync.** `git fetch`, `git pull --ff-only` on `develop`. Read the `[Unreleased]` section of
   `CHANGELOG.md` — it is the raw material. Ask the user for the target version, proposing a bump
   from the current artifact string.

2. **Interview**, three questions, no more:
   - the theme of this release, in one line;
   - anything that changes behaviour for existing missions, and must be called out;
   - anything a mission maker has to do differently after upgrading.

   The second question is the one that earns its place. Skynet changes are felt in flight, not read
   in a diff: a new default, a site that now lights up where it used to stay dark, a setting that
   changed meaning. Say it plainly or someone will file it as a bug.

3. **Bump `SkynetIADS.version`** in `skynet-iads-source/skynet-iads.lua` to the target version, on a
   branch off `develop` (e.g. `release/x.y.z`), and open a pull request. Wait for CI — it builds the
   artifact and runs it against the DCS stub on every pull request, so a chunk that raises fails the
   gate before you ever tag it. **Do not touch `CHANGELOG.md`'s `[Unreleased]` heading here** — it
   must still read `## [Unreleased]` when the tag is pushed in step 5. Merge to `develop`, then
   promote to `master` per the project's branching model.

4. **Never commit the built artifact.** It is git-ignored and rebuilt by CI; nothing in this branch
   should touch `demo-missions/skynet-iads-compiled.lua`.

5. **Tag and let CI publish it** — give the user the commands, let them run them:

   ```bash
   git checkout master && git pull origin master
   git tag v3.5.0
   git push origin v3.5.0
   ```

   The push triggers `.github/workflows/release.yml`: it builds, runs the artifact against the DCS
   stub, and publishes a GitHub release named `v3.5.0` carrying the artifact and whatever is under
   `## [Unreleased]` right now. Watch the run once (`gh run list --workflow=release.yml`), do not
   poll it in a loop.

   A pre-release goes out the same way, from a branch instead of `master` if it must not be on the
   release branch yet: tag it `v3.5.0-rc1` (anything not a plain `vX.Y.Z`), and the workflow marks
   the GitHub release as a pre-release automatically.

6. **Freeze the changelog**, now that the release is out: on `develop`, replace `## [Unreleased]`
   with `## [x.y.z] — YYYY-MM-DD` and open a fresh empty `[Unreleased]` above it. Doing this before
   the tag would have shipped an empty release — the workflow reads the `[Unreleased]` heading
   literally.

7. **Tell the consumer.** The release does not reach a single mission by itself. Say so, and say
   what is waiting on it — normally a vendoring lot in VEAF-Mission-Creation-Tools. If that lot
   exists, name it; if it does not, say that it needs to.

## What not to do

- Do not publish from a dirty working tree, and do not publish an artifact you did not rebuild from
  the sources being tagged.
- Do not skip the changelog because "it is only a fix". The changelog is how the consuming
  repository decides whether to re-vendor.
- Do not reuse or move a tag. If a release is wrong, cut the next one.
