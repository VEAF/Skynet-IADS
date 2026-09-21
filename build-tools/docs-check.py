#!/usr/bin/env python3
"""Guard the published documentation against silent rot.

The site is bilingual: `page.md` is French and `page.en.md` its English twin (see `mkdocs.yml`).
Doubling the pages doubles the ways the site can rot without anyone noticing, and the one that
matters is invisible to `mkdocs build --strict`:

- **A page with no twin.** `mkdocs-static-i18n` falls back rather than failing, so an untranslated
  page is served in the wrong language under the other locale's URL — `/en/faq/` answering with a
  French `<h1>`, exit code 0. VMCT shipped one like that for months before anyone saw it, and this
  gate exists because of that page. mkdocs does not help either way: a page in no menu is an
  `INFO`, not a warning, so `--strict` stays green on it.

Ported from `veaf_build/docs_check.py` in VEAF-Mission-Creation-Tools, keeping the two subtleties
that repository got wrong first and fixed, both verified there against the published HTML, and
both re-measured here on a real build:

- **An explicit `{#anchor}` replaces the generated id**, it does not add to it. Registering both is
  how five dead anchors passed the gate while 404ing on the site.
- **Relative links are language-agnostic** — the plugin rewrites them, so an English page linking
  to `page.md` is served `page/` resolved inside `/en/` and its reader never lands in French. Only
  a *missing target* is a defect there. **Anchors are not rewritten**, so an anchor is checked
  against the page the reader actually lands on.

`wrong_language_links` therefore reports a **style** rule, not a broken page: every English page
spells its target `.en.md`, so that what the file says and what the reader gets cannot drift apart.

Anchor arithmetic is duplicated work — `mkdocs.yml` sets `validation.links.anchors: warn`, and the
strict build checks the same thing with the real slugifier, in the right language. This module
keeps it because `implicit_anchors` needs to know *which* anchors are explicit, which mkdocs never
reports.

Run it with `python build-tools/docs-check.py`; the `Docs Check` workflow runs the same thing.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field, fields
from pathlib import Path

#: An inline link's target, with `<...>` around it allowed, and a reference definition's target.
#: Both forms resolve to a file, so both have to be checked — a `[see][ref]` whose `[ref]:` line
#: points nowhere is as broken as an inline link, and reads as ordinary prose to the eye.
_LINK = re.compile(r"\[[^\]]*\]\(\s*<?([^)\s<>]+?)>?(?:\s+\"[^\"]*\")?\s*\)")
_LINK_DEFINITION = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?([^\s<>]+)>?", re.MULTILINE)
_HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*$", re.MULTILINE)
#: Both spellings attr_list accepts: `{#id}` and the canonical `{: #id }`.
_EXPLICIT_ANCHOR = re.compile(r"\{:?\s*#([A-Za-z0-9_-]+)\s*\}\s*$")
#: A fenced code block, so links and `#` comments inside one are not mistaken for prose. api.md
#: alone holds 66 of them; a shell comment there would otherwise register as a heading, and a
#: sample link as a real one.
_FENCE = re.compile(r"^(?P<fence>```+|~~~+)[^\n]*\n.*?^(?P=fence)[^\n]*$", re.MULTILINE | re.DOTALL)
#: mkdocs.yml carries a `!!python/object/apply` tag, so it cannot go through yaml.safe_load; the
#: nav is a flat list of `key: path.md` lines, which this reads directly. A title is optional and
#: the path may be quoted — both are legal YAML, and missing either makes the entry invisible to
#: `nav_dangling` while its page is reported as an orphan.
_NAV_ENTRY = re.compile(r"""^\s*-\s*(?:[^:\n]+:\s*)?["']?([A-Za-z0-9_./-]+\.md)["']?\s*$""", re.MULTILINE)

#: Marks a deliberate language-switcher link (see `wrong_language_links`).
_LANGUAGE_FLAG = "🇫🇷"

#: Pages that legitimately have no translation and sit in no menu. Empty here, and an entry needs a
#: reason beside it: an exemption nobody can justify is indistinguishable from neglect.
EXEMPT: frozenset[str] = frozenset()


def slugify(title: str) -> str:
    """Return the anchor id mkdocs generates for a heading.

    Mirrors `pymdownx.slugs.slugify(case="lower")` as configured in `mkdocs.yml`: inline code and
    emphasis markers are dropped, punctuation is stripped, spaces become dashes, and **accents are
    preserved** — which matters here, where half the pages are French.

    Args:
        title: The heading text, with or without a trailing explicit `{#anchor}`.

    Returns:
        The generated anchor id.
    """
    title = _EXPLICIT_ANCHOR.sub("", title).strip()
    # `_` is deliberately absent from the stripped class: it is a word character for pymdownx, so
    # `## Connecting Skynet to the MOOSE AI_A2A_DISPATCHER` really is served with the underscores
    # in place.
    title = re.sub(r"[`*]", "", title)
    # No strip after the punctuation is removed, and that is the whole point: pymdownx does not
    # strip either, so the space French puts before a `?` becomes a **trailing dash**. `## Y a-t-il
    # des bogues connus ?` is served as `y-a-t-il-des-bogues-connus-`. Stripping it made this
    # function disagree with the site on 8 of the 126 generated anchors, every one of them French
    # — and the divergence ran the wrong way: a link copied from the permalink the page itself
    # displays was reported dead, while the id that 404s was accepted.
    return re.sub(r"[^\w\- ]", "", title, flags=re.UNICODE).lower().replace(" ", "-")


def prose_of(page: Path) -> str:
    """Return a page's text with its fenced code blocks blanked out.

    Everything this module looks for — a link, a heading — means something inside a code block
    that it does not mean outside one: a sample link points nowhere on purpose, and `# comment` in
    a shell snippet is not a heading. Blanking rather than deleting keeps the line numbering, so a
    finding still points where a human would look.

    Args:
        page: Path to a markdown page.

    Returns:
        The page text, fences replaced by blank lines of the same height.
    """
    text = page.read_text(encoding="utf-8")
    return _FENCE.sub(lambda m: "\n" * m.group(0).count("\n"), text)


def anchors_of(page: Path) -> tuple[set[str], set[str]]:
    """Return the anchors a page exposes, split by kind.

    Args:
        page: Path to a markdown page.

    Returns:
        `(all_anchors, explicit_anchors)` — explicit ones are those declared with `{#anchor}`,
        which survive both a reword and a translation.
    """
    every: set[str] = set()
    explicit: set[str] = set()
    for title in _HEADING.findall(prose_of(page)):
        match = _EXPLICIT_ANCHOR.search(title)
        if match:
            # attr_list makes the explicit id **replace** the generated one, so the heading-derived
            # slug is not an id the site serves.
            every.add(match.group(1))
            explicit.add(match.group(1))
            continue
        every.add(slugify(title))
    return every, explicit


def _twin(page: Path) -> Path:
    """Return the English counterpart of a French page (`x.md` -> `x.en.md`)."""
    return page.parent / (page.name[:-3] + ".en.md")


@dataclass
class Report:
    """Everything the check found, one list per defect kind."""

    broken_links: list[str] = field(default_factory=list)
    dead_anchors: list[str] = field(default_factory=list)
    implicit_anchors: list[str] = field(default_factory=list)
    wrong_language_links: list[str] = field(default_factory=list)
    missing_translations: list[str] = field(default_factory=list)
    nav_orphans: list[str] = field(default_factory=list)
    nav_dangling: list[str] = field(default_factory=list)

    @property
    def total(self) -> int:
        """Number of defects across every kind."""
        return sum(len(getattr(self, entry.name)) for entry in fields(self))


def check_docs(doc_dir: Path, mkdocs_yml: Path, require_explicit_anchors: bool = True) -> Report:
    """Audit the documentation tree and return everything that is wrong.

    Args:
        doc_dir: The `docs_dir` root (`documentation/`).
        mkdocs_yml: Path to `mkdocs.yml`, read for its `nav`.
        require_explicit_anchors: When True, a cross-page link whose anchor is derived from a
            heading rather than declared with `{#anchor}` is reported: such a link breaks on the
            next reword, and differs between the two languages.

    Returns:
        A `Report`; `report.total == 0` means the documentation is clean.
    """
    report = Report()
    pages = sorted(doc_dir.rglob("*.md"))
    fr_pages = [p for p in pages if not p.name.endswith(".en.md")]

    nav_text = mkdocs_yml.read_text(encoding="utf-8").split("\nnav:", 1)[-1]
    nav_targets = set(_NAV_ENTRY.findall(nav_text))

    for page in pages:
        rel = page.relative_to(doc_dir).as_posix()
        is_en = page.name.endswith(".en.md")
        text = prose_of(page)
        # A language switcher on an English page points at the French one *on purpose*, which is
        # exactly the shape wrong_language_links reports. The flag emoji is the signal that says
        # "this link is meant to change language".
        switcher_targets = {m for line in text.splitlines() if _LANGUAGE_FLAG in line for m in _LINK.findall(line)}
        same_page_anchors, _ = anchors_of(page)
        for target in _LINK.findall(text) + _LINK_DEFINITION.findall(text):
            if target.startswith("#"):
                # A same-page anchor. Checked with the same rule as a cross-page one, but never
                # *required* to be explicit: the two reasons for that requirement — a reword
                # breaking the link, and the anchor differing between languages — are both about
                # crossing pages.
                if target[1:] and target[1:] not in same_page_anchors:
                    report.dead_anchors.append(f"{rel} -> {target} (no '{target[1:]}' in this page)")
                continue
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            path_part, _, anchor = target.partition("#")
            if not path_part.endswith(".md"):
                continue
            resolved = (page.parent / path_part).resolve()
            if not resolved.exists():
                report.broken_links.append(f"{rel} -> {target}")
                continue
            if is_en and not path_part.endswith(".en.md") and target not in switcher_targets and _twin(resolved).exists():
                # Style, not breakage: the plugin rewrites the link and the reader does land in
                # English. What this keeps is the file saying what the reader gets, so the day one
                # of the two twins goes away the link reads as wrong before it behaves as wrong.
                report.wrong_language_links.append(f"{rel} -> {target} (write {_twin(resolved).name})")
            if not anchor:
                continue
            # Anchors are not rewritten by the i18n plugin: check the page the reader lands on.
            if is_en and not path_part.endswith(".en.md") and _twin(resolved).exists():
                resolved = _twin(resolved)
            every, explicit = anchors_of(resolved)
            landed = resolved.relative_to(doc_dir.resolve()).as_posix()
            if anchor not in every:
                report.dead_anchors.append(f"{rel} -> {target} (no '{anchor}' in {landed})")
            elif require_explicit_anchors and anchor not in explicit:
                report.implicit_anchors.append(f"{rel} -> {target} (add {{#{anchor}}} in {landed})")

    # Both directions. Walking the French pages alone leaves an `x.en.md` with no `x.md` checked by
    # nobody: it is not a French page, so it is asked for neither a twin nor a nav entry, and
    # mkdocs logs a page outside the nav as INFO — so `--strict` stays green while the page is
    # missing from the French site entirely. In a repository whose every other file is English,
    # that is the easy half to write first.
    for page in fr_pages:
        rel = page.relative_to(doc_dir).as_posix()
        if rel in EXEMPT:
            continue
        if not _twin(page).exists():
            report.missing_translations.append(rel)
        if rel not in nav_targets:
            report.nav_orphans.append(rel)

    for page in pages:
        if not page.name.endswith(".en.md"):
            continue
        french = page.parent / (page.name[: -len(".en.md")] + ".md")
        rel = french.relative_to(doc_dir).as_posix()
        if rel in EXEMPT or french.exists():
            continue
        report.missing_translations.append(page.relative_to(doc_dir).as_posix())
        if rel not in nav_targets:
            report.nav_orphans.append(page.relative_to(doc_dir).as_posix())

    for target in sorted(nav_targets):
        if not (doc_dir / target).exists():
            report.nav_dangling.append(target)

    return report


_LABELS = {
    "broken_links": "Links whose target file does not exist",
    "dead_anchors": "Links pointing at an anchor the target does not expose",
    "implicit_anchors": "Cross-page links relying on a heading-derived anchor (declare {#anchor})",
    "wrong_language_links": "English pages spelling a link `page.md` where `page.en.md` exists (style)",
    "missing_translations": "Pages with no counterpart in the other language",
    "nav_orphans": "Pages absent from the mkdocs nav (unreachable by menu)",
    "nav_dangling": "Nav entries pointing at a file that does not exist",
}


def format_report(report: Report) -> str:
    """Render *report* as the text the CI job prints.

    Args:
        report: The audit result.

    Returns:
        A human-readable multi-line summary.
    """
    if report.total == 0:
        return "docs-check: no defect found."
    lines = [f"docs-check: {report.total} defect(s) found.", ""]
    for key, label in _LABELS.items():
        entries = getattr(report, key)
        if not entries:
            continue
        lines.append(f"{label} ({len(entries)}):")
        lines += [f"  - {entry}" for entry in entries]
        lines.append("")
    return "\n".join(lines).rstrip()


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: audit the docs and exit non-zero on any defect.

    Args:
        argv: Argument list; defaults to `sys.argv[1:]`.

    Returns:
        `0` when the documentation is clean, `1` otherwise.
    """
    repo_root = Path(__file__).parent.parent
    parser = argparse.ArgumentParser(description="Check the documentation for rot.")
    parser.add_argument("--doc-dir", type=Path, default=repo_root / "documentation")
    parser.add_argument("--mkdocs", type=Path, default=repo_root / "mkdocs.yml")
    parser.add_argument(
        "--allow-implicit-anchors",
        action="store_true",
        help="Do not report cross-page links that rely on a heading-derived anchor.",
    )
    args = parser.parse_args(argv)

    report = check_docs(args.doc_dir, args.mkdocs, require_explicit_anchors=not args.allow_implicit_anchors)
    print(format_report(report))
    return 1 if report.total else 0


if __name__ == "__main__":
    sys.exit(main())
