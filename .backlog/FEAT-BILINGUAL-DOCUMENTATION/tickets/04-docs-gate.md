# 04 — The documentation gate

**Status**: ⬜ ready

## Problem

Doubling the number of pages doubles the ways the site can rot quietly, and the docs workflow only
runs **after** a merge — a dangling nav entry or a page whose translation was never written reaches
the published site before anyone sees it.

## Work

Port VMCT's `veaf_build/docs_check.py` to `build-tools/docs-check.py`, stdlib-only, keeping the
checks that apply here:

| check | what it catches |
|---|---|
| `broken_links` | a relative link whose target file does not exist |
| `dead_anchors` | an anchor no heading provides, checked on the page the reader actually lands on |
| `implicit_anchors` | a cross-page link relying on a generated anchor — breaks on the next reword, and differs between languages |
| `wrong_language_links` | an English page sending its reader to the French twin |
| `missing_translations` | a French page with no `.en.md` |
| `nav_orphans` / `nav_dangling` | a page in no menu, a menu entry with no page |

Two behaviours VMCT got wrong first and fixed — keep them: an explicit `{#id}` **replaces** the
generated slug rather than adding to it, and relative links are language-agnostic (the plugin
rewrites them) while anchors are not.

Plus `.github/workflows/docs-check.yml` running it on pull requests and pushes, and unit tests in
`test/python/`.

## Done when

`python build-tools/docs-check.py` exits 0 on a clean tree, non-zero on each defect above, and the
workflow runs on a pull request touching `documentation/`.
