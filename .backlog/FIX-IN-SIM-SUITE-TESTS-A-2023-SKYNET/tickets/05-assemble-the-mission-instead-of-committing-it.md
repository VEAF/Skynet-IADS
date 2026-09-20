# 05 — Assemble the mission instead of committing a copy of the code

Status: ✅ done — 2026-09-20, bar the DCS pass

David's idea, 2026-09-20, after reading what tickets 01 and 04 cost to keep working: *"ça serait
encore mieux d'avoir un script qui construit la mission de démo avec le code existant dans les
sources"*.

He is right, and it removes a problem rather than arbitrating it.

## What it replaces

Ticket 01 put the current deliverable into both archives and added a check that compares the
committed copy against a fresh build. That works, and it has a standing cost: **every pull request
touching `skynet-iads-source/` starts red** until somebody rebuilds, re-syncs and commits two 230 KB
binaries. In a project whose whole subject is that Lua, that is almost every pull request, and the
diffs get a pair of unreadable blobs each time.

The alternative was to compare only the version number — cheap, but it lets the copy age for months
between releases, which is the same defect at a smaller scale.

**Assembling the mission makes the question disappear.** There is no committed copy to keep in step,
so nothing to compare, nothing to remember, and no binary in the diff.

## What was built

- **The committed archives hold a placeholder for every script.** Valid Lua, marked with
  `--SKYNET-PLACEHOLDER`, explaining in a comment what the file is not — and calling `env.error` so
  that a mission opened unbuilt says so on screen rather than running nothing. Only the first
  script the mission loads raises the popup; ten would say it no better.
- **`miz-suite.py build`** assembles the playable missions into `build/missions/`, git-ignored, by
  putting the real files in. It needs the deliverable built first, because that is generated too.
- **`miz-suite.py stub`** puts the placeholders back — run when a suite is added to an archive, and
  once to convert the archives. Day to day nothing calls it, which is the point.
- **`check` now fails if git is holding a real script**, in either direction: a copy in an archive,
  or a suite in `unit-tests/` that no trigger loads.
- `sync`, `comparable()` and the build-stamp regex are gone. They existed only to keep a committed
  copy in step with the code beside it.
- CI assembles both missions and parses the Lua in **those**, not in the placeholders.

The committed archives shrank from 142 KB to 55 KB and from 139 KB to 25 KB — what is left is the
mission: terrain, units, triggers, wiring. That changes when the mission changes, which is rare.

## Watch out for

**The procedure for a DCS pass changed**, and it is now two commands rather than a copy:

```
pwsh -File build-tools/build-compiled-script.ps1
python build-tools/miz-suite.py build
```

then copy `build/missions/<name>.miz` into the DCS `Missions` folder under `Saved Games`.

**The committed `.miz` is no longer playable on its own.** Opening it directly gives the placeholder
message. That is deliberate — the alternative is what this lot exists to fix — but it will surprise
anyone who has opened one before, which is why the message names the command.

## Definition of done

- Both committed archives hold placeholders, and `check` fails if one holds a script. ✅
- `build` assembles the playable missions, and CI proves it can on every pull request. ✅
- The tool, `CLAUDE.md` and `test/lua/README.md` describe assembling, not refreshing. ✅
- ⬜ **Pending the DCS pass**: an assembled mission has not been loaded in DCS yet. That is the one
  thing CI cannot answer, and the one thing this ticket changes about what DCS receives.
