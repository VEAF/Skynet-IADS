# 01 — A manual trigger on the documentation workflow

**Status**: ⬜ ready

## Work

`workflow_dispatch` on `.github/workflows/docs.yml`, taking the version to republish and whether
to move `latest` with it. Three things to get right, all three learned from VMCT's copy:

- **The existing `develop` step must not fire on a dispatch.** Its condition is the ref, and a
  dispatch run from `develop` carries that ref — so a manual republish of 3.5.0 would redeploy the
  `dev` alias as a side effect. Add `github.event_name == 'push'`.
- **The input is untrusted**, so it reaches the shell through an environment variable, never
  interpolated into the script.
- **An empty version means "just redeploy `dev`"**, which is the other thing one wants a manual
  run for.

## Done when

`gh workflow run docs.yml -f version=3.5.0` republishes `/3.5.0/` and `/latest/` from the current
`develop`, leaves the tag and the artifact untouched, and does not touch `dev`.
