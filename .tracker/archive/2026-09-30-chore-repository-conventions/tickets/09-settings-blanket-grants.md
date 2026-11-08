# 09 — The shipped settings stop pre-approving every shell command

**Status**: ✅ done

## Problem

`.claude/settings.json` is checked in, so `Bash(*)` and `PowerShell(*)` pre-approved every shell
command for **every contributor** who opens this repository in Claude Code, not only the maintainer
who added them.

This is the same objection that removed the `Bash` section from `CLAUDE.md` in ticket 08, except that
this file is the one that actually grants anything: instruction files are advisory context,
`settings.json` is enforcement.

## Work

Remove both blanket grants. Keep the two `WebFetch` domains — narrow, read-only, and the DCS wiki is
what the instruction to verify behaviour against a real source points at. A project-scoped domain
allowlist is what a checked-in settings file is for.

`.claude/settings.local.json` is git-ignored and is not touched.

## Done when

No blanket grant ships. Work is not blocked by the removal: in auto mode a classifier reviews actions
regardless of this file, and outside it a contributor is asked about a command they never
pre-approved, which is the intended behaviour.
