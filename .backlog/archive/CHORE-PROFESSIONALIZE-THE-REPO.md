# CHORE-PROFESSIONALIZE-THE-REPO — bring this repository up to the standard of the other two

Closed 2026-09-20, seven tickets. PRs [#10](https://github.com/VEAF/Skynet-IADS/pull/10)–[#14](https://github.com/VEAF/Skynet-IADS/pull/14),
[#16](https://github.com/VEAF/Skynet-IADS/pull/16), [#29](https://github.com/VEAF/Skynet-IADS/pull/29)–[#31](https://github.com/VEAF/Skynet-IADS/pull/31).

Origin: David, 2026-09-19 — *"je veux aussi qu'on professionnalise le repo VEAF/Skynet (backlog,
tests unitaires, CI, releases automatisées, skills, documentation publiée, etc.) comme CTLD et
VMCT"*.

The premise: this is no longer a fork of convenience. **VEAF maintains Skynet** — the Regroupement's
repository is read-only and walder has been inactive for years — and the tooling should say so.

## What it put in place

| | |
|---|---|
| 01 | gitflow: `develop` as default and target, `master` for releases, branches deleted on merge |
| 02 | `.backlog/`, `CHANGELOG.md`, `CLAUDE.md`, `CONTEXT.md`, `docs/agents/`, and the `skynet-runtime-debug` and `release` skills |
| 03 | the build on the CI runner (pure PowerShell, Ubuntu), `check-artifact.lua`, and a release published on a `v*` tag |
| 05 | `luacheck` and `stylua`, with a ratchet pinning the first run's warnings to their exact file and code — to erode, never to grow |
| 06 | the MkDocs Material site, versioned with `mike`, at <https://veaf.github.io/Skynet-IADS/> |
| 07 | repository hygiene |
| 04 | the legacy suites migrated |

## Ticket 04, the one that took the longest

`abstract-radar-element` ported in four slices, all 46 of its live tests. **Six legacy suites removed
from both copies** — the loose `unit-tests/*.lua` and the one inside `skynet-unit-tests.miz` — and a
CI job added that checks that archive, which no gate had ever looked at. Test coverage 91.17% →
**94.63%**.

Verified in DCS 2026-09-20: the in-sim suite ran 118 tests where it ran 168, exactly the 50 removed,
with no script-loading error. Its four remaining failures pinned DCS figures last updated in 2023 and
became `FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET` ticket 03.

## The drift this archive exists to stop

This lot's own PRD said *"six of seven done, only 04 is still running"* until **2026-09-21**, a day
after ticket 04 merged. A status line nobody re-reads is a status line that lies.
