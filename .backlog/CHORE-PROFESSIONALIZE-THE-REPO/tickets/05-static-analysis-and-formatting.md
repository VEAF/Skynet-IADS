# 05 — Static analysis and formatting

Status: ⬜ ready

Neither exists here. Both other VEAF repositories gate on them, for the same reason in all three:
this is Lua 5.1, with no compiler and no type checker, so a typo in a rarely-taken branch ships in
silence. The `syknet` → `skynet` sweep of `1cd651e` is the kind of thing a linter finds for free.

## What to add

- **`luacheck`**, with a `.luacheckrc` declaring the DCS globals (`env`, `timer`, `world`,
  `coalition`, `Unit`, `Group`, `Controller`, `AI`, `trigger`, `missionCommands`, `Weapon`,
  `Object`…) and the project's own globals. Expect a large first run: adopt the ratchet used on the
  VMCT side — exclusions are technical debt to erode lot by lot, never to grow, and no new entry is
  ever added.
- **A formatter**, `stylua`, with its configuration committed. Run it once over
  `skynet-iads-source/` and `test/lua/` in a formatting-only commit, so that commit's diff is pure
  noise and every later diff is pure signal.
- Both in CI, as their own job, failing the build.

## Scope

`skynet-iads-source/` and `test/lua/` only. Not `unit-tests/`, which is on its way out
([ticket 04](04-finish-migrating-the-legacy-suites.md)), and not the built artifact, which is
generated. Getting the scope wrong here is a known trap: on the VMCT side, pointing the formatter at
a parent directory pulled in generated files and produced a diff nobody could read.

## Definition of done

- `.luacheckrc` and the formatter configuration committed, both scoped as above.
- A formatting-only commit, separate from everything else.
- CI fails on a lint error or an unformatted file.
- No exclusion added that the first run did not already require.
