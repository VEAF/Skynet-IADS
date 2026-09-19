# 01 — Adopt gitflow

Status: ✅ done

**Do this first.** Every other ticket in this lot, and both tickets of
`FEAT-LAST-LINE-OF-DEFENSE`, will be delivered as pull requests — they need a target branch that is
not the release branch.

## Today

Two branches: `master`, which is both the default and where everything lands, and
`feat/insim-tests`. No `develop`. Commits go straight to `master` (`29da7e6`, `1cd651e` and
`f6d77e6` are on it), so there is no place where work accumulates before it is released, and no
branch a consumer can point at and call stable.

The other two VEAF repositories both work the other way: `develop` is the default and the target of
every PR, `master` carries releases.

## What to do

1. Create `develop` from the current `master`.
2. Make `develop` the **default branch** on GitHub. This matters beyond convenience: on
   VEAF-Mission-Creation-Tools, leaving the default on the wrong branch had Dependabot opening
   sixteen pull requests nobody wanted and silently disabled the scheduled jobs.
3. Point the CI at it — `.github/workflows/lua-tests.yml` currently triggers on `push` to `master`;
   it should run on `develop` too, and on PRs to either.
4. Branch naming: `feature/<lot-or-ticket>` and `fix/<lot-or-ticket>`, cut from `develop`. One
   branch and one PR per lot, not per ticket, unless a lot is large enough to need splitting.
5. Merge to `master` only to release — see
   [ticket 03](03-build-in-ci-and-automated-releases.md).
6. Enable *delete branch on merge*. A surviving branch with a fixed name silenced a scheduled robot
   on the VMCT side for three weeks before anyone noticed.
7. ~~Say all of it in `contributing.md`~~ — **done 2026-09-19**, rewritten end to end.

## Watch out for

- `feat/insim-tests` is open work. Rebase it onto `develop` rather than leaving it pointing at
  `master`, and tell Flogas before moving anything he has in flight.
- Nothing is protected today. Making `develop` the default does **not** protect `master`; decide
  separately whether to require a PR to reach it. On the VMCT side `develop` is unprotected, which
  is why `gh pr merge --auto` merges immediately there — worth knowing before copying habits across.

## Definition of done

- ~~`develop` exists and is the default branch.~~ **Done** — and *delete branch on merge* is on.
- ~~CI runs on pushes to `develop` and on PRs.~~ **Done** — every workflow triggers on
  `[master, develop]` and on pull requests.
- ~~`contributing.md` describes the flow, the branch naming and the release path.~~ **Done.**
- ~~`feat/insim-tests` rebased or explicitly left alone, with Flogas informed.~~ **Left alone,
  deliberately** — David informed Flogas on 2026-09-19. The branch is Flogas's open work and still
  points at `master`; rebasing someone else's branch under them buys nothing here, and it will be
  rebased or merged by its owner.
