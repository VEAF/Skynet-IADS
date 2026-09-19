---
name: release
description: Cut a Skynet release — build the artifact, prove it runs, freeze the changelog, tag, and publish the GitHub release. Use when the user wants to ship a version.
disable-model-invocation: true
---

# Release

Interactive, step by step. **Wait for the user's confirmation at each step.** Never push a tag or
publish a release without an explicit go: both are irreversible and both are visible to everyone who
consumes this project.

## Read this first: the release is manual today

There is no release workflow. `CHORE-PROFESSIONALIZE-THE-REPO` ticket 03 will add one; until it
lands, every step below is done by hand. The steps marked **→ automated later** are the ones that
will disappear.

## Why it matters more than usual here

The consumer of this repository is another repository:
[VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools) vendors
`skynet-iads-compiled.lua` into `src/scripts/community/`. Nothing reaches a mission until they
re-vendor, and that copy has run a month behind without anyone noticing. **A release is the signal
that makes the copy possible** — so the release notes are written for them as much as for players,
and a release without a changelog entry is a release nobody can act on.

## Versioning — settle this on the first use

Two numbering schemes coexist and have never been reconciled:

| | |
|---|---|
| Inherited tags | `v1.1.1` … `v2.0.1`, from walder's lineage |
| The artifact's own string | `3.4.0RP-VEAF build DD.MM.YYYY` — the `RP` is the Regroupement's fork |

**Recommendation, to confirm with the user before the first release**: continue the artifact's
lineage, because that is the number anyone reads in a log — so `3.5.0` for the first VEAF release.
Tag it `v3.5.0`, matching the shape of the existing tags without colliding with any of them. Drop
the `RP` suffix: the Regroupement no longer maintains this. Record the decision in `CHANGELOG.md` so
the question is settled once.

Semantic versioning, as `contributing.md` already states. A change to what a mission sees at runtime
is at least a minor.

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

3. **Build and prove it runs.**

   ```
   pwsh -File build-tools/build-compiled-script.ps1
   ```

   Then **execute** the result against the DCS stub — do not settle for loading it.
   `assert(loadfile(f))` parses the file and says nothing about a main chunk that raises, and that
   is exactly how a CTLD release passed its gate and killed every radio menu in the mission. One
   raise takes down the whole concatenated chunk a mission loads.

   Check the artifact's first line carries the new version and build date before going further.

   → automated later: ticket 03 moves both the build and this check into CI.

4. **Freeze the changelog.** Replace `## [Unreleased]` with `## [x.y.z] — YYYY-MM-DD` and open a
   fresh empty `[Unreleased]` above it. Entries are appended at the end of that section by every
   pull request, so the order already reads chronologically.

5. **Release branch and pull request.** `release/x.y.z` from `develop`, carrying the changelog and
   whatever version string lives in the sources. Target `develop`. Title: `release: prepare x.y.z`.
   Wait for CI and review, then merge.

   **Never commit the built artifact from a release branch.** It is a build output; publishing it is
   step 6's job.

6. **Tag and publish** — give the user the commands, let them run them:

   ```bash
   git checkout develop && git pull origin develop
   git tag v3.5.0
   git push origin v3.5.0
   gh release create v3.5.0 skynet-iads-compiled.lua \
     --title "Skynet-IADS v3.5.0" \
     --notes-file <the changelog section for this version>
   ```

   → automated later: pushing the tag will do all of it.

7. **Tell the consumer.** The release does not reach a single mission by itself. Say so, and say
   what is waiting on it — normally a vendoring lot in VEAF-Mission-Creation-Tools. If that lot
   exists, name it; if it does not, say that it needs to.

## What not to do

- Do not publish from a dirty working tree, and do not publish an artifact you did not rebuild from
  the sources being tagged.
- Do not skip the changelog because "it is only a fix". The changelog is how the consuming
  repository decides whether to re-vendor.
- Do not reuse or move a tag. If a release is wrong, cut the next one.
