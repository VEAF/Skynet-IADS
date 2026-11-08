# Issue tracker: local markdown in `.tracker/`

Configuration for Pocock's skills. It maps this repository's tracker onto their vocabulary; the rules
themselves are in `CONTRIBUTING.md` and are not restated here.

- The tracker is local markdown in `.tracker/`, not `.scratch/`.
- A feature is a folder `.tracker/<type>-<slug>/`, named like its branch `<type>/<slug>`.
- Its spec is `.tracker/<type>-<slug>/spec.md`. The first line after the title is `Status: <value>`,
  one of the values `CONTRIBUTING.md` lists. Discussion is appended under `## Comments`.
- Anything else written into the folder — issues, a map — is the skills' to shape.
- Publishing a spec means committing it straight to `develop`, as `CONTRIBUTING.md` describes.
- Finished work is under `.tracker/archive/`.
