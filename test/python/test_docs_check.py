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

    def test_nav_orphan(self):
        pages = dict(CLEAN)
        pages["orphan.md"] = "# Orpheline\n"
        pages["orphan.en.md"] = "# Orphan\n"
        report = self._check(pages, ["index.md"])
        self.assertEqual(report.nav_orphans, ["orphan.md"])

    def test_nav_dangling(self):
        report = self._check(CLEAN, ["index.md", "gone.md"])
        self.assertEqual(report.nav_dangling, ["gone.md"])

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
