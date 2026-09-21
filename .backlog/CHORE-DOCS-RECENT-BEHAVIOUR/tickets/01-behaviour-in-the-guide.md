# 01 — The behaviour pages carry the behaviour

**Status**: ⬜ ready

`setting-up.md` describes the elements of an IADS — sites, radars, power, nodes, AWACS, ships. It
says nothing about three behaviours that are on by default:

- **the last line of defense**, which wakes a dark site on proximity alone;
- **the coverage refresh**, which is why an AWACS flying home frees the batteries behind it;
- **the setup warnings**, which is how a mistyped group name announces itself on screen.

Each gets a short section there, explaining what happens and why, and pointing at `api.md` for the
knobs — the reference keeps owning the call signatures. Explicit anchors, identical in both
languages, and both twins in the same commit.

## Done when

A reader of *Setting up an IADS* meets all three, `docs-check` is clean, and the strict build
passes.
