# 06 — What CONTEXT.md is for, and what survives

**Status**: 🔄 in-progress — amended and reviewed, pending commit

## Problem

Much of `CONTEXT.md` came from an agent-driven analysis of the **compiled** Skynet artifact as
vendored in the VEAF mission tools repository — not from these sources. That explains both of its
faults at once: the VEAF-specific framing, and a set of claims inferred about code the analysis did
not have in front of it.

It also gave the file no stopping condition. Written as a catalogue of technical peculiarities, it
can only grow: any program has an unbounded supply of them, and each one added leaves the code
exactly as unclear as it was.

Three errors, found 2026-09-24 — and each is the signature of reading a concatenated blob rather
than the sources:

- **`goDark()` and HARM is stated backwards.** The file says it *refuses* while the site is hiding
  from an anti-radiation missile. In the code `harmSilenceID ~= nil` is a reason to go dark that
  **overrides** the tracking and missiles-in-flight refusals — `and` binds tighter than `or`.
  Defending a HARM forces the shutdown; it does not prevent it.
- **"Autonomous means abandoned, not independent" inverts the meaning.** `goAutonomous()` branches on
  `autonomousBehaviour`, whose default `AUTONOMOUS_STATE_DCS_AI` calls `goLive()`. The site runs on
  its own radar under its own control — independence, which is what the word already says. The file
  also never mentions that the behaviour is a two-mode setting.
- **"Acting as EW is a role, not a type" explains a phrase that explains itself.** "Acting as"
  announces a role. There is no trap here.

## The criterion

> **If a fact has a home in the code, it belongs there.** `CONTEXT.md` carries only what has nowhere
> else to live.

The file keeps what defines the domain — the premise, what Skynet is and where its boundary lies,
and the vocabulary the codebase uses. What leaves is the technical peculiarity that has a home:

- **A property of an interaction between parts.** *A dark site is never asked what it sees* belongs
  to `evaluateContacts` × `goDark`; neither function can state it honestly, because each sees half.
- **What is deliberately absent.** No file can carry a fact about what is not there.
- **Intent that forbids an obvious fix.** *Sites stay dark because that is what makes them
  survivable.* Without it the blindness above reads as a bug, and someone repairs it.

The rule inverts the file's growth. Anything a reader wants to add is first a question about whether
the code can say it, so the file shrinks as the code improves — the same direction as the
`.luacheckrc` ratchet.

**It is not vendor-neutral today, and that is the same defect in another form.** The file states that
Skynet does not know about VEAF, which is itself VEAF-specific knowledge, and then names
`veafSkynetIadsHelper.lua` and VEAF's helper as examples. The useful fact — enrolment, mission
configuration and radio menus belong to the consumer — needs no consumer named and is stronger
without one. `skynet-iads-source/skynet-iads.lua:94` carries the same bias into the shipped
artifact; that is a source change and out of this lot's scope, recorded separately.

## Work

Review Florent's amended file in two passes, kept separate so an amendment of his is never confused
with a finding of mine.

- **The diff**, claim by claim, against `skynet-iads-source/`. Anything unconfirmed is reported as
  unverified rather than accepted; anything asserting *DCS* behaviour needs the datamine or a real
  log, never inference.
- **Suspect inference over incident.** The file's errors are not things someone got bitten by; they
  are claims made without the sources at hand — a misread operator precedence, a branch not noticed,
  a relationship that spans two files. Read the function, not the sentence about the function.
- **The rest of the file**, against the criterion — including what was kept. Reviewing only the diff
  would leave the untouched half unexamined, and the untouched half is where all three known errors
  were.

Each surviving section answers *where else could this live?* with nothing. Anything displaced is
recorded as a to-do for the code rather than deleted silently.

## Done when

The vocabulary is correct — not merely that the amendments were applied. Every claim matches what
the sources do; no technical peculiarity remains that a comment in the code could carry, and each one
displaced is recorded rather than dropped; anything left unverified reads as unverified; and no
consumer is named.
