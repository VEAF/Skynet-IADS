# CHORE-DOCS-RECENT-BEHAVIOUR

Put what 3.5.0 changed where a reader looks, and retire the original author's donation block.

## Why

David, 2026-09-21, reading the freshly published bilingual site: *"I can't find the last things we
did — last line of defense for instance."*

Measured, and he is right in a way worth naming precisely. The features **are** documented, and
only in `api.md`:

| | index | setting-up | tactics | api | faq |
|---|---|---|---|---|---|
| Last line of defense | — | — | — | yes | mentioned |
| Coverage refresh | — | — | — | yes | — |
| Setup warnings on screen | — | — | — | yes | — |

All three are **on by default** and change what an existing mission does. The API reference is a
catalogue of calls, consulted when you already know what you are looking for; someone reading
*Setting up an IADS* to understand the system never meets them. That is a discoverability defect,
not a missing page.

Checked at the same time: of the 22 public setters in the sources, 8 are undocumented and all
eight are internal (`setContacts`, `setDCSRepresentation`, `setHARMState`, …). Nothing to add.

## Also

`index.md` still carries the original author's PayPal button and his acknowledgements. The project
has changed hands. David asked for a block saying so, and thanking him.

Spearzone, Coranthia and Grimes are kept in that block rather than dropped: they are other
people's credit, and erasing them to retire a donation link is not the same request.

## Tickets

| # | Ticket | Status |
|---|--------|--------|
| 01 | [The behaviour pages carry the behaviour](tickets/01-behaviour-in-the-guide.md) | ⬜ |
| 02 | [A project taken over, not a donation link](tickets/02-handover-block.md) | ⬜ |
