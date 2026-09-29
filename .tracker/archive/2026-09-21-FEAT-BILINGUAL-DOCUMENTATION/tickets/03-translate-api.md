# 03 — Translate the API reference

**Status**: ✅ done

778 lines, 38 headings. Prose translated, code samples untouched, method and option names left
exactly as the Lua spells them. Anchors identical to `api.en.md`.

Separate from ticket 02 so that the plumbing and the bulk translation can be read, and reverted,
apart.

## Done when

`documentation/api.md` is French, `mkdocs build --strict` passes, and the gate of ticket 04 reports
nothing.
