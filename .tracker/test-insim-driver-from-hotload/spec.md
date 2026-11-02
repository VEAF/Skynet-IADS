# The in-sim suite runs on dcs-hotload's own driver

Status: done

## The problem

The in-sim engine's driver core (`test/insim/engine/`: `mailbox.py`, `luadata.py`, `driver.py`) was
written to leave this repository. dcs-hotload 3.0.0 now ships it as its client, `bin/hotload.py`. It
reads the mission's state from hotload's heartbeat, `user-outbox/_heartbeat.lua`, instead of the probe
command this suite sends every few seconds and answers itself (`insim.lua`'s `status()`). Two copies of
the core would drift, and the probe costs a command round trip and files to clear on every look.

## What to build

- **Vendor dcs-hotload 3.0.0** in `test/insim/dcs-hotload/`: its release's shipped files as they are
  (`bin/hotload.sh` goes, `bin/hotload.py` comes). The suite's own folders (`user-lib/`, `user-f10/`,
  the mailbox) are untouched.
- **The engine imports `hotload`** from the vendored `bin/`, put on `sys.path` by `engine/__init__.py`.
  `suite.py` and `verify.py` use its `parse`, `dump` and `LuaDataError`. `run-insim.py` uses its
  `Mailbox`.
- **`engine/driver.py` becomes an adapter** over `hotload.Driver`, adding what the test layer reads:
  - `run(key, prefix, code, timeout)`: the core's journalled run, with no silence cap: the suite
    never concludes anything from silence;
  - `entry(key)`: the key's journal lines merged, so `sent_at`, written on the `sent` line, is there
    once the key has `ended`;
  - `wait_for_mission(hint)`: waits until the heartbeat advances, says `hint` once while it does not,
    returns the heartbeat (`mission`, `time`);
  - at start, removes the `stop-*` commands a killed driver left.
- **The core's `lost` is the suite's `crashed`**: `suite.py` reads `lost` where it read `crashed`. The
  verdict and its messages are unchanged.
- **The probe goes**: `insim.lua`'s `status()` and its test, the `probe-` names reserved by
  `check_name`, and `PROBE_CODE` in `run-insim.py`.
- `mailbox.py`, `luadata.py`, `test_insim_mailbox.py` and `test_insim_luadata.py` are removed: hotload
  carries that code and its tests. `test_insim_driver.py` tests the adapter, against a fake mission that
  plays hotload on real files.

## Decisions

| Decision | Turned down | Why |
|---|---|---|
| A thin adapter in `engine/driver.py` | `suite.py` calling `hotload.Driver` directly | `entry` and `wait_for_mission` are what the test layer needs, not the core; the suite and its tests keep their shape |
| `lost` mapped to `crashed` in `suite.py` | renaming the verdict | the verdict is what a contributor reads; the core knows only that the run is gone |
| The vendored folder's path put on `sys.path` by `engine/__init__.py` | a copy of `hotload.py` in `engine/` | the vendored release stays the one copy, unedited |

## Out of scope

- Any change to `mission.py`, the scenarios, or the Skynet layer.
- A silence cap for the suite.
