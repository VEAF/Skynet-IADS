# 05 — CLAUDE.md keeps what prevents damage

**Status**: ⬜ ready

## Problem

`CLAUDE.md` is 231 lines and is loaded into every agent context, every session, whether or not any of
it is relevant. Most of it is reference — the build command, the bilingual rules, the coverage floor,
`miz-suite.py` — which ticket 04 has now put in `CONTRIBUTING.md`.

## Work

Reduce `CLAUDE.md` to what the governing decision keeps inline: anything an agent can get wrong
*before* it would have any reason to open the contributor guide.

Stays: never edit the compiled deliverable; never open a pull request against the upstream archives;
surgical mode, simplicity, zero assumptions; the hard parts of git flow (never commit to `develop` or
`master`, one pull request per lot, one commit per ticket, the `.backlog/` exception); English
everywhere; bash authorization; read `CONTEXT.md` before touching the radar element hierarchy; the
two skills; the ordered default workflow, which is the index that makes delegation work.

**Three commands stay, as bare lines**: `pwsh -File build-tools/build-compiled-script.ps1`,
`lua5.1 test/lua/run.lua`, `build-tools/lint.sh`. They cannot be guessed, they are needed on almost
every task, and an agent that cannot find them greps the repository or invents one. Their
explanations do not stay; those are in `CONTRIBUTING.md`. See the PRD on why repeating a command is
not the duplication this lot exists to end.

**The test command needs its Windows form beside it**, because this is a Windows-first project and
`lua5.1` is not on PATH there:

```
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
```

Measured, 2026-09-24: an agent given only `lua5.1 test/lua/run.lua` on this checkout gets
`command not found` and concludes no interpreter is installed — while `test/lua/README.md` has
carried the working invocation, the PowerShell call operator and the `cmd.exe` variant all along.
The command existed in exactly one deep file and that was the same as not existing. The full
explanation stays in `test/lua/README.md`; only the invocation is repeated.

The Windows `lint.sh` quirk stays too — a developer environment quirk, and the reason that script
exists at all.

Goes, with a pointer row each: the build's *explanation*, static analysis, the bilingual
documentation rules, the test suites and the coverage floor, the mission archives, the changelog
mechanics.

**The pointer table is task-indexed, not a single "read CONTRIBUTING.md first".** That version is
easy to skim and gives no reason to comply. Rows read *about to change a source file →
CONTRIBUTING.md § Building, § Test first*, so an agent scanning for its current task meets the
instruction.

**Cut every passage that argues a rule from the backlog.** Five, all in the surviving text:

- the two dangling pointers, "see ticket 06 / ticket 03 in `CHORE-PROFESSIONALIZE-THE-REPO`";
- "David's call, 2026-09-19" on the `.backlog/` exception;
- "David's call, 2026-09-19, after `CHORE-PROFESSIONALIZE-THE-REPO` reached nine pull requests and
  `CHORE-TEST-COVERAGE-FLOOR` five, none of which he had been asked about";
- "`FEAT-LAST-LINE-OF-DEFENSE` shipped the proximity wake-up and the coverage rebuild as a single
  commit (`0ebbc01`) … Flogas caught it".

Keep the reason, drop the citation. "Two subjects in one commit cannot be read, reverted or bisected
apart" is general and stays; the lot that proved it goes. Roughly half the git-flow section is
citation, which is a large part of this ticket's saving.

Naming `.backlog/` as the tracker, and pointing at `BACKLOG-CONVENTIONS.md` for its rules, is not
what this forbids — see the PRD.

Fix the one remaining defect in the surviving text: the garbled sentence at the current line 130,
"`demo-missions/` archives are attached to it" — "it" has no referent and means *attached to a
release*.

## Done when

Every line left in `CLAUDE.md` answers *would removing this cause a mistake?* with yes; every section
removed has a row in the pointer table naming where it went; the three commands are runnable straight
from the file; `grep -n "CHORE-\|FEAT-\|FIX-\|David's call\|Flogas" CLAUDE.md` returns nothing; and a
reader who follows only `CLAUDE.md` still cannot edit the deliverable, commit to `develop`, or open a
pull request upstream by accident.

No line count is a target. The file will land where those tests put it.
