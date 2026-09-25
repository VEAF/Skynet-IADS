# 04 — CONTRIBUTING.md becomes the single source

**Status**: ⬜ ready

## Problem

Seven subjects are written twice, in `CLAUDE.md` and in `CONTRIBUTING.md`: joint maintenance,
English-everywhere, the deliverable and the build, git flow, the bilingual-documentation rules,
test-first and the stub warning, and the changelog rule. Two of the four defects this lot exists to
fix are drift between those copies.

## Work

Fold the delegated half of `CLAUDE.md` into `CONTRIBUTING.md`, so that each of the seven subjects is
stated once, in the guide. Then fix what the merge exposes:

- **Settle the git-flow disagreement.** `CONTRIBUTING.md` says never commit directly to `develop`;
  `CLAUDE.md` grants the `.backlog/`-only exception. The exception is right and the guide is out of
  date. Carry it across stating its reason — a pull request whose entire diff is the tracker costs a
  review cycle and protects nothing CI can check — and not the lot or the date that settled it.
- **No rule in the guide argues from the backlog.** Every rule states itself and its reason; none
  cites a PRD, a ticket, a lot or a commit. See the PRD. `CONTRIBUTING.md` is nearly clean already —
  its two `.backlog/` rows name the tracker as a directory, which is allowed — so this is mostly a
  constraint on what ticket 05 moves in. The "Settled on 2026-09-19" in § Versioning is a fact about
  the numbering, not a backlog pointer, and stays.
- **Carry "one commit per ticket" across verbatim.** It is wrong — it states a prohibition and none
  of the three exceptions the project relies on — and `.backlog/IDEAS.md` holds the analysis. Do not
  fix it here: that is a decision about how the project works, not about where a file lives, and
  smuggling it into a documentation merge is how a rule changes without anyone agreeing to it. Leave
  the entry open.
- **Add the missing lint section.** `build-tools/lint.sh`, what `luacheck` and `stylua` gate, the
  `.luacheckrc` ratchet, and the two Windows workarounds. It exists only in `CLAUDE.md` today, where
  a contributor has no reason to look, while `lint.yml` fails their first pull request.
- **Put the Windows test invocation where someone starting out will meet it** — § What you need,
  beside the Lua 5.1 prerequisite:
  `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua`. It is documented today only in
  `test/lua/README.md`, which is named twice in passing and never as the answer to *how do I run the
  tests on Windows*. Repeat the invocation; leave the explanation — PowerShell's call operator, the
  `cmd.exe` form — where it is.
- **Fix the pointer to that file.** `CLAUDE.md` currently ends the *mission archives* bullet with
  "See `test/lua/README.md`", attaching the test-suite door to a paragraph about `miz-suite.py`.
  Ticket 05 rewrites that section; the pointer belongs with the test row of its table.
- **Write down the file naming conventions**, for the first time. Per directory, as practice already
  has them: UPPERCASE for root markdown; kebab for `skynet-iads-source/`, `build-tools/` and
  `documentation/`; `test_<snake>.lua` and `test_<snake>.py` for test files, mirroring `test/python/`
  where snake_case is forced because Python cannot import a module with a hyphen in it; `<LOT-ID>/`
  and `NN-slug.md` in `.backlog/`. The conventions **describe what the repository already does**;
  they do not legislate new territory. Two things they must therefore cover rather than contradict:
  `build-tools/listToMerge.txt`, recorded as an inherited exception with why it was not renamed, and
  `.claude/skills/<kebab-name>/SKILL.md`, whose uppercase filename inside a kebab directory is
  imposed by Claude Code and is not ours to choose. An outlier a written rule does not mention reads
  as an oversight; one it names reads as a decision.

## Done when

Each of the seven subjects appears once in the repository; `CONTRIBUTING.md` describes the lint gate
and the naming conventions; the git-flow section states the `.backlog/` exception; "one commit per
ticket" is unchanged from its current wording; and every subject `CLAUDE.md` holds today is either
present in `CONTRIBUTING.md` or deliberately staying inline — checked section by section against
`CLAUDE.md` as it stands before ticket 05 touches it, so that nothing is dropped rather than moved.
