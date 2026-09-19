# 07 — Repository hygiene

Status: ✅ done

Small things, each costing a few minutes and saving someone an hour.

## ~~`contributing.md` is upstream's~~ — done 2026-09-19

It points at walder's Discord, tells contributors to add unit tests to `skynet-unit-tests.miz`, and
says nothing about `test/lua/`, about gitflow, or about the compiled file being generated. Someone
following it today would do the wrong thing three times over. Rewrite it around what this repository
actually does, and keep what is still true — the test-first philosophy and the semantic versioning
both are.

## `tmp/` is committed

`tmp/skynet-iads-compiled.lua`, 76 bytes. Now explained: the build creates `./tmp/` as scratch space
and deletes it at the end, so an interrupted build leaves a stub behind — and someone committed one.
Remove it and add `tmp/` to `.gitignore`, which also stops the next interrupted build from offering
the same trap.

## `.gitignore` is three lines

`.DS_STORE`, `/demo-missions/spikes/`, `/.superpowers/`. Add what the project actually produces —
including the built artifact, if [ticket 03](03-build-in-ci-and-automated-releases.md) stops
committing it:
build output, editor directories, and whatever a test run can leave behind. If you are tempted by
nested `.gitignore` files, do not — on the VMCT side a root rule ignoring every subdirectory
`.gitignore` made three of them invisible for months. Put the rules at the root and check with
`git check-ignore -v`.

## The inherited tags

Tags run to `v2.0.1` from upstream while the artifact calls itself `3.4.0RP-VEAF`. Decide what VEAF
numbering is and record it in the changelog — see
[ticket 03](03-build-in-ci-and-automated-releases.md). Do **not** delete the inherited tags: they
are history, and something may reference them.

## Definition of done

- ~~`contributing.md` describes this repository's workflow, not upstream's.~~ **Done.**
- ~~`tmp/` untracked and ignored.~~ **Done** — the committed stub is removed, and the rewritten
  build (ticket 03) no longer writes there at all, but the rule stays as a defensive default.
- ~~`.gitignore` covers what the project generates, verified with `git check-ignore -v`.~~ **Done**
  — added `Thumbs.db`, `/.vscode/`, `/.idea/`; verified every rule with `git check-ignore -v`
  against a matching file.
