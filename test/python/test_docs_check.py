"""Tests for build-tools/docs-check.py, the bilingual documentation gate.

Run from anywhere:

    python -m unittest discover -s test/python

A gate that finds nothing is indistinguishable from a gate that checks nothing, and this one spends
most of its life reporting zero. So each defect kind gets a tree that contains exactly that defect
and nothing else, and the clean tree at the end proves the gate is not simply silent.

Two behaviours are worth the fixtures they cost, because VMCT — where this code comes from — got
both wrong before it got them right, and each mistake made the gate pass while the published site
404ed:

- an explicit `{#anchor}` **replaces** the generated slug rather than adding to it;
- an anchor is resolved against the page the reader *lands on*, which from an English page is the
  English twin.
"""

import importlib.util
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_spec = importlib.util.spec_from_file_location("docs_check", os.path.join(ROOT, "build-tools", "docs-check.py"))
dc = importlib.util.module_from_spec(_spec)
# Registered before it runs: `@dataclass` resolves annotations through `sys.modules[__module__]`,
# and a module loaded by path alone is not there yet — the decorator dies on a None lookup.
sys.modules["docs_check"] = dc
_spec.loader.exec_module(dc)


def _tree(tmp: Path, pages: dict[str, str], nav: list[str]) -> tuple[Path, Path]:
    """Write *pages* under a docs dir and a mkdocs.yml whose nav lists *nav*.

    Args:
        tmp: Directory to build the fixture in.
        pages: Page path relative to the docs dir -> markdown body.
        nav: Page paths to list in the nav, in order.

    Returns:
        `(doc_dir, mkdocs_yml)`, ready for `check_docs`.
    """
    doc_dir = tmp / "documentation"
    doc_dir.mkdir(parents=True, exist_ok=True)
    for name, body in pages.items():
        path = doc_dir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")
    entries = "\n".join(f"  - Page {i}: {target}" for i, target in enumerate(nav))
    mkdocs = tmp / "mkdocs.yml"
    mkdocs.write_text(f"site_name: Test\n\nnav:\n{entries}\n", encoding="utf-8")
    return doc_dir, mkdocs


#: The smallest tree the gate considers clean: one page, its twin, both in the nav.
CLEAN = {
    "index.md": "# Accueil\n\n## Section {#section}\n\nVoir [la section](#section).\n",
    "index.en.md": "# Home\n\n## Section {#section}\n\nSee [the section](#section).\n",
}


class SlugifyTest(unittest.TestCase):
    """The slug has to match what pymdownx produces, or every check built on it drifts."""

    def test_keeps_accents(self):
        # An ASCII-folding slugifier would say `rfrence-de-lapi` and report every French anchor as
        # broken.
        self.assertEqual(dc.slugify("Référence de l'API"), "référence-de-lapi")

    def test_keeps_underscores(self):
        self.assertEqual(
            dc.slugify("Connecting Skynet to the MOOSE AI_A2A_DISPATCHER"),
            "connecting-skynet-to-the-moose-ai_a2a_dispatcher",
        )

    def test_drops_code_markers_and_punctuation(self):
        self.assertEqual(dc.slugify("Which SAM systems can engage HARMS?"), "which-sam-systems-can-engage-harms")
        self.assertEqual(dc.slugify("The `build` step"), "the-build-step")

    def test_ignores_a_trailing_explicit_anchor(self):
        self.assertEqual(dc.slugify("Point defence {#point-defence}"), "point-defence")

    def test_keeps_the_dash_a_french_space_before_a_question_mark_leaves(self):
        # pymdownx does not strip, so the space French puts before `?` becomes a trailing dash and
        # the id the site serves ends with one. Stripping it disagreed with the site on 8 of this
        # repository's 126 generated anchors — and the wrong way round: a link copied from the
        # page's own permalink was reported dead, while the id that 404s was accepted.
        self.assertEqual(dc.slugify("Y a-t-il des bogues connus ?"), "y-a-t-il-des-bogues-connus-")
        self.assertEqual(dc.slugify("Are there any known bugs?"), "are-there-any-known-bugs")

    @unittest.skipUnless(importlib.util.find_spec("markdown"), "markdown/pymdown-extensions not installed")
    def test_every_anchor_matches_the_id_the_rendered_page_carries(self):
        # The assertion that cannot drift, and it took two tries to write. Comparing `slugify` to
        # `pymdownx.slugs.slugify` looks like the right check and is not: mkdocs hands that
        # function the **rendered** heading, so feeding it raw markdown has both sides wrong at
        # once. `## Voir la [documentation](x.md)` is served as `voir-la-documentation` while both
        # produce `voir-la-documentationindexmd`, and the test stays green.
        #
        # So render the pages and read the ids out of the HTML, which is what a reader's link has
        # to match. The skip is not a way out: this is the only test here needing anything
        # installed, the suite also runs in a job that installs nothing on purpose, and the `Docs
        # Check` workflow runs it a second time with the docs requirements in place — importing
        # the module first, so a skip everywhere cannot pass for a pass.
        anchors_in_html = self._render_and_extract_ids()
        self.assertGreater(sum(len(v) for v in anchors_in_html.values()), 100, "the documentation shrank")
        for page, served in anchors_in_html.items():
            every, _ = dc.anchors_of(page)
            self.assertEqual(every, served, f"{page.name}: what docs-check computes is not what the page serves")

    @unittest.skipUnless(importlib.util.find_spec("markdown"), "markdown/pymdown-extensions not installed")
    def test_headings_the_repository_does_not_have_yet(self):
        # The documentation happens to contain no heading with a link, a tag, a tab or a doubled
        # space in it — so rendering only the real pages would leave exactly the shapes that were
        # wrong uncovered. These are rendered the same way and compared to the same ids.
        import markdown
        from pymdownx.slugs import slugify as pymdownx_slugify

        adversarial = [
            "Voir la [documentation](index.md)",
            "Titre  avec   espaces",
            "Deux\ttabulations",
            "<span>Balise</span> HTML",
            "a ? b",
            "Portée — tiret cadratin (et parenthèses)",
            "Un **gras** et un *italique*",
            "The `build_variants` step",
        ]
        converter = markdown.Markdown(
            extensions=["toc", "attr_list", "pymdownx.highlight", "pymdownx.superfences"],
            extension_configs={"toc": {"slugify": pymdownx_slugify(case="lower"), "permalink": True}},
        )
        for title in adversarial:
            converter.reset()
            html = converter.convert(f"## {title}\n")
            served = re.findall(r'<h2[^>]*\bid="([^"]+)"', html)
            self.assertEqual([dc.slugify(title)], served, f"heading {title!r}")

    @staticmethod
    def _render_and_extract_ids() -> dict:
        """Render every documentation page and return {path: set of heading ids it serves}."""
        import markdown
        from pymdownx.slugs import slugify as pymdownx_slugify

        converter = markdown.Markdown(
            extensions=["toc", "attr_list", "pymdownx.highlight", "pymdownx.superfences"],
            extension_configs={"toc": {"slugify": pymdownx_slugify(case="lower"), "permalink": True}},
        )
        served = {}
        for page in sorted(Path(ROOT).joinpath("documentation").glob("*.md")):
            converter.reset()
            html = converter.convert(page.read_text(encoding="utf-8"))
            served[page] = set(re.findall(r'<h[1-6][^>]*\bid="([^"]+)"', html))
        return served


class AnchorsOfTest(unittest.TestCase):
    """What a page exposes, and — the subtle half — what it no longer exposes."""

    def test_an_explicit_anchor_replaces_the_generated_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            page = Path(tmp) / "page.md"
            page.write_text("# Titre\n\n## Défense rapprochée {#point-defence}\n", encoding="utf-8")
            every, explicit = dc.anchors_of(page)
            self.assertEqual(explicit, {"point-defence"})
            # `défense-rapprochée` is NOT served: attr_list replaced it. Registering it here is how
            # a dead link passes the gate.
            self.assertEqual(every, {"titre", "point-defence"})

    def test_both_attr_list_spellings(self):
        with tempfile.TemporaryDirectory() as tmp:
            page = Path(tmp) / "page.md"
            page.write_text("# Titre\n\n## Une {#compact}\n\n### Deux {: #canonical }\n", encoding="utf-8")
            _, explicit = dc.anchors_of(page)
            self.assertEqual(explicit, {"compact", "canonical"})

    def test_a_comment_in_a_code_block_is_not_a_heading(self):
        with tempfile.TemporaryDirectory() as tmp:
            page = Path(tmp) / "page.md"
            page.write_text("# Titre\n\n```bash\n# install the thing\n```\n", encoding="utf-8")
            every, _ = dc.anchors_of(page)
            self.assertEqual(every, {"titre"})


class CheckDocsTest(unittest.TestCase):
    """One tree per defect kind, each containing that defect and nothing else."""

    def _check(self, pages, nav, **kwargs):
        with tempfile.TemporaryDirectory() as tmp:
            doc_dir, mkdocs = _tree(Path(tmp), pages, nav)
            return dc.check_docs(doc_dir, mkdocs, **kwargs)

    def test_clean_tree_reports_nothing(self):
        report = self._check(CLEAN, ["index.md"])
        self.assertEqual(report.total, 0, dc.format_report(report))

    def test_broken_link(self):
        pages = dict(CLEAN)
        pages["index.md"] += "\n[missing](nowhere.md)\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(len(report.broken_links), 1)
        self.assertIn("nowhere.md", report.broken_links[0])

    def test_dead_cross_page_anchor(self):
        pages = dict(CLEAN)
        pages["other.md"] = "# Autre\n\n## Présent {#present}\n"
        pages["other.en.md"] = "# Other\n\n## Present {#present}\n"
        pages["index.md"] += "\n[absent](other.md#absent)\n"
        report = self._check(pages, ["index.md", "other.md"])
        self.assertEqual(len(report.dead_anchors), 1)
        self.assertIn("other.md", report.dead_anchors[0])

    def test_dead_same_page_anchor(self):
        pages = dict(CLEAN)
        pages["index.md"] += "\n[absent](#absent)\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(len(report.dead_anchors), 1)

    def test_implicit_cross_page_anchor(self):
        pages = dict(CLEAN)
        pages["other.md"] = "# Autre\n\n## Une section\n"
        pages["other.en.md"] = "# Other\n\n## A section\n"
        pages["index.md"] += "\n[section](other.md#une-section)\n"
        report = self._check(pages, ["index.md", "other.md"])
        # The link resolves today and breaks the moment the heading is reworded — and it has no
        # equivalent in English, where the heading reads differently.
        self.assertEqual(len(report.implicit_anchors), 1)
        self.assertEqual(report.dead_anchors, [])

    def test_implicit_same_page_anchor_is_allowed(self):
        pages = dict(CLEAN)
        pages["index.md"] += "\n## Autre section\n\n[ici](#autre-section)\n"
        pages["index.en.md"] += "\n## Other section\n\n[here](#other-section)\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(report.total, 0, dc.format_report(report))

    def test_allow_implicit_anchors_silences_only_that_kind(self):
        pages = dict(CLEAN)
        pages["other.md"] = "# Autre\n\n## Une section\n"
        pages["other.en.md"] = "# Other\n\n## A section\n"
        pages["index.md"] += "\n[section](other.md#une-section)\n[missing](nowhere.md)\n"
        report = self._check(pages, ["index.md", "other.md"], require_explicit_anchors=False)
        self.assertEqual(report.implicit_anchors, [])
        self.assertEqual(len(report.broken_links), 1)

    def test_english_page_linking_to_the_french_twin(self):
        pages = dict(CLEAN)
        pages["other.md"] = "# Autre\n"
        pages["other.en.md"] = "# Other\n"
        pages["index.en.md"] += "\n[other](other.md)\n"
        report = self._check(pages, ["index.md", "other.md"])
        self.assertEqual(len(report.wrong_language_links), 1)
        self.assertIn("other.en.md", report.wrong_language_links[0])

    def test_a_french_page_linking_to_the_english_twin(self):
        # The mirror of the case above, and not a style matter: `other.en.md` is not a page of the
        # French build, so the link leads nowhere there.
        pages = dict(CLEAN)
        pages["other.md"] = "# Autre\n"
        pages["other.en.md"] = "# Other\n"
        pages["index.md"] += "\n[other](other.en.md)\n"
        report = self._check(pages, ["index.md", "other.md"])
        self.assertEqual(len(report.broken_links), 1)
        self.assertIn("not part of the French build", report.broken_links[0])

    def test_an_unclosed_fence_swallows_the_rest_of_the_page(self):
        # mkdocs renders everything after it as code, so the gate must not read it as prose.
        pages = dict(CLEAN)
        pages["index.md"] += "\n```lua\n[exemple](nexistepas.md)\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(report.total, 0, dc.format_report(report))

    def test_a_nav_title_containing_a_colon(self):
        with tempfile.TemporaryDirectory() as tmp:
            doc_dir, mkdocs = _tree(Path(tmp), CLEAN, [])
            mkdocs.write_text('site_name: Test\n\nnav:\n  - "Home: the start": index.md\n', encoding="utf-8")
            self.assertEqual(dc.check_docs(doc_dir, mkdocs).total, 0)

    def test_a_flagged_link_is_a_language_switcher(self):
        pages = dict(CLEAN)
        pages["other.md"] = "# Autre\n"
        pages["other.en.md"] = "# Other\n"
        pages["index.en.md"] += "\n> 🇫🇷 [`other.md`](other.md)\n"
        report = self._check(pages, ["index.md", "other.md"])
        self.assertEqual(report.wrong_language_links, [])

    def test_anchor_is_resolved_against_the_english_twin(self):
        # The English page links to the French file (already reported above), but the anchor must
        # be looked up in the twin the reader lands on. Here the anchor exists only in French; the
        # English reader gets a 404, and the gate has to say so.
        pages = dict(CLEAN)
        pages["other.md"] = "# Autre\n\n## Section {#only-in-french}\n"
        pages["other.en.md"] = "# Other\n\n## Section {#section}\n"
        pages["index.en.md"] += "\n[other](other.md#only-in-french)\n"
        report = self._check(pages, ["index.md", "other.md"])
        self.assertEqual(len(report.dead_anchors), 1)
        self.assertIn("other.en.md", report.dead_anchors[0])

    def test_missing_translation(self):
        report = self._check({"index.md": "# Accueil\n"}, ["index.md"])
        self.assertEqual(report.missing_translations, ["index.md"])

    def test_an_english_page_with_no_french_twin(self):
        # The mirror of the case above, and the easy one to write first in a repository whose
        # every other file is English. It is in no nav entry either — and mkdocs logs a page
        # outside the nav as INFO, so `--strict` stays green while the page is missing from the
        # French site entirely.
        pages = dict(CLEAN)
        pages["solo.en.md"] = "# Solo\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(report.missing_translations, ["solo.en.md"])
        self.assertEqual(report.nav_orphans, ["solo.en.md"])

    def test_a_link_inside_a_code_block_is_not_a_link(self):
        pages = dict(CLEAN)
        pages["index.md"] += "\n```markdown\n[exemple](nexistepas.md)\n```\n"
        pages["index.en.md"] += "\n```markdown\n[example](nowhere.md)\n```\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(report.total, 0, dc.format_report(report))

    def test_reference_style_link(self):
        pages = dict(CLEAN)
        pages["index.md"] += "\nVoir [la page][ref].\n\n[ref]: nexistepas.md\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(len(report.broken_links), 1)
        self.assertIn("nexistepas.md", report.broken_links[0])

    def test_a_link_outside_the_documentation_tree(self):
        # `[the changelog](../CHANGELOG.md#unreleased)` is the shape that gets written. The file
        # exists, but the site never publishes it, so the link 404s for a reader — and with an
        # anchor it used to reach `relative_to` and kill the gate with a traceback.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "CHANGELOG.md").write_text("# Changelog\n\n## Unreleased\n", encoding="utf-8")
            pages = dict(CLEAN)
            pages["index.md"] += "\n[chgl](../CHANGELOG.md#unreleased)\n"
            doc_dir, mkdocs = _tree(root, pages, ["index.md"])
            report = dc.check_docs(doc_dir, mkdocs)
            self.assertEqual(len(report.broken_links), 1)
            self.assertIn("outside the documentation tree", report.broken_links[0])

    def test_a_fence_indented_inside_a_list_item(self):
        pages = dict(CLEAN)
        pages["index.md"] += "\n1. Comme ceci :\n\n   ```markdown\n   [exemple](nexistepas.md)\n   ```\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(report.total, 0, dc.format_report(report))

    def test_a_block_indented_by_four_spaces_is_code_too(self):
        # Markdown's other way of writing a code block, and the one nobody remembers is code.
        # mkdocs renders this as a sample; the gate used to report it as a broken link.
        pages = dict(CLEAN)
        pages["index.md"] += "\nExemple :\n\n    [exemple](nexistepas.md)\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(report.total, 0, dc.format_report(report))

    def test_a_config_without_a_nav_key_fails_loudly(self):
        # Silently treating the whole file as the nav makes every page look listed, which is the
        # one outcome worse than a false positive here.
        with tempfile.TemporaryDirectory() as tmp:
            doc_dir, mkdocs = _tree(Path(tmp), CLEAN, ["index.md"])
            mkdocs.write_text("site_name: Test\n", encoding="utf-8")
            with self.assertRaises(SystemExit):
                dc.check_docs(doc_dir, mkdocs)

    def test_angle_bracketed_target(self):
        pages = dict(CLEAN)
        pages["index.md"] += "\n[la page](<nexistepas.md>)\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(len(report.broken_links), 1)

    def test_nav_orphan(self):
        pages = dict(CLEAN)
        pages["orphan.md"] = "# Orpheline\n"
        pages["orphan.en.md"] = "# Orphan\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(report.nav_orphans, ["orphan.md"])

    def test_nav_dangling(self):
        report = self._check(CLEAN, ["index.md", "gone.md"])
        self.assertEqual(report.nav_dangling, ["gone.md"])

    def test_nav_entries_without_a_title_or_with_a_quoted_path(self):
        # Both are legal YAML. Missing either makes its page look like an orphan *and* makes the
        # entry invisible to nav_dangling — two findings that read as real and are not.
        with tempfile.TemporaryDirectory() as tmp:
            doc_dir, mkdocs = _tree(Path(tmp), CLEAN, [])
            mkdocs.write_text('site_name: Test\n\nnav:\n  - index.md\n', encoding="utf-8")
            self.assertEqual(dc.check_docs(doc_dir, mkdocs).total, 0)
            mkdocs.write_text('site_name: Test\n\nnav:\n  - Home: "index.md"\n', encoding="utf-8")
            self.assertEqual(dc.check_docs(doc_dir, mkdocs).total, 0)

    def test_an_english_page_is_never_asked_for_a_translation(self):
        # `.en.md` files are the translations; asking for `x.en.en.md` would report every page.
        report = self._check(CLEAN, ["index.md"])
        self.assertEqual(report.missing_translations, [])
        self.assertEqual(report.nav_orphans, [])


class RealDocumentationTest(unittest.TestCase):
    """The gate against this repository's own documentation, which must stay clean."""

    def test_the_published_documentation_has_no_defect(self):
        report = dc.check_docs(Path(ROOT) / "documentation", Path(ROOT) / "mkdocs.yml")
        self.assertEqual(report.total, 0, dc.format_report(report))


if __name__ == "__main__":
    unittest.main()
