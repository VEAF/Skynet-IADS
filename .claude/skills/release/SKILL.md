---
name: release
description: Cut a Skynet release — build the artifact, prove it runs, tag and publish the GitHub release, then freeze the changelog. Use when the user wants to ship a version.
disable-model-invocation: true
---

# Release

Interactive, step by step, through the release procedure in `CONTRIBUTING.md`. The rules live
there; this skill walks the user through them. **Wait for the user's confirmation at each step.**
Never push a tag or publish a release without an explicit go: both are irreversible and both are
visible to everyone who takes this project.

## Before step 1

`git fetch`, then `git pull --ff-only` on `develop`. Read `## [Unreleased]` in `CHANGELOG.md` — it is
the raw material. Ask for the target version, proposing a bump from the current `SkynetIADS.version`
and the versioning rule in `CONTRIBUTING.md`.

Then interview, three questions, no more:

- the theme of this release, in one line;
- anything that changes behaviour for existing missions, and must be called out;
- anything a mission maker has to do differently after upgrading.

The second question is the one that earns its place. Skynet changes are felt in flight, not read in a
diff: a new default, a site that now lights up where it used to stay dark, a setting that changed
meaning. Say it plainly or someone will file it as a bug.

## Fly it, before the version is bumped

CI cannot: GitHub runners have no DCS. Build the missions and run the in-sim smoke checks against a
DCS with the release candidate in it:

```bash
pwsh -File build-tools/build-compiled-script.ps1
python build-tools/miz-suite.py build --with-bridge
python build-tools/run-smoke.py --target demo
python build-tools/run-smoke.py --target lastline --tier slow
```

**Consultative, not a gate.** A red check is a conversation, not a stop: report the table and ask.
No DCS to hand means the runner skips and exits 0; then say the release goes out unflown rather than
implying it was checked. `unit-tests/README.md` has the checks.

## Then the procedure

Take the user through every step of the release procedure in `CONTRIBUTING.md`, one at a time:

- open the pull requests with `gh pr create --repo VEAF/Skynet-IADS`, `--base develop` for the
  release branches and `--base master --head develop` for the promotion, and wait for CI on each;
- for the tag, give the user the commands and let them run them:

  ```bash
  git checkout master && git pull origin master
  git tag v<x.y.z>
  git push origin v<x.y.z>
  ```

  then watch the release run once with `gh run list --workflow=release.yml` — do not poll it in a
  loop;
- for the last step, say what is waiting on the release, and that it reaches no mission by itself.

Never commit `demo-missions/skynet-iads-compiled.lua`: it is git-ignored and rebuilt by CI. Never
publish from a dirty working tree.
