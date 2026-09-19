# CHORE-PROFESSIONALIZE-THE-REPO — bring this repository up to the standard of the other two

Status: 🔄 in-progress — six tickets of seven are done; only 04, the migration of the legacy
suites, is still running

Origin: David, 2026-09-19 — *"je veux aussi qu'on professionnalise le repo VEAF/Skynet (backlog,
tests unitaires, CI, releases automatisées, skills, documentation publiée, etc.) comme CTLD et
VMCT"*.

## Where this repository stands today

It is no longer a fork of convenience: **VEAF maintains Skynet**. The Regroupement's repository is
read-only and walder has been inactive for years, so this is the living home of the project. The
tooling should say so.

What is already here, and good:

| | |
|---|---|
| A standalone Lua 5.1 test suite | `test/lua/`, 14 suites, its own DCS stub and fixtures, a runner and a README |
| A CI that runs it | `.github/workflows/lua-tests.yml`, on push to `master` and on every PR |
| A build | `build-tools/build-compiled-script.ps1`, which concatenates the sources into the shipped artifact |
| An ideas tracker | `docs/evolutions.md` |
| Demo missions | `demo-missions/` |

What is missing, and is the scope of this lot:

| | |
|---|---|
| A branching model | one branch, `master`, which is both the default and where everything lands. No `develop`, so nowhere for work to accumulate before release and no branch a consumer can call stable |
| A backlog | no `.backlog/` — this lot creates it, and is its first entry alongside `FEAT-LAST-LINE-OF-DEFENSE` |
| A changelog | none. Nothing tells a consumer what changed between two artifacts |
| Agent instructions | no `CLAUDE.md`, no agent skills. Every session rediscovers the conventions |
| A release | tags up to `v2.0.1` inherited from upstream, **no GitHub release at all**. VEAF-Mission-Creation-Tools vendors this project by copying a file by hand |
| The build in CI | the build is PowerShell, the runner is Ubuntu. Nothing checks that the sources still concatenate into a loadable artifact |
| Static analysis | no `luacheck`, no formatter. The other two repositories gate on both |
| Published documentation | a 43 KB `README.md` inherited from upstream, and `docs/evolutions.md`. Nothing published, nothing versioned |
| The legacy suites | `unit-tests/*.lua` still hold the bulk of the coverage and only run inside DCS. `test/lua/README.md` already records the intent to migrate |

## Tickets

| # | Ticket | Status |
|---|---|---|
| 01 | [Adopt gitflow](tickets/01-adopt-gitflow.md) | ✅ |
| 02 | [A backlog, a changelog and agent instructions](tickets/02-backlog-changelog-and-agent-instructions.md) | ✅ |
| 03 | [Build on the CI runner, and release automatically](tickets/03-build-in-ci-and-automated-releases.md) | ✅ |
| 04 | [Finish migrating the legacy suites](tickets/04-finish-migrating-the-legacy-suites.md) | 🔄 |
| 05 | [Static analysis and formatting](tickets/05-static-analysis-and-formatting.md) | ✅ |
| 06 | [Publish the documentation](tickets/06-publish-the-documentation.md) | ✅ |
| 07 | [Repository hygiene](tickets/07-repository-hygiene.md) | ✅ |

**Ticket 01 comes first**: every other ticket here, and both tickets of `FEAT-LAST-LINE-OF-DEFENSE`,
will be delivered as pull requests, and they need a target branch that is not the release branch.

The rest are independent of each other. Ticket 03 has the most leverage: without a release, every
consumer copies a file by hand and nobody knows which version they hold.

## What this lot is not

It is **not** a rewrite, and it does not touch behaviour. Any change that alters what Skynet does at
runtime belongs in its own lot with its own tests — the point of this one is that such a lot becomes
cheap and safe to run.

## Definition of done

Each ticket carries its own. Across the lot: a contributor arriving on this repository finds the
same shape as on VEAF-Mission-Creation-Tools and CTLD — a branch to work from, a backlog that says
what is planned, a CI that refuses what is broken, a release that says what shipped, and
documentation that is published rather than buried in a README.
