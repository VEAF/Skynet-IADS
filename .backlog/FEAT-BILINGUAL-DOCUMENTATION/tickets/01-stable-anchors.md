# 01 — Stable anchors and link hygiene

**Status**: ⬜ ready

## Problem

Eleven cross-page and same-page links target anchors mkdocs derives from English headings —
`api.md#last-line-of-defense`, `tactics.md#point-defence`, `index.md#quick-start`… Translate the
heading and the anchor changes with it, so every one of those links breaks on the French side.

## Work

- Add `attr_list` and `toc: { slugify: pymdownx.slugs.slugify(case=lower), permalink: true }` to
  `mkdocs.yml`, as VMCT has them. No title here is non-ASCII, so no anchor moves.
- On every heading that is the target of a link, declare the anchor explicitly with the value it
  already has: `## Point defence { #point-defence }`. Reusing the current value is what keeps the
  links published elsewhere — forum posts, Discord — alive.

## Done when

The five English pages carry explicit anchors on every linked heading, the site builds, and no
published URL has moved.
