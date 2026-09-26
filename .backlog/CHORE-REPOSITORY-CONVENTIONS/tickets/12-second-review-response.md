# 12 — Second review response

**Status**: ✅ done

## Problem

The first review response was reviewed again, before the pull request was opened. Most of it held.
What follows is what it left open, and one thing the first review had *caused*: its item 7 asked for
the conditions under which an element goes autonomous, and they came back transcribed from the code
as a list — with two mistakes in the transcription.

## What it found

**The four decisions were recorded nowhere.** Ticket 11 said they were in the PRD. They were in the
commit messages and nothing else, so the next compaction would have lost them. The PRD now has a
section of its own for them, and the section on duplication — which still described the policy from
before the review — names the bare copy of the git rules in `CLAUDE.md` as a second allowed
duplication, says why, and states the drift it accepts.

**Four wrong claims in `CONTEXT.md`.** The autonomy list pointed at the wrong bullet as the expected
case, and attributed to an EWR a condition that belongs to a SAM site acting as EW — said correctly,
it names the case the old wording buried: a site can be cut off with every radar around it intact.
The vocabulary called an EWR "permanently lit" four lines below a section saying Skynet takes an EWR
dark to evade a HARM, and described a contact by its fields rather than by what it is.

**A new generated-anchor link, added while fixing the old one.** `CONTRIBUTING.md` pointed at
`README.md#maintenance`, and that file has two `## Maintenance` headings, English and French. The
English one carries an explicit anchor now.

**Issues and lots contradicted each other.** The tracker said a report that becomes work becomes a
lot, which the new threshold had just made untrue.

**Two small ones**: the release skill said a tag takes the shape `vX.Y.Z` while the same file
describes `-rc1` pre-releases; and the archiving paragraph ran past the file's width.

## Decisions

**`documentation/` does not count as a second home for `CONTEXT.md`'s material.** The review proposed
cutting the file to roughly 40 lines, on the grounds that the FAQ already answers what *covered*
means and `setting-up` covers command centres and connection nodes — both verified, and the FAQ
answer is nearly word for word. Florent's call: the published site serves a mission maker and this
file serves someone reading the code, and the same fact explained for two audiences is not the
duplication this lot targets. The sections stay; only the wrong claims were fixed.

**No rule names a consumer.** The reason behind the changelog rule was one repository and its
vendoring habits, in three files. Florent's call: remove it from all of them, Skynet has no consumer
of its own. The reason survives in general form, which covers every consumer rather than one.

## Not done, and why

The review's item 3 asked for what left `CONTEXT.md` to be recorded as owed to the code. Nothing
left it, so there is nothing to record. The existing `.backlog/IDEAS.md` entry covering the two facts
displaced in ticket 06 is unaffected.

## Done when

Every item is answered or declined in writing, and the PRD carries the decisions rather than the
commit messages alone.
