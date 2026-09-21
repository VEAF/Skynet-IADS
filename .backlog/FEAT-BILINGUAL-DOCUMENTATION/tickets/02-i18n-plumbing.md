# 02 — i18n plumbing and the four short pages

**Status**: ✅ done

## Work

- `build-tools/docs-requirements.txt`: add `mkdocs-static-i18n`.
- `mkdocs.yml`: the `i18n` plugin, `docs_structure: suffix`, `fr` default and `en`, the French
  `nav_translations`, and `search: lang: [fr, en]`.
- `git mv documentation/X.md documentation/X.en.md` for the five pages, so the English text keeps
  its history, and repoint the links inside them to `.en.md`.
- Write the French `index.md`, `setting-up.md`, `tactics.md` and `faq.md`, anchors identical to
  their English twins.

## Done when

`mkdocs build --strict` passes, the language selector appears, `/` serves French and `/en/` serves
English.
