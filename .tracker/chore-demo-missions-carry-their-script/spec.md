# The demo missions carry their Skynet script

Status: open

## The problem

The demo missions under `demo-missions/` hold a placeholder where the Skynet script goes. `build-tools/miz-suite.py build` assembles playable copies into `build/missions/`, and CI checks that git holds no copy of the script. A mission downloaded from the repository does not run as it stands, and the tool that assembles it also carries the legacy in-sim suites under `unit-tests/`, which are being replaced by `test/insim/`.

## The target

- The only `.miz` files in the repository are the in-sim suite's (`test/insim/miz/`) and the demos (`demo-missions/`).
- **The demo missions are committed with their scripts**, no placeholder: a demo opened from a checkout runs.
- **`miz-demo-update.py` replaces `miz-suite.py`**: it only replaces the Skynet script embedded in each demo mission with the current build. It runs on release, so the committed demos carry the released script.
- `build/missions/` is dropped: the committed demos are updated in place.
- The documentation loses the placeholder and "never edit a `.miz` by hand" passages, and says that a release refreshes the demos' embedded script.

## What to build

- `build-tools/miz-demo-update.py`, with its tests in `test/python/`, replacing `build-tools/miz-suite.py` and `test/python/test_miz_suite.py`.
- The demo missions under `demo-missions/` committed with the current build embedded.
- The release workflow runs the update before attaching the demos.
- The `mission-archives` CI job is replaced or removed accordingly.
- `CONTRIBUTING.md`, `CLAUDE.md`, `.gitignore` and `documentation/` updated to match.

## Decided

| Decision | Turned down | Why |
|---|---|---|
| The demos are committed with the script inside | placeholders assembled on demand | a demo opened from a checkout or downloaded from GitHub runs as it is |
| The script is refreshed on release | on every build | a demo carries the released Skynet, which is what it demonstrates |

## Open

- Whether this lands before or after `test-port-unit-tests-to-insim`: `miz-suite.py` also handles the two in-sim suites under `unit-tests/`. Landing first means `miz-demo-update.py` leaves them alone until that work removes them.
- What replaces CI's check that a committed demo is not broken.

## Out of scope

- The in-sim suite's mission, which embeds no script and is handled by `test/insim/run.py`.
- Porting or removing `unit-tests/`: `test-port-unit-tests-to-insim`.
