# 02 — a floor that only goes up

Status: ✅ done — merged in [PR #21](https://github.com/VEAF/Skynet-IADS/pull/21). The floor is `build-tools/test-coverage-floor.txt`, at **70**. Proved on the branch: a commit raising it to 71 turned the job red with *"below the floor of 71% (1698 lines) — 19 lines short"*, every other check green

Ticket 01 prints a number. This one makes the build fail when the number drops.

## What to build

**A floor, recorded in one place, checked by the job.** `build-tools/report-test-coverage.lua`
gains a threshold: below it, non-zero exit and a message naming both figures.

```
test coverage: 68.91%  (floor: 70.00%) — FAIL, 26 lines short
```

Where the floor lives is a small decision with one constraint: **raising it has to be a visible,
deliberate edit in the diff.** A literal in `.luacov` — `testCoverageFloor = 70` — reads well
because the denominator policy is already there; a plain `build-tools/test-coverage-floor.txt`
reads even better in a pull request. Either is fine. A floor computed from the previous run is not:
a floor that follows the measurement is not a floor.

## Where it starts, and why not at 90

**It starts at 70**, the measured 70.22% rounded down — not at the 90 this lot aims for.

A gate set to 90 today fails every build on `develop` from the moment it lands, twenty points
short. A gate that is red before anyone has done anything wrong gets bypassed within a week, and
then it protects nothing. The floor's job is to stop a regression; the climb to 90 is the job of
tickets 03 to 06, and each of them raises the floor by what it actually bought.

The steps it should pass through, if the tickets land in order: **70 → 83 → 90 → 94**.

This is the shape `.luacheckrc` already uses in this repository, and its comment says why: *it
exists to erode, never to grow*. Same rule here, in the other direction — the floor rises and never
falls. Lowering it is a decision someone takes in the open, in a diff, with a reason in the commit
message.

## The raise, written into the ticket that earns it

Every ticket of this lot ends the same way: run the measurement, raise the floor to the new figure
rounded down, in the same pull request as the tests that earned it. A pull request that adds tests
and leaves the floor where it was has not finished.

## Watch out for

- **A drop is not always a regression in the tests.** Deleting covered code, or adding a whole new
  uncovered file, moves the number too. The failure message should give the per-file summary, not
  just the total, so the cause is visible without re-running.
- The job must fail on the threshold, not on a missing report. A `luacov` that installed badly and
  produced nothing must be loud and distinct from 68%.

## Definition of done

- A pull request that removes test coverage fails CI, with a message naming the floor and the
  measured value.
- The floor is 70, recorded in one place, and raising it is one line in a diff.
- A run producing no report fails with a different message from a run below the floor.
