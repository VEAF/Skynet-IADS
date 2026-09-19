# 06 — Publish the documentation, and shrink the README to a door

Status: ✅ done

The gap this ticket closed with — `documentation/api.md` not documenting the wake-up entry point
`FEAT-LAST-LINE-OF-DEFENSE` adds, because that lot had not landed — is **filled**: `api.md` carries
the last line of defense, its three settings (`setLastLineOfDefence`, `setLastLineOfDefenceRadius`,
`setLastLineOfDefencePersistence`) and the public `reportContact` door, since that lot merged.

## Decision

David, 2026-09-19: **the README comes out of the build and is rewritten short, pointing at the
documentation. The documentation is what gets generated** — the CTLD and VMCT model.

Today it is the other way round: a 43 KB `README.md` *is* the manual, and it is **generated** by the
build from `skynet-iads-source/README_source.md` with a table of contents substituted into
`{TOC_PLACEHOLDER}`. Nothing is published, nothing is versioned, nothing is searchable. A mission
maker looking for how to set a go-live range scrolls.

## The model to copy

CTLD publishes with **MkDocs Material + mike**, deployed by `.github/workflows/docs.yml`, and the
versioning discipline is the part worth copying rather than the tooling:

| Push | Publishes as |
|---|---|
| `develop` | `dev`, and it is the site default while no stable exists |
| `master` | `latest` |
| tag `v3.5.0` | that exact version, **and** `latest` — but a pre-release publishes its version only and leaves `latest` alone |

That last rule is why it matters: a reader landing on an old release page gets the pages that match
it, and a release candidate never becomes what a newcomer reads by default.

## What to do

1. **Split `README_source.md`** along its natural seams: what an IADS is and how Skynet models it,
   setting one up in a mission, the public API, the supported units, the debug and status output,
   the contributor's guide. It is 36 KB of prose that already has sections — this is reorganising,
   not rewriting.
2. **Rewrite `README.md` by hand**, short: what the project is, who maintains it, where the
   documentation is, how to get the script, where to report a problem. It stops being generated, so
   `{TOC_PLACEHOLDER}` and `gh-md-toc.exe` go with it — which is what unblocks the build on the CI
   runner ([ticket 03](03-build-in-ci-and-automated-releases.md)).
3. **Set up MkDocs + mike** and the deploy workflow, with the version mapping above.
4. **Do not leave two copies of the same prose.** Every paragraph is either in the site or in the
   README, never both. This is the failure mode of a split like this one, and it is invisible until
   the two copies contradict each other.

The public API page carries an obligation of its own: `FEAT-LAST-LINE-OF-DEFENSE` adds a public
wake-up entry point, deliberately, so that VEAF code outside Skynet can call it. An entry point
nobody can find is not public.

## Language

English. This project has users beyond VEAF, and English is what the existing documentation and the
code comments are written in. That differs from VMCT, which is French-first with English twins, and
the difference is deliberate — do not copy their bilingual machinery here.

## Definition of done

- A documentation site building in CI and deployed on merge, versioned as above.
- `README.md` hand-written, short, and no longer produced by the build.
- `gh-md-toc.exe` removed from the repository.
- The public API documented, the new wake-up entry point included.
- No prose duplicated between the README and the site.
