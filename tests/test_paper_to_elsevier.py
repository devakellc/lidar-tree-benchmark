"""Regressions for scripts/paper_to_elsevier.py (markdown to the Elsevier
LaTeX version for the ISPRS Journal of Photogrammetry and Remote Sensing).

The unit tests need no external tools. The pandoc tests and the end-to-end
tests run when pandoc is available (on PATH or via the PANDOC environment
variable): the end-to-end tests convert the repository's paper and check that
no word, number or table row is lost and that the journal's front and back
matter rules hold, and convert a small synthetic paper that exercises what
the real paper may not use yet. The BibTeX test runs elsarticle-harv.bst on
the Elsevier copy of the bibliography when bibtex is available (on PATH or via
BIBTEX). The word and number comparison, the table-row count and the width
factor checks are those of tests/test_paper_to_ieee.py, loaded as a module.

From the repository root:

    python3 -m unittest discover -s tests -p 'test_paper_to_elsevier.py'
"""
import contextlib
import importlib.util
import io
import os
import re
import subprocess
import tempfile
import unittest
import zipfile
from collections import Counter
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


p2e = load("paper_to_elsevier", ROOT / "scripts/paper_to_elsevier.py")
p2i = p2e.p2i  # the instance the converter uses, so a patched REPO reaches it
tie = load("test_paper_to_ieee_helpers", ROOT / "tests/test_paper_to_ieee.py")
PANDOC, BIBTEX = tie.PANDOC, tie.BIBTEX
PDFLATEX = tie.find_tool("PDFLATEX", "pdflatex")
NB = "\u00a0"
GROUP = r"\[@[a-z0-9]+(?:;\s*@[a-z0-9]+)*\]"

LABELS = {"kuhn1955hungarian": ("Kuhn", "1955"), "eysn2015benchmark": ("Eysn et al.", "2015"),
          "hamraz2016robust": ("Hamraz et al.", "2016")}


def els_tex_words(tex):
    """tex_words of the IEEE tests, after dropping natbib citations and the
    Elsevier front-matter commands, whose text the markdown does not print."""
    tex = re.sub(r"\\cite[pt]?\{[^}]*\}", " ", tex)
    for name in ("affiliation", "ead", "cortext", "fntext", "journal"):
        tex = tie.drop_command(tex, name, 1)
    return tie.tex_words(tex)


def els_main_md(md):
    """The parts of the manuscript's markdown that main.tex prints: every
    section after the title block but the references, which BibTeX writes."""
    return "\n".join(h + "\n" + t for h, t in p2i.split_sections(md)[1:] if h != "## References")


def els_supp_md(supp, known, title):
    """The supplement as supplement.tex prints it: the LaTeX title replaces
    the H1, the opening names the paper, and the manuscript's numbers stay."""
    supp, code = p2i.hold_code(supp)
    supp = re.sub(r"(?m)^# .*$", "", supp)
    supp = re.sub(r"Supplement to the draft manuscript \[[^\]]*\]\(manuscript\.md\)\.",
                  f"Supplement to the manuscript \u201c{title}.\u201d", supp)
    return p2i.restore_code(p2i.convert_refs(supp, "supp", known, "elsevier"), code)


def md_cite_keys(md):
    """Every citation key of a markdown text, with its count, outside code."""
    held, _ = p2i.hold_code(md)
    keys = Counter(k for g in re.findall(GROUP, held) for k in re.findall(r"@([a-z0-9]+)", g))
    return keys + Counter(re.findall(r"(?<![\w@\\{])@([a-z0-9]+)", re.sub(GROUP, " ", held)))


def tex_cite_keys(tex):
    """Every key of the \\citep and \\citet commands of a LaTeX text, with its
    count, outside comments and code."""
    body = re.sub(r"(?<!\\)%.*", " ", p2i.VERBATIM.sub(" ", tex))
    return Counter(k for g in re.findall(r"\\cite[pt]\{([^}]*)\}", body) for k in g.split(","))


def md_back_heads(md):
    """The back-matter headings of a manuscript, in order: between the last
    numbered section and the references."""
    heads = [h for h, _ in p2i.split_sections(md)]
    start = heads.index("## 1. Introduction")
    end = next(i for i, h in enumerate(heads) if i > start and not re.match(r"## \d", h))
    return [h[3:] for h in heads[end:heads.index("## References")]]


def els_table_rows(tex):
    """Body rows of every table: between \\midrule and \\bottomrule, or after
    \\endfoot in a supplement table."""
    rows = []
    for env in re.findall(r"(?s)\\begin\{(?:tabularx|tabular|xltabular)\}.*?\\end\{(?:tabularx|tabular|xltabular)\}",
                          tex):
        body = env.split("\\endfoot", 1)[1] if "\\endfoot" in env else env.split("\\midrule", 1)[1]
        rows.append(len(re.findall(r"\\\\\s*$", body, flags=re.M)))
    return rows


def run_converter(argv):
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            p2e.main(argv)
    except SystemExit as e:
        raise RuntimeError(f"the converter stopped: {e}") from e


class CitationTests(unittest.TestCase):
    def test_groups_and_narrative_citations(self):
        md = "As in @kuhn1955hungarian, matches [@eysn2015benchmark; @hamraz2016robust] hold."
        self.assertEqual(p2e.convert_citations(md, LABELS),
                         "As in \\citet{kuhn1955hungarian}, matches \\citep{eysn2015benchmark,hamraz2016robust} hold.")

    def test_unknown_keys_and_unsupported_forms_stop(self):
        for md in ("[@nobody2020]", "@nobody2020 found", "[see @kuhn1955hungarian]",
                   "[@kuhn1955hungarian, p. 3]", "@kuhn1955hungarian [p. 3]"):
            with self.subTest(md=md), self.assertRaises(SystemExit):
                p2e.convert_citations(md, LABELS)
        # A key with capitals is read as pandoc reads it, so a mistyped key
        # stops instead of printing as it is written.
        for md in ("[@Unknown2026]", "@Unknown2026 found", "[@kuhn1955hungarian; @Unknown2026]"):
            with self.subTest(md=md), self.assertRaisesRegex(
                    SystemExit, "citation of Unknown2026, which docs/references.bib does not hold"):
                p2e.convert_citations(md, LABELS)
        with self.assertRaisesRegex(SystemExit, r"'\[@ kuhn1955hungarian\]' holds an at-sign but is not a citation "
                                                r"the converter reads"):
            p2e.convert_citations("as [@ kuhn1955hungarian] shows", LABELS)

    def test_keys_with_capitals_underscores_and_inner_marks(self):
        labels = dict(LABELS, **{"Doe_2020-a": ("Doe", "2020"), "SmithX2021": ("Smith", "2021"),
                                 "lee:2019.b": ("Lee", "2019")})
        md = "As @Doe_2020-a found, [@SmithX2021; @lee:2019.b; @kuhn1955hungarian] agree; see @SmithX2021."
        self.assertEqual(p2e.convert_citations(md, labels),
                         "As \\citet{Doe_2020-a} found, \\citep{SmithX2021,lee:2019.b,kuhn1955hungarian} agree; "
                         "see \\citet{SmithX2021}.")

    def test_addresses_are_not_citations(self):
        self.assertEqual(p2e.convert_citations("mail a@b.org", LABELS), "mail a@b.org")
        self.assertEqual(p2e.convert_citations("write to [a@b.org](mailto:a@b.org).", LABELS),
                         "write to [a@b.org](mailto:a@b.org).")

    def test_cite_text_for_width_estimates(self):
        self.assertEqual(p2e.cite_text("x \\citep{eysn2015benchmark,kuhn1955hungarian} y", LABELS),
                         "x (Eysn et al., 2015; Kuhn, 1955) y")
        self.assertEqual(p2e.cite_text("after \\citet{kuhn1955hungarian}, Section~\\ref{sec:4.2}", LABELS),
                         "after Kuhn (1955), Section~4.2")

    def test_labels_from_the_bibliography(self):
        labels = p2e.cite_labels(tie.BIB)
        self.assertTrue(labels)
        self.assertTrue(all(re.fullmatch(r"\d{4}", y) for _, y in labels.values()))


KNOWN = {"sec": {"1", "4", "4.2"}, "tab": {"3"}, "fig": {"2"}, "ssec": {"S1"}, "stab": {"S12c"}, "sfig": {"S1"}}


class ReferenceTests(unittest.TestCase):
    def test_main_uses_labels_and_keeps_panels(self):
        out = p2i.convert_refs("Section 4.2, Table 3, Fig. 2d and Figs. 2 and S1b.", "main", KNOWN, "elsevier")
        self.assertEqual(out, f"Section{NB}\\ref{{sec:4.2}}, Table{NB}\\ref{{tab:3}}, Fig.{NB}\\ref{{fig:2}}d "
                              f"and Figs.{NB}\\ref{{fig:2}} and S1b.")

    def test_supplement_keeps_the_manuscripts_numbers(self):
        out = p2i.convert_refs("Section 4.2, Table 3 and Fig. 2d (Table S12c).", "supp", KNOWN, "elsevier")
        self.assertEqual(out, f"Section{NB}4.2, Table{NB}3 and Fig.{NB}2d (Table{NB}S12c).")

    def test_ieee_style_is_unchanged(self):
        out = p2i.convert_refs("Section 4.2, Table 3 and Fig. 2d.", "supp", KNOWN)
        self.assertEqual(out, f"Section{NB}IV-B, Table{NB}III and Fig.{NB}2(d).")


class NumberingTests(unittest.TestCase):
    def test_sequence_passes(self):
        p2e.check_numbering("## 1. A\n\n### 1.1 B\n\n### 1.2 C\n\n## 2. D\n\n### 2.1 E\n\n```sh\n## 9. code\n```\n")

    def test_out_of_sequence_or_too_deep_stops(self):
        for md in ("## 1. A\n\n## 3. C\n", "## 1. A\n\n### 1.2 B\n", "## 1. A\n\n### 2.1 B\n",
                   "## 1. A\n\n#### 1.1.1 B\n", "## A\n", "## 1. A\n\n### 1 B\n"):
            with self.subTest(md=md), self.assertRaises(SystemExit):
                p2e.check_numbering(md)


class HighlightsTests(unittest.TestCase):
    def test_wrapped_items_and_markup(self):
        items = p2e.highlights("- One `code`\n  continued.\n- Two.\n- *Three*.\n")
        self.assertEqual(items, ["One `code` continued.", "Two.", "*Three*."])

    def test_limits_stop(self):
        for text in ("- One.\n- Two.\n", "".join(f"- {i}.\n" for i in range(6)),
                     "- A.\n- B.\n- " + "x" * 86 + "\n", "- A.\n- B.\nC.\n"):
            with self.subTest(text=text[:30]), self.assertRaises(SystemExit):
                p2e.highlights(text)
        self.assertEqual(len(p2e.highlights("- A.\n- B.\n- **" + "x" * 85 + "**\n")), 3)  # markup is not counted

    def test_spaces_count_toward_the_limit(self):
        self.assertEqual(len(p2e.highlights("- A.\n- B.\n- " + "word " * 16 + "words\n")), 3)  # 85 characters
        with self.assertRaises(SystemExit):
            p2e.highlights("- A.\n- B.\n- " + "word " * 17 + "x\n")  # 86 characters


class BibliographyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bib = p2e.elsevier_bib(tie.BIB)

    def test_ascii_and_no_at_sign_outside_entries(self):
        self.assertEqual([c for c in set(self.bib) if ord(c) > 127], [])
        outside = re.sub(r"(?ms)^@\w+\{.*?^\}$", "", self.bib)
        self.assertNotIn("@", outside)

    def test_types_doi_eprint_and_notes(self):
        for _, key, fields, _ in p2i.parse_bib(tie.BIB):
            f = dict(fields)
            e = tie.entry(self.bib, key)
            with self.subTest(key=key):
                self.assertNotRegex(e, r"^@(software|online|dataset)\{")
                for gone in ("urldate", "version", "archiveprefix", "primaryclass"):
                    self.assertNotRegex(e, rf"\b{gone}\s*=")
                if "doi" in f:
                    self.assertNotRegex(e, r"\beprint\s*=")
                elif "eprint" in f:
                    self.assertIn(f["eprint"], e)
                note = re.search(r"\bnote\s*=\s*\{(.*)\},?$", e)
                if note:
                    self.assertTrue(note.group(1).startswith("{"), e)  # the style keeps a braced first letter
                if "urldate" in f:
                    y, m, d = (int(x) for x in f["urldate"].split("-"))
                    self.assertIn(f"ccessed {d} {p2e.MONTHS[m - 1]} {y}", e)
                self.assertNotIn("Undated page", e)

    def test_accessed_dates(self):
        self.assertEqual(p2e.accessed("2026-10-02"), "Accessed 2 October 2026")
        with self.assertRaises(SystemExit):
            p2e.accessed("2 Oct 2026")

    def test_proceedings_volume_publisher_and_quotes(self):
        e = p2e.elsevier_entry("inproceedings", "k", [
            ("author", "Doe, Jane"), ("title", "A ``quoted'' title"), ("booktitle", "Proc. of Things"),
            ("series", "LNCS"), ("volume", "XXXVI-8/W2"), ("number", "3"), ("publisher", "Curran Associates, Inc."),
            ("pages", "1--5"), ("year", "2004")])
        self.assertIn("booktitle = {Proc. of Things, LNCS XXXVI-8/W2 (3)}", tie.flat(e))
        self.assertNotRegex(e, r"\b(volume|number|series)\s*=")
        self.assertIn("publisher = {Curran Associates, Inc}", tie.flat(e))
        self.assertIn("``quoted''", e)  # the style does not quote titles, so the source's quotes stay
        # Followed by an address, the publisher keeps its period: the style
        # writes 'publisher, address'.
        e = p2e.elsevier_entry("inproceedings", "k", [
            ("author", "Doe, Jane"), ("title", "T"), ("booktitle", "Proc"), ("publisher", "Curran Associates, Inc."),
            ("address", "Red Hook, NY"), ("pages", "1--5"), ("year", "2021")])
        self.assertIn("publisher = {Curran Associates, Inc.}", tie.flat(e))

    def test_long_hashes_may_break(self):
        e = p2e.elsevier_entry("misc", "k", [("author", "Doe, Jane"), ("title", "T"), ("year", "2024"),
                                             ("note", "revision cc21436bc5d572dde8ff5f93c1e71a32f563cace")])
        self.assertIn("cc21436b\\allowbreak{}c5d572dd\\allowbreak{}", e)
        e = p2e.elsevier_entry("misc", "k", [("author", "Doe, Jane"), ("title", "T"), ("year", "2024"),
                                             ("note", "commit d6082bb68511")])
        self.assertNotIn("allowbreak", e)  # a short hash breaks nothing

    def test_article_issue_joins_its_volume(self):
        # elsarticle-harv.bst prints an article's volume but not its number.
        head = [("author", "Doe, Jane"), ("title", "T"), ("journal", "J"), ("year", "1955")]
        e = p2e.elsevier_entry("article", "k", head + [("volume", "2"), ("number", "1--2"), ("pages", "83--97")])
        self.assertIn("volume = {2 (1--2)}", tie.flat(e))
        self.assertNotRegex(e, r"\bnumber\s*=")
        self.assertEqual(re.findall(r"(?m)^  (\w+)", e), ["author", "title", "journal", "year", "volume", "pages"])
        e = p2e.elsevier_entry("article", "k", head + [("number", "4"), ("pages", "1--5")])
        self.assertIn("volume = {(4)}", tie.flat(e))
        self.assertNotRegex(e, r"\bnumber\s*=")
        self.assertEqual(re.findall(r"(?m)^  (\w+)", e), ["author", "title", "journal", "year", "volume", "pages"])
        e = p2e.elsevier_entry("article", "k", head + [("volume", "7"), ("number", " "), ("pages", "1--5")])
        self.assertIn("volume = {7}", tie.flat(e))  # an empty number changes nothing

    def test_misc_publisher_never_goes_to_organization(self):
        e = p2e.elsevier_entry("software", "k", [
            ("author", "Doe, Jane"), ("title", "Tool"), ("howpublished", "GitHub repository"),
            ("publisher", "Example Foundation"), ("year", "2026")])
        self.assertTrue(e.startswith("@misc{k,"))
        self.assertNotIn("organization", e)
        self.assertRegex(tie.flat(e), r"note += \{\{E\}xample Foundation\}")

    def test_arxiv_preprint_takes_its_doi_and_corporate_author_its_short_name(self):
        e = p2e.elsevier_entry("misc", "k", [("author", "Doe, Jane"), ("title", "Pre"), ("year", "2026"),
                                             ("eprint", "2107.07002"), ("archiveprefix", "arXiv")])
        self.assertIn("doi = {10.48550/arXiv.2107.07002}", tie.flat(e))
        self.assertIn("eprint", e)
        e = p2e.elsevier_entry("misc", "k", [("author", "Doe, Jane"), ("title", "Pre"), ("year", "2026"),
                                             ("eprint", "arXiv:2107.07002v3"), ("archiveprefix", "arXiv")])
        self.assertIn("doi = {10.48550/arXiv.2107.07002}", tie.flat(e))  # arXiv DOIs carry no version
        # The style prints "arXiv:" before the identifier itself, so the
        # stored field drops the prefix and keeps the version.
        self.assertIn("eprint = {2107.07002v3}", tie.flat(e))
        self.assertNotRegex(e, r"(?i)arxiv\s*:")
        for kind in ("article", "inproceedings"):  # a published paper keeps the identifier only
            e = p2e.elsevier_entry(kind, "k", [("author", "Doe, Jane"), ("title", "Pub"), ("year", "2011"),
                                               ("eprint", "2010.16061"), ("archiveprefix", "arXiv")])
            self.assertNotIn("doi", e, kind)
            self.assertIn("2010.16061", e)
        e = p2e.elsevier_entry("article", "k", [("author", "Doe, Jane"), ("title", "Pub"), ("year", "2011"),
                                                ("eprint", "arXiv: 2010.16061"), ("archiveprefix", "arXiv")])
        self.assertIn("eprint = {2010.16061}", tie.flat(e))
        self.assertNotIn("doi", e)
        e = p2e.elsevier_entry("misc", "k", [("author", "{National Ecological Observatory Network (NEON)}"),
                                             ("title", "Data"), ("year", "2026"),
                                             ("publisher", "National Ecological Observatory Network (NEON)")])
        self.assertIn("author = {{National Ecological Observatory Network}}", tie.flat(e))
        self.assertNotIn("howpublished", e)  # the publisher repeats the author
        self.assertEqual(p2e.short_corporate("National Ecological Observatory Network (NEON)"),
                         "National Ecological Observatory Network")
        # The labels used for table widths are the citations as they print.
        labels = p2e.cite_labels((ROOT / "docs/references.bib").read_text(encoding="utf-8"))
        self.assertEqual(labels["neon2026vegetation"], ("National Ecological Observatory Network", "2026"))

    def test_note_protection(self):
        self.assertEqual(p2e.protect_note("model weights"), "{m}odel weights")
        self.assertEqual(p2e.protect_note("MIT licence"), "{MIT} licence")
        self.assertEqual(p2e.protect_note("Accessed 2 October 2026"), "{A}ccessed 2 October 2026")
        self.assertEqual(p2e.protect_note("37th conference"), "37th conference")


class TableFitTests(unittest.TestCase):
    def test_words_fit(self):
        est = [["Detector", "Score"], ["SegmentAnyTree", "0.5 [0.4, 0.6]"]]
        self.assertTrue(p2e.words_fit(["L", "L"], est, 40.0, ["1", "1"]))
        self.assertFalse(p2e.words_fit(["L", "L"], est, 8.0, ["1", "1"]))
        self.assertFalse(p2e.words_fit(["l", "l"], est, 5.0, [None, None]))

    def test_words_fit_leaves_room_for_the_fixed_columns(self):
        est = [["A very long label cell", "Score"], ["x", "word"]]
        fixed, word = p2e.one_line_em("A very long label cell"), max(p2i.word_widths("Score", p2e.SPACE_EM))
        self.assertTrue(p2e.words_fit(["l", "L"], est, fixed + word + 0.01, [None, "1"]))
        self.assertFalse(p2e.words_fit(["l", "L"], est, word + 1.0, [None, "1"]))


@unittest.skipUnless(PANDOC, "pandoc not available (set PANDOC=/path/to/pandoc)")
class TableLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        p2i.PANDOC = PANDOC

    def table(self, header, body, mode="main"):
        return p2e.table_tex("1", "Cap.", header, ["l"] * len(header), body, mode, LABELS)

    def test_small_table_keeps_its_natural_width(self):
        tex = self.table(["Site", "Plots"], [["SJER", "6"], ["SOAP", "18"]])
        self.assertTrue(tex.startswith("\\begin{table}[!htbp]\n\\centering\n{\\footnotesize"))
        self.assertIn("\\begin{tabular}{ll}\n\\toprule\nSite & Plots \\\\\n\\midrule", tex)
        # The caption directly below the table, as the journal asks.
        self.assertTrue(tex.endswith("\\end{tabular}\n}\n\\caption{Cap.}\n\\label{tab:1}\n\\end{table}"))
        self.assertNotIn("\\hline", tex)
        self.assertEqual(els_table_rows(tex), [2])

    def test_wrapping_table_spans_the_text_width(self):
        tex = self.table(["Detector", "Description"], [["A", "A long description " * 6]])
        self.assertIn("\\begin{tabularx}{\\linewidth}", tex)
        self.assertNotIn("sidewaystable", tex)

    def test_table_whose_words_cannot_fit_goes_landscape(self):
        header = ["Detector"] + [f"Column {i}" for i in range(10)]
        body = [["SegmentAnyTree"] + ["+0.048 [+0.028, +0.069]"] * 10 for _ in range(3)]
        tex = self.table(header, body)
        self.assertTrue(tex.startswith("\\begin{sidewaystable}\n\\centering"))
        self.assertIn("\\caption{Cap.}\n\\label{tab:1}\n\\end{sidewaystable}", tex)
        self.assertTrue(tex.endswith("\\end{sidewaystable}"))
        self.assertEqual(els_table_rows(tex), [3])

    def test_supplement_table_breaks_across_pages(self):
        tex = self.table(["Site", "Plots"], [["SJER", "6"]], mode="supp")
        self.assertIn("\\begin{xltabular}{\\textwidth}", tex)
        self.assertIn("\\textbf{Table 1.} Cap.", tex)
        self.assertIn("\\textbf{Table 1} (continued)", tex)
        self.assertIn("\\bottomrule\n\\endfoot", tex)
        self.assertEqual(els_table_rows(tex), [1])


class ArgumentTests(unittest.TestCase):
    def test_bad_arguments_stop_before_writing(self):
        for argv in (["paper/elsevier"], ["FOO=1"]):
            with self.subTest(argv=argv), self.assertRaises(SystemExit):
                p2e.main(argv)


@unittest.skipUnless(PANDOC, "pandoc not available (set PANDOC=/path/to/pandoc)")
class EndToEndTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        out = Path(cls.tmp.name) / "elsevier"
        run_converter([f"OUT={out}", f"PANDOC={PANDOC}"])
        cls.main_tex = (out / "main.tex").read_text(encoding="utf-8")
        cls.supp_tex = (out / "supplement.tex").read_text(encoding="utf-8")
        cls.bib = (out / "references.bib").read_text(encoding="utf-8")
        md = (ROOT / "paper/manuscript.md").read_text(encoding="utf-8")
        cls.title = p2e.front_matter(md)[1]
        cls.main_md = els_main_md(md)
        cls.supp_md = els_supp_md((ROOT / "paper/supplement.md").read_text(encoding="utf-8"), p2i.paper_numbers(),
                                  cls.title)

    def test_class_journal_and_bibliography_style(self):
        self.assertIn("\\documentclass[preprint,12pt,authoryear,a4paper]{elsarticle}", self.main_tex)
        self.assertIn("\\journal{ISPRS Journal of Photogrammetry and Remote Sensing}", self.main_tex)
        self.assertIn("\\biboptions{sort}", self.main_tex)
        self.assertIn("\\usepackage[round,authoryear,sort]{natbib}", self.supp_tex)
        self.assertIn("\\usepackage{rotating}", self.main_tex)
        self.assertRegex(self.main_tex, r"\\end\{frontmatter\}\s*\\linenumbers")
        for tex in (self.main_tex, self.supp_tex):
            self.assertIn("\\bibliographystyle{elsarticle-harv}\n\\bibliography{references}", tex)
            self.assertRegex(tex, tie.PAGE_GROUP)
            self.assertNotRegex(tex, r"\\cite\{")  # natbib's \citep and \citet only

    def test_geometry_matches_the_widths_the_layout_assumes(self):
        for mode, tex in (("main", self.main_tex), ("supp", self.supp_tex)):
            margin = float(re.search(r"\\usepackage\[a4paper,margin=([\d.]+)cm\]\{geometry\}", tex).group(1))
            self.assertAlmostEqual(210 - 20 * margin, p2e.TEXT_WIDTH_MM[mode])
            if mode == "main":
                self.assertAlmostEqual((297 - 20 * margin) / 25.4 * 72.27, p2e.LANDSCAPE_PT)

    def test_every_citation_reaches_the_latex(self):
        md = (ROOT / "paper/manuscript.md").read_text(encoding="utf-8")
        self.assertEqual(tex_cite_keys(self.main_tex), md_cite_keys(els_main_md(md)))
        self.assertEqual(tex_cite_keys(self.supp_tex), md_cite_keys(self.supp_md))

    def test_front_matter(self):
        items = re.search(r"(?s)\\begin\{highlights\}(.*?)\\end\{highlights\}", self.main_tex).group(1)
        self.assertTrue(3 <= items.count("\\item") <= 5)
        keywords = re.search(r"(?s)\\begin\{keyword\}(.*?)\\end\{keyword\}", self.main_tex).group(1)
        self.assertLessEqual(keywords.count("\\sep") + 1, p2e.MAX_KEYWORDS)
        self.assertIn("\\begin{abstract}", self.main_tex)
        self.assertIn("% TODO: complete the author block", self.main_tex)
        self.assertIn("\\title{" + self.title, self.main_tex)

    def test_back_matter_ends_with_the_ai_declaration(self):
        heads = re.findall(r"\\section\*\{([^}]*)\}", self.main_tex)
        md = (ROOT / "paper/manuscript.md").read_text(encoding="utf-8")
        self.assertEqual(heads, md_back_heads(md))  # in the markdown's order, once each
        self.assertEqual(heads[-1], p2e.AI_HEADING[3:])
        tail = self.main_tex.split("\\section*{" + heads[-1], 1)[1]
        self.assertNotRegex(tail.split("\\bibliographystyle", 1)[0], r"\\section")
        for head in ("CRediT authorship contribution statement", "Declaration of competing interest", "Funding",
                     "Acknowledgements"):
            self.assertIn(head, heads)

    def test_floats(self):
        self.assertEqual(len(re.findall(r"\\begin\{figure\}\[!htbp\]", self.main_tex)), 7)
        # Tables 3, 5 and 6 cannot fit the portrait width; the other four can.
        self.assertEqual(len(re.findall(r"\\begin\{sidewaystable\}", self.main_tex)), 3)
        self.assertEqual(len(re.findall(r"\\begin\{table\}\[!htbp\]", self.main_tex)), 4)
        self.assertEqual(re.findall(r"\\label\{tab:(\d+)\}\n\\end\{sidewaystable\}", self.main_tex), ["3", "5", "6"])
        self.assertNotRegex(self.main_tex, r"\\begin\{(?:figure|table)\*\}")

    def test_every_cite_key_is_in_the_bibliography(self):
        keys = set(re.findall(r"^@\w+\{([a-z0-9]+),", self.bib, flags=re.M))
        for tex in (self.main_tex, self.supp_tex):
            cited = {k for g in re.findall(r"\\cite[pt]\{([^}]*)\}", tex) for k in g.split(",")}
            self.assertTrue(cited)
            self.assertEqual(cited - keys, set())

    def test_every_ref_has_one_label(self):
        labels = re.findall(r"\\label\{([^}]*)\}", self.main_tex)
        self.assertEqual(len(labels), len(set(labels)))
        self.assertEqual(set(re.findall(r"\\ref\{([^}]*)\}", self.main_tex)) - set(labels), set())

    def test_supplement_uses_the_manuscripts_numbers(self):
        self.assertNotRegex(self.supp_tex, r"Section~[IVX]+(?:-[A-Z])?\b|Table~[IVX]+\b|Fig\.~\d+\([a-z]\)")

    def test_outputs_are_ascii(self):
        for text in (self.main_tex, self.supp_tex, self.bib):
            self.assertEqual([c for c in set(text) if ord(c) > 127], [])

    def test_figures_print_at_the_width_they_were_drawn(self):
        for mode, tex in (("main", self.main_tex), ("supp", self.supp_tex)):
            for f in p2i.graphics_files(tex):  # the vector PDF wherever there is one
                self.assertTrue(f.endswith(".pdf") or not (ROOT / "paper" / f).with_suffix(".pdf").exists(), f)
            found = re.findall(r"\\includegraphics\[width=([\d.]*)\\textwidth\]\{(figures/[^}]*\.pdf)\}", tex)
            self.assertEqual(len(found), len([f for f in p2i.graphics_files(tex) if f.endswith(".pdf")]))
            for share, f in found:
                with self.subTest(figure=f):
                    text = p2e.TEXT_WIDTH_IN[mode]
                    drawn = min(p2i.pdf_page_width(ROOT / "paper" / f), text)
                    printed = float(share or 1) * text
                    self.assertGreaterEqual(printed, drawn - 1e-9)
                    self.assertLess(printed - drawn, 0.01 * text)

    def test_no_word_is_lost_and_every_number_matches(self):
        for name, md, tex in (("main", self.main_md, self.main_tex), ("supplement", self.supp_md, self.supp_tex)):
            with self.subTest(document=name):
                md_w, tex_w = tie.md_words(md), els_tex_words(tex)
                self.assertEqual(dict(md_w - tex_w), {})
                self.assertEqual(dict(tie.numbers(tex_w) - tie.numbers(md_w)), {})
                self.assertEqual(dict(tie.numbers(md_w) - tie.numbers(tex_w)), {})

    def test_every_table_row_is_kept(self):
        self.assertEqual(els_table_rows(self.main_tex), tie.pipe_table_rows(self.main_md))
        self.assertEqual(els_table_rows(self.supp_tex), tie.pipe_table_rows(self.supp_md))

    def test_table_column_widths(self):
        for name, tex in (("main", self.main_tex), ("supplement", self.supp_tex)):
            preambles = re.findall(r"(?m)^\\begin\{(?:tabularx|xltabular)\}\{\\(?:text|line)width\}\{(.*)\}$", tex)
            self.assertEqual(len(preambles), len(re.findall(r"\\begin\{(?:tabularx|xltabular)\}", tex)))
            for pre in preambles:
                with self.subTest(document=name, preamble=pre):
                    cols = tie.preamble_columns(pre)
                    self.assertTrue(any(c in "LRC" for c, _ in cols))
                    tie.check_x_factors(self, [f for c, f in cols if c in "LRC"])


SYNTH_HIGHLIGHTS = "- A first highlight.\n- A second highlight.\n- A third highlight.\n"


@unittest.skipUnless(PANDOC, "pandoc not available (set PANDOC=/path/to/pandoc)")
class SyntheticPaperTests(unittest.TestCase):
    """The IEEE tests' synthetic paper, with three highlights, in a temporary
    copy of the repository layout."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        root = Path(cls.tmp.name)
        patcher = mock.patch.object(p2i, "REPO", root)
        patcher.start()
        cls.addClassCleanup(patcher.stop)
        (root / "docs").mkdir()
        (root / "docs/references.bib").write_text(tie.BIB, encoding="utf-8")
        md = tie.SYNTH_MANUSCRIPT.format(title="a short title: with a subtitle").replace("- A highlight.\n",
                                                                                         SYNTH_HIGHLIGHTS)
        (root / "paper/figures").mkdir(parents=True)
        (root / "paper/manuscript.md").write_text(md, encoding="utf-8")
        (root / "paper/supplement.md").write_text(tie.SYNTH_SUPPLEMENT, encoding="utf-8")
        tie.write_png(root / "paper/figures/figure_1.png", 50, 20)
        tie.write_pdf(root / "paper/figures/figure_1.pdf", 360, 144)  # 5 in of 6.30 in: 0.80 of the text width
        tie.write_png(root / "paper/figures/figure_s1.png", 40, 40)
        run_converter([f"OUT={root / 'out'}", f"PANDOC={PANDOC}", f"ZIP={root / 'up/isprs.zip'}"])
        cls.main_tex = (root / "out/main.tex").read_text(encoding="utf-8")
        cls.supp_tex = (root / "out/supplement.tex").read_text(encoding="utf-8")
        cls.zip_names = sorted(zipfile.ZipFile(root / "up/isprs.zip").namelist())
        cls.main_md = els_main_md(md)
        cls.supp_md = els_supp_md(tie.SYNTH_SUPPLEMENT, p2i.manuscript_numbers(md, tie.SYNTH_SUPPLEMENT),
                                  "a short title: with a subtitle")

    def test_figures_and_zip(self):
        self.assertIn("\\includegraphics[width=0.80\\textwidth]{figures/figure_1.pdf}", self.main_tex)
        self.assertIn("{\\centering\\includegraphics[width=0.72\\textwidth]{figures/figure_s1.png}\\par}",
                      self.supp_tex)
        self.assertEqual(self.zip_names, ["figures/figure_1.pdf", "figures/figure_s1.png", "main.tex",
                                          "references.bib", "supplement.tex"])

    def test_references_citations_and_math(self):
        self.assertIn(f"control is in Fig.~S1, its panel (b) in Fig.~S1b and both in Figs.~\\ref{{fig:1}} and S1.",
                      self.main_tex)
        self.assertIn("The method of \\citet{kuhn1955hungarian} assigns", self.main_tex)
        self.assertIn("and a citation \\citep{kuhn1955hungarian}.", self.main_tex)
        self.assertIn("\\begin{equation}\nF_1^{c} = \\frac{F_1 - F_1^{0}}{1 - F_1^{0}}\n\\end{equation}",
                      self.main_tex)
        self.assertIn("\\textbf{Figure S1.} Dense control at 2 m; see Section~2 and Fig.~1.\n\\end{figure}",
                      self.supp_tex)
        self.assertNotIn("equation", self.supp_tex)
        self.assertIn("\\section{Introduction}\\label{sec:1}", self.main_tex)

    def test_citations_and_back_matter_order(self):
        md = (p2i.REPO / "paper/manuscript.md").read_text(encoding="utf-8")
        self.assertEqual(tex_cite_keys(self.main_tex), md_cite_keys(els_main_md(md)))
        self.assertEqual(re.findall(r"\\section\*\{([^}]*)\}", self.main_tex), md_back_heads(md))

    def test_front_and_back_matter(self):
        self.assertEqual(re.search(r"(?s)\\begin\{highlights\}(.*?)\\end\{highlights\}", self.main_tex)
                         .group(1).count("\\item"), 3)
        self.assertIn("\\begin{keyword}\nbeta \\sep alpha\n\\end{keyword}", self.main_tex)
        self.assertIn("\\fntext[orcid1]{ORCID: \\url{https://orcid.org/0000-0002-1825-009X}.}", self.main_tex)
        self.assertIn("\\section*{CRediT authorship contribution statement}\n% TODO: complete this section.",
                      self.main_tex)
        self.assertIn("Supplementary material for ``a short title:\nwith a subtitle''", self.supp_tex)
        # The supplement has its own author line, which must list the authors
        # completed in main.tex.
        self.assertIn("% TODO: list every author here too, as in main.tex.\n\\author{Jane Doe}\n", self.supp_tex)

    def test_graphics_path_reaches_the_paper_folder_from_out(self):
        # OUT is root/out, so the figure paths (figures/figure_1.pdf) are read
        # relative to ../paper/, after ./ for the Overleaf zip.
        for tex in (self.main_tex, self.supp_tex):
            self.assertRegex(tex, r"(?m)^" + re.escape("\\graphicspath{{./}{../paper/}}") + "$")

    def test_code_blocks(self):
        self.assertIn("\\begin{verbatim}\ngrep -E '\\[0-9\\]+' log.txt # \\( Table 9 @kuhn1955hungarian {x} $y$\n"
                      "\\end{verbatim}", self.main_tex)

    def test_no_word_is_lost_and_every_number_matches(self):
        for name, md, tex in (("main", self.main_md, self.main_tex), ("supplement", self.supp_md, self.supp_tex)):
            with self.subTest(document=name):
                md_w, tex_w = tie.md_words(md), els_tex_words(tex)
                self.assertEqual(dict(md_w - tex_w), {})
                self.assertEqual(dict(tie.numbers(tex_w) - tie.numbers(md_w)), {})
                self.assertEqual(dict(tie.numbers(md_w) - tie.numbers(tex_w)), {})
                self.assertEqual(els_table_rows(tex), tie.pipe_table_rows(md))

    def test_manuscript_rules_stop_the_build(self):
        md = (p2i.REPO / "paper/manuscript.md").read_text(encoding="utf-8")
        # Each case breaks one rule and stops for that reason; the numbering
        # case swaps two subsection numbers, which the supplement does not cite.
        md = md.replace("## 2. Methods\n", "## 2. Methods\n\n### 2.1 First\n\nA.\n\n### 2.2 Second\n\nB.\n")
        bad = {"3 highlights; the journal asks|1 highlights": md.replace(SYNTH_HIGHLIGHTS, "- Only one.\n"),
               "7 keywords; the journal takes": md.replace("**Keywords:** beta; alpha.",
                                                           "**Keywords:** a; b; c; d; e; f; g."),
               "out of sequence": md.replace("### 2.1 First", "### 2.9 First"),
               "section before the references must be": md.replace("## Acknowledgements\n\nThanks.\n\n", "").replace(
                   "## References", "## Acknowledgements\n\nThanks.\n\n## References"),
               # LaTeX numbers floats in order of appearance and the supplement
               # writes the markdown's numbers: swapped, skipped (the text still
               # cites Table 1 and Fig. 1) or repeated numbers stop the build.
               "tables are numbered 2, 1 in the order they appear": md.replace("**Table 1.**", "**Table 9.**").replace(
                   "**Table 2.**", "**Table 1.**").replace("**Table 9.**", "**Table 2.**"),
               "tables are numbered 3, 2 in the order they appear": md.replace("**Table 1.**", "**Table 3.**"),
               "tables are numbered 1, 1 in the order they appear": md.replace("**Table 2.**", "**Table 1.**"),
               "figures are numbered 2 in the order they appear": md.replace("![Figure 1.]", "![Figure 2.]").replace(
                   "**Figure 1.**", "**Figure 2.**"),
               # An unnumbered section before a numbered one would make it back
               # matter, its references printing "Section ??".
               r"numbered section '3\. Discussion' comes after 'A preliminary note'.*every numbered section must "
               r"come before the first unnumbered one": md.replace(
                   "## CRediT", "## A preliminary note\n\nA note.\n\n## 3. Discussion\n\nShort.\n\n## CRediT")}
        original = (p2i.REPO / "paper/manuscript.md").read_text(encoding="utf-8")
        for reason, text in bad.items():
            with self.subTest(reason=reason):
                self.assertNotEqual(text, md)
                (p2i.REPO / "paper/manuscript.md").write_text(text, encoding="utf-8")
                try:
                    with self.assertRaisesRegex(RuntimeError, reason):
                        run_converter([f"OUT={p2i.REPO / 'bad'}", f"PANDOC={PANDOC}"])
                    self.assertFalse((p2i.REPO / "bad").exists())  # nothing is written on a failed build
                finally:
                    (p2i.REPO / "paper/manuscript.md").write_text(original, encoding="utf-8")


@unittest.skipUnless(BIBTEX, "bibtex not available (set BIBTEX=/path/to/bibtex)")
class BibtexTests(unittest.TestCase):
    """Run elsarticle-harv.bst on the Elsevier copy of the whole bibliography."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        out = Path(cls.tmp.name)
        cls.source = (ROOT / "docs/references.bib").read_text(encoding="utf-8")
        (out / "references.bib").write_text(p2e.elsevier_bib(cls.source), encoding="utf-8")
        (out / "all.aux").write_text("\\relax\n\\citation{*}\n\\bibstyle{elsarticle-harv}\n\\bibdata{references}\n")
        cls.proc = subprocess.run([BIBTEX, "all"], cwd=out, capture_output=True, text=True)
        cls.blg = (out / "all.blg").read_text()
        cls.bbl = (out / "all.bbl").read_text()
        cls.items = {m.group(1): tie.flat(m.group(2)) for m in re.finditer(
            r"(?s)\\bibitem\[[^\]]*\]\{([^}]*)\}(.*?)(?=\\bibitem|\\end\{thebibliography\})", cls.bbl)}

    def test_bibtex_runs_clean(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stdout + self.proc.stderr)
        self.assertNotIn("Warning--", self.blg)
        self.assertEqual(len(self.items), len(p2i.parse_bib(self.source)))

    def test_printed_fields(self):
        bbl = tie.flat(self.bbl)
        for text in ("{V}ersion RELEASE-2026", "{MIT} licence", "Zenodo", "{A}ccessed 2 October 2026",
                     "\\doi{10.48443/pypa-qf12}", "arXiv:2108.13264"):
            self.assertIn(text, bbl)
        for text in ("Undated page", "------", "{v}ersion"):
            self.assertNotIn(text, bbl)
        # The version of record: the DOI, not the arXiv identifier.
        self.assertIn("\\doi{", self.items["hamraz2016robust"])
        self.assertNotIn("1701.00198", self.items["hamraz2016robust"])
        # Proceedings volumes, preprint DOIs, one period after a publisher,
        # corporate authors without their abbreviation, quotes in titles.
        for key in ("yu2004effects", "hirata2004effects"):
            self.assertIn("Sciences XXXVI-8/W2}", self.items[key])
        self.assertIn("Systems 34}", self.items["agarwal2021deep"])
        self.assertIn("\\doi{10.48550/arXiv.2107.07002}", self.items["dehghani2021benchmark"])
        self.assertNotRegex(bbl, r"\.\}\. ")
        self.assertNotIn("(NEON)", self.items["neon2026vegetation"])
        for key in ("powers2011evaluation", "agarwal2021deep"):  # published: no preprint DOI
            self.assertNotIn("10.48550", self.items[key])
        self.assertIn("``equitable threat score''", self.items["hogan2010equitability"])

    def test_article_issues_print_with_their_volumes(self):
        # The style ignores an article's number, so the copy joins it to the
        # volume, as the journal prints "58 (5-6)".
        self.assertIn("\\bibinfo{volume}{2 (1--2)}", self.items["kuhn1955hungarian"])
        joined = 0
        for etype, key, fields, _ in p2i.parse_bib(self.source):
            f = dict(fields)
            if etype.lower() == "article" and f.get("volume", "").strip() and f.get("number", "").strip():
                joined += 1
                with self.subTest(key=key):
                    want = f"\\bibinfo{{volume}}{{{tie.flat(f['volume'])} ({tie.flat(f['number'])})}}"
                    self.assertIn(want, self.items[key])
        self.assertGreater(joined, 1)


@unittest.skipUnless(PANDOC and BIBTEX and PDFLATEX,
                     "pandoc, bibtex or pdflatex not available (set PANDOC, BIBTEX and PDFLATEX)")
class CompileTests(unittest.TestCase):
    """Convert the paper and compile both documents with pdfLaTeX and BibTeX,
    as Overleaf does: no error, no overfull line, no line stretched to
    badness 10000, no undefined citation or reference and no BibTeX
    warning."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        root = Path(cls.tmp.name)
        out = root / "elsevier"
        # OUT outside paper/: the documents find the figures through their
        # \graphicspath, a path relative to OUT.
        run_converter([f"OUT={out}", f"PANDOC={PANDOC}"])
        # Long log lines unwrapped, so a warning is read whole whatever the TeX
        # installation's default (79 columns in stock TeX Live).
        env = dict(os.environ, max_print_line="10000",
                   PATH=str(Path(PDFLATEX).resolve().parent) + os.pathsep + os.environ.get("PATH", ""))
        cls.logs, cls.blgs, cls.codes = {}, {}, {}
        for doc in ("main", "supplement"):
            codes = []
            for cmd in ([PDFLATEX], [BIBTEX], [PDFLATEX], [PDFLATEX]):
                arg = [doc] if cmd == [BIBTEX] else ["-interaction=nonstopmode", "-halt-on-error", doc]
                codes.append(subprocess.run(cmd + arg, cwd=out, env=env, capture_output=True, text=True).returncode)
            cls.codes[doc] = codes
            cls.logs[doc] = (out / f"{doc}.log").read_text(errors="replace")
            cls.blgs[doc] = (out / f"{doc}.blg").read_text(errors="replace")

    def test_documents_compile_clean(self):
        for doc, log in self.logs.items():
            with self.subTest(document=doc):
                self.assertEqual(self.codes[doc], [0, 0, 0, 0])
                self.assertNotRegex(log, r"(?m)^! ")
                self.assertNotIn("Overfull \\hbox", log)
                self.assertNotRegex(log, r"(Citation|Reference) `[^']*' on page \d+ undefined")
                self.assertNotRegex(log, r"There were undefined (citations|references)")
                self.assertNotIn("Underfull \\hbox (badness 10000)", log)
                self.assertNotIn("Warning--", self.blgs[doc])


if __name__ == "__main__":
    unittest.main()
