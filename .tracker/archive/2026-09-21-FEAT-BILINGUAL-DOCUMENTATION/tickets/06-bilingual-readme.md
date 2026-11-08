# 06 — A bilingual README

**Status**: ✅ done

VMCT's `README.md` carries both languages in one file: English, a rule, then the whole thing again
in French, with a switcher at the top of each half. Same shape here — with a working switcher,
theirs points at `#fr` and no anchor by that name exists in their file.

Found while writing it: the README's link to the setup page,
`https://veaf.github.io/Skynet-IADS/setting-up/`, is a **404 and always has been**. `mike`
publishes every page under its version, so only `/latest/setting-up/` resolves. Measured, not
assumed — the four candidate URLs were requested.

## Done when

Both halves read on GitHub, the two switcher links land on each other, and every documentation URL
in the file returns 200.
