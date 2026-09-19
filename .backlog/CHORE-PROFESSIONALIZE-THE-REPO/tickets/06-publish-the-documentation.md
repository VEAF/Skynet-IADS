# 06 — Publish the documentation

Status: ⬜ ready

## Today

A 43 KB `README.md`, which is the entire user manual. **It is generated**: the build rewrites it from
`skynet-iads-source/README_source.md`, substituting a table of contents into `{TOC_PLACEHOLDER}`.
Never edit the root file — edit the source.

Nothing published, nothing versioned, nothing searchable. A mission maker looking for how to set a
go-live range scrolls.

## What to build

A published documentation site, as VEAF-Mission-Creation-Tools has — MkDocs, built and deployed by a
workflow, versioned alongside the releases from
[ticket 03](03-build-in-ci-and-automated-releases.md).

Split `README_source.md` along its natural seams: what an IADS is and how Skynet models it, how to
set one up in a mission, the public API, the supported units, the debug and status output, and the
contributor's guide. Keep the generated README as an entry point that says what the project is and
links to the site — do not leave two copies of the same prose.

**Settle the generation at the same time.** If the README shrinks to a page, its generated table of
contents stops being worth a 6 MB Windows binary that needs network access — and that binary is the
one thing preventing the build from running on the CI runner
([ticket 03](03-build-in-ci-and-automated-releases.md)). Dropping it may be the simplest way to
unblock both.

The public API page carries a new obligation: `FEAT-LAST-LINE-OF-DEFENSE` adds a public wake-up
entry point, deliberately, so that VEAF code outside Skynet can call it. An entry point nobody can
find is not public.

## Language

English. This project has users outside VEAF — the Regroupement, and whoever still runs walder's
version — and English is what the existing documentation and the code comments are written in. That
differs from VMCT, which is French-first with English twins, and the difference is deliberate.

## Definition of done

- A documentation site building in CI and deployed on merge.
- The README reduced to an entry point.
- The public API documented, the new wake-up entry point included.
- No prose duplicated between the README and the site.
