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

**`CONTEXT.md` is cut by a different test than the review proposed.** The review wanted it reduced to
what has no home in `documentation/` — the FAQ answers what *covered* means nearly word for word, and
`setting-up` covers command centres and connection nodes, both verified. Florent refused that framing:
the published site serves a mission maker and this file serves someone reading the code, and the same
fact for two audiences is not the duplication this lot targets. He also refused the review's proposal
that the file end by pointing at the FAQ.

The test he gave instead is sharper and cuts *within* sections rather than removing them:

> A concept section says why something is the way it is, or what will surprise you. A code
> transcription lists what the code does.

The first survives a refactor. The second is wrong the moment somebody edits the function, and is a
worse copy of the code kept where the code cannot see it. Three passages failed it and are gone — the
cycle's five steps, autonomy's four conditions, and coverage as a flat 2D distance — each leaving
behind what it was for.

**Autonomy does not make an element more dangerous.** The claim survived from the compiled-artifact
analysis this file was built on, and was reintroduced during this round before Florent caught it. An
autonomous element is lit, uncoordinated and sees only its own radar: the DCS default Skynet exists
to improve on. Losing the network degrades the IADS, which is the concept.

**The code-name column is the one thing here with no other home**, and it was the part of the review's
item 2 that had nothing to do with cutting. It was lost because the question put to Florent bundled it
with the proposal he rejected. Every identifier is verified against the sources: `setPointDefence`
does not exist — it is `addPointDefence` — and connection nodes have no class at all.

`CLAUDE.md`'s table is unchanged: its row already promises "the domain, and the words the code uses
for it", a promise the file now keeps.

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
