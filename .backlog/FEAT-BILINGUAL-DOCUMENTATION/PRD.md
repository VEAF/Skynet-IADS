# FEAT-BILINGUAL-DOCUMENTATION

Publish the documentation site in French and English, French being what a visitor gets by default.

## Why

Skynet is maintained by VEAF and the Regroupement de Patrouilles, and most of the people who set up
a mission with it read French first. The site has been English-only since it was published. The two
sibling repositories already solved this: **VEAF-Mission-Creation-Tools** serves French by default
with an English twin per page, **CTLD** does the same the other way round. David's call, 2026-09-21:
*do exactly the same as VMCT* — French default, English twin, same plugin, same conventions, same
gate.

## What "the same as VMCT" means, concretely

| | VMCT | here |
|---|---|---|
| plugin | `mkdocs-static-i18n`, `docs_structure: suffix` | same |
| default locale | `fr` — the unsuffixed `X.md` **is** the French page | same |
| translation | `X.en.md` | same |
| anchors | `toc.slugify = pymdownx.slugs.slugify(case=lower)` + `attr_list`; a heading targeted by a cross-page link carries an explicit `{#id}`, **identical in both languages** | same |
| links | an English page links to `page.en.md`, a French page to `page.md` | same |
| search | `search: lang: [fr, en]` | same |
| gate | `veaf_build/docs_check.py` + a `Docs Check` workflow: broken links, dead anchors, implicit cross-page anchors, missing translations, nav orphans, dangling nav entries | ported to `build-tools/docs-check.py`, same checks |

What is *not* copied, because it is VMCT's own plumbing rather than its bilingual model: Poetry, the
external `VEAF/documentation` deployment repository, the landing page, the version stamper, and the
second repo-wide link pass (`check_repo_links`, added there after a backlog restructure broke 68
links — a VMCT incident, not ours).

## Consequences a reader will notice

- `https://veaf.github.io/Skynet-IADS/latest/setting-up/` **becomes French**. The English page
  moves to `.../latest/en/setting-up/`. Every link that exists today keeps working, it just
  switches language; Material's language selector sits in the header.
- The root `README.md` becomes bilingual **in a single file** — English first, then French, with a
  switcher at the top of each half. That is what VMCT does, and it was worth checking rather than
  assuming: the plan opened with "the README stays English and single, as in both sibling
  repositories", which was half right. Their own switcher link is broken (`#fr` matches no anchor
  in their file); ours uses an explicit `<a id>`.

## Scope

The five published pages — `index`, `setting-up`, `tactics`, `api`, `faq` — 1 197 lines, translated
in full. A reference page left in English would be a hole in the French site exactly where mission
makers spend their time.

## Tickets

| # | Ticket | Status |
|---|--------|--------|
| 01 | [Stable anchors and link hygiene](tickets/01-stable-anchors.md) | ✅ |
| 02 | [i18n plumbing and the four short pages](tickets/02-i18n-plumbing.md) | ✅ |
| 03 | [Translate the API reference](tickets/03-translate-api.md) | ✅ |
| 04 | [The documentation gate](tickets/04-docs-gate.md) | ✅ |
| 05 | [Repository instructions and changelog](tickets/05-instructions.md) | ✅ |
| 06 | [A bilingual README](tickets/06-bilingual-readme.md) | ✅ |

One branch, one pull request, one commit per ticket.
