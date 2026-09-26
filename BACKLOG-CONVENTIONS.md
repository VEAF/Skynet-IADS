# Backlog conventions

How work is tracked in this repository. The live list of lots is [`.backlog/INDEX.md`](.backlog/INDEX.md);
this file is the rules behind it.

## Shape

```
BACKLOG-CONVENTIONS.md       these rules
.backlog/
  INDEX.md                   the lots, with their status. Maintained by hand
  IDEAS.md                   noticed but not committed to
  <LOT-ID>/
    PRD.md                   why, what was decided, and why it was decided that way
    tickets/
      01-<slug>.md           one deliverable each
  archive/
    <LOT-ID>.md              a merged or wontfix lot, compacted into one file
```

`<LOT-ID>` is uppercase and kebab-cased, prefixed by intent: `FEAT-`, `FIX-`, `CHORE-`,
`INVESTIGATE-`, `REFACTOR-`.

## When a lot is required

Not every change needs one. A lot exists to hold reasoning, and work with no reasoning to hold does
not need the apparatus.

**Open a lot when either is true:**

- the work has **more than one deliverable** — more than one change that could be reviewed and
  shipped on its own. The steps of a single change, such as its test, its fix and its changelog
  entry, are one deliverable;
- it makes a **decision worth recording**, one somebody will later ask *why* about: a measurement
  that settles a question, a design refused, a trade-off taken knowingly. Choosing between two ways
  to write the same fix is not one. Recording such decisions is what a PRD is for, and six months
  later it is the only thing anyone wants back.

**Otherwise a branch and a pull request are enough**, however many commits it takes. A typo, a dead
link, a one-line guard, a bug fix that needed two or three iterations after testing: writing a PRD
for it produces a record nobody will ever read and delays the fix.

If you find halfway through that the work has grown a second deliverable or a real decision, open the
lot then. That is the normal way lots are born, and it is cheaper than guessing at the outset.

## What goes where

**The PRD** carries the reasoning. Not just what to build — what was measured, what was rejected and
why, and which trade-offs were taken knowingly. A PRD that only lists tasks is worthless six months
later, when the question is no longer *what* but *why like this*.

Write the measurements down with their limits. "Measured on the log: 7 933 dark status lines, zero
ever lit" is useful; so is "the reporter's own close pass is not in this log, so the mechanism is
proven from the code, not from this measurement". A reader who cannot tell what was proven from what
was inferred will redo the work.

**A ticket** is one deliverable, with its own definition of done. It says what to build and what must
be true when it is finished — including the test that would catch the regression nobody would notice
in play.

**The index** carries one line per lot, describing it well enough that nobody has to open the file to
know whether it is theirs.

## The three trackers

| | |
|---|---|
| **GitHub issues** | Reports arriving from outside. A report that becomes work goes through the test above like anything else — a lot if it earns one, otherwise a branch and a pull request. The issue is closed referencing whichever it became. |
| **`.backlog/IDEAS.md`** | Ideas and things noticed in passing. An idea is a thought; a lot is committed work. Promoting one to the other is the normal path. |
| **`.backlog/`** | What is planned, in progress or done. |

Never create a separate todo file. In-session task lists stay in the session.

## Status

One vocabulary, used identically in `.backlog/INDEX.md` and at the top of every `PRD.md` and ticket.
The status in the index and the status in the PRD must agree — a lot whose two statuses disagree is a
lot nobody trusts.

| | Status | Meaning |
|---|---|---|
| ⬜ | ready | Specified and unblocked. An agent may pick it up and start. |
| 🔄 | in-progress | Someone is on it. Say who, or which branch. |
| 🧑 | waiting-human | Blocked on a person: a decision, a test in DCS, a credential, an answer. **Say what is expected and from whom** — a waiting-human with no named expectation is a lot nobody will ever unblock. |
| ⏸ | paused | Deliberately parked. Unlike 🧑, nothing is expected of anyone; unlike ⬜, nobody should pick it up. Say what would restart it. |
| ✅ | done | The work is committed. For a ticket that is the end of it. |
| 🔀 | merged | **Lots only.** The pull request has landed on `develop`. Next stop is the archive. |
| 🚫 | wontfix | Decided against. **Keep the reasoning** — a wontfix without a reason gets reopened. |

A ticket never reaches 🔀: it is finished when its commit lands on the branch, and it is the lot that
is merged. A lot reaches ✅ when every one of its tickets has, which is the moment its pull request
is worth opening — the work exists and is not yet in `develop`.

### The distinction that matters

⬜ and ⏸ look alike and are opposites. `ready` invites an agent to start; `paused` tells it not to. A
lot waiting on something that has not shipped yet is **paused**, not ready — and its note should say
what it is waiting for, so nobody has to reconstruct it.

### Blocking

When a lot must not be started — because a decision belongs to someone else, or because starting
would pre-empt a conversation — write the block at the **top of the PRD and of every ticket**, in a
blockquote, naming who is expected to act. A status glyph alone is too easy to skim past, and someone
who opens a single ticket never sees the PRD.

## Archiving

A lot merged or marked wontfix more than a few days ago is compacted into
`.backlog/archive/<LOT-ID>.md`: the defect or the goal, the decisions **and why the alternatives were
refused**, the figures that were measured, the pull requests, and the notes that say *do not reopen
this without a new reason*. What it drops is the ticket-by-ticket working material and the process
scaffolding — all still in git history, and most of it restated in `CHANGELOG.md` and in the commit
messages.
