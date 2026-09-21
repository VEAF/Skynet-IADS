# Issue tracker

Lots, PRDs and tickets are markdown files in the repository, not GitHub issues.

## Shape

```
.backlog/
  README.md                  index of active lots, maintained by hand
  <LOT-ID>/
    PRD.md                   why, what was decided, and why it was decided that way
    tickets/
      01-<slug>.md           one deliverable each
  archive/
    <LOT-ID>.md              a closed lot, compacted into one file
```

`<LOT-ID>` is uppercase and kebab-cased, prefixed by intent: `FEAT-`, `FIX-`, `CHORE-`,
`INVESTIGATE-`, `REFACTOR-`.

## What goes where

**The PRD** carries the reasoning. Not just what to build — what was measured, what was rejected and
why, and which trade-offs were taken knowingly. A PRD that only lists tasks is worthless six months
later, when the question is no longer *what* but *why like this*.

Write the measurements down with their limits. "Measured on the log: 7 933 dark status lines, zero
ever lit" is useful; so is "the reporter's own close pass is not in this log, so the mechanism is
proven from the code, not from this measurement". A reader who cannot tell what was proven from what
was inferred will redo the work.

**A ticket** is one deliverable, with its own definition of done. It says what to build and what
must be true when it is finished — including the test that would catch the regression nobody would
notice in play.

**The index** carries one line per lot, describing it well enough that nobody has to open the file
to know whether it is theirs.

## Relationship with the other trackers

| | |
|---|---|
| **GitHub issues** | Reports arriving from outside. A report that becomes work becomes a lot; the issue is then closed referencing it. |
| **`docs/evolutions.md`** | Ideas and things noticed in passing. An evolution is a thought; a lot is committed work. Promoting one to the other is the normal path. |
| **`.backlog/`** | What is planned, in progress or done. |

Never create a separate todo file. In-session task lists stay in the session.

## Status

One vocabulary, defined in `docs/agents/triage-labels.md`. The status in the index and the status in
the PRD must agree — a lot whose two statuses disagree is a lot nobody trusts.
