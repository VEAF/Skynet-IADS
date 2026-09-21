# CHORE-DOCS-MANUAL-REPUBLISH

Let a released version's documentation be republished without moving its tag.

## Why

`FEAT-BILINGUAL-DOCUMENTATION` shipped the site in French and English, and nobody outside the
project can see it. `docs.yml` deploys on a push to `develop` (→ `dev`) and on a `v*` tag (→ that
version, plus `latest`), so between two releases the documentation a visitor reads is frozen at the
last tag — today `3.5.0`, English-only.

Waiting for the next release was one option and David refused it on 2026-09-21: the work stays
invisible for a delay nobody controls, for a change that alters no code.

Republishing is honest here, and that is the point: **the Lua sources have not changed since
`v3.5.0`** — `git diff v3.5.0..develop -- skynet-iads-source/` is empty. The bilingual pages
describe exactly the artifact 3.5.0 ships, in two languages, with one documented method name
corrected. Nothing about the release moves: not the tag, not the artifact, not the number.

This is VMCT's mechanism, added there for the same reason — their own comment says rebuilding from
the *tagged* commit would mean a fix landed after the tag never reaches the published pages.

## Refused alternatives

- **`mike set-default dev`** — one command, no code, and wrong the day `dev` describes behaviour
  that is not released. The repository already decided this: `dev` is the default only while no
  stable release exists.
- **Cutting a 3.5.1** — a version number spent on a translation, with a bit-identical artifact,
  and release notes that would read "the documentation was translated".

## Tickets

| # | Ticket | Status |
|---|--------|--------|
| 01 | [A manual trigger on the documentation workflow](tickets/01-manual-trigger.md) | ⬜ |
