# 02 — A backlog, a changelog and agent instructions

Status: ⬜ ready

## Backlog

`.backlog/` exists as of this lot, with the same shape as VEAF-Mission-Creation-Tools and CTLD:
`<LOT-ID>/PRD.md` plus one file per ticket under `tickets/`, an index in `.backlog/README.md`
maintained by hand, and `archive/<LOT-ID>.md` for lots closed more than a few days.

What remains: agree that it is the tracker. Issues stay for reports coming from outside — like issue
#3 — and a report that turns into work becomes a lot. `docs/evolutions.md` is Flogas's idea tracker
and keeps that role; the difference is that a lot is committed work and an evolution is not.

## Changelog

`CHANGELOG.md`, Keep-a-Changelog shape, an `[Unreleased]` section that every PR appends to at the
**end** — appending conflicts far less than prepending when two PRs land the same day, which is the
convention VMCT settled on after measuring it.

It matters more here than in a normal project: the consumer of this repository is another
repository, which vendors the built artifact. Today nothing tells VMCT what changed between two
copies, and the last vendoring was nine days and a month of work behind without anyone noticing.

## Agent instructions

A `CLAUDE.md` at the root, short, saying what an agent needs and cannot guess:

- sources live in `skynet-iads-source/`, the compiled file is a **build artifact** — never edit it;
- tests go in `test/lua/`, run with `lua5.1 test/lua/run.lua`; `unit-tests/` is the legacy in-sim
  suite being migrated;
- gitflow, per [ticket 01](01-adopt-gitflow.md);
- the backlog is the tracker, the changelog is mandatory;
- VEAF maintains this project; do not open pull requests against walder or the Regroupement.

Then whatever agent skills earn their place — VMCT keeps them under `docs/agents/`, one file per
subject, referenced from `CLAUDE.md`. Start with none, and add the first one when a session has had
to rediscover something twice.

## Definition of done

- `.backlog/README.md` lists every active lot with its status.
- `CHANGELOG.md` exists with an `[Unreleased]` section, and the contributing guide says to update it.
- `CLAUDE.md` exists and is accurate — an agent following it does not edit the artifact by mistake.
